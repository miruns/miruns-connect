import 'dart:convert';

import 'sport_profile.dart';

/// Current phase of the workout lifecycle.
enum WorkoutPhase {
  warmup,
  active,
  cooldown,
  finished;

  String get label => switch (this) {
    warmup => 'Warm Up',
    active => 'Active',
    cooldown => 'Cool Down',
    finished => 'Finished',
  };
}

/// A single heart rate sample recorded during the workout.
class WorkoutHrSample {
  final DateTime timestamp;
  final int bpm;
  final double? rrMs;

  const WorkoutHrSample({
    required this.timestamp,
    required this.bpm,
    this.rrMs,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toIso8601String(),
    'bpm': bpm,
    if (rrMs != null) 'rr': rrMs,
  };

  factory WorkoutHrSample.fromJson(Map<String, dynamic> j) => WorkoutHrSample(
    timestamp: DateTime.parse(j['ts'] as String),
    bpm: j['bpm'] as int,
    rrMs: (j['rr'] as num?)?.toDouble(),
  );
}

/// An EEG brain indicator snapshot during workout.
class WorkoutEegSample {
  final DateTime timestamp;

  /// Relative attention index (0.0 – 1.0).
  final double attention;

  /// Relative relaxation index (0.0 – 1.0).
  final double relaxation;

  /// Cognitive load estimate (0.0 – 1.0).
  final double cognitiveLoad;

  /// Mental fatigue indicator (0.0 – 1.0, higher = more fatigued).
  final double mentalFatigue;

  const WorkoutEegSample({
    required this.timestamp,
    required this.attention,
    required this.relaxation,
    required this.cognitiveLoad,
    required this.mentalFatigue,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toIso8601String(),
    'att': attention,
    'rel': relaxation,
    'cog': cognitiveLoad,
    'fat': mentalFatigue,
  };

  factory WorkoutEegSample.fromJson(Map<String, dynamic> j) => WorkoutEegSample(
    timestamp: DateTime.parse(j['ts'] as String),
    attention: (j['att'] as num).toDouble(),
    relaxation: (j['rel'] as num).toDouble(),
    cognitiveLoad: (j['cog'] as num).toDouble(),
    mentalFatigue: (j['fat'] as num).toDouble(),
  );
}

/// A GPS breadcrumb recorded during the workout.
class WorkoutGpsSample {
  final DateTime timestamp;
  final double lat;
  final double lon;
  final double altitudeM;
  final double speedKmh;

  const WorkoutGpsSample({
    required this.timestamp,
    required this.lat,
    required this.lon,
    required this.altitudeM,
    required this.speedKmh,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toIso8601String(),
    'lat': lat,
    'lon': lon,
    'alt': altitudeM,
    'spd': speedKmh,
  };

  factory WorkoutGpsSample.fromJson(Map<String, dynamic> j) => WorkoutGpsSample(
    timestamp: DateTime.parse(j['ts'] as String),
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    altitudeM: (j['alt'] as num).toDouble(),
    speedKmh: (j['spd'] as num).toDouble(),
  );
}

/// A real-time AI insight delivered during the workout (voice or silent).
class WorkoutInsight {
  final DateTime timestamp;
  final String message;
  final WorkoutInsightType type;
  final bool spokenAloud;

  const WorkoutInsight({
    required this.timestamp,
    required this.message,
    required this.type,
    this.spokenAloud = false,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toIso8601String(),
    'msg': message,
    'type': type.name,
    'spoken': spokenAloud,
  };

  factory WorkoutInsight.fromJson(Map<String, dynamic> j) => WorkoutInsight(
    timestamp: DateTime.parse(j['ts'] as String),
    message: j['msg'] as String,
    type: WorkoutInsightType.values.firstWhere(
      (e) => e.name == j['type'],
      orElse: () => WorkoutInsightType.info,
    ),
    spokenAloud: j['spoken'] as bool? ?? false,
  );
}

enum WorkoutInsightType {
  fatigue,
  energy,
  stress,
  paceAdvice,
  zoneAlert,
  encouragement,
  recovery,
  info;

  String get emoji => switch (this) {
    fatigue => '😓',
    energy => '⚡',
    stress => '😤',
    paceAdvice => '🏃',
    zoneAlert => '❤️',
    encouragement => '💪',
    recovery => '🧘',
    info => 'ℹ️',
  };
}

/// Post-workout user feedback.
class WorkoutFeedback {
  /// 1–10 fatigue level (10 = completely exhausted).
  final int fatigueLevel;

  /// 1–10 energy level (10 = fully energized).
  final int energyLevel;

  /// Optional free-text note.
  final String? note;

  /// Optional RPE (rate of perceived exertion) 1–10.
  final int? rpe;

  /// User-reported mood after workout.
  final String? moodEmoji;

  const WorkoutFeedback({
    required this.fatigueLevel,
    required this.energyLevel,
    this.note,
    this.rpe,
    this.moodEmoji,
  });

