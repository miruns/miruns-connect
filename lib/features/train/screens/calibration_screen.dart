import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/blink_profile.dart';
import '../services/blink_detector_service.dart';
import '../widgets/blink_waveform_monitor.dart';
import '../widgets/calibration_cue_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Calibration Screen — Guided 3-minute blink training wizard
//
// UX highlights:
//   · Step-by-step flow with progress bar
//   · Animated countdown ring before each blink cue
//   · Immediate visual + haptic feedback on blink detection
//   · Live Fp1/Fp2 waveform display at all times
//   · Retry option for any step with <70% accuracy
//   · Results summary with overall calibration quality
// ─────────────────────────────────────────────────────────────────────────────

/// Calibration phases in order.
enum _CalibrationPhase {
  connecting('Connecting', 'Checking signal source…'),
  baseline('Baseline', 'Sit still, eyes open, relax'),
  singleBlinks('Single Blinks', 'Blink firmly when prompted'),
  rest1('Rest', 'Relax for a moment…'),
  doubleBlinks('Double Blinks', 'Two quick blinks when prompted'),
  rest2('Rest', 'Almost there…'),
  longBlinks('Long Blinks', 'Close eyes for ~1 second'),
  rest3('Rest', 'Final rest period'),
  results('Results', 'Calibration complete');

