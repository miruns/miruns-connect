import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// miruns M — drawn as a continuous EEG signal trace.
//
// Phase 1 (0→50% of cycle): The signal pen travels along the M path,
//   leaving a blue→violet gradient stroke behind it, with a glowing cursor dot.
// Phase 2 (50→100%): The completed M pulses with a glow bloom and the whole
//   glyph rotates a few degrees then returns — an artistic breath.
// ─────────────────────────────────────────────────────────────────────────────

class MSignalLogo extends StatefulWidget {
  /// Outer bounding box side length.
  final double size;

  /// When true the animation loops forever. Set to false for a one-shot draw.
  final bool loop;

  /// Total duration of one full draw + glow cycle.
  final Duration cycleDuration;

  const MSignalLogo({
    super.key,
    this.size = 80,
    this.loop = true,
    this.cycleDuration = const Duration(milliseconds: 3200),
  });

  @override
  State<MSignalLogo> createState() => _MSignalLogoState();
}

class _MSignalLogoState extends State<MSignalLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // 0.00 → 0.50 : draw the M from left to right
  late final Animation<double> _draw;

  // 0.50 → 1.00 : glow bloom (in then out)
  late final Animation<double> _glow;

  // 0.50 → 1.00 : subtle artistic rotation (0 → +3.5° → 0)
  late final Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.cycleDuration);

    _draw = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.50, curve: Curves.easeInOut),
    );

    _glow = TweenSequence<double>(
      [
        TweenSequenceItem(
          tween: Tween(
            begin: 0.0,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 1.0,
            end: 0.0,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 1,
        ),
      ],
    ).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.50, 1.0)));

    _rotate =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.061), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 0.061, end: 0.0), weight: 1),
        ]).animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.50, 1.0, curve: Curves.easeInOut),
          ),
        );

    if (widget.loop) {
      _ctrl.repeat();
    } else {
      _ctrl.forward();
    }
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
      builder: (context, _) {
        return Transform.rotate(
          angle: _rotate.value,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _MSignalPainter(
              drawProgress: _draw.value,
              glowIntensity: _ctrl.value > 0.50 ? _glow.value : 0.0,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MSignalPainter extends CustomPainter {
  final double drawProgress; // 0 → 1
  final double glowIntensity; // 0 → 1

  const _MSignalPainter({
    required this.drawProgress,
    required this.glowIntensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (drawProgress <= 0) return;

    final w = size.width;
    final h = size.height;

    // ── M path: 5 key points drawn as a single continuous stroke ─────────────
    //   bottom-left → top-left → center dip → top-right → bottom-right
    //   The center dip sits at ~65% height to give the M a natural, EEG-like
    //   V-valley rather than a flat geometric midpoint.
    final path = Path()
      ..moveTo(0.08 * w, 0.88 * h)
      ..lineTo(0.08 * w, 0.12 * h)
      ..lineTo(0.50 * w, 0.66 * h)
      ..lineTo(0.92 * w, 0.12 * h)
      ..lineTo(0.92 * w, 0.88 * h);

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final drawLen = (metric.length * drawProgress.clamp(0.0, 1.0));
    final drawnPath = metric.extractPath(0, drawLen);

    // ── Glow bloom layer (rendered first, behind main stroke) ────────────────
    if (glowIntensity > 0.01) {
      canvas.drawPath(
        drawnPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppTheme.glow.withValues(alpha: 0.30 * glowIntensity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * glowIntensity),
      );
    }

    // ── Main gradient stroke ──────────────────────────────────────────────────
    canvas.drawPath(
      drawnPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = const LinearGradient(
          colors: [AppTheme.glow, AppTheme.aurora],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // ── Trailing cursor dot — moves with the pen tip during draw phase ────────
    if (drawProgress > 0.02 && drawProgress < 0.98) {
      final tangent = metric.getTangentForOffset(
        (drawLen - 1.0).clamp(0, metric.length),
      );
      if (tangent != null) {
        canvas.drawCircle(
          tangent.position,
          5.0,
          Paint()
            ..color = AppTheme.glow
            ..style = PaintingStyle.fill
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MSignalPainter old) =>
      old.drawProgress != drawProgress || old.glowIntensity != glowIntensity;
}
