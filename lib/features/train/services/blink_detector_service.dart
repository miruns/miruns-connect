import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../../../core/services/ble_source_provider.dart';
import '../models/blink_profile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Blink Detector Service — Pure Dart signal processing pipeline
//
// Raw Fp1/Fp2 → Bandpass → Rectify → Adaptive Threshold → Peak Detection
//   → State Machine → Stream<BlinkEvent>
// ─────────────────────────────────────────────────────────────────────────────

/// Internal state of the blink detection state machine.
enum _DetectorState { idle, peak1, peak2, longHold, cooldown }

/// A detected peak event (internal, before classification).
class _PeakEvent {
  final DateTime time;
  final double amplitude;
  final int channel; // 0 = Fp1, 1 = Fp2
  _PeakEvent(this.time, this.amplitude, this.channel);
}

/// Real-time blink detector processing Fp1/Fp2 EEG channels.
///
/// Uses IIR bandpass filter (0.5–10 Hz), adaptive threshold, peak detection,
/// and a timing state machine to classify blink gestures.
class BlinkDetectorService {
  BlinkDetectorService({
    BlinkProfile? profile,
    this.sampleRateHz = 250.0,
    this.fp1Index = 0,
    this.fp2Index = 1,
  }) : _profile =
           profile ?? const BlinkProfile(id: 'default', createdAt: null) {
    _initFilters();
  }

  // Allow null createdAt for default profile
  // ignore: unused_field
  static const _defaultProfile = BlinkProfile(id: 'default', createdAt: null);

  // ── Configuration ─────────────────────────────────────────────────────────

  final double sampleRateHz;
  final int fp1Index;
  final int fp2Index;
  BlinkProfile _profile;

  BlinkProfile get profile => _profile;

  void updateProfile(BlinkProfile p) {
    _profile = p;
    _adaptiveWindowSize = (p.doubleBlinkWindow / 1000 * sampleRateHz * 5)
        .round()
        .clamp(500, 5000);
  }

  // ── Output stream ─────────────────────────────────────────────────────────

  final _blinkController = StreamController<BlinkEvent>.broadcast();
  Stream<BlinkEvent> get blinkStream => _blinkController.stream;

  // ── Real-time signal stats (exposed for UI) ───────────────────────────────

  double get currentFp1Amplitude => _fp1Rms;
  double get currentFp2Amplitude => _fp2Rms;
  double get currentThreshold => _adaptiveThreshold;
  // ignore: library_private_types_in_public_api
  _DetectorState get debugState => _state;

  // ── IIR Bandpass Filter (0.5–10 Hz, 2nd order Butterworth) ────────────────
  //
  // Pre-computed coefficients for 250 Hz sample rate.
  // Passband: 0.5–10 Hz — preserves blink waveform, removes EEG background.

  // 2nd-order sections for 0.5 Hz highpass
  static const _hpB = [0.9695, -1.9391, 0.9695];
  static const _hpA = [1.0, -1.9384, 0.9399];

  // 2nd-order sections for 10 Hz lowpass
  static const _lpB = [0.0201, 0.0402, 0.0201];
  static const _lpA = [1.0, -1.5610, 0.6414];

  // Per-channel filter state (Fp1, Fp2)
  late List<List<double>> _hpState; // [channel][2] delay elements
  late List<List<double>> _lpState;

  void _initFilters() {
    _hpState = [
      [0.0, 0.0],
      [0.0, 0.0],
    ];
    _lpState = [
      [0.0, 0.0],
      [0.0, 0.0],
    ];
    _adaptiveWindowSize = (5.0 * sampleRateHz).round(); // 5 seconds default
  }

  double _applyFilter(double x, int ch) {
    // Highpass (0.5 Hz)
    final hpY = _hpB[0] * x + _hpState[ch][0];
    _hpState[ch][0] = _hpB[1] * x - _hpA[1] * hpY + _hpState[ch][1];
    _hpState[ch][1] = _hpB[2] * x - _hpA[2] * hpY;

    // Lowpass (10 Hz)
    final lpY = _lpB[0] * hpY + _lpState[ch][0];
    _lpState[ch][0] = _lpB[1] * hpY - _lpA[1] * lpY + _lpState[ch][1];
    _lpState[ch][1] = _lpB[2] * hpY - _lpA[2] * lpY;

    return lpY;
  }

  // ── Adaptive threshold ────────────────────────────────────────────────────

  final _fp1Buffer = ListQueue<double>();
  final _fp2Buffer = ListQueue<double>();
  int _adaptiveWindowSize = 1250; // 5 s × 250 Hz
  double _adaptiveThreshold = 50.0;

  /// True once enough samples have been collected for a stable threshold.
  bool get isPrimed => _fp1Buffer.length >= (_adaptiveWindowSize ~/ 2);
  double _fp1Rms = 0.0;
  double _fp2Rms = 0.0;

