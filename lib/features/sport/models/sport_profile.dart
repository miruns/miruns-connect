import 'dart:convert';

import 'package:flutter/material.dart';

/// User fitness level — drives coaching intensity, voice prompt frequency,
/// and workout recommendation complexity.
enum SportLevel {
  beginner,
  intermediate,
  advanced;

  String get label => switch (this) {
    beginner => 'Beginner',
    intermediate => 'Intermediate',
    advanced => 'Advanced',
  };

  IconData get icon => switch (this) {
    beginner => Icons.eco_outlined,
    intermediate => Icons.local_fire_department_outlined,
    advanced => Icons.bolt_outlined,
  };

  String get description => switch (this) {
    beginner => 'Just starting out — gentle guidance & encouragement',
    intermediate => 'Regular training — balanced feedback & targets',
    advanced => 'Serious athlete — deep analytics & performance push',
  };
}

/// The type of sport/workout activity.
enum WorkoutType {
  running,
  cycling,
  walking,
  hiit,
  strength,
  yoga,
  swimming,
  custom;

  String get label => switch (this) {
    running => 'Running',
    cycling => 'Cycling',
    walking => 'Walking',
    hiit => 'HIIT',
    strength => 'Strength',
    yoga => 'Yoga',
    swimming => 'Swimming',
    custom => 'Custom',
  };

  IconData get icon => switch (this) {
    running => Icons.directions_run_outlined,
    cycling => Icons.directions_bike_outlined,
    walking => Icons.directions_walk_outlined,
    hiit => Icons.fitness_center_outlined,
    strength => Icons.fitness_center_outlined,
    yoga => Icons.self_improvement_outlined,
    swimming => Icons.pool_outlined,
    custom => Icons.tune_outlined,
  };
}

/// Persistent user sport profile — stored in settings DB.
class SportProfile {
  final SportLevel level;
  final int age;
  final double? weightKg;
  final double? heightCm;
  final int? restingHr;
  final int? maxHr;
  final List<WorkoutType> preferredWorkouts;
  final bool voiceCoachEnabled;
  final bool eegInsightsEnabled;

  const SportProfile({
    this.level = SportLevel.beginner,
    this.age = 30,
    this.weightKg,
    this.heightCm,
    this.restingHr,
    this.maxHr,
    this.preferredWorkouts = const [WorkoutType.running],
    this.voiceCoachEnabled = true,
    this.eegInsightsEnabled = true,
  });

  /// Estimated max heart rate (Tanaka formula).
  int get estimatedMaxHr => maxHr ?? (208 - (0.7 * age)).round();

  /// HR zones as percentage of max HR.
  List<HrZone> get hrZones {
    final max = estimatedMaxHr;
    return [
      HrZone(
        zone: 1,
        name: 'Recovery',
        minBpm: (max * 0.50).round(),
        maxBpm: (max * 0.60).round(),
        color: '0xFF4CAF50',
      ),
      HrZone(
        zone: 2,
        name: 'Endurance',
        minBpm: (max * 0.60).round(),
        maxBpm: (max * 0.70).round(),
        color: '0xFF2196F3',
      ),
      HrZone(
        zone: 3,
        name: 'Tempo',
        minBpm: (max * 0.70).round(),
        maxBpm: (max * 0.80).round(),
        color: '0xFFFFC107',
      ),
      HrZone(
        zone: 4,
        name: 'Threshold',
        minBpm: (max * 0.80).round(),
        maxBpm: (max * 0.90).round(),
        color: '0xFFFF9800',
      ),
      HrZone(
        zone: 5,
        name: 'Max Effort',
        minBpm: (max * 0.90).round(),
        maxBpm: max,
        color: '0xFFFF4444',
      ),
    ];
  }

  HrZone zoneForHr(int bpm) {
    final zones = hrZones;
    for (final z in zones.reversed) {
      if (bpm >= z.minBpm) return z;
    }
    return zones.first;
  }

  SportProfile copyWith({
    SportLevel? level,
    int? age,
    double? weightKg,
    double? heightCm,
    int? restingHr,
    int? maxHr,
    List<WorkoutType>? preferredWorkouts,
    bool? voiceCoachEnabled,
    bool? eegInsightsEnabled,
  }) => SportProfile(
    level: level ?? this.level,
    age: age ?? this.age,
    weightKg: weightKg ?? this.weightKg,
    heightCm: heightCm ?? this.heightCm,
    restingHr: restingHr ?? this.restingHr,
    maxHr: maxHr ?? this.maxHr,
    preferredWorkouts: preferredWorkouts ?? this.preferredWorkouts,
    voiceCoachEnabled: voiceCoachEnabled ?? this.voiceCoachEnabled,
    eegInsightsEnabled: eegInsightsEnabled ?? this.eegInsightsEnabled,
  );

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'age': age,
    'weightKg': weightKg,
    'heightCm': heightCm,
    'restingHr': restingHr,
    'maxHr': maxHr,
    'preferredWorkouts': preferredWorkouts.map((w) => w.name).toList(),
    'voiceCoachEnabled': voiceCoachEnabled,
    'eegInsightsEnabled': eegInsightsEnabled,
  };

  factory SportProfile.fromJson(Map<String, dynamic> json) => SportProfile(
    level: SportLevel.values.firstWhere(
      (e) => e.name == json['level'],
      orElse: () => SportLevel.beginner,
    ),
    age: json['age'] as int? ?? 30,
    weightKg: (json['weightKg'] as num?)?.toDouble(),
    heightCm: (json['heightCm'] as num?)?.toDouble(),
    restingHr: json['restingHr'] as int?,
    maxHr: json['maxHr'] as int?,
    preferredWorkouts:
        (json['preferredWorkouts'] as List<dynamic>?)
            ?.map(
              (w) => WorkoutType.values.firstWhere(
                (e) => e.name == w,
                orElse: () => WorkoutType.running,
              ),
            )
            .toList() ??
        [WorkoutType.running],
    voiceCoachEnabled: json['voiceCoachEnabled'] as bool? ?? true,
    eegInsightsEnabled: json['eegInsightsEnabled'] as bool? ?? true,
  );

  String encode() => jsonEncode(toJson());
  static SportProfile decode(String raw) =>
      SportProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// A single HR training zone with boundaries and metadata.
class HrZone {
  final int zone;
  final String name;
  final int minBpm;
  final int maxBpm;
  final String color;

  const HrZone({
    required this.zone,
    required this.name,
    required this.minBpm,
    required this.maxBpm,
    required this.color,
  });
}
