import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/sport_profile.dart';
import '../models/workout_session.dart';

/// Voice coaching service — delivers audio prompts through earphones
/// during workouts. Adapts verbosity based on user's sport level.
///
/// Uses platform TTS (no network needed) so it works offline and
/// with any Bluetooth headphones.
class VoiceCoachService {
  FlutterTts? _tts;
  bool _initialized = false;
  bool _enabled = true;
  bool _speaking = false;

  /// Queue to avoid overlapping speech.
  final List<String> _queue = [];
  Timer? _cooldown;

  /// Minimum interval between voice prompts per level.
  static const _cooldownByLevel = {
    SportLevel.beginner: Duration(seconds: 45),
    SportLevel.intermediate: Duration(seconds: 30),
    SportLevel.advanced: Duration(seconds: 20),
  };

  SportLevel _level = SportLevel.beginner;

  bool get isEnabled => _enabled;

  Future<void> initialize() async {
    if (_initialized) return;
    _tts = FlutterTts();

    await _tts!.setLanguage('en-US');
    await _tts!.setSpeechRate(0.5);
    await _tts!.setVolume(0.9);
    await _tts!.setPitch(1.0);

    // Route audio to music stream so it plays through earphones.
    await _tts!.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
      IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      IosTextToSpeechAudioCategoryOptions.duckOthers,
    ]);

    _tts!.setCompletionHandler(() {
      _speaking = false;
      _processQueue();
    });

    _initialized = true;
  }

  void setLevel(SportLevel level) => _level = level;
  void setEnabled(bool enabled) => _enabled = enabled;

  /// Speak a workout start announcement.
  Future<void> announceWorkoutStart(WorkoutType type) async {
    await _speak('Starting ${type.label} workout. Let\'s go!');
  }

  /// Speak phase transition.
  Future<void> announcePhaseChange(WorkoutPhase phase) async {
    final msg = switch (phase) {
      WorkoutPhase.warmup => 'Warm up phase. Take it easy.',
      WorkoutPhase.active => 'Active phase. Push your limits!',
      WorkoutPhase.cooldown => 'Cool down. Great work, slow it down.',
      WorkoutPhase.finished => 'Workout complete. Amazing effort!',
    };
    await _speak(msg);
  }

  /// Speak an AI-generated coaching insight.
  Future<void> speakInsight(WorkoutInsight insight) async {
    if (_cooldown?.isActive == true) return;
    await _speak(insight.message);
    _cooldown = Timer(
      _cooldownByLevel[_level] ?? const Duration(seconds: 30),
      () {},
    );
  }

  /// Speak periodic metrics update (e.g. every km or every 5 min).
  Future<void> announceMetrics({
    required Duration elapsed,
    required int currentHr,
    required String zoneName,
    double? distanceKm,
    double? paceMinPerKm,
  }) async {
    if (_cooldown?.isActive == true) return;

    final parts = <String>[];
    parts.add('${elapsed.inMinutes} minutes');
    if (distanceKm != null && distanceKm > 0) {
      parts.add('${distanceKm.toStringAsFixed(1)} kilometers');
    }
    parts.add('heart rate $currentHr, zone $zoneName');
    if (paceMinPerKm != null && paceMinPerKm > 0 && paceMinPerKm < 30) {
      final paceMins = paceMinPerKm.floor();
      final paceSecs = ((paceMinPerKm - paceMins) * 60).round();
      parts.add('pace $paceMins:${paceSecs.toString().padLeft(2, '0')}');
    }

    await _speak(parts.join('. '));
    _cooldown = Timer(
      _cooldownByLevel[_level] ?? const Duration(seconds: 30),
      () {},
    );
  }

  /// Speak EEG-based mental state feedback.
  Future<void> announceEegState({
    required double attention,
    required double mentalFatigue,
  }) async {
    if (_cooldown?.isActive == true) return;

    if (mentalFatigue > 0.7) {
      await _speak('Mental fatigue detected. Consider slowing down.');
    } else if (attention > 0.8) {
      await _speak('Great focus! You\'re in the zone.');
    } else if (attention < 0.3 && mentalFatigue > 0.5) {
      await _speak('Focus dropping. Take a deep breath.');
    }

    _cooldown = Timer(const Duration(minutes: 1), () {});
  }

  /// Stop all speech and clear queue.
  Future<void> stop() async {
    _queue.clear();
    _cooldown?.cancel();
    if (_tts != null) {
      await _tts!.stop();
    }
    _speaking = false;
  }

  void dispose() {
    stop();
    _tts?.stop();
    _cooldown?.cancel();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _speak(String text) async {
    if (!_enabled || !_initialized) return;
    _queue.add(text);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_speaking || _queue.isEmpty) return;
    _speaking = true;
    final text = _queue.removeAt(0);
    try {
      await _tts!.speak(text);
    } catch (e) {
      debugPrint('[VoiceCoach] TTS error: $e');
      _speaking = false;
    }
  }
}