  // Running accumulators — O(1) per sample instead of O(N)
  double _runSum1 = 0.0, _runSqSum1 = 0.0;
  double _runSum2 = 0.0, _runSqSum2 = 0.0;

  void _updateAdaptiveThreshold(double fp1Abs, double fp2Abs) {
    // Add new values to accumulators
    _runSum1 += fp1Abs;
    _runSqSum1 += fp1Abs * fp1Abs;
    _runSum2 += fp2Abs;
    _runSqSum2 += fp2Abs * fp2Abs;

    _fp1Buffer.addLast(fp1Abs);
    _fp2Buffer.addLast(fp2Abs);

    // Subtract dropped values from accumulators
    if (_fp1Buffer.length > _adaptiveWindowSize) {
      final old = _fp1Buffer.removeFirst();
      _runSum1 -= old;
      _runSqSum1 -= old * old;
    }
    if (_fp2Buffer.length > _adaptiveWindowSize) {
      final old = _fp2Buffer.removeFirst();
      _runSum2 -= old;
      _runSqSum2 -= old * old;
    }

    if (_fp1Buffer.length < 50) return; // Need minimum data

    // Compute mean + 3σ from running sums (O(1))
    final n1 = _fp1Buffer.length.toDouble();
    final mean1 = _runSum1 / n1;
    final variance1 = (_runSqSum1 / n1) - mean1 * mean1;
    final std1 = math.sqrt(math.max(0.0, variance1)).clamp(1.0, 200.0);

    final n2 = _fp2Buffer.length.toDouble();
    final mean2 = _runSum2 / n2;
    final variance2 = (_runSqSum2 / n2) - mean2 * mean2;
    final std2 = math.sqrt(math.max(0.0, variance2)).clamp(1.0, 200.0);

    // Use the lower threshold of the two channels (more sensitive)
    final th1 = mean1 + 3.0 * std1;
    final th2 = mean2 + 3.0 * std2;

    // But never drop below the profile's calibrated floor
    _adaptiveThreshold = math.max(
      math.min(th1, th2),
      math.min(_profile.fp1Threshold, _profile.fp2Threshold) * 0.5,
    );

    // Update RMS for UI display
    _fp1Rms = math.sqrt(_runSqSum1 / n1);
    _fp2Rms = math.sqrt(_runSqSum2 / n2);
  }

  // ── Peak detection ────────────────────────────────────────────────────────

  bool _fp1AboveThreshold = false;
  bool _fp2AboveThreshold = false;
  double _currentPeakAmplitude = 0.0;
  DateTime? _peakOnsetTime;

  // ── State machine ─────────────────────────────────────────────────────────

  _DetectorState _state = _DetectorState.idle;
  _PeakEvent? _peak1;
  _PeakEvent? _peak2;
  Timer? _singleBlinkTimer;
  Timer? _doubleBlinkTimer;
  Timer? _cooldownTimer;
  Timer? _longBlinkTimer;

  StreamSubscription<SignalSample>? _signalSub;

  /// Start processing from a live signal stream.
  void start(Stream<SignalSample> signalStream) {
    _signalSub?.cancel();
    _signalSub = signalStream.listen(_processSample);
  }

  /// Stop processing.
  void stop() {
    _signalSub?.cancel();
    _signalSub = null;
    _cancelTimers();
    _state = _DetectorState.idle;
  }

  void _cancelTimers() {
    _singleBlinkTimer?.cancel();
    _doubleBlinkTimer?.cancel();
    _cooldownTimer?.cancel();
    _longBlinkTimer?.cancel();
  }

