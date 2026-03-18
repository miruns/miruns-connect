import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../../../../../../../../core/theme/app_theme.dart';
import '../../../core/services/service_providers.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';
import '../services/active_workout_notifier.dart';
import '../widgets/sport_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Active Workout — full-screen real-time training interface
//
// All recording state lives in [ActiveWorkoutNotifier] so the workout
// keeps running even when the user navigates to another tab. This screen
// is a pure UI layer that reads from the notifier.
//
// Shows:
//   · Elapsed timer (large, always visible) with phase sub-timer
//   · HR zone ring (center hero with glow)
//   · Phase progress strip (warmup → active → cooldown)
//   · Live metrics grid (pace, distance, speed, altitude)
//   · EEG spectral bands (δ θ α β γ with derived indices)
//   · AI coaching insights
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
  @override
  void initState() {
    super.initState();

    // Start a new workout if one isn't already running (user may be
    // returning to this screen via the banner while the workout is live).
    final notifier = ref.read(activeWorkoutProvider);
    if (!notifier.isActive) {
      notifier.startWorkout(widget.workoutType);
    }
  }

  void _advancePhase() {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(activeWorkoutProvider);
    notifier.advancePhase();

    // If workout just finished, navigate to feedback.
    final finished = notifier.consumeFinishedSession();
    if (finished != null && mounted) {
      context.pushReplacement('/sport/feedback', extra: finished);
    }
  }

  void _togglePause() {
    HapticFeedback.selectionClick();
    ref.read(activeWorkoutProvider).togglePause();
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
      final notifier = ref.read(activeWorkoutProvider);
      await notifier.finishWorkout();
      final finished = notifier.consumeFinishedSession();
      if (finished != null && mounted) {
        context.pushReplacement('/sport/feedback', extra: finished);
      }
    }
  }

  /// Navigate back to the home screen while keeping the workout alive.
  void _minimise() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/sport');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(activeWorkoutProvider);
    final state = notifier.state;

    if (state == null) {
      final finished = notifier.consumeFinishedSession();
      if (finished != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.pushReplacement('/sport/feedback', extra: finished);
          }
        });
      }
      return const Scaffold(
        backgroundColor: AppTheme.void_,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final zone = state.currentHr > 0
        ? state.profile.zoneForHr(state.currentHr)
        : state.profile.hrZones.first;
    final zoneColor = Color(int.parse(zone.color));

    final pace =
        state.gpsMetrics.totalDistanceKm > 0 && state.elapsed.inMinutes > 0
        ? state.elapsed.inMinutes / state.gpsMetrics.totalDistanceKm
        : null;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: AppTheme.void_,
        body: SafeArea(
          child: Column(
            children: [
              // ── Top bar ────────────────────────────────────────────
              _buildTopBar(state, zoneColor),
              _buildPhaseStrip(state, zoneColor),

              // ── Hero: timer + HR ring side by side ─────────────────
              _buildHeroRow(state, zone, zoneColor),

              // ── All data scrollable ────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    children: [
                      // ── Metrics strip ──────────────────────────────
                      _buildMetricsGrid(state, pace),

                      // ── EEG Spectral ───────────────────────────────
                      if (state.latestEeg != null) ...[
                        const SizedBox(height: 10),
                        EegBandsIndicator(eeg: state.latestEeg!),
                      ],

                      // ── AI Insights ────────────────────────────────
                      if (state.recentInsights.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...state.recentInsights
                            .take(3)
                            .map(
                              (insight) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: InsightCard(
                                  message: insight.message,
                                  label: insight.type.label,
                                ),
                              ),
                            ),
                      ],

                      // ── No HR prompt (only when no other data) ─────
                      if (state.currentHr <= 0 &&
                          state.latestEeg == null &&
                          state.gpsMetrics.totalDistanceKm <= 0)
                        _buildConnectHrPrompt(),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // ── Bottom controls ────────────────────────────────────
              _buildBottomControls(state, zoneColor),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────
  Widget _buildTopBar(ActiveWorkoutState state, Color zoneColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Minimise
          GestureDetector(
            onTap: _minimise,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.shimmer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: AppTheme.fog,
              ),
            ),
          ),
          // Phase + Activity
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: zoneColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: zoneColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  state.session.phase.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: zoneColor,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(widget.workoutType.icon, size: 18, color: AppTheme.fog),
              const SizedBox(width: 4),
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
          // Stop
          GestureDetector(
            onTap: _confirmStop,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.crimson.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.crimson.withValues(alpha: 0.3),
                ),
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
    );
  }

  // ── Phase progress strip ─────────────────────────────────────────────────
  Widget _buildPhaseStrip(ActiveWorkoutState state, Color zoneColor) {
    const phases = [
      WorkoutPhase.warmup,
      WorkoutPhase.active,
      WorkoutPhase.cooldown,
    ];
    final currentIdx = phases.indexOf(state.session.phase);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < phases.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              flex: i == 1 ? 3 : 1, // active phase gets more space
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: i <= currentIdx
                      ? zoneColor
                      : AppTheme.shimmer.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Hero row: timer left, HR ring right ───────────────────────────────
  Widget _buildHeroRow(ActiveWorkoutState state, HrZone zone, Color zoneColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Timer + paused label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDuration(state.elapsed),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 40,
                    fontWeight: FontWeight.w200,
                    color: AppTheme.moonbeam,
                    letterSpacing: 2,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                if (state.isPaused)
                  Text(
                    'PAUSED',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.amber,
                      letterSpacing: 3,
                    ),
                  )
                else if (state.currentHr > 0)
                  Row(
                    children: [
                      Text(
                        'Z${zone.zone}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: zoneColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        zone.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: zoneColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // Compact HR ring
          if (state.currentHr > 0)
            HrZoneRing(
              currentHr: state.currentHr,
              zone: zone,
              maxHr: state.profile.estimatedMaxHr,
              size: 100,
            ),
        ],
      ),
    );
  }

  // ── Metrics grid (3-column, compact) ─────────────────────────────────────
  Widget _buildMetricsGrid(ActiveWorkoutState state, double? pace) {
    final tiles = <_MiniMetric>[];

    if (state.gpsMetrics.totalDistanceKm > 0) {
      tiles.add(
        _MiniMetric(
          label: 'Distance',
          value: state.gpsMetrics.totalDistanceKm.toStringAsFixed(2),
          unit: 'km',
        ),
      );
    }

    if (pace != null && pace < 30) {
      tiles.add(
        _MiniMetric(label: 'Pace', value: _formatPace(pace), unit: '/km'),
      );
    }

    if (state.gpsMetrics.currentSpeedKmh > 0) {
      tiles.add(
        _MiniMetric(
          label: 'Speed',
          value: state.gpsMetrics.currentSpeedKmh.toStringAsFixed(1),
          unit: 'km/h',
        ),
      );
    }

    if (state.gpsMetrics.altitudeM > 0) {
      tiles.add(
        _MiniMetric(
          label: 'Altitude',
          value: state.gpsMetrics.altitudeM.toStringAsFixed(0),
          unit: 'm',
        ),
      );
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    // 3-col grid
    final colWidth = (MediaQuery.of(context).size.width - 48) / 3;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tiles.map((t) => SizedBox(width: colWidth, child: t)).toList(),
    );
  }

  Widget _buildConnectHrPrompt() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.favorite_border_rounded,
            size: 20,
            color: AppTheme.fog.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pair a Bluetooth HR sensor for zone tracking',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.fog.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom controls bar ──────────────────────────────────────────────────
  Widget _buildBottomControls(ActiveWorkoutState state, Color zoneColor) {
    final nextLabel = switch (state.session.phase) {
      WorkoutPhase.warmup => 'Go Active',
      WorkoutPhase.active => 'Cool Down',
      WorkoutPhase.cooldown => 'Finish',
      WorkoutPhase.finished => 'Done',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.deepSea,
        border: Border(
          top: BorderSide(color: AppTheme.shimmer.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Pause / Resume
          Expanded(
            child: GestureDetector(
              onTap: _togglePause,
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.shimmer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      state.isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 22,
                      color: AppTheme.moonbeam,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.isPaused ? 'Resume' : 'Pause',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.moonbeam,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (state.session.phase != WorkoutPhase.finished) ...[
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: _advancePhase,
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: zoneColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: zoneColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        state.session.phase == WorkoutPhase.cooldown
                            ? Icons.flag_rounded
                            : Icons.skip_next_rounded,
                        size: 20,
                        color: zoneColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        nextLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: zoneColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? accentColor;

  const _MiniMetric({
    required this.label,
    required this.value,
    this.unit,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.moonbeam;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: AppTheme.fog.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: accent,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(
                  unit!,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.fog.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
