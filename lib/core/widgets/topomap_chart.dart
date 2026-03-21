import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/ble_source_provider.dart';
import '../services/fft_engine.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Topomap — EEG scalp topographic heatmap.
//
// Interpolates band-power values from electrode positions onto a 2D head
// outline, producing the classic neuroscience scalp map. Uses inverse-distance
// weighting for spatial interpolation across a rendered head silhouette.
//
// Matches the Midnight Ocean / bioluminescent palette used elsewhere.
// ─────────────────────────────────────────────────────────────────────────────

/// Which EEG band (or total power) to display on the topomap.
enum TopomapMetric {
  alpha('α Alpha', FrequencyBand.alpha),
  beta('β Beta', FrequencyBand.beta),
  theta('θ Theta', FrequencyBand.theta),
  delta('δ Delta', FrequencyBand.delta),
  gamma('γ Gamma', FrequencyBand.gamma),
  total('Σ Total', null);

  final String label;
  final FrequencyBand? band;
  const TopomapMetric(this.label, this.band);
}

/// Standard 10-20 electrode positions normalised to a unit circle
/// (0,0) = centre of head, radius 1 = edge of scalp.
class ElectrodePosition {
  final String label;
  final double x; // −1 (left) → +1 (right)
  final double y; // −1 (front) → +1 (back)

  const ElectrodePosition(this.label, this.x, this.y);
}

/// Default 8-channel montage matching [Ads1299SourceProvider._labels].
const kDefaultElectrodePositions = [
  ElectrodePosition('Fp1', -0.30, -0.85), // frontal pole left
  ElectrodePosition('Fp2', 0.30, -0.85), // frontal pole right
  ElectrodePosition('C3', -0.55, 0.00), // central left
  ElectrodePosition('C4', 0.55, 0.00), // central right
  ElectrodePosition('P3', -0.45, 0.45), // parietal left
  ElectrodePosition('P4', 0.45, 0.45), // parietal right
  ElectrodePosition('O1', -0.25, 0.85), // occipital left
  ElectrodePosition('O2', 0.25, 0.85), // occipital right
];

/// A stateless topomap painter that renders the scalp heatmap.
///
/// Takes per-channel power values and electrode positions, interpolates
/// across the head silhouette, and renders with the bioluminescent palette.
class TopomapPainter extends CustomPainter {
  /// One value per electrode — the metric to visualise (µV², %, etc.).
  final List<double> values;

  /// Electrode positions (must be same length as [values]).
  final List<ElectrodePosition> electrodes;

  /// Colour stops for the heatmap gradient (low → high).
  final List<Color> gradientColors;

  /// Inverse-distance weighting exponent (higher = sharper peaks).
  final double idwPower;

  /// Resolution of the interpolation grid (pixels per axis).
  final int resolution;

