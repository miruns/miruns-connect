import 'dart:convert';

/// Blink types detected by the blink detector engine.
enum BlinkType {
  single('Single Blink', 'Quick firm blink'),
  double('Double Blink', 'Two fast blinks'),
  long('Long Blink', 'Hold eyes closed ~1s'),
  triple('Triple Blink', 'Three rapid blinks');

  const BlinkType(this.label, this.description);
  final String label;
  final String description;
}

/// A single detected blink event emitted by [BlinkDetectorService].
class BlinkEvent {
  final BlinkType type;
  final DateTime timestamp;

  /// 0.0–1.0 confidence that this was an intentional blink.
  final double confidence;

  /// Peak amplitude in µV of the strongest channel (Fp1 or Fp2).
  final double rawPeakAmplitude;

  /// Duration of the blink gesture in milliseconds.
  final int durationMs;

  const BlinkEvent({
    required this.type,
    required this.timestamp,
    required this.confidence,
    required this.rawPeakAmplitude,
    this.durationMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'ts': timestamp.microsecondsSinceEpoch,
    'conf': confidence,
    'peak': rawPeakAmplitude,
    'dur': durationMs,
  };

  factory BlinkEvent.fromJson(Map<String, dynamic> j) => BlinkEvent(
    type: BlinkType.values.byName(j['type'] as String),
    timestamp: DateTime.fromMicrosecondsSinceEpoch(j['ts'] as int),
    confidence: (j['conf'] as num).toDouble(),
    rawPeakAmplitude: (j['peak'] as num).toDouble(),
    durationMs: (j['dur'] as int?) ?? 0,
  );
}

/// Per-user calibrated blink profile.
///
/// Computed from calibration data and stored in the local database.
class BlinkProfile {
  final String id;
  final DateTime? createdAt;
  final String? deviceId;

  // ── Adaptive thresholds (µV) ──────────────────────────────────────────────
  final double fp1Threshold;
  final double fp2Threshold;

  // ── Timing windows (ms) ───────────────────────────────────────────────────
  final double singleBlinkMaxDuration;
  final double longBlinkMinDuration;
  final double doubleBlinkWindow;

  // ── Asymmetry for winks (future) ──────────────────────────────────────────
  final double winkAsymmetryRatio;

  // ── Quality metrics from calibration ──────────────────────────────────────
  final double singleBlinkAccuracy;
  final double doubleBlinkAccuracy;
  final double longBlinkAccuracy;
  final double falsePositiveRate;

  const BlinkProfile({
    required this.id,
    required this.createdAt,
    this.deviceId,
    this.fp1Threshold = 50.0,
    this.fp2Threshold = 50.0,
    this.singleBlinkMaxDuration = 400.0,
    this.longBlinkMinDuration = 600.0,
    this.doubleBlinkWindow = 700.0,
    this.winkAsymmetryRatio = 3.0,
    this.singleBlinkAccuracy = 0.0,
    this.doubleBlinkAccuracy = 0.0,
    this.longBlinkAccuracy = 0.0,
    this.falsePositiveRate = 0.0,
  });

  /// Overall calibration quality: average accuracy minus false-positive penalty.
  double get overallQuality {
    final avg =
        (singleBlinkAccuracy + doubleBlinkAccuracy + longBlinkAccuracy) / 3;
    return (avg - falsePositiveRate).clamp(0.0, 1.0);
  }

  bool get isCalibrated => overallQuality > 0.5;

  BlinkProfile copyWith({
    double? fp1Threshold,
    double? fp2Threshold,
    double? singleBlinkMaxDuration,
    double? longBlinkMinDuration,
    double? doubleBlinkWindow,
    double? winkAsymmetryRatio,
    double? singleBlinkAccuracy,
    double? doubleBlinkAccuracy,
    double? longBlinkAccuracy,
    double? falsePositiveRate,
  }) {
    return BlinkProfile(
      id: id,
      createdAt: createdAt,
      deviceId: deviceId,
      fp1Threshold: fp1Threshold ?? this.fp1Threshold,
      fp2Threshold: fp2Threshold ?? this.fp2Threshold,
      singleBlinkMaxDuration:
          singleBlinkMaxDuration ?? this.singleBlinkMaxDuration,
      longBlinkMinDuration: longBlinkMinDuration ?? this.longBlinkMinDuration,
      doubleBlinkWindow: doubleBlinkWindow ?? this.doubleBlinkWindow,
      winkAsymmetryRatio: winkAsymmetryRatio ?? this.winkAsymmetryRatio,
      singleBlinkAccuracy: singleBlinkAccuracy ?? this.singleBlinkAccuracy,
      doubleBlinkAccuracy: doubleBlinkAccuracy ?? this.doubleBlinkAccuracy,
      longBlinkAccuracy: longBlinkAccuracy ?? this.longBlinkAccuracy,
      falsePositiveRate: falsePositiveRate ?? this.falsePositiveRate,
    );
  }

  String encode() => jsonEncode(toJson());

  factory BlinkProfile.decode(String s) =>
      BlinkProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt?.toIso8601String(),
    'device_id': deviceId,
    'fp1_threshold': fp1Threshold,
    'fp2_threshold': fp2Threshold,
    'single_max_dur': singleBlinkMaxDuration,
    'long_min_dur': longBlinkMinDuration,
    'double_window': doubleBlinkWindow,
    'wink_asymmetry': winkAsymmetryRatio,
    'single_acc': singleBlinkAccuracy,
    'double_acc': doubleBlinkAccuracy,
    'long_acc': longBlinkAccuracy,
    'fp_rate': falsePositiveRate,
  };

  factory BlinkProfile.fromJson(Map<String, dynamic> j) => BlinkProfile(
    id: j['id'] as String,
    createdAt: j['created_at'] != null
        ? DateTime.parse(j['created_at'] as String)
        : null,
    deviceId: j['device_id'] as String?,
    fp1Threshold: (j['fp1_threshold'] as num?)?.toDouble() ?? 50.0,
    fp2Threshold: (j['fp2_threshold'] as num?)?.toDouble() ?? 50.0,
    singleBlinkMaxDuration: (j['single_max_dur'] as num?)?.toDouble() ?? 400.0,
    longBlinkMinDuration: (j['long_min_dur'] as num?)?.toDouble() ?? 600.0,
    doubleBlinkWindow: (j['double_window'] as num?)?.toDouble() ?? 700.0,
    winkAsymmetryRatio: (j['wink_asymmetry'] as num?)?.toDouble() ?? 3.0,
    singleBlinkAccuracy: (j['single_acc'] as num?)?.toDouble() ?? 0.0,
    doubleBlinkAccuracy: (j['double_acc'] as num?)?.toDouble() ?? 0.0,
    longBlinkAccuracy: (j['long_acc'] as num?)?.toDouble() ?? 0.0,
    falsePositiveRate: (j['fp_rate'] as num?)?.toDouble() ?? 0.0,
  );
}
