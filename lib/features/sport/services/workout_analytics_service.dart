import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/models/ai_models.dart';
import '../../../core/services/ai_service.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';

/// AI-powered workout analytics engine.
///
/// Provides:
/// - Real-time coaching insights during workouts
/// - Post-workout analysis with recovery recommendations
/// - Predictive insights after a few feedback cycles
class WorkoutAnalyticsService {
  final AiService _ai;

  WorkoutAnalyticsService({required AiService ai}) : _ai = ai;

  /// Generate a real-time insight based on current workout state.
  ///
  /// Called periodically during an active workout to provide voice/text prompts.
  Future<WorkoutInsight?> generateRealtimeInsight({
    required WorkoutSession session,
    required SportProfile profile,
    required int currentHr,
    required double? currentSpeedKmh,
    WorkoutEegSample? latestEeg,
    List<WorkoutSession> recentSessions = const [],
  }) async {
    try {
      final zone = profile.zoneForHr(currentHr);
      final duration = session.duration;
      final avgHr = session.hrSamples.isNotEmpty
          ? (session.hrSamples.map((s) => s.bpm).reduce((a, b) => a + b) /
                    session.hrSamples.length)
                .round()
          : currentHr;

      final prompt = StringBuffer()
        ..writeln('You are a sport coach AI inside a workout app.')
        ..writeln(
          'The user is ${profile.level.label} level, age ${profile.age}.',
        )
        ..writeln(
          'Workout: ${session.workoutType.label}, ${duration.inMinutes}min elapsed.',
        )
        ..writeln(
          'Current HR: $currentHr bpm (Zone ${zone.zone}: ${zone.name}), Avg HR: $avgHr bpm.',
        )
        ..writeln('Max HR estimate: ${profile.estimatedMaxHr} bpm.');

      if (currentSpeedKmh != null) {
        prompt.writeln(
          'Current speed: ${currentSpeedKmh.toStringAsFixed(1)} km/h.',
        );
      }

      if (latestEeg != null) {
        prompt
          ..writeln('Brain indicators (EEG):')
          ..writeln(
            '  Attention: ${(latestEeg.attention * 100).toStringAsFixed(0)}%',
          )
          ..writeln(
            '  Relaxation: ${(latestEeg.relaxation * 100).toStringAsFixed(0)}%',
          )
          ..writeln(
            '  Mental fatigue: ${(latestEeg.mentalFatigue * 100).toStringAsFixed(0)}%',
          )
          ..writeln(
            '  Cognitive load: ${(latestEeg.cognitiveLoad * 100).toStringAsFixed(0)}%',
          );
      }

      if (recentSessions.isNotEmpty) {
        final lastFeedbacks = recentSessions
            .where((s) => s.feedback != null)
            .take(3)
            .map(
              (s) =>
                  'fatigue=${s.feedback!.fatigueLevel}/10, energy=${s.feedback!.energyLevel}/10',
            )
            .join('; ');
        if (lastFeedbacks.isNotEmpty) {
          prompt.writeln('Recent session feedbacks: $lastFeedbacks');
        }
      }

      prompt.writeln();
      prompt.writeln(
        'Give ONE short coaching insight (max 15 words) for the user right now.',
      );
      prompt.writeln(
        'Focus on what matters most: fatigue warning, pace advice, zone alert, or encouragement.',
      );
      prompt.writeln(
        'Respond in JSON: {"message": "...", "type": "fatigue|energy|stress|paceAdvice|zoneAlert|encouragement|recovery"}',
      );

      final response = await _ai.chatCompletion([
        ChatMessage.system(
          'You are a real-time sport coach. Always respond with valid JSON only.',
        ),
        ChatMessage.user(prompt.toString()),
      ]);

      final json = _parseJson(response.content);
      if (json == null) return null;

      return WorkoutInsight(
        timestamp: DateTime.now(),
        message: json['message'] as String? ?? '',
        type: WorkoutInsightType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => WorkoutInsightType.encouragement,
        ),
      );
    } catch (e) {
      debugPrint('[WorkoutAnalytics] Realtime insight error: $e');
      return null;
    }
  }

  /// Generate comprehensive post-workout analysis.
  Future<WorkoutAnalysis?> analyzeWorkout({
    required WorkoutSession session,
    required SportProfile profile,
    List<WorkoutSession> history = const [],
  }) async {
    try {
      final prompt = StringBuffer()
        ..writeln('Analyze this completed workout session:')
        ..writeln()
        ..writeln('User: ${profile.level.label}, age ${profile.age}')
        ..writeln(
          'Workout: ${session.workoutType.label}, ${session.duration.inMinutes} minutes',
        )
        ..writeln(
          'HR: avg=${session.avgHr ?? "?"}, max=${session.maxHr ?? "?"}, min=${session.minHr ?? "?"}',
        );

      if (session.avgHrvMs != null) {
        prompt.writeln(
          'HRV (RMSSD): ${session.avgHrvMs!.toStringAsFixed(1)} ms',
        );
      }

      if (session.totalDistanceKm != null) {
        prompt.writeln(
          'Distance: ${session.totalDistanceKm!.toStringAsFixed(2)} km',
        );
        if (session.avgSpeedKmh != null) {
          prompt.writeln(
            'Speed: avg=${session.avgSpeedKmh!.toStringAsFixed(1)} km/h, max=${session.maxSpeedKmh?.toStringAsFixed(1) ?? "?"} km/h',
          );
        }
      }

      if (session.zoneTimeMap != null && session.zoneTimeMap!.isNotEmpty) {
        prompt.writeln('Time in HR zones:');
        for (final entry in session.zoneTimeMap!.entries) {
          final zone = profile.hrZones[entry.key - 1];
          prompt.writeln(
            '  Zone ${entry.key} (${zone.name}): ${entry.value.inMinutes}min',
          );
        }
      }

      if (session.avgAttention != null || session.avgMentalFatigue != null) {
        prompt.writeln('EEG brain indicators:');
        if (session.avgAttention != null) {
          prompt.writeln(
            '  Avg attention: ${(session.avgAttention! * 100).toStringAsFixed(0)}%',
          );
        }
        if (session.avgMentalFatigue != null) {
          prompt.writeln(
            '  Avg mental fatigue: ${(session.avgMentalFatigue! * 100).toStringAsFixed(0)}%',
          );
        }
      }

      if (session.feedback != null) {
        prompt.writeln('User feedback:');
        prompt.writeln('  Fatigue: ${session.feedback!.fatigueLevel}/10');
        prompt.writeln('  Energy: ${session.feedback!.energyLevel}/10');
        if (session.feedback!.rpe != null) {
          prompt.writeln('  RPE: ${session.feedback!.rpe}/10');
        }
        if (session.feedback!.note != null) {
          prompt.writeln('  Note: ${session.feedback!.note}');
        }
      }

      if (history.isNotEmpty) {
        prompt.writeln();
        prompt.writeln('Recent workout history (${history.length} sessions):');
        for (final h in history.take(5)) {
          prompt.writeln(
            '  ${h.workoutType.label} ${h.duration.inMinutes}min, avgHR=${h.avgHr ?? "?"}, feedback=${h.feedback != null ? "fatigue=${h.feedback!.fatigueLevel}, energy=${h.feedback!.energyLevel}" : "none"}',
          );
        }
      }

      prompt.writeln();
      prompt.writeln('Respond in JSON:');
      prompt.writeln('{');
      prompt.writeln('  "summary": "2-3 sentence workout summary",');
      prompt.writeln('  "score": <1-100 performance score>,');
      prompt.writeln('  "fatigue": "fatigue assessment sentence",');
      prompt.writeln('  "recovery": "recovery recommendation sentence",');
      prompt.writeln(
        '  "recoveryMinutes": <estimated recovery time in minutes>,',
      );
      prompt.writeln('  "highlights": ["...", "..."],');
      prompt.writeln('  "improvements": ["...", "..."]');
      if (session.avgAttention != null || session.avgMentalFatigue != null) {
        prompt.writeln(
          '  ,"eegInsight": "insight about brain state during workout"',
        );
      }
      prompt.writeln('}');

      final response = await _ai.chatCompletion([
        ChatMessage.system(
          'You are an expert sport scientist and coach. Analyze workouts and provide evidence-based insights. Always respond with valid JSON only.',
        ),
        ChatMessage.user(prompt.toString()),
      ]);

      final json = _parseJson(response.content);
      if (json == null) return null;

      return WorkoutAnalysis.fromJson({
        ...json,
        'generatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[WorkoutAnalytics] Post-workout analysis error: $e');
      return null;
    }
  }

  /// Generate a prediction/recommendation before starting a workout.
  ///
  /// Requires at least 3 previous sessions with feedback.
  Future<String?> generatePreWorkoutPrediction({
    required SportProfile profile,
    required List<WorkoutSession> history,
    required WorkoutType plannedType,
  }) async {
    if (history.where((s) => s.feedback != null).length < 3) return null;

    try {
      final recentWithFeedback = history
          .where((s) => s.isFinished && s.feedback != null)
          .take(5)
          .toList();

      final prompt = StringBuffer()
        ..writeln(
          'Based on this athlete\'s recent training data, predict their readiness for today\'s ${plannedType.label} workout.',
        )
        ..writeln()
        ..writeln('Athlete: ${profile.level.label}, age ${profile.age}')
        ..writeln()
        ..writeln('Recent sessions:');

      for (final s in recentWithFeedback) {
        final daysSince = DateTime.now()
            .difference(s.endTime ?? s.startTime)
            .inDays;
        prompt.writeln(
          '  ${daysSince}d ago: ${s.workoutType.label} ${s.duration.inMinutes}min, '
          'avgHR=${s.avgHr ?? "?"}, '
          'fatigue=${s.feedback!.fatigueLevel}/10, '
          'energy=${s.feedback!.energyLevel}/10'
          '${s.avgMentalFatigue != null ? ", mentalFatigue=${(s.avgMentalFatigue! * 100).toStringAsFixed(0)}%" : ""}',
        );
      }

      prompt.writeln();
      prompt.writeln(
        'Give a 2-3 sentence prediction about their energy/fatigue levels and one actionable recommendation. Keep it conversational and encouraging.',
      );

      final response = await _ai.chatCompletion([
        ChatMessage.system(
          'You are a supportive sport coach. Be encouraging but honest about recovery needs.',
        ),
        ChatMessage.user(prompt.toString()),
      ]);

      return response.content.trim();
    } catch (e) {
      debugPrint('[WorkoutAnalytics] Prediction error: $e');
      return null;
    }
  }

  Map<String, dynamic>? _parseJson(String raw) {
    try {
      // Strip markdown code fences if present
      var cleaned = raw.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned
            .replaceFirst(RegExp(r'^```\w*\n?'), '')
            .replaceFirst(RegExp(r'\n?```$'), '');
      }
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WorkoutAnalytics] JSON parse error: $e\nRaw: $raw');
      return null;
    }
  }
}
