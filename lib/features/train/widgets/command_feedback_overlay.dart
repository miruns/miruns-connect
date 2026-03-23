import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/blink_profile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Command Feedback Overlay — Transient "command detected" notification
// ─────────────────────────────────────────────────────────────────────────────

/// Shows a brief overlay when a blink command is detected and dispatched.
///
/// Designed to be placed in a [Stack] over the app's main content.
class CommandFeedbackOverlay extends StatefulWidget {
  const CommandFeedbackOverlay({super.key});

  @override
  State<CommandFeedbackOverlay> createState() => CommandFeedbackOverlayState();
}

class CommandFeedbackOverlayState extends State<CommandFeedbackOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  BlinkType? _type;
  String? _actionLabel;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// Show the overlay for a detected blink command.
  void show(BlinkType type, {String? actionLabel}) {
    _hideTimer?.cancel();
    setState(() {
      _type = type;
      _actionLabel = actionLabel;
    });
    _ctrl.forward(from: 0);
    _hideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _ctrl.reverse();
    });
  }

  IconData _iconFor(BlinkType type) {
    switch (type) {
      case BlinkType.single:
        return Icons.visibility_rounded;
      case BlinkType.double:
        return Icons.pause_circle_rounded;
      case BlinkType.long:
        return Icons.record_voice_over_rounded;
      case BlinkType.triple:
        return Icons.emergency_rounded;
    }
  }

  Color _colorFor(BlinkType type) {
    switch (type) {
      case BlinkType.single:
        return AppTheme.seaGreen;
      case BlinkType.double:
        return const Color(0xFF58A6FF);
      case BlinkType.long:
        return AppTheme.amber;
      case BlinkType.triple:
        return AppTheme.crimson;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_type == null) return const SizedBox.shrink();

    final type = _type!;
    final color = _colorFor(type);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            if (_opacity.value == 0) return const SizedBox.shrink();
            return Opacity(
              opacity: _opacity.value,
              child: Transform.scale(
                scale: _scale.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_iconFor(type), color: color, size: 28),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.label,
                            style: AppTheme.geistMono(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color,
                              letterSpacing: 1,
                            ),
                          ),
                          if (_actionLabel != null)
                            Text(
                              _actionLabel!,
                              style: AppTheme.geist(
                                fontSize: 12,
                                color: color.withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
