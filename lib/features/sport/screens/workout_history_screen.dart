import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/workout_session.dart';
import '../services/workout_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Workout History — scrollable list of all past workouts
// ─────────────────────────────────────────────────────────────────────────────

class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  ConsumerState<WorkoutHistoryScreen> createState() =>
      _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  late final WorkoutService _workoutService;
  List<WorkoutSession>? _workouts;

  @override
  void initState() {
    super.initState();
    _workoutService = ref.read(workoutServiceProvider);
    _loadWorkouts();
  }

  Future<void> _loadWorkouts() async {
    final workouts = await _workoutService.loadWorkouts();
    if (mounted) setState(() => _workouts = workouts);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.midnight,
      appBar: AppBar(
        backgroundColor: AppTheme.midnight,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Workout History',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.moonbeam,
          ),
        ),
      ),
      body: _workouts == null
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.glow,
              ),
            )
          : _workouts!.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🏃', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text(
                    'No workouts yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.moonbeam,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Start your first workout from the Sport tab.',
                    style: TextStyle(fontSize: 13, color: AppTheme.fog),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _workouts!.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final w = _workouts![index];
                return _WorkoutHistoryCard(session: w);
              },
            ),
    );
  }
}

class _WorkoutHistoryCard extends StatelessWidget {
  final WorkoutSession session;

  const _WorkoutHistoryCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final duration = session.duration;
    final dateStr = DateFormat('MMM d, yyyy · HH:mm').format(session.startTime);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(session.workoutType.icon, size: 28, color: AppTheme.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.workoutType.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.moonbeam,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(fontSize: 11, color: AppTheme.fog),
                    ),
                  ],
                ),
              ),
              if (session.analysis != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.glow.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${session.analysis!.performanceScore}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.glow,
                        ),
                      ),
                      const Text(
                        'score',
                        style: TextStyle(fontSize: 9, color: AppTheme.fog),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Stats row
          Row(
            children: [
              _StatChip(icon: Icons.timer, value: '${duration.inMinutes} min'),
              if (session.totalDistanceKm != null)
                _StatChip(
                  icon: Icons.straighten,
                  value: '${session.totalDistanceKm!.toStringAsFixed(1)} km',
                ),
              if (session.avgHr != null)
                _StatChip(icon: Icons.favorite, value: '${session.avgHr} bpm'),
              if (session.caloriesBurned != null)
                _StatChip(
                  icon: Icons.local_fire_department,
                  value: '${session.caloriesBurned} kcal',
                ),
            ],
          ),

          // Feedback row
          if (session.feedback != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '⚡ Energy: ${session.feedback!.energyLevel}/10',
                  style: const TextStyle(fontSize: 11, color: AppTheme.fog),
                ),
                const SizedBox(width: 12),
                Text(
                  '😓 Fatigue: ${session.feedback!.fatigueLevel}/10',
                  style: const TextStyle(fontSize: 11, color: AppTheme.fog),
                ),
                if (session.feedback!.moodEmoji != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    session.feedback!.moodEmoji!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ],
            ),
          ],

          // Analysis summary
          if (session.analysis != null) ...[
            const SizedBox(height: 10),
            Text(
              session.analysis!.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.fog,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _StatChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.fog),
          const SizedBox(width: 3),
          Text(
            value,
            style: const TextStyle(fontSize: 11, color: AppTheme.fog),
          ),
        ],
      ),
    );
  }
}
