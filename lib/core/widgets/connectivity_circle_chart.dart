import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/ble_source_provider.dart';
import '../theme/app_theme.dart';
import 'coherence_matrix_chart.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Connectivity Circle (Connectome Ring)
//
// Electrodes are placed equidistant on a circle. Arcs connect coherent pairs;
// arc thickness & opacity encode coherence strength. Arc colour encodes the
// frequency band. Inspired by MNE-Python's plot_connectivity_circle.
// ─────────────────────────────────────────────────────────────────────────────

/// Paints the connectivity ring: electrodes on a circle with coherence arcs.
class ConnectivityCirclePainter extends CustomPainter {
  /// NxN coherence matrix (0–1). Use [CoherenceEngine.compute].
  final List<List<double>> matrix;

  /// Channel labels matching matrix rows/columns.
  final List<String> labels;

  /// Minimum coherence threshold to draw an arc (noise filter).
  final double threshold;

  /// Colour for the arcs.
  final Color arcColor;

  const ConnectivityCirclePainter({
    required this.matrix,
    required this.labels,
    this.threshold = 0.15,
    this.arcColor = AppTheme.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (matrix.isEmpty || labels.isEmpty) return;

    final n = matrix.length;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) * 0.72;
    final labelRadius = radius + 22;

    // ── Background ring ──────────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // ── Compute electrode angles (top = -π/2, clockwise) ─────────────
    final angles = List<double>.generate(
      n,
      (i) => -math.pi / 2 + 2 * math.pi * i / n,
    );

    final positions = angles
        .map(
          (a) => Offset(cx + radius * math.cos(a), cy + radius * math.sin(a)),
        )
        .toList();

    // ── Draw coherence arcs ──────────────────────────────────────────
    // Collect and sort by coherence so strongest lines are on top.
    final arcs = <(int i, int j, double coh)>[];
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final coh = matrix[i][j];
        if (coh >= threshold) {
          arcs.add((i, j, coh));
        }
      }
    }
    arcs.sort((a, b) => a.$3.compareTo(b.$3));

    for (final (i, j, coh) in arcs) {
      final p1 = positions[i];
      final p2 = positions[j];

      // Quadratic Bézier through centre (creates the classic arc shape).
      // Control point pulled towards centre for curved arcs.
      final mid = Offset(
        (p1.dx + p2.dx) / 2 * 0.55 + cx * 0.45,
        (p1.dy + p2.dy) / 2 * 0.55 + cy * 0.45,
      );

      final arcPath = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, p2.dx, p2.dy);

      // Glow pass
      canvas.drawPath(
        arcPath,
        Paint()
          ..color = arcColor.withValues(alpha: coh * 0.25)
          ..strokeWidth = 1.0 + coh * 4.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      // Crisp pass
      canvas.drawPath(
        arcPath,
        Paint()
          ..color = arcColor.withValues(alpha: 0.3 + coh * 0.6)
          ..strokeWidth = 0.5 + coh * 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── Draw electrode nodes ─────────────────────────────────────────
    for (var i = 0; i < n; i++) {
      final pos = positions[i];

      // Compute node "strength" (sum of coherence)
      double strength = 0;
      for (var j = 0; j < n; j++) {
        if (j != i) strength += matrix[i][j];
      }
      strength = (strength / (n - 1)).clamp(0.0, 1.0);

      // Glow
      canvas.drawCircle(
        pos,
        8 + strength * 4,
        Paint()
          ..color = arcColor.withValues(alpha: 0.15 + strength * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Outer ring
      canvas.drawCircle(
        pos,
        7,
        Paint()
          ..color = arcColor.withValues(alpha: 0.3 + strength * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Inner fill
      canvas.drawCircle(
        pos,
        5,
        Paint()..color = arcColor.withValues(alpha: 0.6 + strength * 0.4),
      );

      // Label
      if (i < labels.length) {
        final angle = angles[i];
        final lx = cx + labelRadius * math.cos(angle);
        final ly = cy + labelRadius * math.sin(angle);
        final tp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              fontFamily: 'RobotoMono',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
      }
    }

    // ── Centre label ─────────────────────────────────────────────────
    final titleTp = TextPainter(
      text: TextSpan(
        text: 'COHERENCE',
        style: TextStyle(
          fontFamily: 'RobotoMono',
          fontSize: 8,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.0,
          color: Colors.white.withValues(alpha: 0.15),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    titleTp.paint(
      canvas,
      Offset(cx - titleTp.width / 2, cy - titleTp.height / 2),
    );
  }

  @override
  bool shouldRepaint(ConnectivityCirclePainter old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// CONNECTIVITY CIRCLE VIEW WIDGET
// ═════════════════════════════════════════════════════════════════════════════

class ConnectivityCircleView extends StatelessWidget {
  final List<List<double>> channelBuffers;
  final List<ChannelDescriptor> channelDescriptors;
  final int fftSize;
  final double sampleRateHz;
  final CoherenceBand band;
  final ValueChanged<CoherenceBand>? onBandChanged;

  const ConnectivityCircleView({
    super.key,
    required this.channelBuffers,
    required this.channelDescriptors,
    this.fftSize = 256,
    this.sampleRateHz = 250,
    this.band = CoherenceBand.alpha,
    this.onBandChanged,
  });

  static const _bandColors = {
    CoherenceBand.theta: Color(0xFF40C4FF),
    CoherenceBand.alpha: AppTheme.aurora,
    CoherenceBand.beta: Color(0xFFFFD740),
    CoherenceBand.gamma: Color(0xFFFF5252),
    CoherenceBand.broadband: AppTheme.glow,
  };

  @override
  Widget build(BuildContext context) {
    final engine = CoherenceEngine(
      fftSize: fftSize,
      sampleRateHz: sampleRateHz,
    );
    final matrix = engine.compute(channelBuffers, band);
    final labels = channelDescriptors.map((d) => d.label).toList();

    return Column(
      children: [
        // Band selector
        SizedBox(
          height: 28,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: CoherenceBand.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (_, i) {
              final b = CoherenceBand.values[i];
              final isActive = b == band;
              final color = _bandColors[b] ?? AppTheme.glow;
              return GestureDetector(
                onTap: () => onBandChanged?.call(b),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? color.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isActive
                          ? color.withValues(alpha: 0.5)
                          : AppTheme.fog.withValues(alpha: 0.15),
                      width: isActive ? 1.2 : 0.6,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      b.label,
                      style: AppTheme.geistMono(
                        fontSize: 9,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isActive
                            ? color
                            : AppTheme.fog.withValues(alpha: 0.4),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Circle
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CustomPaint(
                painter: ConnectivityCirclePainter(
                  matrix: matrix,
                  labels: labels,
                  arcColor: _bandColors[band] ?? AppTheme.glow,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
