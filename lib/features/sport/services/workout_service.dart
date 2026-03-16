import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/services/local_db_service.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';

/// Persistence & lifecycle management for workout sessions and sport profile.
///
/// Uses the app's shared SQLite database via [LocalDbService].
/// Workout sessions are stored as JSON blobs in the settings table
/// (key-value) for simplicity, with an index JSON for listing.
class WorkoutService {
  final LocalDbService _db;

  static const _profileKey = 'sport_profile';
  static const _workoutsIndexKey = 'workouts_index';
  static const _workoutPrefix = 'workout_';

  WorkoutService({required LocalDbService db}) : _db = db;

  // ── Sport Profile ─────────────────────────────────────────────────────────

  Future<SportProfile> loadProfile() async {
    final raw = await _db.getSetting(_profileKey);
    if (raw == null) return const SportProfile();
    try {
      return SportProfile.decode(raw);
    } catch (e) {
      debugPrint('[WorkoutService] Failed to decode profile: $e');
      return const SportProfile();
    }
  }

  Future<void> saveProfile(SportProfile profile) async {
    await _db.setSetting(_profileKey, profile.encode());
  }

  Future<bool> hasProfile() async {
    final raw = await _db.getSetting(_profileKey);
    return raw != null;
  }

  // ── Workout Sessions ──────────────────────────────────────────────────────

  Future<void> saveWorkout(WorkoutSession session) async {
    // Save the full session blob
    await _db.setSetting('$_workoutPrefix${session.id}', session.encode());

    // Update the index
    final index = await _loadIndex();
    if (!index.contains(session.id)) {
      index.insert(0, session.id);
    }
    await _db.setSetting(_workoutsIndexKey, jsonEncode(index));
  }

  Future<WorkoutSession?> loadWorkout(String id) async {
    final raw = await _db.getSetting('$_workoutPrefix$id');
    if (raw == null) return null;
    try {
      return WorkoutSession.decode(raw);
    } catch (e) {
      debugPrint('[WorkoutService] Failed to decode workout $id: $e');
      return null;
    }
  }

  Future<List<WorkoutSession>> loadWorkouts({int? limit}) async {
    final index = await _loadIndex();
    final ids = limit != null ? index.take(limit).toList() : index;
    final sessions = <WorkoutSession>[];
    for (final id in ids) {
      final session = await loadWorkout(id);
      if (session != null) sessions.add(session);
    }
    return sessions;
  }

  Future<int> countWorkouts() async {
    final index = await _loadIndex();
    return index.length;
  }

  Future<void> deleteWorkout(String id) async {
    await _db.setSetting('$_workoutPrefix$id', '');
    final index = await _loadIndex();
    index.remove(id);
    await _db.setSetting(_workoutsIndexKey, jsonEncode(index));
  }

  /// Number of completed workouts (used for prediction readiness checks).
  Future<int> countCompletedWithFeedback() async {
    final workouts = await loadWorkouts();
    return workouts.where((w) => w.isFinished && w.feedback != null).length;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<List<String>> _loadIndex() async {
    final raw = await _db.getSetting(_workoutsIndexKey);
    if (raw == null) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (e) {
      return [];
    }
  }
}
