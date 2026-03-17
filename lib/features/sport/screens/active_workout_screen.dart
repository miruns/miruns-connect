import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/ble_heart_rate_service.dart';
import '../../../core/services/gps_metrics_service.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';
import '../services/voice_coach_service.dart';
import '../services/workout_service.dart';
import '../widgets/sport_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Active Workout — full-screen real-time training interface
//
// Shows:
//   · Elapsed timer (large, always visible)
//   · HR zone ring (center hero element)
//   · Live metrics grid (pace, distance, calories estimate)
//   · Brain state indicators (when EEG headband connected)
//   · AI coaching insights (scrolling ticker)
//   · Phase controls (warmup → active → cooldown → finish)
// ─────────────────────────────────────────────────────────────────────────────

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  final WorkoutType workoutType;

  const ActiveWorkoutScreen({super.key, required this.workoutType});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  late final WorkoutService _workoutService;
  late final BleHeartRateService _bleHrService;
  late final GpsMetricsService _gpsService;
  late final VoiceCoachService _voiceCoach;

  late WorkoutSession _session;
  late SportProfile _profile;

  // Live state
  int _currentHr = 0;
  GpsMetrics _gpsMetrics = GpsMetrics.empty();
  WorkoutEegSample? _latestEeg;
  final List<WorkoutInsight> _recentInsights = [];
  Duration _elapsed = Duration.zero;

  // Streams
  StreamSubscription<BleHrReading>? _hrSub;
  StreamSubscription<GpsMetrics>? _gpsSub;
  Timer? _ticker;
  Timer? _insightTimer;
  Timer? _metricAnnounceTimer;

  // BLE state
  BleConnectionState _bleState = BleConnectionState.idle;
  StreamSubscription<BleConnectionState>? _bleStateSub;

  bool _isPaused = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _workoutService = ref.read(workoutServiceProvider);
    _bleHrService = ref.read(bleHeartRateServiceProvider);
    _gpsService = ref.read(gpsMetricsServiceProvider);
    _voiceCoach = ref.read(voiceCoachServiceProvider);

    // Create session
    _session = WorkoutSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
      workoutType: widget.workoutType,
      phase: WorkoutPhase.warmup,
    );

    _profile = const SportProfile();
    _initialize();
  }

  Future<void> _initialize() async {
    // Load profile
    _profile = await _workoutService.loadProfile();

    // Initialize voice coach
    await _voiceCoach.initialize();
    _voiceCoach.setLevel(_profile.level);
    _voiceCoach.setEnabled(_profile.voiceCoachEnabled);
    await _voiceCoach.announceWorkoutStart(widget.workoutType);

    // Start elapsed timer
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && mounted) {
        setState(
          () => _elapsed = DateTime.now().difference(_session.startTime),
        );
      }
    });

    // Start HR monitoring
    _bleState = _bleHrService.state;
    _bleStateSub = _bleHrService.stateStream.listen((state) {
      if (mounted) setState(() => _bleState = state);
    });

    if (_bleState == BleConnectionState.streaming ||
        _bleState == BleConnectionState.idle) {
      _startHrMonitoring();
    }

    // Start GPS tracking
    _startGpsTracking();

    // Start periodic AI insight generation
    _insightTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _generateInsight();
    });

    // Start periodic metric announcements (every 5 min for beginners, 3 for others)
    final announceInterval = _profile.level == SportLevel.beginner
        ? const Duration(minutes: 5)
        : const Duration(minutes: 3);
    _metricAnnounceTimer = Timer.periodic(announceInterval, (_) {
      _announceMetrics();
    });

    setState(() {});
  }

  void _startHrMonitoring() {
    _hrSub = _bleHrService.hrStream.listen((reading) {
      if (!mounted) return;
      setState(() => _currentHr = reading.bpm);

      // Record HR sample
      final sample = WorkoutHrSample(
        timestamp: DateTime.now(),
        bpm: reading.bpm,
        rrMs: reading.rrMs.isNotEmpty ? reading.rrMs.last : null,
      );
      _session = _session.copyWith(hrSamples: [..._session.hrSamples, sample]);
    });
  }

  void _startGpsTracking() {
    _gpsSub = _gpsService.startTracking().listen((metrics) {
      if (!mounted) return;
      setState(() => _gpsMetrics = metrics);

      // Record GPS sample (already throttled by the 5 m distanceFilter)
      final sample = WorkoutGpsSample(
        timestamp: DateTime.now(),
        lat: metrics.lat,
        lon: metrics.lon,
        altitudeM: metrics.altitudeM,
        speedKmh: metrics.currentSpeedKmh,
      );
      _session = _session.copyWith(
        gpsSamples: [..._session.gpsSamples, sample],
      );
    });
  }

  Future<void> _generateInsight() async {
    if (_isPaused || _currentHr == 0) return;

    try {
      final analytics = ref.read(workoutAnalyticsServiceProvider);
      final history = await _workoutService.loadWorkouts(limit: 5);
      final insight = await analytics.generateRealtimeInsight(
        session: _session,
        profile: _profile,
        currentHr: _currentHr,
        currentSpeedKmh: _gpsMetrics.currentSpeedKmh > 0
            ? _gpsMetrics.currentSpeedKmh
            : null,
        latestEeg: _latestEeg,
        recentSessions: history,
      );

      if (insight != null && mounted) {
        setState(() {
          _recentInsights.insert(0, insight);
          if (_recentInsights.length > 5) _recentInsights.removeLast();
        });

        // Speak insight through earphones
        await _voiceCoach.speakInsight(insight);
      }
    } catch (_) {}
  }

  void _announceMetrics() {
    if (_isPaused || _currentHr == 0) return;
    final zone = _profile.zoneForHr(_currentHr);
    final pace = _gpsMetrics.totalDistanceKm > 0 && _elapsed.inMinutes > 0
        ? _elapsed.inMinutes / _gpsMetrics.totalDistanceKm
        : null;

    _voiceCoach.announceMetrics(
      elapsed: _elapsed,
      currentHr: _currentHr,
      zoneName: zone.name,
      distanceKm: _gpsMetrics.totalDistanceKm > 0
          ? _gpsMetrics.totalDistanceKm
          : null,
      paceMinPerKm: pace,
    );
  }

  void _advancePhase() {
    HapticFeedback.mediumImpact();
    final next = switch (_session.phase) {
      WorkoutPhase.warmup => WorkoutPhase.active,
      WorkoutPhase.active => WorkoutPhase.cooldown,
      WorkoutPhase.cooldown => WorkoutPhase.finished,
      WorkoutPhase.finished => WorkoutPhase.finished,
    };

    setState(() {
      _session = _session.copyWith(phase: next);
    });
    _voiceCoach.announcePhaseChange(next);

    if (next == WorkoutPhase.finished) {
      _finishWorkout();
    }
  }

  void _togglePause() {
    HapticFeedback.selectionClick();
    setState(() => _isPaused = !_isPaused);
  }

  Future<void> _finishWorkout() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    // Compute summary metrics
    final hrSamples = _session.hrSamples;
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
        final zone = _profile.zoneForHr(hrSamples[i].bpm);
        final dt = hrSamples[i].timestamp.difference(
          hrSamples[i - 1].timestamp,
        );
        zoneMap[zone.zone] = (zoneMap[zone.zone] ?? Duration.zero) + dt;
      }
    }

    // EEG averages
    double? avgAttention, avgFatigue;
    if (_session.eegSamples.isNotEmpty) {
      avgAttention =
          _session.eegSamples.map((s) => s.attention).reduce((a, b) => a + b) /
          _session.eegSamples.length;
      avgFatigue =
          _session.eegSamples
              .map((s) => s.mentalFatigue)
              .reduce((a, b) => a + b) /
          _session.eegSamples.length;
    }

    // Calorie estimate (rough: based on avg HR and duration)
    int? calories;
    if (avgHr != null) {
      // Simplified calorie formula
      final weight = _profile.weightKg ?? 70.0;
      final durationHours = _elapsed.inSeconds / 3600;
      calories = ((avgHr - 55) * weight * 0.002 * 60 * durationHours).round();
      if (calories < 0) calories = 0;
    }

    final finishedSession = _session.copyWith(
      endTime: DateTime.now(),
      phase: WorkoutPhase.finished,
      totalDistanceKm: _gpsMetrics.totalDistanceKm > 0
          ? _gpsMetrics.totalDistanceKm
          : null,
      avgSpeedKmh: _gpsMetrics.averageSpeedKmh > 0
          ? _gpsMetrics.averageSpeedKmh
          : null,
      maxSpeedKmh: _gpsMetrics.maxSpeedKmh > 0 ? _gpsMetrics.maxSpeedKmh : null,
      avgHr: avgHr,
      maxHr: maxHr,
      minHr: minHr,
      avgHrvMs: avgHrvMs,
      caloriesBurned: calories,
      zoneTimeMap: zoneMap.isNotEmpty ? zoneMap : null,
      avgAttention: avgAttention,
      avgMentalFatigue: avgFatigue,
      insights: _recentInsights,
    );

    // Save to DB
    await _workoutService.saveWorkout(finishedSession);

    // Cleanup
    _hrSub?.cancel();
    _gpsSub?.cancel();
    _gpsService.stopTracking();
    _ticker?.cancel();
    _insightTimer?.cancel();
    _metricAnnounceTimer?.cancel();
    await _voiceCoach.stop();

    if (mounted) {
      // Navigate to feedback screen
      context.pushReplacement('/sport/feedback', extra: finishedSession);
    }
  }

  Future<void> _confirmStop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.current,
        title: const Text(
          'End Workout?',
          style: TextStyle(color: AppTheme.moonbeam),
        ),
        content: const Text(
          'Your progress will be saved.',
          style: TextStyle(color: AppTheme.fog),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Continue',
              style: TextStyle(color: AppTheme.fog),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End', style: TextStyle(color: AppTheme.crimson)),
          ),
        ],
      ),
    );
    if (result == true) {
      _session = _session.copyWith(phase: WorkoutPhase.finished);
      _finishWorkout();
    }
  }

  @override
  void dispose() {
    _hrSub?.cancel();
    _gpsSub?.cancel();
    _bleStateSub?.cancel();
    _gpsService.stopTracking();
    _ticker?.cancel();
    _insightTimer?.cancel();
    _metricAnnounceTimer?.cancel();
    _voiceCoach.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zone = _currentHr > 0
        ? _profile.zoneForHr(_currentHr)
        : _profile.hrZones.first;
    final zoneColor = Color(int.parse(zone.color));

    final pace = _gpsMetrics.totalDistanceKm > 0 && _elapsed.inMinutes > 0
        ? _elapsed.inMinutes / _gpsMetrics.totalDistanceKm
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmStop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.void_,
        body: SafeArea(
          child: Column(
            children: [
              // ── Top bar ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Phase badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: zoneColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _session.phase.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: zoneColor,
                        ),
                      ),
                    ),
                    // Activity label
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.workoutType.icon,
                          size: 18,
                          color: AppTheme.fog,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.workoutType.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.moonbeam,
                          ),
                        ),
                      ],
                    ),
                    // Stop button
                    GestureDetector(
                      onTap: _confirmStop,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.crimson.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.stop_rounded,
                          size: 20,
                          color: AppTheme.crimson,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Elapsed time ───────────────────────────────────────────
              Text(
                _formatDuration(_elapsed),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  color: AppTheme.moonbeam,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),

              // ── HR Zone Ring ───────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (_currentHr > 0)
                        HrZoneRing(
                          currentHr: _currentHr,
                          zone: zone,
                          maxHr: _profile.estimatedMaxHr,
                          size: 160,
                        )
                      else
                        _buildConnectHrPrompt(),

                      const SizedBox(height: 16),

                      // ── Metrics Grid ─────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_gpsMetrics.totalDistanceKm > 0)
                              MetricTile(
                                label: 'Distance',
                                value: _gpsMetrics.totalDistanceKm
                                    .toStringAsFixed(2),
                                unit: 'km',
                                icon: Icons.straighten,
                              ),
                            if (pace != null && pace < 30)
                              MetricTile(
                                label: 'Pace',
                                value: _formatPace(pace),
                                unit: '/km',
                                icon: Icons.speed,
                              ),
                            if (_gpsMetrics.currentSpeedKmh > 0)
                              MetricTile(
                                label: 'Speed',
                                value: _gpsMetrics.currentSpeedKmh
                                    .toStringAsFixed(1),
                                unit: 'km/h',
                                icon: Icons.speed,
                              ),
                            if (_gpsMetrics.altitudeM > 0)
                              MetricTile(
                                label: 'Altitude',
                                value: _gpsMetrics.altitudeM.toStringAsFixed(0),
                                unit: 'm',
                                icon: Icons.terrain,
                              ),
                          ],
                        ),
                      ),

                      // ── Brain State (EEG) ────────────────────────────
                      if (_latestEeg != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: BrainStateIndicator(
                            attention: _latestEeg!.attention,
                            relaxation: _latestEeg!.relaxation,
                            mentalFatigue: _latestEeg!.mentalFatigue,
                            cognitiveLoad: _latestEeg!.cognitiveLoad,
                          ),
                        ),
                      ],

                      // ── AI Insights ──────────────────────────────────
                      if (_recentInsights.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        ..._recentInsights
                            .take(3)
                            .map(
                              (insight) => InsightCard(
                                message: insight.message,
                                label: insight.type.label,
                              ),
                            ),
                      ],

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // ── Bottom controls ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.deepSea,
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.shimmer.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Pause / Resume
                    _ControlButton(
                      icon: _isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      label: _isPaused ? 'Resume' : 'Pause',
                      color: AppTheme.fog,
                      onTap: _togglePause,
                    ),
                    // Next Phase
                    if (_session.phase != WorkoutPhase.finished)
                      _ControlButton(
                        icon: _session.phase == WorkoutPhase.cooldown
                            ? Icons.flag_rounded
                            : Icons.skip_next_rounded,
                        label: switch (_session.phase) {
                          WorkoutPhase.warmup => 'Go Active',
                          WorkoutPhase.active => 'Cool Down',
                          WorkoutPhase.cooldown => 'Finish',
                          WorkoutPhase.finished => 'Done',
                        },
                        color: zoneColor,
                        onTap: _advancePhase,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectHrPrompt() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.favorite_border, size: 40, color: AppTheme.fog),
          const SizedBox(height: 8),
          const Text(
            'Connect a heart rate monitor',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.fog,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Workout tracking is active without HR',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.fog.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String _formatPace(double minPerKm) {
    final mins = minPerKm.floor();
    final secs = ((minPerKm - mins) * 60).round();
    return "$mins'${secs.toString().padLeft(2, '0')}\"";
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
