import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/capture_entry.dart';
import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/fft_engine.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/research_export_sheet.dart';

/// Per-channel colour palette (same as live_signal_chart).
const _channelColors = [
  Color(0xFF00E676), // green
  Color(0xFF40C4FF), // blue
  Color(0xFFFF5252), // red
  Color(0xFFFFD740), // amber
  Color(0xFFE040FB), // purple
  Color(0xFF00E5FF), // cyan
  Color(0xFFFF6E40), // deep orange
  Color(0xFF69F0AE), // light green
];

// ─────────────────────────────────────────────────────────────────────────────
// Session Detail — replay & overview of a recorded signal session
//
// Layout:
//   · Top bar    : back button, session date
//   · Stats row  : duration, channels, sample rate
//   · Waveform   : multi-channel replay with scrubber
//   · Band power : delta/theta/alpha/beta/gamma bars
// ─────────────────────────────────────────────────────────────────────────────

class SessionDetailScreen extends ConsumerStatefulWidget {
  final CaptureEntry entry;

  const SessionDetailScreen({super.key, required this.entry});

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  late final SignalSession _session;

  /// Current scrubber position as fraction 0..1
  double _scrubPosition = 0.0;

  /// Visible time window in seconds
  double _windowSeconds = 4.0;

  /// Selected channel for band power display
  int _selectedChannel = 0;

  /// Lazily created FFT engine (created on first use with correct size).
  FftEngine? _fft;

