import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// miruns M — drawn as a continuous signal / wave trace.
//
// Phase 1 (0→50% of cycle): The signal pen travels along the wavy M path,
//   leaving a blue→violet gradient stroke behind it, with a glowing cursor dot.
// Phase 2 (50→100%): The completed M pulses with a glow bloom and a gentle
//   breathing wobble (±3°).
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
    this.loop = false,
    this.cycleDuration = const Duration(milliseconds: 3200),
  });

  @override
  State<MSignalLogo> createState() => _MSignalLogoState();
}

class _MSignalLogoState extends State<MSignalLogo>
    with TickerProviderStateMixin {
  // draw + glow cycle
  late final AnimationController _ctrl;
  late final Animation<double> _draw; // 0→0.5 : pen travels
  late final Animation<double> _glow; // 0.5→1 : bloom in/out

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
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _MSignalPainter(
            drawProgress: _draw.value,
            glowIntensity: _ctrl.value > 0.50 ? _glow.value : 0.0,
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

    // ── Horizontal wavy M ─────────────────────────────────────────────────────
    //
    //  The letter flows left → right as one continuous stroke at mid height,
    //  rising into two rounded humps and dipping through a smooth U-valley —
    //  matching the brand signal-wave shape.
    //
    //  Anchors (x, y):  entry(0, .56) → peak-L(.22, .10) → valley(.50, .72)
    //                   → peak-R(.78, .10) → exit(1, .56)
    //
    //  Bezier tangents are near-horizontal at crests and valley ends so the
    //  shape reads as a sine wave rather than pointed peaks.

    final path = Path()
      ..moveTo(0.00 * w, 0.56 * h)
      // → left peak
      ..cubicTo(
        0.07 * w,
        0.56 * h, //  cp1: hold horizontal before rising
        0.10 * w,
        0.10 * h, //  cp2: fast lift toward crest
        0.22 * w,
        0.10 * h, //  anchor: left crest
      )
      // left peak → valley
      ..cubicTo(
        0.34 * w,
        0.10 * h, //  cp1: flat exit off crest
        0.42 * w,
        0.72 * h, //  cp2: pull into valley
        0.50 * w,
        0.72 * h, //  anchor: valley bottom
      )
      // valley → right peak
      ..cubicTo(
        0.58 * w,
        0.72 * h, //  cp1: flat exit from valley
        0.66 * w,
        0.10 * h, //  cp2: pull up toward crest
        0.78 * w,
        0.10 * h, //  anchor: right crest
      )
      // right peak → exit
      ..cubicTo(
        0.90 * w,
        0.10 * h, //  cp1: flat exit off crest
        0.93 * w,
        0.56 * h, //  cp2: descend to exit height
        1.00 * w,
        0.56 * h, //  anchor: outgoing tail
      );

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final drawLen = metric.length * drawProgress.clamp(0.0, 1.0);
    final drawnPath = metric.extractPath(0, drawLen);

    final strokeW = w * 0.048; // thin, proportional to canvas size

    // ── Wide soft glow behind the stroke ─────────────────────────────────────
    if (glowIntensity > 0.01) {
      canvas.drawPath(
        drawnPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW * 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppTheme.glow.withValues(alpha: 0.28 * glowIntensity)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            14.0 * glowIntensity,
          ),
      );
    }

    // ── Main gradient stroke ──────────────────────────────────────────────────
    canvas.drawPath(
      drawnPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = const LinearGradient(
          colors: [AppTheme.glow, AppTheme.aurora],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // ── Glowing cursor dot — travels with the pen tip ─────────────────────────
    if (drawProgress > 0.015 && drawProgress < 0.985) {
      final tangent = metric.getTangentForOffset(
        (drawLen - 1.0).clamp(0.0, metric.length),
      );
      if (tangent != null) {
        final r = strokeW * 0.85;
        canvas.drawCircle(
          tangent.position,
          r,
          Paint()
            ..color = AppTheme.glow
            ..style = PaintingStyle.fill
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.1),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MSignalPainter old) =>
      old.drawProgress != drawProgress || old.glowIntensity != glowIntensity;
}
