import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/sport_profile.dart';
import '../services/workout_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sport Profile Setup — first-run + editable profile for sport preferences
// ─────────────────────────────────────────────────────────────────────────────

class SportProfileScreen extends ConsumerStatefulWidget {
  const SportProfileScreen({super.key});

  @override
  ConsumerState<SportProfileScreen> createState() => _SportProfileScreenState();
}

class _SportProfileScreenState extends ConsumerState<SportProfileScreen> {
  late final WorkoutService _workoutService;
  bool _loading = true;
  bool _saving = false;

  // Form state
  SportLevel _level = SportLevel.beginner;
  final _ageController = TextEditingController(text: '30');
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _restingHrController = TextEditingController();
  final _maxHrController = TextEditingController();
  List<WorkoutType> _preferredWorkouts = [WorkoutType.running];
  bool _voiceCoachEnabled = true;
  bool _eegInsightsEnabled = true;

  @override
  void initState() {
    super.initState();
    _workoutService = ref.read(workoutServiceProvider);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _workoutService.loadProfile();
    if (mounted) {
      setState(() {
        _level = profile.level;
        _ageController.text = '${profile.age}';
        if (profile.weightKg != null) {
          _weightController.text = '${profile.weightKg}';
        }
        if (profile.heightCm != null) {
          _heightController.text = '${profile.heightCm}';
        }
        if (profile.restingHr != null) {
          _restingHrController.text = '${profile.restingHr}';
        }
        if (profile.maxHr != null) {
          _maxHrController.text = '${profile.maxHr}';
        }
        _preferredWorkouts = List.of(profile.preferredWorkouts);
        _voiceCoachEnabled = profile.voiceCoachEnabled;
        _eegInsightsEnabled = profile.eegInsightsEnabled;
      });
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final profile = SportProfile(
      level: _level,
      age: int.tryParse(_ageController.text) ?? 30,
      weightKg: double.tryParse(_weightController.text),
      heightCm: double.tryParse(_heightController.text),
      restingHr: int.tryParse(_restingHrController.text),
      maxHr: int.tryParse(_maxHrController.text),
      preferredWorkouts:
          _preferredWorkouts.isEmpty ? [WorkoutType.running] : _preferredWorkouts,
      voiceCoachEnabled: _voiceCoachEnabled,
      eegInsightsEnabled: _eegInsightsEnabled,
    );
    await _workoutService.saveProfile(profile);
    if (mounted) {
      HapticFeedback.mediumImpact();
      context.pop();
    }
  }

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _restingHrController.dispose();
    _maxHrController.dispose();
    super.dispose();
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
          'Sport Profile',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.moonbeam,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              'Save',
              style: TextStyle(
                color: _saving ? AppTheme.fog : AppTheme.glow,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.glow),
            )
          : SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // ── Level selector ──
                        _sectionTitle('Your Level'),
                        const SizedBox(height: 8),
                        ...SportLevel.values.map(_levelCard),

                        const SizedBox(height: 24),

                        // ── Basic info ──
                        _sectionTitle('Basic Info'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _inputField(
                                label: 'Age',
                                controller: _ageController,
                                suffix: 'yrs',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _inputField(
                                label: 'Weight',
                                controller: _weightController,
                                suffix: 'kg',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _inputField(
                                label: 'Height',
                                controller: _heightController,
                                suffix: 'cm',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ── Heart rate ──
                        _sectionTitle('Heart Rate'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _inputField(
                                label: 'Resting HR',
                                controller: _restingHrController,
                                suffix: 'bpm',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _inputField(
                                label: 'Max HR',
                                controller: _maxHrController,
                                suffix: 'bpm',
                                hint:
                                    'Auto: ${208 - (0.7 * (int.tryParse(_ageController.text) ?? 30)).round()}',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Leave Max HR empty to use the Tanaka formula estimate.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.fog.withValues(alpha: 0.7),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Preferred workouts ──
                        _sectionTitle('Preferred Workouts'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: WorkoutType.values.map((t) {
                            final selected = _preferredWorkouts.contains(t);
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  if (selected) {
                                    _preferredWorkouts.remove(t);
                                  } else {
                                    _preferredWorkouts.add(t);
                                  }
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppTheme.glow.withValues(alpha: 0.15)
                                      : AppTheme.tidePool,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? AppTheme.glow
                                        : AppTheme.shimmer
                                            .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  '${t.emoji} ${t.label}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: selected
                                        ? AppTheme.glow
                                        : AppTheme.moonbeam,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 24),

                        // ── Toggles ──
                        _sectionTitle('Features'),
                        const SizedBox(height: 8),
                        _toggleRow(
                          emoji: '🗣️',
                          title: 'Voice Coach',
                          subtitle:
                              'Audio prompts through earphones during workouts',
                          value: _voiceCoachEnabled,
                          onChanged: (v) =>
                              setState(() => _voiceCoachEnabled = v),
                        ),
                        const SizedBox(height: 8),
                        _toggleRow(
                          emoji: '🧠',
                          title: 'EEG Brain Insights',
                          subtitle:
                              'Real-time cognitive state analysis from headphone sensors',
                          value: _eegInsightsEnabled,
                          onChanged: (v) =>
                              setState(() => _eegInsightsEnabled = v),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Helpers ──

  Widget _sectionTitle(String title) => Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.moonbeam,
          letterSpacing: 0.3,
        ),
      );

  Widget _levelCard(SportLevel level) {
    final selected = _level == level;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _level = level);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.glow.withValues(alpha: 0.1)
              : AppTheme.tidePool,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.glow : AppTheme.shimmer.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(level.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    level.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppTheme.glow : AppTheme.moonbeam,
                    ),
                  ),
                  Text(
                    level.description,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.fog, height: 1.4),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppTheme.glow, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _inputField({
    required String label,
    required TextEditingController controller,
    String? suffix,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppTheme.fog)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.moonbeam),
          decoration: InputDecoration(
            hintText: hint ?? '',
            hintStyle: TextStyle(
                fontSize: 12, color: AppTheme.fog.withValues(alpha: 0.5)),
            suffixText: suffix,
            suffixStyle: const TextStyle(fontSize: 11, color: AppTheme.fog),
            filled: true,
            fillColor: AppTheme.tidePool,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: AppTheme.shimmer.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: AppTheme.shimmer.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.glow),
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggleRow({
    required String emoji,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.moonbeam)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.fog, height: 1.3)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppTheme.glow,
          ),
        ],
      ),
    );
  }
}
