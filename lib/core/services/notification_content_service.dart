import 'dart:math';

import '../models/body_blog_entry.dart';
import '../models/capture_entry.dart';
import 'local_db_service.dart';

/// Title + body pair for a notification.
typedef NotifContent = ({String title, String body});

/// Generates rich, data-driven notification content for Miruns.
///
/// Reads recent captures and blog entries to produce personalised,
/// emoji-rich notifications with real biometric data and a clear
/// call-to-action every time.
///
/// All messaging uses sport & fitness language (activity, training,
/// recovery, performance).
///
/// Designed to work both inside the main isolate (via Riverpod) and in
/// the WorkManager background isolate (direct instantiation).
class NotificationContentService {
  NotificationContentService({required LocalDbService db}) : _db = db;

  final LocalDbService _db;
  final _rng = Random();

  // ── Public API ──────────────────────────────────────────────────────────

  /// Build a personalised notification using today's actual data.
  ///
  /// Returns engaging static content when no sensor data is available yet.
  Future<NotifContent> buildSmartNotification() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Gather real data ─────────────────────────────────────────────────
      final blogEntry = await _db.loadEntry(today);
      final captures = await _db.loadCapturesForDate(today);
      final streak = await _computeStreak();
      final stats = _aggregateCaptures(captures);

      // Build a pool of data-driven candidates ──────────────────────────
      final candidates = <NotifContent>[];

      if (stats.steps != null && stats.steps! > 0) {
        candidates.addAll(_stepsMessages(stats.steps!));
      }
      if (stats.sleepHours != null && stats.sleepHours! > 0) {
        candidates.addAll(_sleepMessages(stats.sleepHours!));
      }
      if (stats.heartRate != null && stats.heartRate! > 0) {
        candidates.addAll(_heartRateMessages(stats.heartRate!));
      }
      if (stats.city != null && stats.temperatureC != null) {
        candidates.addAll(
          _weatherMessages(stats.city!, stats.temperatureC!, stats.weatherDesc),
        );
      }
      if (stats.aqiUs != null && stats.aqiUs! > 80) {
        candidates.addAll(_airQualityMessages(stats.aqiUs!, stats.city));
      }
      if (blogEntry != null) {
        candidates.addAll(_blogReadyMessages(blogEntry));
      }
      if (streak >= 2) {
        candidates.addAll(_streakMessages(streak));
      }
      if (captures.length >= 3) {
        candidates.addAll(_captureCountMessages(captures.length));
      }
      if (stats.workouts != null && stats.workouts! > 0) {
        candidates.addAll(_workoutMessages(stats.workouts!));
      }
      if (stats.calories != null && stats.calories! > 100) {
        candidates.addAll(_calorieMessages(stats.calories!));
      }

      // Return a random data-driven notification, or fall back ──────────
      if (candidates.isNotEmpty) {
        return candidates[_rng.nextInt(candidates.length)];
      }