  @override
  void initState() {
    super.initState();
    _session = widget.entry.signalSession!;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _dateStr =>
      DateFormat('EEEE, MMM d yyyy · HH:mm').format(widget.entry.timestamp);

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Compute band power from visible window samples for a single channel
  /// using a real Cooley-Tukey FFT via [FftEngine].
  Map<String, double> _computeBandPower(
    List<SignalSample> windowSamples,
    int channelIndex,
  ) {
    if (windowSamples.length < 4) {
      return {'Delta': 0, 'Theta': 0, 'Alpha': 0, 'Beta': 0, 'Gamma': 0};
    }

    final values = windowSamples
        .map(
          (s) =>
              s.channels.length > channelIndex ? s.channels[channelIndex] : 0.0,
        )
        .toList();

    // Need power-of-2 window for FFT. Pick largest that fits.
    int fftSize = 1;
    while (fftSize * 2 <= values.length) {
      fftSize *= 2;
    }
    if (fftSize < 8) {
      // Too few samples for meaningful FFT — fall back to zero.
      return {'Delta': 0, 'Theta': 0, 'Alpha': 0, 'Beta': 0, 'Gamma': 0};
    }

    // Re-create engine only when size changes.
    if (_fft == null || _fft!.n != fftSize) {
      _fft = FftEngine(n: fftSize, sampleRateHz: _session.sampleRateHz);
    }

    final result = _fft!.analyse(values.sublist(values.length - fftSize));

    return {
      'Delta': result.bandPowers[FrequencyBand.delta] ?? 0,
      'Theta': result.bandPowers[FrequencyBand.theta] ?? 0,
      'Alpha': result.bandPowers[FrequencyBand.alpha] ?? 0,
      'Beta': result.bandPowers[FrequencyBand.beta] ?? 0,
      'Gamma': result.bandPowers[FrequencyBand.gamma] ?? 0,
    };
  }

  List<SignalSample> _getWindowSamples() {
    if (_session.samples.isEmpty) return [];

    final totalDuration = _session.duration.inMilliseconds;
    if (totalDuration <= 0) return _session.samples;

    final windowMs = (_windowSeconds * 1000).toInt();
    final maxStartMs = (totalDuration - windowMs).clamp(0, totalDuration);
    final startMs = (_scrubPosition * maxStartMs).toInt();
    final endMs = (startMs + windowMs).clamp(0, totalDuration);

    final firstTime = _session.samples.first.time;
    return _session.samples.where((s) {
      final ms = s.time.difference(firstTime).inMilliseconds;
      return ms >= startMs && ms <= endMs;
    }).toList();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.deepSea,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        title: Text(
          'Delete session?',
          style: AppTheme.geist(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppTheme.moonbeam,
          ),
        ),
        content: Text(
          'This recording will be permanently removed.',
          style: AppTheme.geist(fontSize: 14, color: AppTheme.fog),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppTheme.geist(color: AppTheme.fog)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: AppTheme.geist(color: AppTheme.crimson),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(localDbServiceProvider).deleteCapture(widget.entry.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final duration = _session.duration;
    final windowSamples = _getWindowSamples();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.void_,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ─────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(8, top + 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppTheme.moonbeam,
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _dateStr,
                      style: AppTheme.geist(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.moonbeam,
                        letterSpacing: -0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => ResearchExportSheet.showForCapture(
                      context,
                      widget.entry,
                    ),
                    icon: const Icon(
                      Icons.ios_share_rounded,
                      color: AppTheme.fog,
                      size: 20,
                    ),
                    tooltip: 'Export & share',
                  ),
                  IconButton(
                    onPressed: _confirmDelete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.fog,
                      size: 20,
                    ),
                    tooltip: 'Delete session',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Stats row ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _StatChip(
                    label: 'Duration',
                    value: _formatDuration(duration),
                    icon: Icons.timer_outlined,
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    label: 'Channels',
                    value: '${_session.channelCount}',
                    icon: Icons.graphic_eq_rounded,
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    label: 'Rate',
                    value: '${_session.sampleRateHz.toInt()} Hz',
                    icon: Icons.speed_rounded,
                  ),
                  if (_session.deviceName != null) ...[
                    const SizedBox(width: 10),
                    _StatChip(
                      label: 'Device',
                      value: _session.deviceName!,
                      icon: Icons.bluetooth_rounded,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Waveform replay ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Signal',
                style: AppTheme.geist(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.fog,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _ReplayChart(
                  samples: windowSamples,
                  channels: _session.channels,
                ),
              ),
            ),

            // ── Scrubber ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: AppTheme.glow,
                      inactiveTrackColor: AppTheme.shimmer,
                      thumbColor: AppTheme.glow,
                      overlayColor: AppTheme.glow.withValues(alpha: 0.12),
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: _scrubPosition,
                      onChanged: (v) => setState(() => _scrubPosition = v),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Window: ${_windowSeconds.toStringAsFixed(0)}s',
                        style: AppTheme.geist(
                          fontSize: 11,
                          color: AppTheme.mist,
                        ),
                      ),
                      Row(
                        children: [
                          _WindowButton(
                            label: '2s',
                            active: _windowSeconds == 2,
                            onTap: () => setState(() => _windowSeconds = 2),
                          ),
                          _WindowButton(
                            label: '4s',
                            active: _windowSeconds == 4,
                            onTap: () => setState(() => _windowSeconds = 4),
                          ),
                          _WindowButton(
                            label: '10s',
                            active: _windowSeconds == 10,
                            onTap: () => setState(() => _windowSeconds = 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Band power bars ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Band Power',
                    style: AppTheme.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.fog,
                    ),
                  ),
                  const Spacer(),
                  // Channel selector chips
                  if (_session.channelCount > 1)
                    ...List.generate(_session.channelCount, (i) {
                      final isActive = _selectedChannel == i;
                      final color = _channelColors[i % _channelColors.length];
                      return Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedChannel = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? color.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isActive
                                    ? color.withValues(alpha: 0.6)
                                    : AppTheme.shimmer,
                                width: isActive ? 1.2 : 0.7,
                              ),
                            ),
                            child: Text(
                              _session.channels[i].label,
                              style: AppTheme.geistMono(
                                fontSize: 9,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: isActive ? color : AppTheme.mist,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: _BandPowerBars(
                  bandPower: _computeBandPower(windowSamples, _selectedChannel),
                ),
              ),
            ),

            SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat chip — compact metadata pill
// ─────────────────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.tidePool,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: AppTheme.shimmer, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: AppTheme.mist),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: AppTheme.geist(fontSize: 10, color: AppTheme.mist),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTheme.geist(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.moonbeam,
                letterSpacing: -0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Window button — time window selector
// ─────────────────────────────────────────────────────────────────────────────

class _WindowButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _WindowButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.glow.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(
            color: active ? AppTheme.glow : AppTheme.shimmer,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.geist(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppTheme.glow : AppTheme.fog,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Replay chart — multi-channel waveform (stacked strips)
// ─────────────────────────────────────────────────────────────────────────────

class _ReplayChart extends StatelessWidget {
  final List<SignalSample> samples;
  final List<ChannelDescriptor> channels;

  const _ReplayChart({required this.samples, required this.channels});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return Center(
        child: Text(
          'No data in window',
          style: AppTheme.geist(fontSize: 13, color: AppTheme.mist),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.shimmer, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ReplayPainter(samples: samples, channels: channels),
      ),
    );
  }
}

class _ReplayPainter extends CustomPainter {
  final List<SignalSample> samples;
  final List<ChannelDescriptor> channels;

  _ReplayPainter({required this.samples, required this.channels});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2 || channels.isEmpty) return;

    final nCh = channels.length;
    final stripHeight = size.height / nCh;
    final dx = size.width / (samples.length - 1);

    // Grid lines (horizontal strip separators)
    final gridPaint = Paint()
      ..color = AppTheme.shimmer
      ..strokeWidth = 0.5;

    for (int ch = 1; ch < nCh; ch++) {
      final y = ch * stripHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw each channel
    for (int ch = 0; ch < nCh; ch++) {
      // Compute min/max for autoscale
      double min = double.infinity;
      double max = double.negativeInfinity;
      for (final s in samples) {
        if (ch < s.channels.length) {
          final v = s.channels[ch];
          if (v < min) min = v;
          if (v > max) max = v;
        }
      }
      final range = (max - min).clamp(0.001, double.infinity);

      final paint = Paint()
        ..color = _channelColors[ch % _channelColors.length]
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;

      final path = Path();
      final topY = ch * stripHeight + 4;
      final usableH = stripHeight - 8;
      bool started = false;

      for (int i = 0; i < samples.length; i++) {
        final s = samples[i];
        if (ch >= s.channels.length) continue;
        final v = s.channels[ch];
        final x = i * dx;
        final y = topY + usableH * (1 - (v - min) / range);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);

      // Channel label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: channels[ch].label,
          style: const TextStyle(
            fontSize: 10,
            color: AppTheme.fog,
            fontFamily: 'Inter',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      labelPainter.paint(canvas, Offset(4, topY + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ReplayPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Band power bars
// ─────────────────────────────────────────────────────────────────────────────

const _bandColors = {
  'Delta': Color(0xFF7C3AED), // violet
  'Theta': Color(0xFF2563EB), // blue
  'Alpha': Color(0xFF10B981), // emerald
  'Beta': Color(0xFFF59E0B), // amber
  'Gamma': Color(0xFFEF4444), // red
};

class _BandPowerBars extends StatelessWidget {
  final Map<String, double> bandPower;
  const _BandPowerBars({required this.bandPower});

  @override
  Widget build(BuildContext context) {
    final maxVal = bandPower.values
        .fold<double>(0, (prev, v) => v > prev ? v : prev)
        .clamp(0.001, double.infinity);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: bandPower.entries.map((e) {
        final fraction = (e.value / maxVal).clamp(0.0, 1.0);
        final color = _bandColors[e.key] ?? AppTheme.glow;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: fraction.clamp(0.05, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.7),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  e.key,
                  style: AppTheme.geist(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.fog,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
