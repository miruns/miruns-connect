import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';
import '../services/workout_service.dart';
import '../widgets/sport_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sport Home — primary sport landing screen
//
// Layout:
//   · Header    : "miruns sport" branding
//   · Quick start: big workout start button
//   · AI prediction: pre-workout insight (after 3+ sessions)
//   · Recent    : last workout summary card
//   · History   : link to full workout history
// ─────────────────────────────────────────────────────────────────────────────

class SportHomeScreen extends ConsumerStatefulWidget {
  const SportHomeScreen({super.key});

  @override
  ConsumerState<SportHomeScreen> createState() => _SportHomeScreenState();
}

class _SportHomeScreenState extends ConsumerState<SportHomeScreen>
    with SingleTickerProviderStateMixin {
  late final WorkoutService _workoutService;

  SportProfile? _profile;
  List<WorkoutSession>? _recentWorkouts;
  String? _prediction;
  bool _loadingPrediction = false;
  WorkoutType _selectedType = WorkoutType.running;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _workoutService = ref.read(workoutServiceProvider);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _loadData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final profile = await _workoutService.loadProfile();
    final workouts = await _workoutService.loadWorkouts(limit: 5);
    if (mounted) {
      setState(() {
        _profile = profile;
        _recentWorkouts = workouts;
        _selectedType = profile.preferredWorkouts.isNotEmpty
            ? profile.preferredWorkouts.first
            : WorkoutType.running;
      });
    }

    // Generate AI prediction if enough data
    if (workouts.where((w) => w.feedback != null).length >= 3) {
      _loadPrediction(profile, workouts);
    }
  }

  Future<void> _loadPrediction(
    SportProfile profile,
    List<WorkoutSession> history,
  ) async {
    setState(() => _loadingPrediction = true);
    try {
      final analytics = ref.read(workoutAnalyticsServiceProvider);
      final prediction = await analytics.generatePreWorkoutPrediction(
        profile: profile,
        history: history,
        plannedType: _selectedType,
      );
      if (mounted) setState(() => _prediction = prediction);
    } catch (_) {}
    if (mounted) setState(() => _loadingPrediction = false);
  }

  void _startWorkout() {
    HapticFeedback.mediumImpact();
    context.push('/sport/active', extra: _selectedType);
  }

  void _openHistory() {
    HapticFeedback.selectionClick();
    context.push('/sport/history');
  }

  void _openProfile() {
    HapticFeedback.selectionClick();
    context.push('/sport/profile');
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile = _profile != null;

    return Scaffold(
      backgroundColor: AppTheme.midnight,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ─────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'miruns',
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.moonbeam,
                            letterSpacing: -1.2,
                          ),
                        ),
                        Text(
                          'sport',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppTheme.glow,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (hasProfile)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.glow.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_profile!.level.emoji} ${_profile!.level.label}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.glow,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _openProfile,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppTheme.tidePool,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.shimmer,
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              size: 18,
                              color: AppTheme.fog,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Workout Type Selection ──────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What are you training today?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.moonbeam,
                      ),
                    ),
                    const SizedBox(height: 12),
                    WorkoutTypeSelector(
                      selected: _selectedType,
                      onSelect: (type) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedType = type);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── Start Button ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: GestureDetector(
                    onTap: _startWorkout,
                    child: AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (context, child) => Transform.scale(
                        scale: 0.95 + (_pulseAnim.value * 0.05),
                        child: child,
                      ),
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppTheme.glow,
                              AppTheme.glow.withValues(alpha: 0.7),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.glow.withValues(alpha: 0.3),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _selectedType.emoji,
                              style: const TextStyle(fontSize: 32),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'START',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── AI Prediction ──────────────────────────────────────────
            if (_loadingPrediction || _prediction != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.tidePool,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.aurora.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: AppTheme.aurora,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'AI Prediction',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.aurora,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_loadingPrediction)
                          const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.aurora,
                              ),
                            ),
                          )
                        else
                          Text(
                            _prediction!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.moonbeam,
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Recent Workouts ─────────────────────────────────────────
            if (_recentWorkouts != null && _recentWorkouts!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recent Sessions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.moonbeam,
                            ),
                          ),
                          GestureDetector(
                            onTap: _openHistory,
                            child: const Text(
                              'View All',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.glow,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._recentWorkouts!
                          .take(3)
                          .map((w) => _RecentWorkoutCard(session: w)),
                    ],
                  ),
                ),
              ),

            // ── Empty state ─────────────────────────────────────────────
            if (_recentWorkouts != null && _recentWorkouts!.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Text('🏃', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text(
                        'Ready for your first workout?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.moonbeam,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Select your activity and hit START.\nJust focus on your sport — we handle the rest.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.fog,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}

/// Compact recent workout summary card.
class _RecentWorkoutCard extends StatelessWidget {
  final WorkoutSession session;

  const _RecentWorkoutCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final duration = session.duration;
    final daysAgo = DateTime.now().difference(session.startTime).inDays;
    final when = daysAgo == 0
        ? 'Today'
        : daysAgo == 1
        ? 'Yesterday'
        : '$daysAgo days ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(session.workoutType.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.workoutType.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.moonbeam,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$when · ${duration.inMinutes}min${session.totalDistanceKm != null ? ' · ${session.totalDistanceKm!.toStringAsFixed(1)}km' : ''}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.fog),
                ),
              ],
            ),
          ),
          if (session.analysis != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.glow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${session.analysis!.performanceScore}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.glow,
                ),
              ),
            ),
          if (session.feedback != null && session.analysis == null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '⚡${session.feedback!.energyLevel}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.fog),
                ),
                const SizedBox(width: 6),
                Text(
                  '😓${session.feedback!.fatigueLevel}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.fog),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