      // No data yet today → nudge to capture
      return nudgeMessages[_rng.nextInt(nudgeMessages.length)];
    } catch (_) {
      return engagingFallbacks[_rng.nextInt(engagingFallbacks.length)];
    }
  }

  /// Whether a smart notification has already been shown today.
  Future<bool> wasSmartNotifShownToday() async {
    final raw = await _db.getSetting('last_smart_notif_date');
    if (raw == null) return false;
    final today = DateTime.now();
    final todayKey =
        '${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    return raw == todayKey;
  }

  /// Mark today's smart notification as shown.
  Future<void> markSmartNotifShown() async {
    final today = DateTime.now();
    await _db.setSetting(
      'last_smart_notif_date',
      '${today.year}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}',
    );
  }

  // ── Streak computation ────────────────────────────────────────────────

  Future<int> _computeStreak() async {
    int streak = 0;
    final now = DateTime.now();
    for (int i = 0; i < 60; i++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: i));
      final captures = await _db.loadCapturesForDate(day);
      if (captures.isEmpty) break;
      streak++;
    }
    return streak;
  }

  // ── Capture aggregation ───────────────────────────────────────────────

  _DayStats _aggregateCaptures(List<CaptureEntry> captures) {
    int? bestSteps;
    double? bestSleep;
    int? latestHr;
    double? latestTemp;
    String? latestWeather;
    String? latestCity;
    int? latestAqi;
    int? totalWorkouts;
    double? bestCalories;

    for (final c in captures) {
      final h = c.healthData;
      if (h != null) {
        if (h.steps != null && (bestSteps == null || h.steps! > bestSteps)) {
          bestSteps = h.steps;
        }
        if (h.sleepHours != null &&
            (bestSleep == null || h.sleepHours! > bestSleep)) {
          bestSleep = h.sleepHours;
        }
        if (h.heartRate != null && h.heartRate! > 0) {
          latestHr = h.heartRate;
        }
        if (h.workouts != null && h.workouts! > 0) {
          totalWorkouts = (totalWorkouts ?? 0) + h.workouts!;
        }
        if (h.calories != null &&
            (bestCalories == null || h.calories! > bestCalories)) {
          bestCalories = h.calories;
        }
      }
      final e = c.environmentData;
      if (e != null) {
        if (e.temperature != null) latestTemp = e.temperature;
        if (e.weatherDescription != null) latestWeather = e.weatherDescription;
        if (e.aqi != null) latestAqi = e.aqi;
      }
      final l = c.locationData;
      if (l != null && l.city != null) {
        latestCity = l.city;
      }
    }

    return _DayStats(
      steps: bestSteps,
      sleepHours: bestSleep,
      heartRate: latestHr,
      temperatureC: latestTemp,
      weatherDesc: latestWeather,
      city: latestCity,
      aqiUs: latestAqi,
      workouts: totalWorkouts,
      calories: bestCalories,
    );
  }

  // ── Data-driven message builders ──────────────────────────────────────

  List<NotifContent> _stepsMessages(int steps) {
    if (steps >= 10000) {
      return [
        (
          title: '🏆 ${_fmtSteps(steps)} steps — you crushed it!',
          body:
              'Incredible day of movement. See your full activity breakdown →',
        ),
        (
          title: '🔥 ${_fmtSteps(steps)} steps and counting!',
          body: 'Your legs put in serious work today. See the full stats →',
        ),
        (
          title: '🚀 ${_fmtSteps(steps)} steps! Who even are you?!',
          body:
              'Seriously impressive. Check out your complete activity report →',
        ),
      ];
    } else if (steps >= 5000) {
      return [
        (
          title: '🚶 ${_fmtSteps(steps)} steps so far — nice rhythm!',
          body: 'Good movement today. See your activity summary →',
        ),
        (
          title: '👟 ${_fmtSteps(steps)} steps in the bank',
          body: 'Solid pace today. Check your progress →',
        ),
      ];
    } else {
      return [
        (
          title: '🌱 ${_fmtSteps(steps)} steps today',
          body: 'Every step counts. See your full activity picture →',
        ),
      ];
    }
  }

  List<NotifContent> _sleepMessages(double hours) {
    final h = hours.toStringAsFixed(1);
    if (hours >= 8) {
      return [
        (
          title: '😴 ${h}h of sleep — great recovery',
          body: 'Well-rested and ready to perform. See your sleep stats →',
        ),
        (
          title: '🌙 Solid $h hours of rest last night',
          body: 'Quality recovery. See how it impacts today\'s readiness →',
        ),
      ];
    } else if (hours >= 6) {
      return [
        (
          title: '🛏️ ${h}h sleep — decent night',
          body: 'Not bad! See your recovery insights →',
        ),
      ];
    } else if (hours > 0) {
      return [
        (
          title: '⚡ Only ${h}h of sleep — recovery affected',
          body: 'Short night. Check your readiness and recovery tips →',
        ),
        (
          title: '☕ ${h}h sleep. Take it easy today.',
          body: 'Low recovery — see how it affects your training readiness →',
        ),
      ];
    }
    return [];
  }

  List<NotifContent> _heartRateMessages(int hr) {
    return [
      (
        title: '❤️ Heart rate: $hr bpm',
        body: 'See your heart rate trends and training zones →',
      ),
      (
        title: '💓 $hr bpm — check your cardio data',
        body:
            'Pulse, pace, patterns — all captured. See your heart rate insights →',
      ),
    ];
  }

  List<NotifContent> _weatherMessages(String city, double temp, String? desc) {
    final t = temp.round();
    final weather = desc ?? '';
    final weatherBit = weather.isNotEmpty ? ' · $weather' : '';
    return [
      (
        title: '🌡️ $t°C in $city$weatherBit',
        body:
            'Outdoor conditions affect performance. See how today\'s weather factors in →',
      ),
      (
        title: '📍 $city · $t°C — training conditions',
        body:
            'Temperature, air, UV — see how outdoor conditions impact your activity →',
      ),
    ];
  }

  List<NotifContent> _airQualityMessages(int aqi, String? city) {
    final where = city != null ? ' in $city' : '';
    if (aqi > 150) {
      return [
        (
          title: '🟠 AQI $aqi$where — poor air quality',
          body:
              'Air quality is low. Consider adjusting your outdoor training →',
        ),
      ];
    }
    return [
      (
        title: '🌫️ AQI $aqi$where today',
        body:
            'Air quality factors into your training conditions. Take a look →',
      ),
    ];
  }

  List<NotifContent> _blogReadyMessages(BodyBlogEntry entry) {
    final mood = entry.moodEmoji.isNotEmpty ? entry.moodEmoji : '📝';
    return [
      (
        title: '$mood "${entry.headline}"',
        body:
            '${entry.summary.length > 80 ? '${entry.summary.substring(0, 77)}…' : entry.summary} — Tap to read →',
      ),
      (
        title: '$mood Your daily journal is ready',
        body:
            '"${entry.headline}" — feeling ${entry.mood}. Open to read today\'s recap →',
      ),
      (
        title: '$mood Fresh daily recap just dropped',
        body:
            'Today\'s mood: ${entry.mood}. See your full activity & wellness summary →',
      ),
    ];
  }

  List<NotifContent> _streakMessages(int days) {
    if (days >= 30) {
      return [
        (
          title: '🏅 $days-day streak — legendary!',
          body:
              'A whole month of consistent tracking. Your dedication is paying off →',
        ),
        (
          title: '👑 $days days. You\'re unstoppable.',
          body: 'Consistency builds results. Keep the momentum going →',
        ),
      ];
    } else if (days >= 7) {
      return [
        (
          title: '🔥 $days days in a row!',
          body: 'Consistency is key to progress. Keep the streak alive →',
        ),
        (
          title: '💪 $days-day streak going strong',
          body:
              'You\'re building a solid training log. Don\'t break the chain →',
        ),
      ];
    }
    return [
      (
        title: '✨ $days-day streak!',
        body:
            'You\'re building a habit. Keep it going — today\'s activity is logged →',
      ),
    ];
  }

  List<NotifContent> _captureCountMessages(int count) {
    return [
      (
        title: '📊 $count captures logged today',
        body: 'Rich data means better insights. See what Miruns uncovered →',
      ),
      (
        title: '🎯 $count snapshots — data-rich day!',
        body: 'More captures = deeper insights. See your detailed report →',
      ),
    ];
  }

  List<NotifContent> _workoutMessages(int workouts) {
    return [
      (
        title: '💪 $workouts workout${workouts > 1 ? 's' : ''} logged today!',
        body: 'Great effort. See your training summary and stats →',
      ),
      (
        title:
            '🏋️ You showed up today — $workouts session${workouts > 1 ? 's' : ''}!',
        body: 'Effort, heart rate, recovery — see the full workout recap →',
      ),
    ];
  }

  List<NotifContent> _calorieMessages(double calories) {
    final cal = calories.round();
    return [
      (
        title: '🔥 $cal kcal burned so far',
        body: 'See your energy expenditure and calorie breakdown →',
      ),
    ];
  }

  // ── Formatting helpers ────────────────────────────────────────────────

  String _fmtSteps(int steps) {
    if (steps >= 1000) return '${(steps / 1000).toStringAsFixed(1)}K';
    return steps.toString();
  }

  // ── Static message pools ──────────────────────────────────────────────

  /// Nudge messages for days with no data yet.
  static const nudgeMessages = <NotifContent>[
    (
      title: '📱 No activity logged yet today',
      body:
          'A quick capture takes 10 seconds — get your daily tracking started →',
    ),
    (
      title: '🫣 No data captured yet today',
      body:
          'Tap to log a quick capture and start building today\'s activity picture →',
    ),
    (
      title: '👋 Hey — nothing tracked yet today',
      body: 'One quick capture now = full insights tonight. Start now →',
    ),
    (
      title: '🤫 Today\'s activity log is empty',
      body: 'Fill it with a capture. Just one tap, real data, zero effort →',
    ),
    (
      title: '⏰ Don\'t miss today\'s data',
      body:
          'Your sensors have been collecting all day. Capture them before they fade →',
    ),
    (
      title: '🫠 No captures yet — let\'s fix that',
      body: 'One capture now = real fitness insights later →',
    ),
    (
      title: '📝 Empty log today',
      body: 'A quick capture is all it takes to start tracking →',
    ),
    (
      title: '🧬 Your data is waiting to be captured',
      body: 'One tap — that\'s all it takes to log today\'s activity →',
    ),
  ];

  /// Engaging fallback messages when data can't be read.
  static const engagingFallbacks = <NotifContent>[
    (
      title: '🧬 Your daily recap is ready',
      body: 'Steps, sleep, heart rate — it\'s all there. Open Miruns →',
    ),
    (
      title: '📖 New entry in your activity journal',
      body: 'Every day tells a different story. Today\'s is waiting for you →',
    ),
    (
      title: '🔬 Your daily activity report is in',
      body: 'Real data, real insights from your day. Check it now →',
    ),
    (
      title: '💡 New insights from today\'s activity',
      body:
          'Patterns you didn\'t notice, trends worth seeing. It\'s all in today\'s recap →',
    ),
    (
      title: '🎯 Daily check-in time!',
      body:
          'Miruns has been tracking everything. See the summary — you might be surprised →',
    ),
    (
      title: '⚡ Fresh fitness insights available',
      body:
          'Heart, steps, sleep, recovery — compiled into today\'s report. Don\'t miss it →',
    ),
    (
      title: '🌟 Your daily fitness dispatch',
      body:
          'No fluff, just your real biometrics in one clear summary. Tap to read →',
    ),
    (
      title: '🧠 Miruns found interesting patterns',
      body: 'It spotted trends today. Check out the insights →',
    ),
    (
      title: '🫀 Pulse. Steps. Sleep. Performance.',
      body: 'Today\'s activity data is compiled. See your latest report →',
    ),
    (
      title: '📊 Data in, insights out',
      body: 'Miruns turned today\'s activity into actionable insights →',
    ),
    (
      title: '🌊 Today\'s activity overview',
      body: 'Energy, recovery, movement — your full daily picture →',
    ),
    (
      title: '🔋 How\'s your recovery today?',
      body:
          'Sleep, steps, and stress all factor in. See your readiness score →',
    ),
    (
      title: '💬 Your daily recap is waiting',
      body: 'Real data. Real insights. Open it →',
    ),
    (
      title: '🏅 Here\'s what Miruns captured today',
      body: 'Steps, heart rate, training — all in today\'s activity summary →',
    ),
    (
      title: '🪞 Day in review: the full breakdown',
      body: 'See your complete activity and recovery data →',
    ),
  ];
}

// ── Internal helpers ──────────────────────────────────────────────────────

class _DayStats {
  const _DayStats({
    this.steps,
    this.sleepHours,
    this.heartRate,
    this.temperatureC,
    this.weatherDesc,
    this.city,
    this.aqiUs,
    this.workouts,
    this.calories,
  });

  final int? steps;
  final double? sleepHours;
  final int? heartRate;
  final double? temperatureC;
  final String? weatherDesc;
  final String? city;
  final int? aqiUs;
  final int? workouts;
  final double? calories;
}
