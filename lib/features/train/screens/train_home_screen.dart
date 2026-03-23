import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/blink_profile.dart';
import '../services/blink_command_service.dart';
import '../widgets/blink_command_tile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Train Home Screen — Dashboard for BCI blink control
//
// Layout:
//   · Header: "Train" + BLE status indicator
//   · Profile card: calibration status + quality ring
//   · Command list: blink → action mapping tiles
//   · Start buttons: Calibrate / Live Test
// ─────────────────────────────────────────────────────────────────────────────

class TrainHomeScreen extends ConsumerStatefulWidget {
  const TrainHomeScreen({super.key});

  @override
  ConsumerState<TrainHomeScreen> createState() => _TrainHomeScreenState();
}

class _TrainHomeScreenState extends ConsumerState<TrainHomeScreen> {
  BlinkProfile? _profile;
  BleSourceState _bleState = BleSourceState.idle;
  StreamSubscription<BleSourceState>? _bleSub;

  final Map<BlinkType, BlinkAction> _commandMap = {
    BlinkType.single: BlinkAction.markLap,
    BlinkType.double: BlinkAction.toggleWorkout,
    BlinkType.long: BlinkAction.voiceStatus,
    BlinkType.triple: BlinkAction.emergencyStop,
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
    final bleSource = ref.read(bleSourceServiceProvider);
    _bleState = bleSource.state;
    _bleSub = bleSource.stateStream.listen((s) {
      if (mounted) setState(() => _bleState = s);
    });
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    // Load from local DB (for now, check if any profile exists)
    final db = ref.read(localDbServiceProvider);
    final json = await db.getSetting('blink_profile');
    if (json != null && mounted) {
      setState(() => _profile = BlinkProfile.decode(json));
    }
  }