  const _CalibrationPhase(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen>
    with TickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  late final BleSourceService _bleSource;
  late final BlinkDetectorService _detector;
  StreamSubscription<BlinkEvent>? _blinkSub;

  // ── Phase tracking ────────────────────────────────────────────────────────
  _CalibrationPhase _phase = _CalibrationPhase.connecting;
  int _phaseIndex = 0;

  // ── Per-phase state ───────────────────────────────────────────────────────
  int _attemptIndex = 0;
  static const _attemptsPerPhase = 10;
  bool _cueActive = false;
  bool _cueDetected = false;
  double _cueCountdown = 0.0;
  Timer? _cueTimer;
  Timer? _phaseTimer;
  Timer? _countdownTicker;

  // ── Waveform display ──────────────────────────────────────────────────────
  final _waveformKey = GlobalKey<MiniWaveformChartState>();
  StreamSubscription<SignalSample>? _signalSub;
  Timer? _waveformRefresh;

  // ── Calibration data collection ───────────────────────────────────────────
  final _baselineAmplitudes = <double>[];
  final _singleBlinkPeaks = <double>[];
  final _singleBlinkDurations = <double>[];
  int _singleDetected = 0;
  final _doubleBlinkPeaks = <double>[];
  int _doubleDetected = 0;
  final _longBlinkPeaks = <double>[];
  final _longBlinkDurations = <double>[];
  int _longDetected = 0;

  // False positives during rest
  int _restFalsePositives = 0;
  int _totalRestSamples = 0;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _phaseTransition;

  @override
  void initState() {
    super.initState();
    _bleSource = ref.read(bleSourceServiceProvider);
    _detector = BlinkDetectorService(fp1Index: 0, fp2Index: 1);
    _phaseTransition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _startCalibration();
  }

  @override
  void dispose() {
    _blinkSub?.cancel();
    _signalSub?.cancel();
    _cueTimer?.cancel();
    _phaseTimer?.cancel();
    _countdownTicker?.cancel();
    _waveformRefresh?.cancel();
    _detector.dispose();
    _phaseTransition.dispose();
    super.dispose();
  }

  // ── Calibration flow ──────────────────────────────────────────────────────

  void _startCalibration() {
    // Start the detector on the BLE signal stream
    _detector.start(_bleSource.signalStream);

    // Listen for blink events
    _blinkSub = _detector.blinkStream.listen(_onBlinkDuringCalibration);

    // Feed waveform display
    _signalSub = _bleSource.signalStream.listen((sample) {
      if (sample.channels.length >= 2) {
        _waveformKey.currentState?.addSample(
          sample.channels[0].abs(),
          sample.channels[1].abs(),
        );
        _waveformKey.currentState?.setThreshold(_detector.currentThreshold);
      }
    });

    // Refresh waveform at 30fps
    _waveformRefresh = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted) setState(() {});
    });

    // Start with a short delay then move to baseline
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _advanceToPhase(_CalibrationPhase.baseline);
    });
  }

  void _advanceToPhase(_CalibrationPhase phase) {
    _cueTimer?.cancel();
    _phaseTimer?.cancel();
    _countdownTicker?.cancel();
    _detector.reset();
    _detector.start(_bleSource.signalStream);

    setState(() {
      _phase = phase;
      _phaseIndex = _CalibrationPhase.values.indexOf(phase);
      _attemptIndex = 0;
      _cueActive = false;
      _cueDetected = false;
      _cueCountdown = 0.0;
    });

    _phaseTransition.forward(from: 0);

    switch (phase) {
      case _CalibrationPhase.connecting:
        break;
      case _CalibrationPhase.baseline:
        _runBaseline();
        break;
      case _CalibrationPhase.singleBlinks:
        _runBlinkPhase(BlinkType.single);
        break;
      case _CalibrationPhase.rest1:
      case _CalibrationPhase.rest2:
      case _CalibrationPhase.rest3:
        _runRest();
        break;
      case _CalibrationPhase.doubleBlinks:
        _runBlinkPhase(BlinkType.double);
        break;
      case _CalibrationPhase.longBlinks:
        _runBlinkPhase(BlinkType.long);
        break;
      case _CalibrationPhase.results:
        // No action — results screen rendered directly
        break;
    }
  }

  void _runBaseline() {
    _baselineAmplitudes.clear();
    // Collect 10 seconds of baseline data
    _phaseTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) _advanceToPhase(_CalibrationPhase.singleBlinks);
    });

    // Track countdown
    _startCountdown(10);
  }

  void _runBlinkPhase(BlinkType type) {
    _attemptIndex = 0;
    // First cue after 2 seconds
    _cueTimer = Timer(const Duration(seconds: 2), () {
      _showCue(type);
    });
  }

  void _showCue(BlinkType type) {
    if (!mounted) return;

    HapticFeedback.lightImpact();

    setState(() {
      _cueActive = true;
      _cueDetected = false;
      _cueCountdown = 0.0;
    });

    // Countdown animation (3 seconds to respond)
    final start = DateTime.now();
    _countdownTicker?.cancel();
    _countdownTicker = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final progress = (elapsed / 3000).clamp(0.0, 1.0);
      setState(() => _cueCountdown = progress);

      if (progress >= 1.0) {
        t.cancel();
        // Missed this cue — advance anyway
        _onCueTimeout(type);
      }
    });
  }

  void _onCueTimeout(BlinkType type) {
    setState(() {
      _cueActive = false;
      _attemptIndex++;
    });

    if (_attemptIndex >= _attemptsPerPhase) {
      _advanceToNextPhase();
    } else {
      // Next cue in 2–3.5 seconds (randomized to prevent anticipation)
      final delay = 2000 + (math.Random().nextInt(1500));
      _cueTimer = Timer(Duration(milliseconds: delay), () {
        _showCue(type);
      });
    }
  }

  void _runRest() {
    _totalRestSamples++;
    _phaseTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _advanceToNextPhase();
    });
    _startCountdown(5);
  }

  void _startCountdown(int seconds) {
    final start = DateTime.now();
    _countdownTicker?.cancel();
    _countdownTicker = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final progress = (elapsed / (seconds * 1000)).clamp(0.0, 1.0);
      setState(() => _cueCountdown = progress);
      if (progress >= 1.0) t.cancel();
    });
  }

  void _advanceToNextPhase() {
    final phases = _CalibrationPhase.values;
    final nextIndex = _phaseIndex + 1;
    if (nextIndex < phases.length) {
      _advanceToPhase(phases[nextIndex]);
    }
  }

  // ── Blink event handling during calibration ───────────────────────────────

  void _onBlinkDuringCalibration(BlinkEvent event) {
    if (!mounted) return;

    // Update waveform marker
    _waveformKey.currentState?.addBlinkMarker(event.type);

    switch (_phase) {
      case _CalibrationPhase.baseline:
        // During baseline, any blink is just amplitude data
        _baselineAmplitudes.add(event.rawPeakAmplitude);
        break;

      case _CalibrationPhase.singleBlinks:
        if (_cueActive && event.type == BlinkType.single) {
          _singleDetected++;
          _singleBlinkPeaks.add(event.rawPeakAmplitude);
          _singleBlinkDurations.add(event.durationMs.toDouble());
          _onSuccessfulDetection(BlinkType.single);
        }
        break;

      case _CalibrationPhase.doubleBlinks:
        if (_cueActive && event.type == BlinkType.double) {
          _doubleDetected++;
          _doubleBlinkPeaks.add(event.rawPeakAmplitude);
          _onSuccessfulDetection(BlinkType.double);
        }
        break;

      case _CalibrationPhase.longBlinks:
        if (_cueActive && event.type == BlinkType.long) {
          _longDetected++;
          _longBlinkPeaks.add(event.rawPeakAmplitude);
          _longBlinkDurations.add(event.durationMs.toDouble());
          _onSuccessfulDetection(BlinkType.long);
        }
        break;

      case _CalibrationPhase.rest1:
      case _CalibrationPhase.rest2:
      case _CalibrationPhase.rest3:
        // Any detection during rest = false positive
        _restFalsePositives++;
        break;

      default:
        break;
    }
  }

  void _onSuccessfulDetection(BlinkType type) {
    HapticFeedback.mediumImpact();
    _countdownTicker?.cancel();

    setState(() {
      _cueDetected = true;
    });

    // Brief green flash, then advance
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        _cueActive = false;
        _cueDetected = false;
        _attemptIndex++;
      });

      if (_attemptIndex >= _attemptsPerPhase) {
        _advanceToNextPhase();
      } else {
        // Next cue in 2–3.5 seconds
        final delay = 2000 + (math.Random().nextInt(1500));
        _cueTimer = Timer(Duration(milliseconds: delay), () {
          _showCue(type);
        });
      }
    });
  }

  // ── Compute calibration results ───────────────────────────────────────────

  BlinkProfile _computeProfile() {
    double mean(List<double> list) {
      if (list.isEmpty) return 0;
      return list.reduce((a, b) => a + b) / list.length;
    }

    double std(List<double> list) {
      if (list.length < 2) return 0;
      final m = mean(list);
      final variance =
          list.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) /
          list.length;
      return math.sqrt(variance);
    }

    // Thresholds: mean peak − 2σ (catches ~95% of real blinks)
    final allPeaks = [
      ..._singleBlinkPeaks,
      ..._doubleBlinkPeaks,
      ..._longBlinkPeaks,
    ];
    final peakMean = mean(allPeaks);
    final peakStd = std(allPeaks);
    final threshold = math.max(20.0, peakMean - 2 * peakStd);

    final singleAcc = _singleDetected / _attemptsPerPhase;
    final doubleAcc = _doubleDetected / _attemptsPerPhase;
    final longAcc = _longDetected / _attemptsPerPhase;

    // False positive rate: detections during rest / total rest periods
    final fpRate = _totalRestSamples > 0
        ? (_restFalsePositives / (_totalRestSamples * 3)).clamp(0.0, 1.0)
        : 0.0;

    return BlinkProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      deviceId: _bleSource.connectedDevice?.remoteId.str,
      fp1Threshold: threshold,
      fp2Threshold: threshold,
      singleBlinkMaxDuration: _singleBlinkDurations.isNotEmpty
          ? mean(_singleBlinkDurations) + std(_singleBlinkDurations)
          : 400,
      longBlinkMinDuration: _longBlinkDurations.isNotEmpty
          ? mean(_longBlinkDurations) - std(_longBlinkDurations)
          : 600,
      doubleBlinkWindow: 700,
      singleBlinkAccuracy: singleAcc,
      doubleBlinkAccuracy: doubleAcc,
      longBlinkAccuracy: longAcc,
      falsePositiveRate: fpRate,
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;
    final phases = _CalibrationPhase.values;
    final progress = (_phaseIndex + 1) / phases.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: colors.textBody),
          onPressed: () => _confirmExit(context),
        ),
        title: Text(
          'Calibration',
          style: AppTheme.geist(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textStrong,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Progress bar ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _phase.title,
                        style: AppTheme.geistMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.seaGreen,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        '${_phaseIndex + 1} / ${phases.length}',
                        style: AppTheme.geistMono(
                          fontSize: 11,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: colors.tintSubtle,
                      valueColor: const AlwaysStoppedAnimation(
                        AppTheme.seaGreen,
                      ),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Phase subtitle ──────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Padding(
                key: ValueKey(_phase),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _phase.subtitle,
                  textAlign: TextAlign.center,
                  style: AppTheme.geist(
                    fontSize: 15,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Central content ─────────────────────────────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _buildPhaseContent(),
              ),
            ),

            // ── Live waveform (always visible) ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF58A6FF),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        'Fp1',
                        style: AppTheme.geistMono(
                          fontSize: 10,
                          color: const Color(0xFF58A6FF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF6B8A),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        'Fp2',
                        style: AppTheme.geistMono(
                          fontSize: 10,
                          color: const Color(0xFFFF6B8A),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'TH: ${_detector.currentThreshold.toStringAsFixed(0)} µV',
                        style: AppTheme.geistMono(
                          fontSize: 10,
                          color: AppTheme.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  MiniWaveformChart(
                    key: _waveformKey,
                    height: 80,
                    bufferSize: 500,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseContent() {
    switch (_phase) {
      case _CalibrationPhase.connecting:
        return _buildConnecting();
      case _CalibrationPhase.baseline:
        return _buildBaselinePhase();
      case _CalibrationPhase.singleBlinks:
        return _buildBlinkPhase(BlinkType.single, _singleDetected);
      case _CalibrationPhase.rest1:
      case _CalibrationPhase.rest2:
      case _CalibrationPhase.rest3:
        return _buildRestPhase();
      case _CalibrationPhase.doubleBlinks:
        return _buildBlinkPhase(BlinkType.double, _doubleDetected);
      case _CalibrationPhase.longBlinks:
        return _buildBlinkPhase(BlinkType.long, _longDetected);
      case _CalibrationPhase.results:
        return _buildResults();
    }
  }

  Widget _buildConnecting() {
    final colors = context.miruns;
    return Center(
      key: const ValueKey('connecting'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Verifying signal quality…',
            style: AppTheme.geist(fontSize: 15, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildBaselinePhase() {
    final colors = context.miruns;
    return Center(
      key: const ValueKey('baseline'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.self_improvement_rounded,
            size: 80,
            color: colors.textMuted,
          ),
          const SizedBox(height: 20),
          Text(
            'Stay still, eyes open',
            style: AppTheme.geist(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textStrong,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Recording your resting brain activity.\nTry to avoid blinking for a few seconds.',
            textAlign: TextAlign.center,
            style: AppTheme.geist(fontSize: 14, color: colors.textSecondary),
          ),
          const SizedBox(height: 24),
          // Countdown ring
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: _cueCountdown,
              strokeWidth: 3,
              color: AppTheme.seaGreen,
              backgroundColor: colors.tintSubtle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlinkPhase(BlinkType type, int detected) {
    return Center(
      key: ValueKey('blink-${type.name}'),
      child: CalibrationCueWidget(
        blinkType: type,
        isActive: _cueActive,
        detected: _cueDetected,
        countdown: _cueCountdown,
        attempt: _attemptIndex,
        totalAttempts: _attemptsPerPhase,
      ),
    );
  }

  Widget _buildRestPhase() {
    final colors = context.miruns;
    return Center(
      key: const ValueKey('rest'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.spa_rounded, size: 60, color: colors.textMuted),
          const SizedBox(height: 16),
          Text(
            'Relax',
            style: AppTheme.geist(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textStrong,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Look at the screen naturally.\nWe\u2019re checking for false positives.',
            textAlign: TextAlign.center,
            style: AppTheme.geist(fontSize: 14, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final profile = _computeProfile();
    final colors = context.miruns;
    final quality = profile.overallQuality;
    final qualityColor = quality >= 0.7
        ? AppTheme.seaGreen
        : quality >= 0.4
        ? AppTheme.amber
        : AppTheme.crimson;

    return SingleChildScrollView(
      key: const ValueKey('results'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Quality ring
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: quality,
                  strokeWidth: 6,
                  color: qualityColor,
                  backgroundColor: colors.tintSubtle,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(quality * 100).round()}%',
                      style: AppTheme.geistMono(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: qualityColor,
                      ),
                    ),
                    Text(
                      'Quality',
                      style: AppTheme.geist(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Per-command accuracy
          _AccuracyRow(
            label: 'Single Blink',
            value: profile.singleBlinkAccuracy,
            detected: _singleDetected,
            total: _attemptsPerPhase,
          ),
          const SizedBox(height: 8),
          _AccuracyRow(
            label: 'Double Blink',
            value: profile.doubleBlinkAccuracy,
            detected: _doubleDetected,
            total: _attemptsPerPhase,
          ),
          const SizedBox(height: 8),
          _AccuracyRow(
            label: 'Long Blink',
            value: profile.longBlinkAccuracy,
            detected: _longDetected,
            total: _attemptsPerPhase,
          ),
          const SizedBox(height: 8),
          _AccuracyRow(
            label: 'False Positives',
            value: 1.0 - profile.falsePositiveRate,
            detected: _restFalsePositives,
            total: _totalRestSamples * 3,
            inverted: true,
          ),

          const SizedBox(height: 8),

          // Calibrated threshold
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.tintFaint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: colors.textMuted, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Threshold: ${profile.fp1Threshold.toStringAsFixed(0)} µV',
                  style: AppTheme.geistMono(
                    fontSize: 13,
                    color: colors.textBody,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              // Retry button (if quality is low)
              if (quality < 0.7)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _restartCalibration,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textBody,
                      side: BorderSide(color: colors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              if (quality < 0.7) const SizedBox(width: 12),

              // Save button
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _saveProfile(profile),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(quality >= 0.7 ? 'Save Profile' : 'Save Anyway'),
                  style: FilledButton.styleFrom(
                    backgroundColor: qualityColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _restartCalibration() {
    _singleDetected = 0;
    _doubleDetected = 0;
    _longDetected = 0;
    _restFalsePositives = 0;
    _totalRestSamples = 0;
    _singleBlinkPeaks.clear();
    _singleBlinkDurations.clear();
    _doubleBlinkPeaks.clear();
    _longBlinkPeaks.clear();
    _longBlinkDurations.clear();
    _baselineAmplitudes.clear();
    _detector.reset();
    _advanceToPhase(_CalibrationPhase.baseline);
  }

  void _saveProfile(BlinkProfile profile) {
    // Navigate to results screen or pop with profile
    context.pop(profile);
  }

  void _confirmExit(BuildContext context) {
    if (_phase == _CalibrationPhase.connecting ||
        _phase == _CalibrationPhase.results) {
      context.pop();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        final colors = ctx.miruns;
        return AlertDialog(
          backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
          title: Text(
            'Quit calibration?',
            style: AppTheme.geist(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colors.textStrong,
            ),
          ),
          content: Text(
            'Your progress will be lost.',
            style: AppTheme.geist(fontSize: 14, color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Continue',
                style: AppTheme.geist(color: colors.textBody),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.pop();
              },
              child: Text(
                'Quit',
                style: AppTheme.geist(color: AppTheme.crimson),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Accuracy row widget ───────────────────────────────────────────────────────

class _AccuracyRow extends StatelessWidget {
  const _AccuracyRow({
    required this.label,
    required this.value,
    required this.detected,
    required this.total,
    this.inverted = false,
  });

  final String label;
  final double value;
  final int detected;
  final int total;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;
    final color = value >= 0.7
        ? AppTheme.seaGreen
        : value >= 0.4
        ? AppTheme.amber
        : AppTheme.crimson;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.tintFaint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.geist(fontSize: 14, color: colors.textBody),
            ),
          ),
          Text(
            inverted ? '$detected false' : '$detected / $total',
            style: AppTheme.geistMono(fontSize: 12, color: colors.textMuted),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 50,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                backgroundColor: colors.tintSubtle,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(value * 100).round()}%',
            style: AppTheme.geistMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
