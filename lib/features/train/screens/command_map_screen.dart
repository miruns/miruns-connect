import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../models/blink_profile.dart';
import '../services/blink_command_service.dart';
import '../widgets/blink_command_tile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Command Map Screen — Assign blink gestures to app actions
// ─────────────────────────────────────────────────────────────────────────────

class CommandMapScreen extends ConsumerStatefulWidget {
  const CommandMapScreen({super.key});

  @override
  ConsumerState<CommandMapScreen> createState() => _CommandMapScreenState();
}

class _CommandMapScreenState extends ConsumerState<CommandMapScreen> {
  final Map<BlinkType, BlinkAction> _commandMap = {
    BlinkType.single: BlinkAction.markLap,
    BlinkType.double: BlinkAction.toggleWorkout,
    BlinkType.long: BlinkAction.voiceStatus,
    BlinkType.triple: BlinkAction.emergencyStop,
  };

  double _confidenceGate = 0.8;
  bool _hapticFeedback = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textBody),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Command Map',
          style: AppTheme.geist(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textStrong,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _resetDefaults,
            child: Text(
              'Reset',
              style: AppTheme.geist(fontSize: 13, color: colors.textMuted),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Section: Command assignments ───────────────────────────
          Text(
            'GESTURE → ACTION',
            style: AppTheme.geistMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),

          ...BlinkType.values.map(
            (type) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BlinkCommandTile(
                blinkType: type,
                action: _commandMap[type] ?? BlinkAction.none,
                onActionChanged: (action) {
                  setState(() => _commandMap[type] = action);
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Section: Settings ──────────────────────────────────────
          Text(
            'SETTINGS',
            style: AppTheme.geistMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),

          // Confidence gate slider
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.tintFaint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      color: colors.textMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Confidence Gate',
                      style: AppTheme.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textStrong,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(_confidenceGate * 100).round()}%',
                      style: AppTheme.geistMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.seaGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Minimum confidence to trigger a command. Lower = more sensitive but more false positives.',
                  style: AppTheme.geist(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.seaGreen,
                    inactiveTrackColor: colors.tintSubtle,
                    thumbColor: AppTheme.seaGreen,
                    overlayColor: AppTheme.seaGreen.withValues(alpha: 0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _confidenceGate,
                    min: 0.3,
                    max: 1.0,
                    divisions: 14,
                    onChanged: (v) => setState(() => _confidenceGate = v),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Haptic toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.tintFaint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.vibration_rounded,
                  color: colors.textMuted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Haptic Feedback',
                    style: AppTheme.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textStrong,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: _hapticFeedback,
                  activeTrackColor: AppTheme.seaGreen,
                  onChanged: (v) => setState(() => _hapticFeedback = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _resetDefaults() {
    setState(() {
      _commandMap[BlinkType.single] = BlinkAction.markLap;
      _commandMap[BlinkType.double] = BlinkAction.toggleWorkout;
      _commandMap[BlinkType.long] = BlinkAction.voiceStatus;
      _commandMap[BlinkType.triple] = BlinkAction.emergencyStop;
      _confidenceGate = 0.8;
      _hapticFeedback = true;
    });
  }
}
