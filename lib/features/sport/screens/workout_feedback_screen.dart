import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/workout_session.dart';
import '../services/workout_service.dart';
import '../widgets/sport_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Post-Workout Feedback — collects user perception, then runs AI analysis.
//
// Flow:
//   1. "Great work!" header with summary stats
//   2. Fatigue slider (1–10)
//   3. Energy slider (1–10)
//   4. Optional RPE + mood + note
//   5. Submit → AI analysis → show results
// ─────────────────────────────────────────────────────────────────────────────

class WorkoutFeedbackScreen extends ConsumerStatefulWidget {
  final WorkoutSession session;

  const WorkoutFeedbackScreen({super.key, required this.session});

  @override
  ConsumerState<WorkoutFeedbackScreen> createState() =>
      _WorkoutFeedbackScreenState();
}

class _WorkoutFeedbackScreenState extends ConsumerState<WorkoutFeedbackScreen> {
  late final WorkoutService _workoutService;

  int _fatigueLevel = 5;
  int _energyLevel = 5;
  int? _rpe;
  String? _moodEmoji;
  final TextEditingController _noteController = TextEditingController();

  bool _submitted = false;
  bool _analyzing = false;
  WorkoutAnalysis? _analysis;

  static const _moodOptions = ['😊', '😎', '💪', '😤', '😴', '😌', '🤔', '😔'];