  Future<void> _saveProfile(BlinkProfile profile) async {
    final db = ref.read(localDbServiceProvider);
    await db.setSetting('blink_profile', profile.encode());
    if (mounted) setState(() => _profile = profile);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_rounded,
                      color: AppTheme.seaGreen,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Train',
                        style: AppTheme.geist(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: colors.textStrong,
                        ),
                      ),
                    ),
                    // BLE status chip
                    _BleStatusChip(state: _bleState),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Text(
                  'Control the app hands-free using eye blinks',
                  style: AppTheme.geist(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),

            // ── Calibration status card ─────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _CalibrationCard(
                  profile: _profile,
                  onCalibrate: _startCalibration,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // ── Command mappings ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'COMMANDS',
                      style: AppTheme.geistMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.textMuted,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    if (_profile != null)
                      GestureDetector(
                        onTap: () => context.push('/train/commands'),
                        child: Text(
                          'Edit',
                          style: AppTheme.geist(
                            fontSize: 13,
                            color: AppTheme.seaGreen,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: BlinkType.values.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final type = BlinkType.values[index];
                  return BlinkCommandTile(
                    blinkType: type,
                    action: _commandMap[type] ?? BlinkAction.none,
                    enabled: _profile?.isCalibrated ?? false,
                    onActionChanged: (action) {
                      setState(() => _commandMap[type] = action);
                    },
                  );
                },
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── Action buttons ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Live Test button
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.bug_report_rounded,
                        label: 'Live Test',
                        enabled:
                            _profile != null &&
                            _bleState == BleSourceState.streaming,
                        onTap: () => context.push('/train/test'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Calibrate button
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.tune_rounded,
                        label: _profile != null ? 'Recalibrate' : 'Calibrate',
                        primary: true,
                        enabled: _bleState == BleSourceState.streaming,
                        onTap: _startCalibration,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── How it works section ────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
                child: Text(
                  'HOW IT WORKS',
                  style: AppTheme.geistMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.tintFaint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HowItWorksStep(
                        number: '1',
                        title: 'Wear your headset',
                        subtitle:
                            'The Fp1 and Fp2 channels detect eye blinks as large voltage peaks',
                        colors: colors,
                      ),
                      const SizedBox(height: 14),
                      _HowItWorksStep(
                        number: '2',
                        title: 'Calibrate (~3 min)',
                        subtitle:
                            'We learn your unique blink signature — amplitude, timing, rhythm',
                        colors: colors,
                      ),
                      const SizedBox(height: 14),
                      _HowItWorksStep(
                        number: '3',
                        title: 'Test your commands',
                        subtitle:
                            'Try each blink type in the live test to verify accuracy',
                        colors: colors,
                      ),
                      const SizedBox(height: 14),
                      _HowItWorksStep(
                        number: '4',
                        title: 'Use during workouts',
                        subtitle:
                            'Mark laps, pause, get voice readouts — all hands-free',
                        colors: colors,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Future<void> _startCalibration() async {
    final result = await context.push<BlinkProfile>('/train/calibrate');
    if (result != null && mounted) {
      await _saveProfile(result);
    }
  }
}

// ── Supporting widgets ──────────────────────────────────────────────────────

class _BleStatusChip extends StatelessWidget {
  const _BleStatusChip({required this.state});
  final BleSourceState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;
    final connected = state == BleSourceState.streaming;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: connected
            ? AppTheme.seaGreen.withValues(alpha: 0.12)
            : colors.tintFaint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connected
              ? AppTheme.seaGreen.withValues(alpha: 0.3)
              : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? AppTheme.seaGreen : colors.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? 'Connected' : 'No Signal',
            style: AppTheme.geistMono(
              fontSize: 11,
              color: connected ? AppTheme.seaGreen : colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalibrationCard extends StatelessWidget {
  const _CalibrationCard({required this.profile, required this.onCalibrate});

  final BlinkProfile? profile;
  final VoidCallback onCalibrate;

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;

    if (profile == null) {
      return GestureDetector(
        onTap: onCalibrate,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.seaGreen.withValues(alpha: 0.08),
                AppTheme.seaGreen.withValues(alpha: 0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.seaGreen.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.psychology_alt_rounded,
                size: 48,
                color: AppTheme.seaGreen.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 12),
              Text(
                'Not Calibrated',
                style: AppTheme.geist(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: colors.textStrong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Calibrate your blink profile to enable hands-free control.\nTakes about 3 minutes.',
                textAlign: TextAlign.center,
                style: AppTheme.geist(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.seaGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Start Calibration',
                  style: AppTheme.geist(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final quality = profile!.overallQuality;
    final qualityColor = quality >= 0.7
        ? AppTheme.seaGreen
        : quality >= 0.4
        ? AppTheme.amber
        : AppTheme.crimson;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.tintFaint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Row(
        children: [
          // Quality ring
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: quality,
                  strokeWidth: 4,
                  color: qualityColor,
                  backgroundColor: colors.tintSubtle,
                ),
                Text(
                  '${(quality * 100).round()}%',
                  style: AppTheme.geistMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: qualityColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Calibrated',
                  style: AppTheme.geist(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Single ${(profile!.singleBlinkAccuracy * 100).round()}%  ·  '
                  'Double ${(profile!.doubleBlinkAccuracy * 100).round()}%  ·  '
                  'Long ${(profile!.longBlinkAccuracy * 100).round()}%',
                  style: AppTheme.geistMono(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Threshold: ${profile!.fp1Threshold.toStringAsFixed(0)} µV',
                  style: AppTheme.geistMono(
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: primary ? AppTheme.seaGreen : colors.tintFaint,
            borderRadius: BorderRadius.circular(14),
            border: primary
                ? null
                : Border.all(color: colors.border, width: 0.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: primary ? Colors.white : colors.textBody,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTheme.geist(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : colors.textBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.colors,
  });

  final String number;
  final String title;
  final String subtitle;
  final MirunsColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.seaGreen.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Text(
              number,
              style: AppTheme.geistMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.seaGreen,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.geist(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textStrong,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTheme.geist(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
