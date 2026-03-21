import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/ble_source_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Coherence Matrix — Cross-channel spectral coherence heatmap.
//
// Computes coherence between every channel pair from FFT cross-spectra,
// displaying the result as an N×N heat matrix. High coherence indicates
// functional connectivity between brain regions.
//
// Coherence(i,j) = |Σ Xi·Yj*|² / (Σ|Xi|² · Σ|Yj|²)
// where Xi, Yj are complex FFT bins within the selected frequency band.
// ─────────────────────────────────────────────────────────────────────────────

/// Which frequency band to compute coherence for.
enum CoherenceBand {
  alpha('α 8–13 Hz', 8, 13),
  beta('β 13–30 Hz', 13, 30),
  theta('θ 4–8 Hz', 4, 8),
  gamma('γ 30–60 Hz', 30, 60),
  broadband('BB 1–60 Hz', 1, 60);

  final String label;
  final double lowHz;
  final double highHz;
  const CoherenceBand(this.label, this.lowHz, this.highHz);
}

/// Computes spectral coherence from raw channel buffers.
///
/// Uses the same FFT pipeline as the existing engine but retains
/// complex FFT output for cross-spectral computation.
class CoherenceEngine {
  final int fftSize;
  final double sampleRateHz;

  late final Float64List _window;