  Map<String, dynamic> toJson() => {
    'fatigue': fatigueLevel,
    'energy': energyLevel,
    if (note != null) 'note': note,
    if (rpe != null) 'rpe': rpe,
    if (moodEmoji != null) 'mood': moodEmoji,
  };

  factory WorkoutFeedback.fromJson(Map<String, dynamic> j) => WorkoutFeedback(
    fatigueLevel: j['fatigue'] as int,
    energyLevel: j['energy'] as int,
    note: j['note'] as String?,
    rpe: j['rpe'] as int?,
    moodEmoji: j['mood'] as String?,
  );
}

/// AI-generated post-workout analysis.
class WorkoutAnalysis {
  final String summary;
  final int performanceScore;
  final String fatigueAssessment;
  final String recoveryRecommendation;
  final Duration estimatedRecoveryTime;
  final List<String> highlights;
  final List<String> improvements;
  final String? eegInsight;
  final DateTime generatedAt;

  const WorkoutAnalysis({
    required this.summary,
    required this.performanceScore,
    required this.fatigueAssessment,
    required this.recoveryRecommendation,
    required this.estimatedRecoveryTime,
    required this.highlights,
    required this.improvements,
    this.eegInsight,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'score': performanceScore,
    'fatigue': fatigueAssessment,
    'recovery': recoveryRecommendation,
    'recoveryMinutes': estimatedRecoveryTime.inMinutes,
    'highlights': highlights,
    'improvements': improvements,
    if (eegInsight != null) 'eegInsight': eegInsight,
    'generatedAt': generatedAt.toIso8601String(),
  };

  factory WorkoutAnalysis.fromJson(Map<String, dynamic> j) => WorkoutAnalysis(
    summary: j['summary'] as String? ?? '',
    performanceScore: j['score'] as int? ?? 50,
    fatigueAssessment: j['fatigue'] as String? ?? '',
    recoveryRecommendation: j['recovery'] as String? ?? '',
    estimatedRecoveryTime: Duration(
      minutes: j['recoveryMinutes'] as int? ?? 60,
    ),
    highlights: List<String>.from(j['highlights'] as List? ?? []),
    improvements: List<String>.from(j['improvements'] as List? ?? []),
    eegInsight: j['eegInsight'] as String?,
    generatedAt: j['generatedAt'] != null
        ? DateTime.parse(j['generatedAt'] as String)
        : DateTime.now(),
  );
}

/// Complete workout session persisted to the database.
class WorkoutSession {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final WorkoutType workoutType;
  final WorkoutPhase phase;

  // Recorded samples
  final List<WorkoutHrSample> hrSamples;
  final List<WorkoutEegSample> eegSamples;
  final List<WorkoutGpsSample> gpsSamples;
  final List<WorkoutInsight> insights;

  // Summary metrics (computed on finish)
  final double? totalDistanceKm;
  final double? avgSpeedKmh;
  final double? maxSpeedKmh;
  final int? avgHr;
  final int? maxHr;
  final int? minHr;
  final double? avgHrvMs;
  final int? caloriesBurned;
  final Map<int, Duration>? zoneTimeMap;

  // EEG summary
  final double? avgAttention;
  final double? avgMentalFatigue;

  // Feedback & analysis
  final WorkoutFeedback? feedback;
  final WorkoutAnalysis? analysis;

  // Linked capture ID (connects to full CaptureEntry for cross-analysis).
  final String? captureId;

  WorkoutSession({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.workoutType,
    this.phase = WorkoutPhase.warmup,
    this.hrSamples = const [],
    this.eegSamples = const [],
    this.gpsSamples = const [],
    this.insights = const [],
    this.totalDistanceKm,
    this.avgSpeedKmh,
    this.maxSpeedKmh,
    this.avgHr,
    this.maxHr,
    this.minHr,
    this.avgHrvMs,
    this.caloriesBurned,
    this.zoneTimeMap,
    this.avgAttention,
    this.avgMentalFatigue,
    this.feedback,
    this.analysis,
    this.captureId,
  });

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  bool get isFinished => endTime != null;

