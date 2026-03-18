import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../core/services/ble_heart_rate_service.dart';
import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/gps_metrics_service.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';
import 'eeg_metrics_service.dart';
import 'voice_coach_service.dart';
import 'workout_analytics_service.dart';
import 'workout_service.dart';

/// Immutable snapshot of the active workout state, consumed by UI.
class ActiveWorkoutState {
  final WorkoutSession session;
  final SportProfile profile;
  final int currentHr;
  final GpsMetrics gpsMetrics;
  final WorkoutEegSample? latestEeg;
  final List<WorkoutInsight> recentInsights;
  final Duration elapsed;
  final bool isPaused;
  final bool isFinishing;
  final BleConnectionState bleState;

  const ActiveWorkoutState({
    required this.session,
    required this.profile,
    this.currentHr = 0,
    required this.gpsMetrics,
    this.latestEeg,
    this.recentInsights = const [],
    this.elapsed = Duration.zero,
    this.isPaused = false,
    this.isFinishing = false,
    this.bleState = BleConnectionState.idle,
  });

  ActiveWorkoutState copyWith({
    WorkoutSession? session,
    SportProfile? profile,
    int? currentHr,
    GpsMetrics? gpsMetrics,
    WorkoutEegSample? latestEeg,
    List<WorkoutInsight>? recentInsights,
    Duration? elapsed,
    bool? isPaused,
    bool? isFinishing,
    BleConnectionState? bleState,
  }) => ActiveWorkoutState(
    session: session ?? this.session,
    profile: profile ?? this.profile,
    currentHr: currentHr ?? this.currentHr,
    gpsMetrics: gpsMetrics ?? this.gpsMetrics,
    latestEeg: latestEeg ?? this.latestEeg,
    recentInsights: recentInsights ?? this.recentInsights,
    elapsed: elapsed ?? this.elapsed,
    isPaused: isPaused ?? this.isPaused,
    isFinishing: isFinishing ?? this.isFinishing,
    bleState: bleState ?? this.bleState,
  );
}

/// Manages the active workout lifecycle independently of any screen.
///
/// Lives in the Riverpod container so the workout keeps recording when the
/// user navigates to other tabs (Sport home, Capture, etc.). A compact
/// [ActiveWorkoutBanner] reads this notifier to show a music-player-style
/// strip on every screen while a workout is running.
class ActiveWorkoutNotifier extends ChangeNotifier {
  ActiveWorkoutNotifier({
    required BleHeartRateService bleHrService,
    required GpsMetricsService gpsService,
    required VoiceCoachService voiceCoach,
    required WorkoutService workoutService,
    required WorkoutAnalyticsService analyticsService,
    required BleSourceService bleSourceService,
  }) : _bleHrService = bleHrService,
       _gpsService = gpsService,
       _voiceCoach = voiceCoach,
       _workoutService = workoutService,
       _analyticsService = analyticsService,
       _bleSourceService = bleSourceService;

  final BleHeartRateService _bleHrService;
  final GpsMetricsService _gpsService;
  final VoiceCoachService _voiceCoach;
  final WorkoutService _workoutService;
  final WorkoutAnalyticsService _analyticsService;
  final BleSourceService _bleSourceService;

  ActiveWorkoutState? _state;

  // Subscriptions & timers
  StreamSubscription<BleHrReading>? _hrSub;
  StreamSubscription<GpsMetrics>? _gpsSub;
  StreamSubscription<WorkoutEegSample>? _eegSub;
  StreamSubscription<BleConnectionState>? _bleStateSub;
  EegMetricsService? _eegMetrics;
  Timer? _ticker;
  Timer? _insightTimer;
  Timer? _metricAnnounceTimer;

  /// `null` when no workout is running.
  ActiveWorkoutState? get state => _state;

  /// Whether a workout is currently active.
  bool get isActive => _state != null;