  @override
  void initState() {
    super.initState();
    _workoutService = ref.read(workoutServiceProvider);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    HapticFeedback.mediumImpact();

    final feedback = WorkoutFeedback(
      fatigueLevel: _fatigueLevel,
      energyLevel: _energyLevel,
      rpe: _rpe,
      moodEmoji: _moodEmoji,
      note: _noteController.text.isNotEmpty ? _noteController.text : null,
    );

    // Save feedback
    final updated = widget.session.copyWith(feedback: feedback);
    await _workoutService.saveWorkout(updated);

    setState(() {
      _submitted = true;
      _analyzing = true;
    });

    // Run AI analysis
    try {
      final profile = await _workoutService.loadProfile();
      final history = await _workoutService.loadWorkouts(limit: 10);
      final analytics = ref.read(workoutAnalyticsServiceProvider);

      final analysis = await analytics.analyzeWorkout(
        session: updated,
        profile: profile,
        history: history,
      );

      if (analysis != null) {
        final withAnalysis = updated.copyWith(analysis: analysis);
        await _workoutService.saveWorkout(withAnalysis);
      }

      if (mounted) {
        setState(() {
          _analysis = analysis;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _done() {
    HapticFeedback.selectionClick();
    context.go('/sport');
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final duration = session.duration;

    return Scaffold(
      backgroundColor: AppTheme.midnight,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── Header ───────────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Icon(
                      session.workoutType.icon,
                      size: 48,
                      color: AppTheme.cyan,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _submitted ? 'Analyzing...' : 'Great Work!',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.moonbeam,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${session.workoutType.label} · ${duration.inMinutes} min',
                      style: const TextStyle(fontSize: 14, color: AppTheme.fog),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Quick stats ──────────────────────────────────────────
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (session.avgHr != null)
                    MetricTile(
                      label: 'Avg HR',
                      value: '${session.avgHr}',
                      unit: 'bpm',
                      icon: Icons.favorite,
                      accentColor: AppTheme.crimson,
                    ),
                  if (session.maxHr != null)
                    MetricTile(
                      label: 'Max HR',
                      value: '${session.maxHr}',
                      unit: 'bpm',
                      icon: Icons.favorite,
                    ),
                  if (session.totalDistanceKm != null)
                    MetricTile(
                      label: 'Distance',
                      value: session.totalDistanceKm!.toStringAsFixed(2),
                      unit: 'km',
                      icon: Icons.straighten,
                    ),
                  if (session.caloriesBurned != null)
                    MetricTile(
                      label: 'Calories',
                      value: '${session.caloriesBurned}',
                      unit: 'kcal',
                      icon: Icons.local_fire_department,
                      accentColor: AppTheme.amber,
                    ),
                ],
              ),

              if (!_submitted) ...[
                const SizedBox(height: 32),

                // ── Feedback Section ──────────────────────────────────
                const Text(
                  'How do you feel?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.moonbeam,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your feedback helps the AI learn and improve predictions.',
                  style: TextStyle(fontSize: 12, color: AppTheme.fog),
                ),

                const SizedBox(height: 20),

                FeedbackSlider(
                  label: 'Fatigue Level',
                  value: _fatigueLevel,
                  onChanged: (v) => setState(() => _fatigueLevel = v),
                  lowLabel: '😊 Fresh',
                  highLabel: '😓 Burned',
                  color: AppTheme.amber,
                ),

                const SizedBox(height: 20),

                FeedbackSlider(
                  label: 'Energy Level',
                  value: _energyLevel,
                  onChanged: (v) => setState(() => _energyLevel = v),
                  lowLabel: '😴 Low',
                  highLabel: '⚡ High',
                  color: AppTheme.seaGreen,
                ),

                const SizedBox(height: 24),

                // ── Mood selector ──────────────────────────────────────
                const Text(
                  'Mood',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.moonbeam,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _moodOptions
                      .map(
                        (emoji) => GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(
                              () => _moodEmoji = _moodEmoji == emoji
                                  ? null
                                  : emoji,
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _moodEmoji == emoji
                                  ? AppTheme.glow.withValues(alpha: 0.2)
                                  : AppTheme.tidePool,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _moodEmoji == emoji
                                    ? AppTheme.glow
                                    : AppTheme.shimmer.withValues(alpha: 0.3),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),

                const SizedBox(height: 20),

                // ── Note ───────────────────────────────────────────────
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  style: const TextStyle(
                    color: AppTheme.moonbeam,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Any notes about this workout? (optional)',
                    hintStyle: TextStyle(
                      color: AppTheme.fog.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: AppTheme.tidePool,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(
                        color: AppTheme.shimmer.withValues(alpha: 0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(
                        color: AppTheme.shimmer.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: AppTheme.glow),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Submit button ──────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.glow,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: const Text(
                      'Submit & Analyze',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],

              // ── Analysis Results ────────────────────────────────────
              if (_submitted) ...[
                const SizedBox(height: 32),

                if (_analyzing)
                  const Center(
                    child: Column(
                      children: [
                        SizedBox(height: 20),
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppTheme.aurora,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'AI is analyzing your workout...',
                          style: TextStyle(fontSize: 14, color: AppTheme.fog),
                        ),
                      ],
                    ),
                  ),

                if (_analysis != null) ...[
                  // Performance score
                  Center(
                    child: Column(
                      children: [
                        Text(
                          '${_analysis!.performanceScore}',
                          style: GoogleFonts.inter(
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.glow,
                          ),
                        ),
                        const Text(
                          'Performance Score',
                          style: TextStyle(fontSize: 12, color: AppTheme.fog),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Summary
                  _AnalysisCard(
                    icon: Icons.summarize,
                    title: 'Summary',
                    content: _analysis!.summary,
                    color: AppTheme.glow,
                  ),

                  const SizedBox(height: 10),

                  _AnalysisCard(
                    icon: Icons.battery_alert,
                    title: 'Fatigue Assessment',
                    content: _analysis!.fatigueAssessment,
                    color: AppTheme.amber,
                  ),

                  const SizedBox(height: 10),

                  _AnalysisCard(
                    icon: Icons.self_improvement,
                    title: 'Recovery',
                    content:
                        '${_analysis!.recoveryRecommendation}\n\nEstimated recovery: ${_analysis!.estimatedRecoveryTime.inHours}h ${_analysis!.estimatedRecoveryTime.inMinutes.remainder(60)}min',
                    color: AppTheme.seaGreen,
                  ),

                  if (_analysis!.eegInsight != null) ...[
                    const SizedBox(height: 10),

                    _AnalysisCard(
                      icon: Icons.psychology,
                      title: 'Brain Insight',
                      content: _analysis!.eegInsight!,
                      color: AppTheme.aurora,
                    ),
                  ],

                  if (_analysis!.highlights.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Highlights',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.moonbeam,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._analysis!.highlights.map(
                      (h) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('✨ ', style: TextStyle(fontSize: 14)),
                            Expanded(
                              child: Text(
                                h,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.moonbeam,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (_analysis!.improvements.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Areas to Improve',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.moonbeam,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._analysis!.improvements.map(
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('🎯 ', style: TextStyle(fontSize: 14)),
                            Expanded(
                              child: Text(
                                i,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.moonbeam,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Done button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _done,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.glow,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],

                // Done button if analysis failed
                if (!_analyzing && _analysis == null) ...[
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Analysis not available right now.\nYour feedback has been saved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppTheme.fog),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _done,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.glow,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  final Color color;

  const _AnalysisCard({
    required this.icon,
    required this.title,
    required this.content,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.moonbeam,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
