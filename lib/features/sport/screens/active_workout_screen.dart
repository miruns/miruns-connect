import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';
import '../widgets/sport_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Active Workout — full-screen real-time training interface
//
// All recording state lives in [ActiveWorkoutNotifier] so the workout
// keeps running even when the user navigates to another tab. This screen
// is a pure UI layer that reads from the notifier.
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

    // If the notifier has no active workout (e.g. finished while we were
    // building), check for a finished session to hand off.
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
              // ── Top bar ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Minimise (back arrow — keeps workout alive)
                    GestureDetector(
                      onTap: _minimise,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.shimmer.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: AppTheme.fog,
                        ),
                      ),
                    ),
                    // Phase badge + Activity label
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
                          ),
                          child: Text(
                            state.session.phase.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: zoneColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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
                _formatDuration(state.elapsed),
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
                      if (state.currentHr > 0)
                        HrZoneRing(
                          currentHr: state.currentHr,
                          zone: zone,
                          maxHr: state.profile.estimatedMaxHr,
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
                            if (state.gpsMetrics.totalDistanceKm > 0)
                              MetricTile(
                                label: 'Distance',
                                value: state.gpsMetrics.totalDistanceKm
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
                            if (state.gpsMetrics.currentSpeedKmh > 0)
                              MetricTile(
                                label: 'Speed',
                                value: state.gpsMetrics.currentSpeedKmh
                                    .toStringAsFixed(1),
                                unit: 'km/h',
                                icon: Icons.speed,
                              ),
                            if (state.gpsMetrics.altitudeM > 0)
                              MetricTile(
                                label: 'Altitude',
                                value: state.gpsMetrics.altitudeM
                                    .toStringAsFixed(0),
                                unit: 'm',
                                icon: Icons.terrain,
                              ),
                          ],
                        ),
                      ),

                      // ── Brain State (EEG) ────────────────────────────
                      if (state.latestEeg != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: BrainStateIndicator(
                            attention: state.latestEeg!.attention,
                            relaxation: state.latestEeg!.relaxation,
                            mentalFatigue: state.latestEeg!.mentalFatigue,
                            cognitiveLoad: state.latestEeg!.cognitiveLoad,
                          ),
                        ),
                      ],

                      // ── AI Insights ──────────────────────────────────
                      if (state.recentInsights.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        ...state.recentInsights
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
                      icon: state.isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      label: state.isPaused ? 'Resume' : 'Pause',
                      color: AppTheme.fog,
                      onTap: _togglePause,
                    ),
                    // Next Phase
                    if (state.session.phase != WorkoutPhase.finished)
                      _ControlButton(
                        icon: state.session.phase == WorkoutPhase.cooldown
                            ? Icons.flag_rounded
                            : Icons.skip_next_rounded,
                        label: switch (state.session.phase) {
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
        borderRadius: BorderRadius.circular(6),
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
