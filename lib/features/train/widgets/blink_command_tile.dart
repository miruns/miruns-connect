import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/blink_profile.dart';
import '../services/blink_command_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Blink Command Tile — Shows a command mapping + sensitivity control
// ─────────────────────────────────────────────────────────────────────────────

class BlinkCommandTile extends StatelessWidget {
  const BlinkCommandTile({
    super.key,
    required this.blinkType,
    required this.action,
    required this.onActionChanged,
    this.enabled = true,
  });

  final BlinkType blinkType;
  final BlinkAction action;
  final ValueChanged<BlinkAction> onActionChanged;
  final bool enabled;

  IconData _blinkIcon(BlinkType t) {
    switch (t) {
      case BlinkType.single:
        return Icons.visibility_rounded;
      case BlinkType.double:
        return Icons.filter_2_rounded;
      case BlinkType.long:
        return Icons.visibility_off_rounded;
      case BlinkType.triple:
        return Icons.filter_3_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.tintFaint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Blink gesture icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.tintSubtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _blinkIcon(blinkType),
                color: colors.textBody,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),

            // Labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    blinkType.label,
                    style: AppTheme.geist(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    blinkType.description,
                    style: AppTheme.geist(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Action arrow + label
            Icon(
              Icons.arrow_forward_rounded,
              color: colors.textMuted,
              size: 16,
            ),
            const SizedBox(width: 8),

            // Action selector
            GestureDetector(
              onTap: enabled ? () => _showActionPicker(context) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.tintSubtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Text(
                  action.label,
                  style: AppTheme.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textBody,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActionPicker(BuildContext context) {
    final colors = context.miruns;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Assign action for ${blinkType.label}',
                    style: AppTheme.geist(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textStrong,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...BlinkAction.values.map(
                  (a) => ListTile(
                    leading: Icon(
                      a == action
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: a == action ? AppTheme.seaGreen : colors.textMuted,
                      size: 20,
                    ),
                    title: Text(
                      a.label,
                      style: AppTheme.geist(
                        fontSize: 14,
                        color: colors.textStrong,
                      ),
                    ),
                    subtitle: Text(
                      a.description,
                      style: AppTheme.geist(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    onTap: () {
                      onActionChanged(a);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
