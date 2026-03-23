import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/blink_profile.dart';
import '../services/blink_detector_service.dart';
import '../widgets/blink_waveform_monitor.dart';
import '../widgets/command_feedback_overlay.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Live Test Screen — Free-run blink detection validation
//
// Shows real-time detection with:
//   · Fp1/Fp2 waveform with threshold + blink markers
//   · Detection history log (last 20 events)
//   · Per-command confidence meters
//   · Accuracy counter (session stats)
// ─────────────────────────────────────────────────────────────────────────────

class LiveTestScreen extends ConsumerStatefulWidget {
  const LiveTestScreen({super.key});

  @override
  ConsumerState<LiveTestScreen> createState() => _LiveTestScreenState();
}

class _LiveTestScreenState extends ConsumerState<LiveTestScreen> {
  late final BleSourceService _bleSource;
  late final BlinkDetectorService _detector;

  StreamSubscription<SignalSample>? _signalSub;
  StreamSubscription<BlinkEvent>? _blinkSub;
  Timer? _refreshTimer;

  final _waveformKey = GlobalKey<MiniWaveformChartState>();
  final _overlayKey = GlobalKey<CommandFeedbackOverlayState>();

  // Detection stats
  final _history = <BlinkEvent>[];
  int _singleCount = 0;
  int _doubleCount = 0;
  int _longCount = 0;
  int _tripleCount = 0;
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    _bleSource = ref.read(bleSourceServiceProvider);
    _sessionStart = DateTime.now();

    // Load profile and create detector
    _initDetector();
  }

  Future<void> _initDetector() async {
    BlinkProfile? profile;
    final db = ref.read(localDbServiceProvider);
    final json = await db.getSetting('blink_profile');
    if (json != null) {
      profile = BlinkProfile.decode(json);
    }

    _detector = BlinkDetectorService(
      profile: profile,
      fp1Index: 0,
      fp2Index: 1,
    );

    _detector.start(_bleSource.signalStream);

    _blinkSub = _detector.blinkStream.listen(_onBlink);

    _signalSub = _bleSource.signalStream.listen((sample) {
      if (sample.channels.length >= 2) {
        _waveformKey.currentState?.addSample(
          sample.channels[0].abs(),
          sample.channels[1].abs(),
        );
        _waveformKey.currentState?.setThreshold(_detector.currentThreshold);
      }
    });

    _refreshTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _signalSub?.cancel();
    _blinkSub?.cancel();
    _refreshTimer?.cancel();
    _detector.dispose();
    super.dispose();
  }

  void _onBlink(BlinkEvent event) {
    HapticFeedback.mediumImpact();
    _waveformKey.currentState?.addBlinkMarker(event.type);

    setState(() {
      _history.insert(0, event);
      if (_history.length > 20) _history.removeLast();

      switch (event.type) {
        case BlinkType.single:
          _singleCount++;
          break;
        case BlinkType.double:
          _doubleCount++;
          break;
        case BlinkType.long:
          _longCount++;
          break;
        case BlinkType.triple:
          _tripleCount++;
          break;
      }
    });

    _overlayKey.currentState?.show(event.type, actionLabel: event.type.label);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.miruns;
    final elapsed = _sessionStart != null
        ? DateTime.now().difference(_sessionStart!)
        : Duration.zero;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: colors.textBody,
                        ),
                        onPressed: () => context.pop(),
                      ),
                      Expanded(
                        child: Text(
                          'Live Test',
                          style: AppTheme.geist(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: colors.textStrong,
                          ),
                        ),
                      ),
                      // Session timer
                      Text(
                        _formatDuration(elapsed),
                        style: AppTheme.geistMono(
                          fontSize: 13,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Stats row ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _StatChip(
                        label: 'Single',
                        count: _singleCount,
                        color: AppTheme.seaGreen,
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        label: 'Double',
                        count: _doubleCount,
                        color: const Color(0xFF58A6FF),
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        label: 'Long',
                        count: _longCount,
                        color: AppTheme.amber,
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        label: 'Triple',
                        count: _tripleCount,
                        color: AppTheme.crimson,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Waveform ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF58A6FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            'Fp1',
                            style: AppTheme.geistMono(
                              fontSize: 10,
                              color: const Color(0xFF58A6FF),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF6B8A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            'Fp2',
                            style: AppTheme.geistMono(
                              fontSize: 10,
                              color: const Color(0xFFFF6B8A),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'TH: ${_detector.currentThreshold.toStringAsFixed(0)} µV',
                            style: AppTheme.geistMono(
                              fontSize: 10,
                              color: AppTheme.amber,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      MiniWaveformChart(
                        key: _waveformKey,
                        height: 140,
                        bufferSize: 750,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Detection log header ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'DETECTION LOG',
                        style: AppTheme.geistMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.textMuted,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      if (_history.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _history.clear();
                              _singleCount = 0;
                              _doubleCount = 0;
                              _longCount = 0;
                              _tripleCount = 0;
                              _sessionStart = DateTime.now();
                            });
                          },
                          child: Text(
                            'Clear',
                            style: AppTheme.geist(
                              fontSize: 12,
                              color: AppTheme.crimson,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── Detection log ───────────────────────────────────────
                Expanded(
                  child: _history.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility_rounded,
                                size: 48,
                                color: colors.tintMedium,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Waiting for blinks…',
                                style: AppTheme.geist(
                                  fontSize: 15,
                                  color: colors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Try a single, double, or long blink',
                                style: AppTheme.geist(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _history.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            return _DetectionLogTile(event: _history[index]);
                          },
                        ),
                ),
              ],
            ),
          ),

          // ── Command overlay ─────────────────────────────────────────
          CommandFeedbackOverlay(key: _overlayKey),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Supporting widgets ──────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: AppTheme.geistMono(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: AppTheme.geistMono(
                fontSize: 9,
                color: color.withValues(alpha: 0.7),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectionLogTile extends StatelessWidget {
  const _DetectionLogTile({required this.event});
  final BlinkEvent event;

  Color _typeColor(BlinkType type) {
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
    final colors = context.miruns;
    final color = _typeColor(event.type);
    final confidence = (event.confidence * 100).round();
    final time = event.timestamp;
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.tintFaint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Type indicator
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),

          // Type label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.type.label,
                  style: AppTheme.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  '${event.rawPeakAmplitude.toStringAsFixed(0)} µV  ·  $confidence% conf',
                  style: AppTheme.geistMono(
                    fontSize: 10,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Confidence bar
          SizedBox(
            width: 40,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: event.confidence.clamp(0.0, 1.0),
                backgroundColor: colors.tintSubtle,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 5,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Timestamp
          Text(
            timeStr,
            style: AppTheme.geistMono(fontSize: 10, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}