  TopomapPainter({
    required this.values,
    required this.electrodes,
    this.gradientColors = const [
      Color(0xFF060A14), // abyss — lowest
      Color(0xFF0B253A), // deep sea
      Color(0xFF125C6D), // teal dark
      Color(0xFF00E676), // bioluminescent green
      Color(0xFFFFD740), // amber
      Color(0xFFFF5252), // red hot
      Color(0xFFFFFFFF), // white — highest
    ],
    this.idwPower = 2.5,
    this.resolution = 64,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || electrodes.isEmpty) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final headRadius = math.min(cx, cy) * 0.82;

    // ── Interpolation values range ───────────────────────────────────
    double vMin = double.infinity, vMax = -double.infinity;
    for (final v in values) {
      if (v < vMin) vMin = v;
      if (v > vMax) vMax = v;
    }
    if (vMax <= vMin) {
      vMax = vMin + 1;
    }

    // ── Render interpolated scalp heatmap ────────────────────────────
    final cellW = (headRadius * 2) / resolution;
    final cellH = (headRadius * 2) / resolution;

    for (var gy = 0; gy < resolution; gy++) {
      for (var gx = 0; gx < resolution; gx++) {
        // Grid position in normalised coordinates
        final nx = -1.0 + 2.0 * (gx + 0.5) / resolution;
        final ny = -1.0 + 2.0 * (gy + 0.5) / resolution;
        final dist = math.sqrt(nx * nx + ny * ny);

        // Only draw inside the head circle
        if (dist > 1.05) continue;

        // Inverse-distance weighted interpolation
        double weightSum = 0;
        double valueSum = 0;
        bool exact = false;
        double exactVal = 0;

        for (var i = 0; i < electrodes.length && i < values.length; i++) {
          final dx = nx - electrodes[i].x;
          final dy = ny - electrodes[i].y;
          final d = math.sqrt(dx * dx + dy * dy);

          if (d < 0.001) {
            exact = true;
            exactVal = values[i];
            break;
          }

          final w = 1.0 / math.pow(d, idwPower);
          weightSum += w;
          valueSum += w * values[i];
        }

        final interpolated = exact ? exactVal : valueSum / weightSum;
        final norm = ((interpolated - vMin) / (vMax - vMin)).clamp(0.0, 1.0);

        // Fade out at edges of head
        double alpha = 1.0;
        if (dist > 0.92) {
          alpha = ((1.05 - dist) / 0.13).clamp(0.0, 1.0);
        }

        final color = _sampleGradient(norm).withValues(alpha: alpha);

        final px = cx + (nx * headRadius) - cellW / 2;
        final py = cy + (ny * headRadius) - cellH / 2;

        canvas.drawRect(
          Rect.fromLTWH(px, py, cellW + 0.5, cellH + 0.5),
          Paint()..color = color,
        );
      }
    }

    // ── Head outline ─────────────────────────────────────────────────
    final headPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), headRadius, headPaint);

    // ── Nose indicator (triangle at top) ─────────────────────────────
    final nosePath = Path()
      ..moveTo(cx - headRadius * 0.08, cy - headRadius)
      ..lineTo(cx, cy - headRadius - headRadius * 0.12)
      ..lineTo(cx + headRadius * 0.08, cy - headRadius);
    canvas.drawPath(
      nosePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );

    // ── Ear indicators ───────────────────────────────────────────────
    _drawEar(canvas, cx - headRadius, cy, headRadius, isLeft: true);
    _drawEar(canvas, cx + headRadius, cy, headRadius, isLeft: false);

    // ── Electrode markers ────────────────────────────────────────────
    for (var i = 0; i < electrodes.length && i < values.length; i++) {
      final ex = cx + electrodes[i].x * headRadius;
      final ey = cy + electrodes[i].y * headRadius;
      final norm = ((values[i] - vMin) / (vMax - vMin)).clamp(0.0, 1.0);

      // Glow
      canvas.drawCircle(
        Offset(ex, ey),
        6,
        Paint()
          ..color = _sampleGradient(norm).withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Electrode dot
      canvas.drawCircle(
        Offset(ex, ey),
        3.5,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        Offset(ex, ey),
        2.5,
        Paint()..color = _sampleGradient(norm),
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: electrodes[i].label,
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(ex - tp.width / 2, ey + 6));
    }

    // ── Colour bar legend ────────────────────────────────────────────
    _drawColourBar(canvas, size, vMin, vMax);
  }

  void _drawEar(
    Canvas canvas,
    double x,
    double y,
    double headR, {
    required bool isLeft,
  }) {
    final sign = isLeft ? -1.0 : 1.0;
    final earPath = Path()
      ..moveTo(x, y - headR * 0.12)
      ..quadraticBezierTo(x + sign * headR * 0.08, y, x, y + headR * 0.12);
    canvas.drawPath(
      earPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _drawColourBar(Canvas canvas, Size size, double vMin, double vMax) {
    final barW = 12.0;
    final barH = size.height * 0.5;
    final barX = size.width - barW - 8;
    final barY = (size.height - barH) / 2;

    // Gradient bar
    for (var i = 0; i < barH.toInt(); i++) {
      final t = 1.0 - i / barH; // top = high
      final color = _sampleGradient(t);
      canvas.drawLine(
        Offset(barX, barY + i),
        Offset(barX + barW, barY + i),
        Paint()..color = color,
      );
    }

    // Border
    canvas.drawRect(
      Rect.fromLTWH(barX, barY, barW, barH),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Labels
    final topTp = TextPainter(
      text: TextSpan(
        text: vMax.toStringAsFixed(1),
        style: TextStyle(
          fontFamily: 'RobotoMono',
          fontSize: 7,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    topTp.paint(canvas, Offset(barX - topTp.width - 3, barY - 2));

    final botTp = TextPainter(
      text: TextSpan(
        text: vMin.toStringAsFixed(1),
        style: TextStyle(
          fontFamily: 'RobotoMono',
          fontSize: 7,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    botTp.paint(
      canvas,
      Offset(barX - botTp.width - 3, barY + barH - botTp.height),
    );
  }

  Color _sampleGradient(double t) {
    if (t <= 0) return gradientColors.first;
    if (t >= 1) return gradientColors.last;

    final n = gradientColors.length - 1;
    final segment = t * n;
    final i = segment.floor().clamp(0, n - 1);
    final frac = segment - i;
    return Color.lerp(gradientColors[i], gradientColors[i + 1], frac)!;
  }

  @override
  bool shouldRepaint(TopomapPainter old) => true;
}

/// Convenience widget wrapping [TopomapPainter] with metric selector.
class TopomapView extends StatelessWidget {
  final List<SpectrumResult?> spectra;
  final List<ChannelDescriptor> channelDescriptors;
  final TopomapMetric metric;
  final ValueChanged<TopomapMetric>? onMetricChanged;

  const TopomapView({
    super.key,
    required this.spectra,
    required this.channelDescriptors,
    this.metric = TopomapMetric.alpha,
    this.onMetricChanged,
  });

  /// Map channel descriptors labels to electrode positions.
  List<ElectrodePosition> _resolvePositions() {
    final positions = <ElectrodePosition>[];
    for (var i = 0; i < channelDescriptors.length; i++) {
      final label = channelDescriptors[i].label;
      final match = kDefaultElectrodePositions
          .where((e) => e.label == label)
          .toList();
      if (match.isNotEmpty) {
        positions.add(match.first);
      } else {
        // Fallback: distribute in a circle
        final angle =
            -math.pi / 2 + (2 * math.pi * i / channelDescriptors.length);
        positions.add(
          ElectrodePosition(
            label,
            0.6 * math.cos(angle),
            0.6 * math.sin(angle),
          ),
        );
      }
    }
    return positions;
  }

  List<double> _extractValues() {
    final vals = <double>[];
    for (var i = 0; i < spectra.length; i++) {
      final s = spectra.length > i ? spectra[i] : null;
      if (s == null) {
        vals.add(0);
        continue;
      }
      if (metric == TopomapMetric.total) {
        vals.add(s.totalPower);
      } else {
        vals.add(s.bandPowers[metric.band!] ?? 0);
      }
    }
    return vals;
  }

  @override
  Widget build(BuildContext context) {
    final electrodes = _resolvePositions();
    final values = _extractValues();

    return Column(
      children: [
        // Metric selector
        SizedBox(
          height: 28,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: TopomapMetric.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 4),
            itemBuilder: (_, i) {
              final m = TopomapMetric.values[i];
              final isActive = m == metric;
              return GestureDetector(
                onTap: () => onMetricChanged?.call(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.aurora.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isActive
                          ? AppTheme.aurora.withValues(alpha: 0.5)
                          : AppTheme.fog.withValues(alpha: 0.15),
                      width: isActive ? 1.2 : 0.6,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      m.label,
                      style: AppTheme.geistMono(
                        fontSize: 9,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isActive
                            ? AppTheme.aurora
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
        // Topomap
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CustomPaint(
                painter: TopomapPainter(values: values, electrodes: electrodes),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
