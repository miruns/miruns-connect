import 'dart:async';
import 'dart:collection';

import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/fft_engine.dart';
import '../models/workout_session.dart';

/// Converts raw EEG [SignalSample]s from [BleSourceService] into
/// [WorkoutEegSample] metrics (attention, relaxation, cognitiveLoad,
/// mentalFatigue) using FFT band-power analysis.
///
/// Typical usage during an active workout:
/// ```dart
/// final eegMetrics = EegMetricsService(bleSourceService.signalStream);
/// eegMetrics.metricsStream.listen((sample) => /* update UI & session */);
/// eegMetrics.dispose();
/// ```
class EegMetricsService {
  /// FFT window: 256 samples ≈ 1 s at 250 Hz.
  static const int _fftSize = 256;

  /// Emit a metric every ~2 seconds (every 2nd FFT window).
  static const int _emitEveryNWindows = 2;

  final Stream<SignalSample> _signalStream;
  final double _sampleRateHz;

  late final FftEngine _fft;
  final _metricsController = StreamController<WorkoutEegSample>.broadcast();

  /// Per-channel ring buffer (only channel 0 is used for metrics by default,
  /// but we keep all channels in case of multi-channel averaging later).
  final _buffer = ListQueue<double>();
  int _sampleCount = 0;

  StreamSubscription<SignalSample>? _sub;

  /// Emits derived [WorkoutEegSample] at regular intervals while EEG is
  /// streaming.
  Stream<WorkoutEegSample> get metricsStream => _metricsController.stream;

  EegMetricsService(this._signalStream, {double sampleRateHz = 250})
    : _sampleRateHz = sampleRateHz {
    _fft = FftEngine(n: _fftSize, sampleRateHz: _sampleRateHz);
    _sub = _signalStream.listen(_onSample);
  }

  void _onSample(SignalSample sample) {
    if (sample.channels.isEmpty) return;

    // Use the first channel (Fp1 / frontal — best for attention metrics).
    _buffer.addLast(sample.channels.first);

    // Keep buffer trimmed to FFT window size.
    while (_buffer.length > _fftSize) {
      _buffer.removeFirst();
    }

    // Wait until we have a full window.
    if (_buffer.length < _fftSize) return;

    _sampleCount++;
    if (_sampleCount % (_fftSize * _emitEveryNWindows) != 0) return;

    final result = _fft.analyse(_buffer.toList());
    final bp = result.bandPowers;
    final total = result.totalPower;

    if (total <= 0) return;

    // ── Derive cognitive metrics from EEG band powers ────────────────
    //
    // These are standard neurofeedback-derived indices:
    //
    //   Attention  ≈ β / (θ + α)          — engagement / focused attention
    //   Relaxation ≈ α / (β + total)       — eyes-closed calm
    //   CogLoad    ≈ (θ + β) / total       — working memory demand
    //   Fatigue    ≈ (θ + δ) / (α + β)     — drowsiness / depletion

    final delta = bp[FrequencyBand.delta] ?? 0;
    final theta = bp[FrequencyBand.theta] ?? 0;
    final alpha = bp[FrequencyBand.alpha] ?? 0;
    final beta = bp[FrequencyBand.beta] ?? 0;
    final gamma = bp[FrequencyBand.gamma] ?? 0;

    double attention = 0;
    if ((theta + alpha) > 0) {
      attention = beta / (theta + alpha);
    }

    double relaxation = 0;
    if ((beta + total) > 0) {
      relaxation = alpha / (beta + total);
    }

    double cognitiveLoad = 0;
    if (total > 0) {
      cognitiveLoad = (theta + beta) / total;
    }

    double mentalFatigue = 0;
    if ((alpha + beta) > 0) {
      mentalFatigue = (theta + delta) / (alpha + beta);
    }

    // Normalise all values to 0 – 1 range using sigmoid-like clamping.
    attention = _normalise(attention, 0.3, 3.0);
    relaxation = _normalise(relaxation, 0.01, 0.3);
    cognitiveLoad = _normalise(cognitiveLoad, 0.1, 0.8);
    mentalFatigue = _normalise(mentalFatigue, 0.3, 3.0);

    if (!_metricsController.isClosed) {
      _metricsController.add(
        WorkoutEegSample(
          timestamp: sample.time,
          attention: attention,
          relaxation: relaxation,
          cognitiveLoad: cognitiveLoad,
          mentalFatigue: mentalFatigue,
          deltaPct: total > 0 ? delta / total : 0,
          thetaPct: total > 0 ? theta / total : 0,
          alphaPct: total > 0 ? alpha / total : 0,
          betaPct: total > 0 ? beta / total : 0,
          gammaPct: total > 0 ? gamma / total : 0,
          dominantHz: result.dominantFrequency,
        ),
      );
    }
  }

  /// Maps [value] from [minExpected..maxExpected] into [0..1], clamped.
  static double _normalise(
    double value,
    double minExpected,
    double maxExpected,
  ) {
    if (maxExpected <= minExpected) return 0.5;
    final norm = (value - minExpected) / (maxExpected - minExpected);
    return norm.clamp(0.0, 1.0);
  }

  void dispose() {
    _sub?.cancel();
    _metricsController.close();
  }
}