  void _processSample(SignalSample sample) {
    if (sample.channels.length <= math.max(fp1Index, fp2Index)) return;

    final rawFp1 = sample.channels[fp1Index];
    final rawFp2 = sample.channels[fp2Index];

    // Apply bandpass filter
    final filteredFp1 = _applyFilter(rawFp1, 0);
    final filteredFp2 = _applyFilter(rawFp2, 1);

    // Rectify
    final absFp1 = filteredFp1.abs();
    final absFp2 = filteredFp2.abs();

    // Update adaptive threshold
    _updateAdaptiveThreshold(absFp1, absFp2);

    // Threshold for this profile
    final th = _adaptiveThreshold;

    // Peak detection: check if either channel crosses threshold
    final fp1Over = absFp1 > th;
    final fp2Over = absFp2 > th;
    final peakNow = fp1Over || fp2Over;
    final peakAmplitude = math.max(absFp1, absFp2);
    final wasAbove = _fp1AboveThreshold || _fp2AboveThreshold;

    if (peakNow) {
      _currentPeakAmplitude = math.max(_currentPeakAmplitude, peakAmplitude);
    }

    // Rising edge — peak onset
    if (peakNow && !wasAbove) {
      _peakOnsetTime = sample.time;
      _currentPeakAmplitude = peakAmplitude;
    }

    // Falling edge — peak offset → emit to state machine
    if (!peakNow && wasAbove && _peakOnsetTime != null) {
      final duration = sample.time.difference(_peakOnsetTime!);
      final ch = absFp1 >= absFp2 ? 0 : 1;
      _onPeakDetected(
        _PeakEvent(sample.time, _currentPeakAmplitude, ch),
        duration,
      );
      _currentPeakAmplitude = 0.0;
      _peakOnsetTime = null;
    }

    // Long blink detection: sustained above threshold
    if (peakNow && wasAbove && _peakOnsetTime != null) {
      final holdDuration = sample.time.difference(_peakOnsetTime!);
      if (_state == _DetectorState.peak1 &&
          holdDuration.inMilliseconds >= _profile.longBlinkMinDuration) {
        _onLongBlinkDetected(holdDuration);
      }
    }

    _fp1AboveThreshold = fp1Over;
    _fp2AboveThreshold = fp2Over;
  }

  void _onPeakDetected(_PeakEvent peak, Duration duration) {
    switch (_state) {
      case _DetectorState.idle:
        _peak1 = peak;
        _state = _DetectorState.peak1;
        // Start timer for single blink classification
        _singleBlinkTimer?.cancel();
        _singleBlinkTimer = Timer(
          Duration(milliseconds: _profile.doubleBlinkWindow.round()),
          () {
            // No second peak arrived → single blink
            if (_state == _DetectorState.peak1) {
              _emitBlink(BlinkType.single, _peak1!);
              _enterCooldown();
            }
          },
        );
        break;

      case _DetectorState.peak1:
        // Check timing for double blink
        final gap = peak.time.difference(_peak1!.time).inMilliseconds;
        if (gap >= 200 && gap <= _profile.doubleBlinkWindow) {
          _singleBlinkTimer?.cancel();
          _peak2 = peak;
          _state = _DetectorState.peak2;
          // Wait for possible triple blink
          _doubleBlinkTimer?.cancel();
          _doubleBlinkTimer = Timer(const Duration(milliseconds: 500), () {
            if (_state == _DetectorState.peak2) {
              _emitBlink(BlinkType.double, _peak2!);
              _enterCooldown();
            }
          });
        }
        break;

      case _DetectorState.peak2:
        // Third peak → triple blink
        final gap = peak.time.difference(_peak2!.time).inMilliseconds;
        if (gap >= 150 && gap <= 600) {
          _doubleBlinkTimer?.cancel();
          _emitBlink(BlinkType.triple, peak);
          _enterCooldown();
        }
        break;

      case _DetectorState.longHold:
      case _DetectorState.cooldown:
        // Ignore peaks during cooldown or while holding
        break;
    }
  }

  void _onLongBlinkDetected(Duration holdDuration) {
    _singleBlinkTimer?.cancel();
    _state = _DetectorState.longHold;
    _emitBlink(
      BlinkType.long,
      _peak1 ?? _PeakEvent(DateTime.now(), _currentPeakAmplitude, 0),
      durationMs: holdDuration.inMilliseconds,
    );
    _enterCooldown();
  }

  void _emitBlink(BlinkType type, _PeakEvent peak, {int durationMs = 0}) {
    // Compute confidence based on peak amplitude relative to threshold
    final ratio = peak.amplitude / _adaptiveThreshold;
    final confidence = (ratio / 3.0).clamp(0.0, 1.0); // 3× threshold = 100%

    _blinkController.add(
      BlinkEvent(
        type: type,
        timestamp: peak.time,
        confidence: confidence,
        rawPeakAmplitude: peak.amplitude,
        durationMs: durationMs,
      ),
    );
  }

  void _enterCooldown() {
    _cancelTimers();
    _state = _DetectorState.cooldown;
    _cooldownTimer = Timer(const Duration(milliseconds: 1000), () {
      _state = _DetectorState.idle;
      _peak1 = null;
      _peak2 = null;
    });
  }

  /// Reset all state (useful between calibration phases).
  void reset() {
    _cancelTimers();
    _state = _DetectorState.idle;
    _peak1 = null;
    _peak2 = null;
    _fp1AboveThreshold = false;
    _fp2AboveThreshold = false;
    _currentPeakAmplitude = 0.0;
    _peakOnsetTime = null;
    _fp1Buffer.clear();
    _fp2Buffer.clear();
    _runSum1 = 0.0;
    _runSqSum1 = 0.0;
    _runSum2 = 0.0;
    _runSqSum2 = 0.0;
    _initFilters();
  }

  void dispose() {
    stop();
    _blinkController.close();
  }
}
