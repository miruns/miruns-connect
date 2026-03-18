import 'dart:math' as math;
import 'dart:ui';

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
// Active Workout — cinematic full-screen real-time training interface
//
// All recording state lives in [ActiveWorkoutNotifier] so the workout
// keeps running even when the user navigates to another tab. This screen
// is a pure UI layer that reads from the notifier.
// ─────────────────────────────────────────────────────────────────────────────

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  final WorkoutType workoutType;

  const ActiveWorkoutScreen({super.key, required this.workoutType});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ──
  AnimationController? _breatheCtrl;
  AnimationController? _particleCtrl;
  AnimationController? _entranceCtrl;
  AnimationController? _pulseCtrl;

  Animation<double>? _breatheAnim;
  Animation<double>? _entranceAnim;
  Animation<double>? _pulseAnim;

  bool _animsReady = false;

  @override
  void initState() {
    super.initState();

    // Slow breathing ambient glow (6s cycle)
    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _breatheAnim = CurvedAnimation(
      parent: _breatheCtrl!,
      curve: Curves.easeInOut,
    );

    // Continuous particle drift
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Entrance stagger
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _entranceAnim = CurvedAnimation(
      parent: _entranceCtrl!,
      curve: Curves.easeOutCubic,
    );

    // HR pulse (fast heartbeat feel)
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut));

    _animsReady = true;

    // Start workout if needed
    final notifier = ref.read(activeWorkoutProvider);
    if (!notifier.isActive) {
      notifier.startWorkout(widget.workoutType);
    }
  }

  @override
  void dispose() {
    _breatheCtrl?.dispose();
    _particleCtrl?.dispose();
    _entranceCtrl?.dispose();
    _pulseCtrl?.dispose();
    super.dispose();
  }

  void _advancePhase() {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(activeWorkoutProvider);
    notifier.advancePhase();

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

  void _minimise() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/sport');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_animsReady) {
      return const Scaffold(
        backgroundColor: AppTheme.void_,
        body: SizedBox.shrink(),
      );
    }

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
        body: Stack(
          children: [
            // ── Layer 0: Animated ambient background ────────────────
            _CinematicBackground(
              zoneColor: zoneColor,
              zoneNumber: zone.zone,
              breatheAnim: _breatheAnim!,
              particleAnim: _particleCtrl!,
              isPaused: state.isPaused,
            ),

            // ── Layer 1: Content ────────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(state, zoneColor),
                  _buildPhaseStrip(state, zoneColor),
                  _buildHeroRow(state, zone, zoneColor),
                  Expanded(
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: const [0, 0.02, 0.95, 1],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: _buildScrollContent(state, pace, zoneColor),
                      ),
                    ),
                  ),
                  _buildBottomControls(state, zoneColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Scroll content with staggered entrance ────────────────────────────
  Widget _buildScrollContent(
    ActiveWorkoutState state,
    double? pace,
    Color zoneColor,
  ) {
    return AnimatedBuilder(
      animation: _entranceAnim!,
      builder: (context, _) {
        return Column(
          children: [
            // Metrics
            _staggerChild(0, child: _buildMetricsGrid(state, pace)),

            // EEG
            if (state.latestEeg != null) ...[
              const SizedBox(height: 10),
              _staggerChild(1, child: EegBandsIndicator(eeg: state.latestEeg!)),
            ],

            // Insights
            if (state.recentInsights.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...state.recentInsights
                  .take(3)
                  .toList()
                  .asMap()
                  .entries
                  .map(
                    (e) => _staggerChild(
                      2 + e.key,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InsightCard(
                          message: e.value.message,
                          label: e.value.type.label,
                        ),
                      ),
                    ),
                  ),
            ],

            // No-HR prompt
            if (state.currentHr <= 0 &&
                state.latestEeg == null &&
                state.gpsMetrics.totalDistanceKm <= 0)
              _staggerChild(2, child: _buildConnectHrPrompt()),

            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /// Staggered entrance: each child slides up & fades in with a delay offset.
  Widget _staggerChild(int index, {required Widget child}) {
    final delay = (index * 0.15).clamp(0.0, 0.6);
    final end = (delay + 0.4).clamp(0.0, 1.0);
    final progress = Interval(delay, end, curve: Curves.easeOutCubic);
    final t = progress.transform(_entranceAnim!.value);
    return Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 20 * (1 - t)), child: child),
    );
  }

  // ── Top bar with glass effect ────────────────────────────────────────────
  Widget _buildTopBar(ActiveWorkoutState state, Color zoneColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Minimise — glass circle
          GestureDetector(
            onTap: _minimise,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: AppTheme.fog,
                  ),
                ),
              ),
            ),
          ),
          // Phase badge + Activity label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing phase badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: zoneColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: zoneColor.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: zoneColor.withValues(alpha: 0.2),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Text(
                  state.session.phase.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: zoneColor,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                widget.workoutType.icon,
                size: 18,
                color: AppTheme.fog.withValues(alpha: 0.8),
              ),
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
          // Stop — crimson glass with glow
          GestureDetector(
            onTap: _confirmStop,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.crimson.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.crimson.withValues(alpha: 0.25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.crimson.withValues(alpha: 0.15),
                    blurRadius: 10,
                    spreadRadius: -2,
                  ),
                ],
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

  // ── Phase strip with animated glow on active segment ─────────────────────
  Widget _buildPhaseStrip(ActiveWorkoutState state, Color zoneColor) {
    const phases = [
      WorkoutPhase.warmup,
      WorkoutPhase.active,
      WorkoutPhase.cooldown,
    ];
    final currentIdx = phases.indexOf(state.session.phase);

    return AnimatedBuilder(
      animation: _breatheAnim!,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (var i = 0; i < phases.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  flex: i == 1 ? 3 : 1,
                  child: Container(
                    height: i == currentIdx ? 4 : 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: i < currentIdx
                          ? zoneColor.withValues(alpha: 0.6)
                          : i == currentIdx
                          ? zoneColor
                          : AppTheme.shimmer.withValues(alpha: 0.2),
                      boxShadow: i == currentIdx
                          ? [
                              BoxShadow(
                                color: zoneColor.withValues(
                                  alpha: 0.3 + _breatheAnim!.value * 0.3,
                                ),
                                blurRadius: 8 + _breatheAnim!.value * 4,
                                spreadRadius: -1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Hero row: cinematic timer + BPM readout ──────────────────────────
  Widget _buildHeroRow(ActiveWorkoutState state, HrZone zone, Color zoneColor) {
    return AnimatedBuilder(
      animation: _pulseAnim!,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Timer with ambient glow
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Giant timer with zone-color glow
                    Text(
                      _formatDuration(state.elapsed),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 44,
                        fontWeight: FontWeight.w200,
                        color: AppTheme.moonbeam,
                        letterSpacing: 2,
                        height: 1.0,
                        shadows: state.currentHr > 0
                            ? [
                                Shadow(
                                  color: zoneColor.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (state.isPaused)
                      // Pulsing PAUSED label
                      Opacity(
                        opacity: 0.5 + _pulseAnim!.value * 0.5,
                        child: Text(
                          'PAUSED',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.amber,
                            letterSpacing: 4,
                          ),
                        ),
                      )
                    else if (state.currentHr > 0)
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: zoneColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Z${zone.zone}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: zoneColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
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
              // Large BPM readout (no circle)
              if (state.currentHr > 0)
                Transform.scale(
                  scale: _pulseAnim!.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${state.currentHr}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 52,
                          fontWeight: FontWeight.w300,
                          color: zoneColor,
                          height: 1.0,
                          shadows: [
                            Shadow(
                              color: zoneColor.withValues(alpha: 0.4),
                              blurRadius: 30,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'bpm',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: zoneColor.withValues(alpha: 0.6),
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Metrics grid — glass morphism tiles ──────────────────────────────────
  Widget _buildMetricsGrid(ActiveWorkoutState state, double? pace) {
    final tiles = <_CinematicMetric>[];

    if (state.gpsMetrics.totalDistanceKm > 0) {
      tiles.add(
        _CinematicMetric(
          label: 'Distance',
          value: state.gpsMetrics.totalDistanceKm.toStringAsFixed(2),
          unit: 'km',
        ),
      );
    }

    if (pace != null && pace < 30) {
      tiles.add(
        _CinematicMetric(label: 'Pace', value: _formatPace(pace), unit: '/km'),
      );
    }

    if (state.gpsMetrics.currentSpeedKmh > 0) {
      tiles.add(
        _CinematicMetric(
          label: 'Speed',
          value: state.gpsMetrics.currentSpeedKmh.toStringAsFixed(1),
          unit: 'km/h',
        ),
      );
    }

    if (state.gpsMetrics.altitudeM > 0) {
      tiles.add(
        _CinematicMetric(
          label: 'Altitude',
          value: state.gpsMetrics.altitudeM.toStringAsFixed(0),
          unit: 'm',
        ),
      );
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    final colWidth = (MediaQuery.of(context).size.width - 48) / 3;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tiles.map((t) => SizedBox(width: colWidth, child: t)).toList(),
    );
  }

  Widget _buildConnectHrPrompt() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.favorite_border_rounded,
                size: 20,
                color: AppTheme.fog.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pair a Bluetooth HR sensor for zone tracking',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.fog.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom controls — glass bar with glowing action button ───────────────
  Widget _buildBottomControls(ActiveWorkoutState state, Color zoneColor) {
    final nextLabel = switch (state.session.phase) {
      WorkoutPhase.warmup => 'Go Active',
      WorkoutPhase.active => 'Cool Down',
      WorkoutPhase.cooldown => 'Finish',
      WorkoutPhase.finished => 'Done',
    };

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.deepSea.withValues(alpha: 0.7),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Row(
            children: [
              // Pause / Resume — subtle glass
              Expanded(
                child: GestureDetector(
                  onTap: _togglePause,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
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
                // Advance — glowing accent button
                Expanded(
                  child: GestureDetector(
                    onTap: _advancePhase,
                    child: AnimatedBuilder(
                      animation: _breatheAnim!,
                      builder: (context, child) => Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              zoneColor.withValues(alpha: 0.15),
                              zoneColor.withValues(alpha: 0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: zoneColor.withValues(
                              alpha: 0.2 + _breatheAnim!.value * 0.15,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: zoneColor.withValues(
                                alpha: 0.1 + _breatheAnim!.value * 0.1,
                              ),
                              blurRadius: 15,
                              spreadRadius: -3,
                            ),
                          ],
                        ),
                        child: child,
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
                              fontWeight: FontWeight.w600,
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
        ),
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

// ═══════════════════════════════════════════════════════════════════════════
// Cinematic Background — animated gradient + floating particles
// ═══════════════════════════════════════════════════════════════════════════

class _CinematicBackground extends StatelessWidget {
  final Color zoneColor;
  final int zoneNumber;
  final Animation<double> breatheAnim;
  final AnimationController particleAnim;
  final bool isPaused;

  const _CinematicBackground({
    required this.zoneColor,
    required this.zoneNumber,
    required this.breatheAnim,
    required this.particleAnim,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([breatheAnim, particleAnim]),
      builder: (context, _) {
        final t = breatheAnim.value;
        return SizedBox.expand(
          child: CustomPaint(
            painter: _AmbientPainter(
              zoneColor: zoneColor,
              zoneNumber: zoneNumber,
              breathe: t,
              particlePhase: particleAnim.value,
              isPaused: isPaused,
            ),
          ),
        );
      },
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final Color zoneColor;
  final int zoneNumber;
  final double breathe;
  final double particlePhase;
  final bool isPaused;

  _AmbientPainter({
    required this.zoneColor,
    required this.zoneNumber,
    required this.breathe,
    required this.particlePhase,
    required this.isPaused,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Zone-aware intensity — higher zones = more dramatic
    final zoneIntensity = zoneNumber / 5.0; // 0.2 … 1.0
    final baseAlpha = isPaused ? 0.03 : 0.04 + zoneIntensity * 0.06;
    final glowAlpha = baseAlpha + breathe * 0.04 * zoneIntensity;

    // ── 1. Primary bloom — rises from bottom as zone increases ──
    // Z1: sits at very bottom, soft & wide
    // Z5: climbs to center, intense & tight
    final primaryY = 1.0 - (zoneNumber - 1) * 0.25; // 1.0 → 0.0
    final primaryRadius = 1.4 - zoneIntensity * 0.4 + breathe * 0.15;
    final primary = RadialGradient(
      center: Alignment(0.0, primaryY.clamp(-0.2, 1.0)),
      radius: primaryRadius,
      colors: [
        zoneColor.withValues(alpha: glowAlpha * 1.5),
        zoneColor.withValues(alpha: glowAlpha * 0.5),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = primary.createShader(rect));

    // ── 2. Secondary accent bloom (opposite corner, subtle) ──
    final secY = -0.6 + zoneIntensity * 0.4;
    final secondary = RadialGradient(
      center: Alignment(-0.5, secY),
      radius: 0.9 + breathe * 0.1,
      colors: [
        zoneColor.withValues(alpha: glowAlpha * 0.35),
        Colors.transparent,
      ],
    );
    canvas.drawRect(rect, Paint()..shader = secondary.createShader(rect));

    // ── 3. Hot-edge vignette for Z4/Z5 — cinematic tension ──
    if (zoneNumber >= 4) {
      final edgeAlpha = (zoneNumber == 5 ? 0.08 : 0.04) + breathe * 0.03;
      // Bottom edge glow
      final edgeGrad = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.center,
        colors: [
          zoneColor.withValues(alpha: edgeAlpha),
          Colors.transparent,
        ],
      );
      canvas.drawRect(rect, Paint()..shader = edgeGrad.createShader(rect));
      // Side vignettes for Z5
      if (zoneNumber == 5) {
        for (final side in [-1.0, 1.0]) {
          final sideGrad = RadialGradient(
            center: Alignment(side, 0.3),
            radius: 0.8,
            colors: [
              zoneColor.withValues(alpha: edgeAlpha * 0.5),
              Colors.transparent,
            ],
          );
          canvas.drawRect(rect, Paint()..shader = sideGrad.createShader(rect));
        }
      }
    }

    // ── 4. Floating particles — density scales with zone ──
    if (!isPaused) {
      _drawParticles(canvas, size, zoneIntensity);
    }
  }

  void _drawParticles(Canvas canvas, Size size, double zoneIntensity) {
    final rng = math.Random(42);
    final count = 15 + (zoneIntensity * 20).round(); // 17…35 particles
    final paint = Paint()..style = PaintingStyle.fill;
    final speed0 = 0.15 + zoneIntensity * 0.3; // faster at high zones

    for (var i = 0; i < count; i++) {
      final baseX = rng.nextDouble();
      final baseY = rng.nextDouble();
      final speed = speed0 + rng.nextDouble() * 0.6;
      final radius = 0.8 + rng.nextDouble() * (1.5 + zoneIntensity);

      final phase = (particlePhase * speed + baseY) % 1.0;
      final sway = 12.0 + zoneIntensity * 10;
      final x =
          baseX * size.width +
          math.sin((particlePhase + i) * math.pi * 2) * sway;
      final y = size.height * (1.0 - phase);

      final edgeFade =
          (phase < 0.1
                  ? phase / 0.1
                  : phase > 0.9
                  ? (1 - phase) / 0.1
                  : 1.0)
              .clamp(0.0, 1.0);

      paint.color = zoneColor.withValues(
        alpha: (0.06 + breathe * 0.05 + zoneIntensity * 0.04) * edgeFade,
      );
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Glass-morphism metric tile
// ═══════════════════════════════════════════════════════════════════════════

class _CinematicMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? accentColor;

  const _CinematicMetric({
    required this.label,
    required this.value,
    this.unit,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.moonbeam;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                  color: AppTheme.fog.withValues(alpha: 0.6),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 17,
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
                        color: AppTheme.fog.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
