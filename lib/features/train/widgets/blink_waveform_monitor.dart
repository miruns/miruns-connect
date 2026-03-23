import 'dart:collection';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/blink_profile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Blink Waveform Monitor — Real-time Fp1/Fp2 mini chart with blink markers
// ─────────────────────────────────────────────────────────────────────────────

/// Compact real-time waveform display for Fp1 and Fp2 channels.
///
/// Shows the live filtered signal with threshold line and blink event markers.
class BlinkWaveformMonitor extends StatefulWidget {
  const BlinkWaveformMonitor({
    super.key,
    required this.fp1Buffer,
    required this.fp2Buffer,
    required this.threshold,
    this.height = 120,
    this.blinkMarkers = const [],
  });

  /// Ring buffer of recent Fp1 values (rectified, in µV).
  final List<double> fp1Buffer;

  /// Ring buffer of recent Fp2 values (rectified, in µV).
  final List<double> fp2Buffer;

  /// Current adaptive threshold (µV).
  final double threshold;

  /// Widget height.
  final double height;

  /// Recent blink events as fractional positions (0.0=left, 1.0=right).
  final List<BlinkMarkerData> blinkMarkers;

  @override
  State<BlinkWaveformMonitor> createState() => _BlinkWaveformMonitorState();
}

class BlinkMarkerData {
  final double position; // 0.0 – 1.0
  final BlinkType type;
  const BlinkMarkerData(this.position, this.type);
}

class _BlinkWaveformMonitorState extends State<BlinkWaveformMonitor> {
  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: colors.tintFaint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _WaveformPainter(
            fp1: widget.fp1Buffer,
            fp2: widget.fp2Buffer,
            threshold: widget.threshold,
            markers: widget.blinkMarkers,
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.fp1,
    required this.fp2,
    required this.threshold,
    required this.markers,
  });

  final List<double> fp1;
  final List<double> fp2;
  final double threshold;
  final List<BlinkMarkerData> markers;

  @override
  void paint(Canvas canvas, Size size) {
    if (fp1.isEmpty && fp2.isEmpty) return;

    // Determine y-axis scale
    double maxVal = threshold * 2;
    for (final v in fp1) {
      if (v.abs() > maxVal) maxVal = v.abs();
    }
    for (final v in fp2) {
      if (v.abs() > maxVal) maxVal = v.abs();
    }
    maxVal *= 1.1; // 10% padding

    final h = size.height;
    final w = size.width;
    final midY = h / 2;

    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, midY), Offset(w, midY), gridPaint);
    canvas.drawLine(Offset(0, h * 0.25), Offset(w, h * 0.25), gridPaint);
    canvas.drawLine(Offset(0, h * 0.75), Offset(w, h * 0.75), gridPaint);

    // Threshold lines
    final thY1 = midY - (threshold / maxVal) * midY;
    final thY2 = midY + (threshold / maxVal) * midY;
    final thPaint = Paint()
      ..color = AppTheme.amber.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, thY1), Offset(w, thY1), thPaint);
    canvas.drawLine(Offset(0, thY2), Offset(w, thY2), thPaint);

    // Draw traces
    _drawTrace(
      canvas,
      size,
      fp1,
      maxVal,
      midY,
      const Color(0xFF58A6FF),
    ); // Fp1: blue
    _drawTrace(
      canvas,
      size,
      fp2,
      maxVal,
      midY,
      const Color(0xFFFF6B8A),
    ); // Fp2: pink

    // Blink markers
    for (final m in markers) {
      final x = m.position * w;
      final markerPaint = Paint()
        ..color = AppTheme.seaGreen.withValues(alpha: 0.7)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, 0), Offset(x, h), markerPaint);
      // Small dot at top
      canvas.drawCircle(Offset(x, 8), 4, Paint()..color = AppTheme.seaGreen);
    }
  }

  void _drawTrace(
    Canvas canvas,
    Size size,
    List<double> data,
    double maxVal,
    double midY,
    Color color,
  ) {
    if (data.isEmpty) return;
    final w = size.width;
    final n = data.length;
    final dx = w / (n - 1).clamp(1, n);

    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = dx * i;
      final y = midY - (data[i] / maxVal) * midY;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Glow
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Crisp line
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => true; // Always repaint (live data)
}

/// Standalone mini waveform that receives raw sample values and manages its
/// own ring buffer internally.
class MiniWaveformChart extends StatefulWidget {
  const MiniWaveformChart({
    super.key,
    this.height = 100,
    this.bufferSize = 250,
  });

  final double height;
  final int bufferSize;

  @override
  State<MiniWaveformChart> createState() => MiniWaveformChartState();
}

class MiniWaveformChartState extends State<MiniWaveformChart> {
  final _fp1 = ListQueue<double>();
  final _fp2 = ListQueue<double>();
  double _threshold = 50.0;
  final _markers = <BlinkMarkerData>[];

  void addSample(double fp1, double fp2) {
    _fp1.addLast(fp1);
    _fp2.addLast(fp2);
    if (_fp1.length > widget.bufferSize) _fp1.removeFirst();
    if (_fp2.length > widget.bufferSize) _fp2.removeFirst();
  }

  void setThreshold(double t) => _threshold = t;

  void addBlinkMarker(BlinkType type) {
    if (_fp1.isEmpty) return;
    _markers.add(BlinkMarkerData(1.0, type)); // right edge = latest
    if (_markers.length > 5) _markers.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    return BlinkWaveformMonitor(
      fp1Buffer: _fp1.toList(),
      fp2Buffer: _fp2.toList(),
      threshold: _threshold,
      height: widget.height,
      blinkMarkers: _markers,
    );
  }
}