  WorkoutSession copyWith({
    DateTime? endTime,
    WorkoutPhase? phase,
    List<WorkoutHrSample>? hrSamples,
    List<WorkoutEegSample>? eegSamples,
    List<WorkoutGpsSample>? gpsSamples,
    List<WorkoutInsight>? insights,
    double? totalDistanceKm,
    double? avgSpeedKmh,
    double? maxSpeedKmh,
    int? avgHr,
    int? maxHr,
    int? minHr,
    double? avgHrvMs,
    int? caloriesBurned,
    Map<int, Duration>? zoneTimeMap,
    double? avgAttention,
    double? avgMentalFatigue,
    WorkoutFeedback? feedback,
    WorkoutAnalysis? analysis,
    String? captureId,
  }) => WorkoutSession(
    id: id,
    startTime: startTime,
    endTime: endTime ?? this.endTime,
    workoutType: workoutType,
    phase: phase ?? this.phase,
    hrSamples: hrSamples ?? this.hrSamples,
    eegSamples: eegSamples ?? this.eegSamples,
    gpsSamples: gpsSamples ?? this.gpsSamples,
    insights: insights ?? this.insights,
    totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
    avgSpeedKmh: avgSpeedKmh ?? this.avgSpeedKmh,
    maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
    avgHr: avgHr ?? this.avgHr,
    maxHr: maxHr ?? this.maxHr,
    minHr: minHr ?? this.minHr,
    avgHrvMs: avgHrvMs ?? this.avgHrvMs,
    caloriesBurned: caloriesBurned ?? this.caloriesBurned,
    zoneTimeMap: zoneTimeMap ?? this.zoneTimeMap,
    avgAttention: avgAttention ?? this.avgAttention,
    avgMentalFatigue: avgMentalFatigue ?? this.avgMentalFatigue,
    feedback: feedback ?? this.feedback,
    analysis: analysis ?? this.analysis,
    captureId: captureId ?? this.captureId,
  );

  // ── Serialization ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    if (endTime != null) 'endTime': endTime!.toIso8601String(),
    'workoutType': workoutType.name,
    'phase': phase.name,
    'hrSamples': hrSamples.map((s) => s.toJson()).toList(),
    'eegSamples': eegSamples.map((s) => s.toJson()).toList(),
    'gpsSamples': gpsSamples.map((s) => s.toJson()).toList(),
    'insights': insights.map((i) => i.toJson()).toList(),
    if (totalDistanceKm != null) 'totalDistanceKm': totalDistanceKm,
    if (avgSpeedKmh != null) 'avgSpeedKmh': avgSpeedKmh,
    if (maxSpeedKmh != null) 'maxSpeedKmh': maxSpeedKmh,
    if (avgHr != null) 'avgHr': avgHr,
    if (maxHr != null) 'maxHr': maxHr,
    if (minHr != null) 'minHr': minHr,
    if (avgHrvMs != null) 'avgHrvMs': avgHrvMs,
    if (caloriesBurned != null) 'caloriesBurned': caloriesBurned,
    if (zoneTimeMap != null)
      'zoneTimeMap': zoneTimeMap!.map(
        (k, v) => MapEntry(k.toString(), v.inSeconds),
      ),
    if (avgAttention != null) 'avgAttention': avgAttention,
    if (avgMentalFatigue != null) 'avgMentalFatigue': avgMentalFatigue,
    if (feedback != null) 'feedback': feedback!.toJson(),
    if (analysis != null) 'analysis': analysis!.toJson(),
    if (captureId != null) 'captureId': captureId,
  };

  factory WorkoutSession.fromJson(Map<String, dynamic> j) {
    final zoneMap = (j['zoneTimeMap'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(int.parse(k), Duration(seconds: v as int)),
    );

    return WorkoutSession(
      id: j['id'] as String,
      startTime: DateTime.parse(j['startTime'] as String),
      endTime: j['endTime'] != null
          ? DateTime.parse(j['endTime'] as String)
          : null,
      workoutType: WorkoutType.values.firstWhere(
        (e) => e.name == j['workoutType'],
        orElse: () => WorkoutType.running,
      ),
      phase: WorkoutPhase.values.firstWhere(
        (e) => e.name == j['phase'],
        orElse: () => WorkoutPhase.finished,
      ),
      hrSamples:
          (j['hrSamples'] as List<dynamic>?)
              ?.map((e) => WorkoutHrSample.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      eegSamples:
          (j['eegSamples'] as List<dynamic>?)
              ?.map((e) => WorkoutEegSample.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      gpsSamples:
          (j['gpsSamples'] as List<dynamic>?)
              ?.map((e) => WorkoutGpsSample.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      insights:
          (j['insights'] as List<dynamic>?)
              ?.map((e) => WorkoutInsight.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalDistanceKm: (j['totalDistanceKm'] as num?)?.toDouble(),
      avgSpeedKmh: (j['avgSpeedKmh'] as num?)?.toDouble(),
      maxSpeedKmh: (j['maxSpeedKmh'] as num?)?.toDouble(),
      avgHr: j['avgHr'] as int?,
      maxHr: j['maxHr'] as int?,
      minHr: j['minHr'] as int?,
      avgHrvMs: (j['avgHrvMs'] as num?)?.toDouble(),
      caloriesBurned: j['caloriesBurned'] as int?,
      zoneTimeMap: zoneMap,
      avgAttention: (j['avgAttention'] as num?)?.toDouble(),
      avgMentalFatigue: (j['avgMentalFatigue'] as num?)?.toDouble(),
      feedback: j['feedback'] != null
          ? WorkoutFeedback.fromJson(j['feedback'] as Map<String, dynamic>)
          : null,
      analysis: j['analysis'] != null
          ? WorkoutAnalysis.fromJson(j['analysis'] as Map<String, dynamic>)
          : null,
      captureId: j['captureId'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());
  static WorkoutSession decode(String raw) =>
      WorkoutSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
