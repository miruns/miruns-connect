import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/blink_profile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Calibration Cue Widget — Visual / audio prompt for "BLINK NOW"
//
// Shows an animated radial countdown ring with a central icon/text cue.
// Glows green on successful blink detection during calibration.
// ─────────────────────────────────────────────────────────────────────────────

/// Visual cue shown during calibration to prompt a specific blink gesture.
class CalibrationCueWidget extends StatefulWidget {
  const CalibrationCueWidget({
    super.key,
    required this.blinkType,
    required this.isActive,
    this.detected = false,
    this.countdown = 0.0,
    this.attempt = 0,
    this.totalAttempts = 10,
  });

  /// Which blink type we're prompting.
  final BlinkType blinkType;

  /// Whether the cue is actively prompting (animated ring).
  final bool isActive;

  /// Whether the blink was detected (green flash).
  final bool detected;

  /// 0.0–1.0 countdown progress (fills ring clockwise).
  final double countdown;

  /// Current attempt index.
  final int attempt;

  /// Total attempts for this phase.
  final int totalAttempts;

  @override
  State<CalibrationCueWidget> createState() => _CalibrationCueWidgetState();
}

class _CalibrationCueWidgetState extends State<CalibrationCueWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  IconData get _icon {
    switch (widget.blinkType) {
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

  String get _label {
    switch (widget.blinkType) {
      case BlinkType.single:
        return 'BLINK';
      case BlinkType.double:
        return 'DOUBLE\nBLINK';
      case BlinkType.long:
        return 'CLOSE\nEYES';
      case BlinkType.triple:
        return 'TRIPLE\nBLINK';
    }
  }

  String get _hint {
    switch (widget.blinkType) {
      case BlinkType.single:
        return 'One firm blink';
      case BlinkType.double:
        return 'Two quick blinks';
      case BlinkType.long:
        return 'Hold eyes closed ~1 second';
      case BlinkType.triple:
        return 'Three rapid blinks';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;
    final detected = widget.detected;
    final active = widget.isActive;

    final ringColor =
        detected
            ? AppTheme.seaGreen
            : active
            ? Colors.white
            : colors.textMuted;

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final pulse = active ? 1.0 + _pulseCtrl.value * 0.08 : 1.0;
        return Transform.scale(
          scale: pulse,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Countdown ring + icon ─────────────────────────────────
              SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background ring
                    CustomPaint(
                      size: const Size(180, 180),
                      painter: _RingPainter(
                        progress: widget.countdown,
                        color: ringColor,
                        bgColor: colors.tintSubtle,
                        detected: detected,
                      ),
                    ),

                    // Detected flash overlay
                    if (detected)
                      AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.seaGreen.withValues(alpha: 0.15),
                          ),
                        ),
                      ),

                    // Central content
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          detected ? Icons.check_rounded : _icon,
                          size: 48,
                          color: detected ? AppTheme.seaGreen : ringColor,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          detected ? 'DETECTED' : (active ? _label : 'WAIT'),
                          textAlign: TextAlign.center,
                          style: AppTheme.geistMono(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: detected ? AppTheme.seaGreen : ringColor,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Hint text ─────────────────────────────────────────────
              if (active && !detected)
                Text(
                  _hint,
                  style: AppTheme.geist(
                    fontSize: 15,
                    color: colors.textSecondary,
                  ),
                ),

              const SizedBox(height: 12),

              // ── Attempt counter dots ──────────────────────────────────
              _AttemptDots(
                total: widget.totalAttempts,
                completed: widget.attempt,
                active: active,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Animated ring painter for countdown / progress.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.bgColor,
    required this.detected,
  });

  final double progress;
  final Color color;
  final Color bgColor;
  final bool detected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    const strokeWidth = 4.0;

    // Background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = bgColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Progress arc
    if (progress > 0) {
      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + (detected ? 2 : 0)
          ..strokeCap = StrokeCap.round,
      );
    }

    // Glow effect on detection
    if (detected) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.detected != detected;
}

/// Row of dots showing calibration attempt progress.
class _AttemptDots extends StatelessWidget {
  const _AttemptDots({
    required this.total,
    required this.completed,
    required this.active,
  });

  final int total;
  final int completed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final done = i < completed;
        final current = i == completed && active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: current ? 12 : 8,
          height: current ? 12 : 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                done
                    ? AppTheme.seaGreen
                    : current
                    ? Colors.white
                    : colors.tintSubtle,
            boxShadow:
                done
                    ? [
                      BoxShadow(
                        color: AppTheme.seaGreen.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ]
                    : null,
          ),
        );
      }),
    );
  }
}
