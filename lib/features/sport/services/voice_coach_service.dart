import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/services/tts_service.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';

/// Voice coaching service — delivers audio prompts through earphones
/// during workouts. Adapts verbosity based on user's sport level.
///
/// Uses platform TTS (no network needed) so it works offline and
/// with any Bluetooth headphones.
class VoiceCoachService {
  final TtsService _tts;
  bool _initialized = false;
  bool _enabled = true;
  bool _speaking = false;

  VoiceCoachService({required TtsService tts}) : _tts = tts;

  /// Queue to avoid overlapping speech.
  final List<String> _queue = [];
  Timer? _cooldown;
  Timer? _urgentCooldown;

  static final _rng = Random();

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
    await _tts.initialize();
    _tts.onComplete = () {
      _speaking = false;
      _processQueue();
    };
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

  /// Speak an AI-generated coaching insight with companion delivery.
  ///
  /// Wraps the raw insight in a warm lead-in phrase so it feels like
  /// a real coach checking in through the earphones. Urgent insights
  /// (fatigue, stress) bypass the normal cooldown.
  Future<void> speakInsight(WorkoutInsight insight) async {
    final urgent = _isUrgent(insight.type);

    // Urgent insights use a shorter cooldown; normal ones respect full cooldown
    if (!urgent && _cooldown?.isActive == true) return;
    if (urgent && _urgentCooldown?.isActive == true) return;

    // Companion-style delivery: warm lead-in → pause → message
    final leadIn = _leadInFor(insight.type);
    final wrapped = '$leadIn. ${insight.message}';

    await _speak(wrapped, priority: urgent);

    if (urgent) {
      _urgentCooldown = Timer(const Duration(seconds: 15), () {});
    }
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
    _urgentCooldown?.cancel();
    await _tts.stop();
    _speaking = false;
  }

  void dispose() {
    stop();
    _tts.dispose();
    _cooldown?.cancel();
    _urgentCooldown?.cancel();
  }

  // ── Companion personality ─────────────────────────────────────────────────

  /// Whether this insight type is urgent enough to bypass normal cooldown.
  static bool _isUrgent(WorkoutInsightType type) => switch (type) {
    WorkoutInsightType.fatigue => true,
    WorkoutInsightType.stress => true,
    _ => false,
  };

  /// Short, warm lead-in phrase that humanises the delivery.
  ///
  /// Varies randomly so repetitive insights don't sound robotic.
  static String _leadInFor(WorkoutInsightType type) => switch (type) {
    WorkoutInsightType.fatigue => _pick([
      'Heads up',
      'Just so you know',
      'Quick check',
    ]),
    WorkoutInsightType.energy => _pick([
      'Looking good',
      'Nice one',
      'Good news',
    ]),
    WorkoutInsightType.stress => _pick([
      'Hey',
      'Take a moment',
      'Quick thought',
    ]),
    WorkoutInsightType.paceAdvice => _pick([
      'Pace check',
      'Quick note',
      'About your pace',
    ]),
    WorkoutInsightType.zoneAlert => _pick([
      'Zone update',
      'Heart rate check',
      'Quick flag',
    ]),
    WorkoutInsightType.encouragement => _pick([
      'Hey',
      'Keep it up',
      'Right there with you',
    ]),
    WorkoutInsightType.recovery => _pick([
      'Recovery note',
      'Checking in',
      'Quick update',
    ]),
    WorkoutInsightType.info => _pick([
      'Just so you know',
      'Quick update',
      'Note',
    ]),
  };

  static String _pick(List<String> options) =>
      options[_rng.nextInt(options.length)];

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _speak(String text, {bool priority = false}) async {
    if (!_enabled || !_initialized) return;
    if (priority) {
      _queue.insert(0, text);
    } else {
      _queue.add(text);
    }
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_speaking || _queue.isEmpty) return;
    _speaking = true;
    final text = _queue.removeAt(0);
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[VoiceCoach] TTS error: $e');
      _speaking = false;
    }
  }
}