  /// The finished session — set after [finishWorkout] completes.
  WorkoutSession? _finishedSession;
  WorkoutSession? get finishedSession => _finishedSession;

  /// Consume the finished session (returns it once, then clears).
  WorkoutSession? consumeFinishedSession() {
    final s = _finishedSession;
    _finishedSession = null;
    return s;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Start a new workout. Initialises all tracking streams and timers.
  Future<void> startWorkout(WorkoutType type) async {
    // Prevent double-start
    if (_state != null) return;

    _finishedSession = null;

    final profile = await _workoutService.loadProfile();

    final session = WorkoutSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
      workoutType: type,
      phase: WorkoutPhase.warmup,
    );

    _state = ActiveWorkoutState(
      session: session,
      profile: profile,
      gpsMetrics: GpsMetrics.empty(),
    );
    notifyListeners();

    // Voice coach
    await _voiceCoach.initialize();
    _voiceCoach.setLevel(profile.level);
    _voiceCoach.setEnabled(profile.voiceCoachEnabled);
    await _voiceCoach.announceWorkoutStart(type);

    // Elapsed ticker
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state == null || _state!.isPaused) return;
      _state = _state!.copyWith(
        elapsed: DateTime.now().difference(_state!.session.startTime),
      );
      notifyListeners();
    });

    // BLE state
    _state = _state!.copyWith(bleState: _bleHrService.state);
    _bleStateSub = _bleHrService.stateStream.listen((s) {
      if (_state == null) return;
      _state = _state!.copyWith(bleState: s);
      notifyListeners();
    });

    // HR monitoring
    _startHrMonitoring();

    // GPS tracking
    _startGpsTracking();

    // EEG monitoring
    _startEegMonitoring();

    // Periodic AI insight generation
    _insightTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _generateInsight();
    });

    // Metric announcements
    final announceInterval = profile.level == SportLevel.beginner
        ? const Duration(minutes: 5)
        : const Duration(minutes: 3);
    _metricAnnounceTimer = Timer.periodic(announceInterval, (_) {
      _announceMetrics();
    });

    // Update foreground notification
    _updateForegroundNotification();
  }

  void _startHrMonitoring() {
    _hrSub = _bleHrService.hrStream.listen((reading) {
      if (_state == null) return;
      _state = _state!.copyWith(currentHr: reading.bpm);

      if (!_state!.isPaused) {
        final sample = WorkoutHrSample(
          timestamp: DateTime.now(),
          bpm: reading.bpm,
          rrMs: reading.rrMs.isNotEmpty ? reading.rrMs.last : null,
        );
        _state = _state!.copyWith(
          session: _state!.session.copyWith(
            hrSamples: [..._state!.session.hrSamples, sample],
          ),
        );
      }
      notifyListeners();
    });
  }

  void _startGpsTracking() {
    _gpsSub = _gpsService.startTracking().listen((metrics) {
      if (_state == null) return;
      _state = _state!.copyWith(gpsMetrics: metrics);

      if (!_state!.isPaused) {
        final sample = WorkoutGpsSample(
          timestamp: DateTime.now(),
          lat: metrics.lat,
          lon: metrics.lon,
          altitudeM: metrics.altitudeM,
          speedKmh: metrics.currentSpeedKmh,
        );
        _state = _state!.copyWith(
          session: _state!.session.copyWith(
            gpsSamples: [..._state!.session.gpsSamples, sample],
          ),
        );
      }
      notifyListeners();
    });
  }

  void _startEegMonitoring() {
    if (!_bleSourceService.isStreaming) return;

    _eegMetrics = EegMetricsService(_bleSourceService.signalStream);
    _eegSub = _eegMetrics!.metricsStream.listen((sample) {
      if (_state == null) return;
      _state = _state!.copyWith(latestEeg: sample);

      if (!_state!.isPaused) {
        _state = _state!.copyWith(
          session: _state!.session.copyWith(
            eegSamples: [..._state!.session.eegSamples, sample],
          ),
        );
      }
      notifyListeners();
    });
  }

  Future<void> _generateInsight() async {
    final s = _state;
    if (s == null || s.isPaused || s.currentHr == 0) return;

    try {
      final history = await _workoutService.loadWorkouts(limit: 5);
      final insight = await _analyticsService.generateRealtimeInsight(
        session: s.session,
        profile: s.profile,
        currentHr: s.currentHr,
        currentSpeedKmh: s.gpsMetrics.currentSpeedKmh > 0
            ? s.gpsMetrics.currentSpeedKmh
            : null,
        latestEeg: s.latestEeg,
        recentSessions: history,
      );

      if (insight != null && _state != null) {
        final insights = [insight, ..._state!.recentInsights];
        _state = _state!.copyWith(
          recentInsights: insights.length > 5
              ? insights.sublist(0, 5)
              : insights,
        );
        notifyListeners();
        await _voiceCoach.speakInsight(insight);
      }
    } catch (_) {}
  }

  void _announceMetrics() {
    final s = _state;
    if (s == null || s.isPaused || s.currentHr == 0) return;

    final zone = s.profile.zoneForHr(s.currentHr);
    final pace = s.gpsMetrics.totalDistanceKm > 0 && s.elapsed.inMinutes > 0
        ? s.elapsed.inMinutes / s.gpsMetrics.totalDistanceKm
        : null;

    _voiceCoach.announceMetrics(
      elapsed: s.elapsed,
      currentHr: s.currentHr,
      zoneName: zone.name,
      distanceKm: s.gpsMetrics.totalDistanceKm > 0
          ? s.gpsMetrics.totalDistanceKm
          : null,
      paceMinPerKm: pace,
    );
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  void togglePause() {
    if (_state == null) return;
    _state = _state!.copyWith(isPaused: !_state!.isPaused);
    notifyListeners();
    _updateForegroundNotification();
  }

  void advancePhase() {
    if (_state == null) return;

    final next = switch (_state!.session.phase) {
      WorkoutPhase.warmup => WorkoutPhase.active,
      WorkoutPhase.active => WorkoutPhase.cooldown,
      WorkoutPhase.cooldown => WorkoutPhase.finished,
      WorkoutPhase.finished => WorkoutPhase.finished,
    };

    _state = _state!.copyWith(session: _state!.session.copyWith(phase: next));
    notifyListeners();
    _voiceCoach.announcePhaseChange(next);

    if (next == WorkoutPhase.finished) {
      finishWorkout();
    }
  }

  /// End the workout, compute summaries, save to DB, and tear down streams.
  Future<void> finishWorkout() async {
    if (_state == null || _state!.isFinishing) return;
    _state = _state!.copyWith(isFinishing: true);
    notifyListeners();

    final session = _state!.session;
    final profile = _state!.profile;
    final elapsed = _state!.elapsed;
    final gpsMetrics = _state!.gpsMetrics;

    // Compute summary metrics
    final hrSamples = session.hrSamples;
    int? avgHr, maxHr, minHr;
    double? avgHrvMs;

    if (hrSamples.isNotEmpty) {
      final bpms = hrSamples.map((s) => s.bpm).toList();
      avgHr = (bpms.reduce((a, b) => a + b) / bpms.length).round();
      maxHr = bpms.reduce((a, b) => a > b ? a : b);
      minHr = bpms.reduce((a, b) => a < b ? a : b);

      final rrs = hrSamples
          .where((s) => s.rrMs != null)
          .map((s) => s.rrMs!)
          .toList();
      if (rrs.length > 1) {
        var sumSqDiffs = 0.0;
        for (var i = 1; i < rrs.length; i++) {
          final diff = rrs[i] - rrs[i - 1];
          sumSqDiffs += diff * diff;
        }
        avgHrvMs = sqrt(sumSqDiffs / (rrs.length - 1));
      }
    }

    // Zone time map
    final zoneMap = <int, Duration>{};
    if (hrSamples.length > 1) {
      for (var i = 1; i < hrSamples.length; i++) {
        final zone = profile.zoneForHr(hrSamples[i].bpm);
        final dt = hrSamples[i].timestamp.difference(
          hrSamples[i - 1].timestamp,
        );
        zoneMap[zone.zone] = (zoneMap[zone.zone] ?? Duration.zero) + dt;
      }
    }

    // EEG averages
    double? avgAttention, avgFatigue;
    if (session.eegSamples.isNotEmpty) {
      avgAttention =
          session.eegSamples.map((s) => s.attention).reduce((a, b) => a + b) /
          session.eegSamples.length;
      avgFatigue =
          session.eegSamples
              .map((s) => s.mentalFatigue)
              .reduce((a, b) => a + b) /
          session.eegSamples.length;
    }

    // Calorie estimate
    int? calories;
    if (avgHr != null) {
      final weight = profile.weightKg ?? 70.0;
      final durationHours = elapsed.inSeconds / 3600;
      calories = ((avgHr - 55) * weight * 0.002 * 60 * durationHours).round();
      if (calories < 0) calories = 0;
    }

    final finishedSession = session.copyWith(
      endTime: DateTime.now(),
      phase: WorkoutPhase.finished,
      totalDistanceKm: gpsMetrics.totalDistanceKm > 0
          ? gpsMetrics.totalDistanceKm
          : null,
      avgSpeedKmh: gpsMetrics.averageSpeedKmh > 0
          ? gpsMetrics.averageSpeedKmh
          : null,
      maxSpeedKmh: gpsMetrics.maxSpeedKmh > 0 ? gpsMetrics.maxSpeedKmh : null,
      avgHr: avgHr,
      maxHr: maxHr,
      minHr: minHr,
      avgHrvMs: avgHrvMs,
      caloriesBurned: calories,
      zoneTimeMap: zoneMap.isNotEmpty ? zoneMap : null,
      avgAttention: avgAttention,
      avgMentalFatigue: avgFatigue,
      insights: _state!.recentInsights,
    );

    // Save to DB
    await _workoutService.saveWorkout(finishedSession);

    // Tear down
    _cancelSubscriptions();
    await _voiceCoach.stop();

    _finishedSession = finishedSession;
    _state = null;
    notifyListeners();

    // Restore foreground notification
    _restoreForegroundNotification();
  }

  void _cancelSubscriptions() {
    _hrSub?.cancel();
    _hrSub = null;
    _gpsSub?.cancel();
    _gpsSub = null;
    _eegSub?.cancel();
    _eegSub = null;
    _bleStateSub?.cancel();
    _bleStateSub = null;
    _eegMetrics?.dispose();
    _eegMetrics = null;
    _gpsService.stopTracking();
    _ticker?.cancel();
    _ticker = null;
    _insightTimer?.cancel();
    _insightTimer = null;
    _metricAnnounceTimer?.cancel();
    _metricAnnounceTimer = null;
  }

  // ── Foreground notification ───────────────────────────────────────────────

  void _updateForegroundNotification() {
    final s = _state;
    if (s == null) return;

    final type = s.session.workoutType.label;
    final paused = s.isPaused ? ' (Paused)' : '';
    final elapsed = _formatDuration(s.elapsed);
    final hr = s.currentHr > 0 ? ' · ${s.currentHr} bpm' : '';

    FlutterForegroundTask.updateService(
      notificationTitle: '🏃 $type$paused',
      notificationText: '$elapsed$hr',
    ).ignore();
  }

  void _restoreForegroundNotification() {
    FlutterForegroundTask.updateService(
      notificationTitle: '🫀 Miruns',
      notificationText: 'Tracking your activity',
    ).ignore();
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _voiceCoach.dispose();
    super.dispose();
  }
}
