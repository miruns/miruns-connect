import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Compact persistent banner shown at the top of every screen while a
/// workout is active — like a music player mini-bar.
///
/// Displays: workout type icon · elapsed time · heart rate · pause state.
/// Tapping it navigates to the full [ActiveWorkoutScreen].
class ActiveWorkoutBanner extends ConsumerWidget {
  const ActiveWorkoutBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(activeWorkoutProvider);
    final state = notifier.state;

    if (state == null) return const SizedBox.shrink();

    final zone = state.currentHr > 0
        ? state.profile.zoneForHr(state.currentHr)
        : state.profile.hrZones.first;
    final zoneColor = Color(int.parse(zone.color));

    return GestureDetector(
      onTap: () =>
          context.push('/sport/active', extra: state.session.workoutType),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.tidePool,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: state.isPaused
                ? AppTheme.shimmer
                : zoneColor.withValues(alpha: 0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (state.isPaused ? AppTheme.shimmer : zoneColor).withValues(
                alpha: 0.10,
              ),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Pulsating activity indicator
            _PulsingDot(color: state.isPaused ? AppTheme.fog : zoneColor),
            const SizedBox(width: 10),

            // Workout type icon
            Icon(
              state.session.workoutType.icon,
              size: 18,
              color: AppTheme.moonbeam,
            ),
            const SizedBox(width: 8),

            // Elapsed time
            Text(
              _formatDuration(state.elapsed),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppTheme.moonbeam,
                letterSpacing: 1,
              ),
            ),

            const Spacer(),

            // Heart rate (if available)
            if (state.currentHr > 0) ...[
              Icon(Icons.favorite, size: 14, color: zoneColor),
              const SizedBox(width: 4),
              Text(
                '${state.currentHr}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: zoneColor,
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Distance (if GPS active)
            if (state.gpsMetrics.totalDistanceKm > 0.01) ...[
              Text(
                '${state.gpsMetrics.totalDistanceKm.toStringAsFixed(2)} km',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.fog,
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Pause indicator or chevron
            if (state.isPaused)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PAUSED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.amber,
                    letterSpacing: 0.5,
                  ),
                ),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppTheme.fog,
              ),
          ],
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
}

/// Small pulsing dot indicating active recording.
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.4 + _ctrl.value * 0.6),
        ),
      ),
    );
  }
}