  CoherenceEngine({required this.fftSize, required this.sampleRateHz}) {
    _window = Float64List(fftSize);
    for (var i = 0; i < fftSize; i++) {
      _window[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (fftSize - 1)));
    }
  }

  /// Compute the NxN coherence matrix for channels within [band].
  ///
  /// [channelBuffers] — list of raw sample buffers, one per channel.
  /// Each buffer must contain at least [fftSize] samples.
  ///
  /// Returns an NxN matrix where entry [i][j] is the magnitude-squared
  /// coherence between channels i and j (0.0 – 1.0).
  List<List<double>> compute(
    List<List<double>> channelBuffers,
    CoherenceBand band,
  ) {
    final n = channelBuffers.length;
    final matrix = List.generate(n, (_) => List<double>.filled(n, 0.0));

    if (channelBuffers.any((b) => b.length < fftSize)) return matrix;

    // Compute FFT for each channel, keeping complex output.
    final fftResults = <(Float64List re, Float64List im)>[];
    for (var ch = 0; ch < n; ch++) {
      final offset = channelBuffers[ch].length - fftSize;
      final re = Float64List(fftSize);
      final im = Float64List(fftSize);
      for (var i = 0; i < fftSize; i++) {
        re[i] = channelBuffers[ch][offset + i] * _window[i];
        im[i] = 0.0;
      }
      _fft(re, im);
      fftResults.add((re, im));
    }

    // Frequency resolution
    final df = sampleRateHz / fftSize;
    final kLow = (band.lowHz / df).ceil().clamp(0, fftSize ~/ 2);
    final kHigh = (band.highHz / df).floor().clamp(0, fftSize ~/ 2);

    // Compute coherence for each pair
    for (var i = 0; i < n; i++) {
      matrix[i][i] = 1.0; // self-coherence is always 1
      for (var j = i + 1; j < n; j++) {
        double crossRe = 0, crossIm = 0;
        double autoI = 0, autoJ = 0;

        for (var k = kLow; k <= kHigh; k++) {
          final xr = fftResults[i].$1[k];
          final xi = fftResults[i].$2[k];
          final yr = fftResults[j].$1[k];
          final yi = fftResults[j].$2[k];

          // Cross-spectrum: X · conj(Y)
          crossRe += xr * yr + xi * yi;
          crossIm += xi * yr - xr * yi;

          // Auto-spectra
          autoI += xr * xr + xi * xi;
          autoJ += yr * yr + yi * yi;
        }

        // Magnitude-squared coherence
        final denom = autoI * autoJ;
        final coh = denom > 0
            ? (crossRe * crossRe + crossIm * crossIm) / denom
            : 0.0;
        matrix[i][j] = coh.clamp(0.0, 1.0);
        matrix[j][i] = matrix[i][j];
      }
    }

    return matrix;
  }

  // ── Minimal in-place radix-2 FFT ───────────────────────────────────

  void _fft(Float64List re, Float64List im) {
    final n = re.length;
    final logN = _log2(n);

    // Bit-reversal
    for (var i = 0; i < n; i++) {
      final j = _reverseBits(i, logN);
      if (j > i) {
        var tmp = re[i];
        re[i] = re[j];
        re[j] = tmp;
        tmp = im[i];
        im[i] = im[j];
        im[j] = tmp;
      }
    }

    // Butterfly stages
    for (var size = 2; size <= n; size *= 2) {
      final half = size ~/ 2;
      final angle = -2.0 * math.pi / size;
      for (var i = 0; i < n; i += size) {
        for (var j = 0; j < half; j++) {
          final wr = math.cos(angle * j);
          final wi = math.sin(angle * j);
          final ei = i + j;
          final oi = i + j + half;
          final tr = wr * re[oi] - wi * im[oi];
          final ti = wr * im[oi] + wi * re[oi];
          re[oi] = re[ei] - tr;
          im[oi] = im[ei] - ti;
          re[ei] = re[ei] + tr;
          im[ei] = im[ei] + ti;
        }
      }
    }
  }

  static int _log2(int v) {
    int r = 0;
    var val = v;
    while (val > 1) {
      val >>= 1;
      r++;
    }
    return r;
  }

  static int _reverseBits(int x, int bits) {
    int result = 0;
    var val = x;
    for (var i = 0; i < bits; i++) {
      result = (result << 1) | (val & 1);
      val >>= 1;
    }
    return result;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// COHERENCE MATRIX PAINTER
// ═════════════════════════════════════════════════════════════════════════════

class CoherenceMatrixPainter extends CustomPainter {
  final List<List<double>> matrix;
  final List<String> labels;

  static const _gradientColors = [
    Color(0xFF060A14), // 0.0 — no coherence
    Color(0xFF0B253A),
    Color(0xFF125C6D),
    Color(0xFF00E676), // mid — moderate
    Color(0xFFFFD740),
    Color(0xFFFF5252),
    Color(0xFFFFFFFF), // 1.0 — perfect coherence
  ];

  const CoherenceMatrixPainter({required this.matrix, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    if (matrix.isEmpty) return;

    final n = matrix.length;
    final labelSpace = 36.0;
    final barSpace = 20.0;
    final gridSize = math.min(
      size.width - labelSpace - barSpace,
      size.height - labelSpace - barSpace,
    );
    if (gridSize <= 0) return;

    final cellSize = gridSize / n;
    final originX = labelSpace;
    final originY = labelSpace;

    // ── Draw matrix cells ────────────────────────────────────────────
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final v = matrix[row][col].clamp(0.0, 1.0);
        final rect = Rect.fromLTWH(
          originX + col * cellSize,
          originY + row * cellSize,
          cellSize,
          cellSize,
        );

        // Cell fill
        canvas.drawRect(rect, Paint()..color = _sampleGradient(v));

        // Cell border
        canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.06)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );

        // Value text (only if cells are large enough)
        if (cellSize > 28) {
          final tp = TextPainter(
            text: TextSpan(
              text: v.toStringAsFixed(2),
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: math.min(cellSize * 0.25, 10),
                fontWeight: FontWeight.w600,
                color: v > 0.5
                    ? Colors.black.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.6),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(
              rect.center.dx - tp.width / 2,
              rect.center.dy - tp.height / 2,
            ),
          );
        }
      }
    }

    // ── Row labels (left) ────────────────────────────────────────────
    for (var i = 0; i < n && i < labels.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          originX - tp.width - 4,
          originY + i * cellSize + cellSize / 2 - tp.height / 2,
        ),
      );
    }

    // ── Column labels (top) ──────────────────────────────────────────
    for (var i = 0; i < n && i < labels.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          originX + i * cellSize + cellSize / 2 - tp.width / 2,
          originY - tp.height - 3,
        ),
      );
    }

    // ── Colour bar ───────────────────────────────────────────────────
    final barX = originX + gridSize + 8;
    final barW = 10.0;
    final barH = gridSize;

    for (var i = 0; i < barH.toInt(); i++) {
      final t = 1.0 - i / barH;
      canvas.drawLine(
        Offset(barX, originY + i),
        Offset(barX + barW, originY + i),
        Paint()..color = _sampleGradient(t),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(barX, originY, barW, barH),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Bar labels
    for (final (t, label) in [(1.0, '1.0'), (0.5, '0.5'), (0.0, '0.0')]) {
      final y = originY + barH * (1.0 - t);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: 'RobotoMono',
            fontSize: 7,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(barX + barW + 3, y - tp.height / 2));
    }
  }

  static Color _sampleGradient(double t) {
    if (t <= 0) return _gradientColors.first;
    if (t >= 1) return _gradientColors.last;

    final n = _gradientColors.length - 1;
    final segment = t * n;
    final i = segment.floor().clamp(0, n - 1);
    final frac = segment - i;
    return Color.lerp(_gradientColors[i], _gradientColors[i + 1], frac)!;
  }

  @override
  bool shouldRepaint(CoherenceMatrixPainter old) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// COHERENCE VIEW WIDGET
// ═════════════════════════════════════════════════════════════════════════════

class CoherenceMatrixView extends StatelessWidget {
  /// Per-channel raw sample buffers (used for cross-spectral computation).
  final List<List<double>> channelBuffers;
  final List<ChannelDescriptor> channelDescriptors;
  final int fftSize;
  final double sampleRateHz;
  final CoherenceBand band;
  final ValueChanged<CoherenceBand>? onBandChanged;

  const CoherenceMatrixView({
    super.key,
    required this.channelBuffers,
    required this.channelDescriptors,
    this.fftSize = 256,
    this.sampleRateHz = 250,
    this.band = CoherenceBand.alpha,
    this.onBandChanged,
  });

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
                        ? AppTheme.glow.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isActive
                          ? AppTheme.glow.withValues(alpha: 0.5)
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
                            ? AppTheme.glow
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
        // Matrix
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CustomPaint(
                painter: CoherenceMatrixPainter(matrix: matrix, labels: labels),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
