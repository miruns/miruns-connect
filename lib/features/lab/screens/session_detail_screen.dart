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
  late CaptureEntry _entry;

  /// Current scrubber position as fraction 0..1
  double _scrubPosition = 0.0;

  /// Visible time window in seconds
  double _windowSeconds = 4.0;

  /// Selected channel for band power display
  int _selectedChannel = 0;

  /// Lazily created FFT engine (created on first use with correct size).
  FftEngine? _fft;

  /// Zoom level for waveform (1.0 = fit window, higher = zoomed in).
  double _zoomLevel = 1.0;

  /// Pan offset as fraction 0..1 within the zoomed window.
  double _panOffset = 0.0;

  /// Baseline zoom when pinch starts.
  double _baseZoom = 1.0;

  /// Artifact markers (stored as tags with prefix `artifact:`).
  List<_ArtifactMarker> _artifacts = [];

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _session = _entry.signalSession!;
    _artifacts = _parseArtifacts(_entry.tags);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _dateStr =>
      DateFormat('EEEE, MMM d yyyy · HH:mm').format(_entry.timestamp);

  /// Parse title from first line of userNote (if present).
  String? get _sessionTitle {
    final note = _entry.userNote;
    if (note == null || note.isEmpty) return null;
    final firstLine = note.split('\n').first.trim();
    return firstLine.isEmpty ? null : firstLine;
  }

  /// Parse notes from lines after the first in userNote.
  String? get _sessionNotes {
    final note = _entry.userNote;
    if (note == null || note.isEmpty) return null;
    final lines = note.split('\n');
    if (lines.length <= 1) return null;
    final rest = lines.sublist(1).join('\n').trim();
    return rest.isEmpty ? null : rest;
  }

  /// Show edit dialog for session title and notes.
  void _editTitleAndNotes() {
    final titleCtrl = TextEditingController(text: _sessionTitle ?? '');
    final notesCtrl = TextEditingController(text: _sessionNotes ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.deepSea,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.fog.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Session Details',
              style: AppTheme.geist(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.moonbeam,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              style: AppTheme.geist(fontSize: 15, color: AppTheme.moonbeam),
              decoration: InputDecoration(
                hintText: 'Session title',
                hintStyle: AppTheme.geist(fontSize: 15, color: AppTheme.mist),
                filled: true,
                fillColor: AppTheme.tidePool,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  borderSide: BorderSide(color: AppTheme.shimmer),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  borderSide: BorderSide(color: AppTheme.shimmer),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  borderSide: BorderSide(color: AppTheme.glow),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              maxLines: 4,
              style: AppTheme.geist(fontSize: 14, color: AppTheme.moonbeam),
              decoration: InputDecoration(
                hintText: 'Notes…',
                hintStyle: AppTheme.geist(fontSize: 14, color: AppTheme.mist),
                filled: true,
                fillColor: AppTheme.tidePool,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  borderSide: BorderSide(color: AppTheme.shimmer),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  borderSide: BorderSide(color: AppTheme.shimmer),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  borderSide: BorderSide(color: AppTheme.glow),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final title = titleCtrl.text.trim();
                  final notes = notesCtrl.text.trim();
                  String? userNote;
                  if (title.isNotEmpty || notes.isNotEmpty) {
                    userNote = title.isNotEmpty && notes.isNotEmpty
                        ? '$title\n$notes'
                        : title.isNotEmpty
                        ? title
                        : notes;
                  }
                  final updated = _entry.copyWith(
                    userNote: userNote,
                    clearUserNote: userNote == null,
                  );
                  ref.read(localDbServiceProvider).saveCapture(updated);
                  setState(() => _entry = updated);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.glow.withValues(alpha: 0.15),
                  foregroundColor: AppTheme.glow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                ),
                child: Text(
                  'Save',
                  style: AppTheme.geist(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

    // Base window from the scrubber.
    final baseWindowMs = (_windowSeconds * 1000).toInt();
    final maxStartMs = (totalDuration - baseWindowMs).clamp(0, totalDuration);
    final baseStartMs = (_scrubPosition * maxStartMs).toInt();

    // Apply zoom: divide the window by zoom level.
    final zoomedWindowMs = (baseWindowMs / _zoomLevel).toInt().clamp(
      1,
      baseWindowMs,
    );
    final maxPanMs = baseWindowMs - zoomedWindowMs;
    final panMs = (_panOffset * maxPanMs).toInt();
    final startMs = baseStartMs + panMs;
    final endMs = (startMs + zoomedWindowMs).clamp(0, totalDuration);

    final firstTime = _session.samples.first.time;
    return _session.samples.where((s) {
      final ms = s.time.difference(firstTime).inMilliseconds;
      return ms >= startMs && ms <= endMs;
    }).toList();
  }

  void _onScaleStart(ScaleStartDetails _) {
    _baseZoom = _zoomLevel;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      // Pinch zoom
      if (details.scale != 1.0) {
        _zoomLevel = (_baseZoom * details.scale).clamp(1.0, 20.0);
      }
      // Horizontal pan (single finger drag)
      if (details.pointerCount == 1) {
        _panOffset = (_panOffset - details.focalPointDelta.dx * 0.002).clamp(
          0.0,
          1.0,
        );
      }
    });
  }

  // ── Artifact marking ──────────────────────────────────────────────────────

  static const _artifactTypes = ['Blink', 'Jaw clench', 'Movement', 'Other'];

  List<_ArtifactMarker> _parseArtifacts(List<String> tags) {
    return tags
        .where((t) => t.startsWith('artifact:'))
        .map((t) {
          final parts = t.split(':');
          if (parts.length < 3) return null;
          final ms = int.tryParse(parts[1]);
          if (ms == null) return null;
          return _ArtifactMarker(timeMs: ms, type: parts.sublist(2).join(':'));
        })
        .whereType<_ArtifactMarker>()
        .toList()
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  }

  List<String> _serializeArtifacts(List<_ArtifactMarker> markers) {
    return markers.map((m) => 'artifact:${m.timeMs}:${m.type}').toList();
  }

  void _addArtifact(int timeMs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.deepSea,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.fog.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Mark Artifact at ${_formatMs(timeMs)}',
              style: AppTheme.geist(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.moonbeam,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(_artifactTypes.length, (i) {
              final type = _artifactTypes[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _artifactIcon(type),
                  color: AppTheme.amber,
                  size: 20,
                ),
                title: Text(
                  type,
                  style: AppTheme.geist(fontSize: 14, color: AppTheme.moonbeam),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _persistArtifact(timeMs, type);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _persistArtifact(int timeMs, String type) {
    final marker = _ArtifactMarker(timeMs: timeMs, type: type);
    final updated = List<_ArtifactMarker>.from(_artifacts)..add(marker);
    updated.sort((a, b) => a.timeMs.compareTo(b.timeMs));

    // Merge artifact tags with non-artifact tags.
    final nonArtifactTags = _entry.tags
        .where((t) => !t.startsWith('artifact:'))
        .toList();
    final allTags = [...nonArtifactTags, ..._serializeArtifacts(updated)];

    final newEntry = _entry.copyWith(tags: allTags);
    ref.read(localDbServiceProvider).saveCapture(newEntry);
    setState(() {
      _artifacts = updated;
      _entry = newEntry;
    });
  }

  void _removeArtifact(_ArtifactMarker marker) {
    final updated = List<_ArtifactMarker>.from(_artifacts)
      ..removeWhere((m) => m.timeMs == marker.timeMs && m.type == marker.type);

    final nonArtifactTags = _entry.tags
        .where((t) => !t.startsWith('artifact:'))
        .toList();
    final allTags = [...nonArtifactTags, ..._serializeArtifacts(updated)];

    final newEntry = _entry.copyWith(tags: allTags);
    ref.read(localDbServiceProvider).saveCapture(newEntry);
    setState(() {
      _artifacts = updated;
      _entry = newEntry;
    });
  }

  /// Convert a tap on the waveform to a timestamp in ms relative to session start.
  void _onWaveformTap(TapUpDetails details, BoxConstraints constraints) {
    final windowSamples = _getWindowSamples();
    if (windowSamples.length < 2) return;

    final tapFraction = details.localPosition.dx / constraints.maxWidth;
    final firstTime = windowSamples.first.time;
    final lastTime = windowSamples.last.time;
    final windowDuration = lastTime.difference(firstTime).inMilliseconds;
    final tapTimeMs = (tapFraction * windowDuration).toInt();

    // Convert to session-relative time.
    final sessionStartTime = _session.samples.first.time;
    final absoluteMs =
        firstTime.difference(sessionStartTime).inMilliseconds + tapTimeMs;

    HapticFeedback.mediumImpact();
    _addArtifact(absoluteMs);
  }

  /// Filter artifacts that fall within the current window of samples.
  List<_ArtifactMarker> _artifactsInWindow(List<SignalSample> windowSamples) {
    if (windowSamples.length < 2 || _artifacts.isEmpty) return [];
    final sessionStart = _session.samples.first.time;
    final winStartMs = windowSamples.first.time
        .difference(sessionStart)
        .inMilliseconds;
    final winEndMs = windowSamples.last.time
        .difference(sessionStart)
        .inMilliseconds;
    return _artifacts
        .where((m) => m.timeMs >= winStartMs && m.timeMs <= winEndMs)
        .toList();
  }

  String _formatMs(int ms) {
    final s = (ms / 1000).toStringAsFixed(1);
    return '${s}s';
  }

  IconData _artifactIcon(String type) {
    switch (type) {
      case 'Blink':
        return Icons.visibility_off_rounded;
      case 'Jaw clench':
        return Icons.face_rounded;
      case 'Movement':
        return Icons.directions_walk_rounded;
      default:
        return Icons.flag_rounded;
    }
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
      await ref.read(localDbServiceProvider).deleteCapture(_entry.id);
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
                    child: GestureDetector(
                      onTap: _editTitleAndNotes,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_sessionTitle != null)
                            Text(
                              _sessionTitle!,
                              style: AppTheme.geist(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.moonbeam,
                                letterSpacing: -0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            _dateStr,
                            style: AppTheme.geist(
                              fontSize: _sessionTitle != null ? 11 : 15,
                              fontWeight: _sessionTitle != null
                                  ? FontWeight.w400
                                  : FontWeight.w500,
                              color: _sessionTitle != null
                                  ? AppTheme.fog
                                  : AppTheme.moonbeam,
                              letterSpacing: -0.3,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _editTitleAndNotes,
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppTheme.fog,
                      size: 18,
                    ),
                    tooltip: 'Edit title & notes',
                  ),
                  IconButton(
                    onPressed: () =>
                        ResearchExportSheet.showForCapture(context, _entry),
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
              child: Row(
                children: [
                  Text(
                    'Signal',
                    style: AppTheme.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.fog,
                    ),
                  ),
                  if (_zoomLevel > 1.0) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        _zoomLevel = 1.0;
                        _panOffset = 0.0;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.glow.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_zoomLevel.toStringAsFixed(1)}× · Reset',
                          style: AppTheme.geistMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.glow,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(
                  builder: (ctx, constraints) => GestureDetector(
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onTapUp: (d) => _onWaveformTap(d, constraints),
                    child: _ReplayChart(
                      samples: windowSamples,
                      channels: _session.channels,
                      artifacts: _artifactsInWindow(windowSamples),
                      onRemoveArtifact: _removeArtifact,
                    ),
                  ),
                ),
              ),
            ),

            // ── Artifact chips ──────────────────────────────────────────
            if (_artifacts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: SizedBox(
                  height: 28,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _artifacts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (ctx, i) {
                      final m = _artifacts[i];
                      return Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        backgroundColor: AppTheme.amber.withValues(alpha: 0.15),
                        side: BorderSide(
                          color: AppTheme.amber.withValues(alpha: 0.3),
                        ),
                        deleteIconColor: AppTheme.amber,
                        label: Text(
                          '${m.type} ${_formatMs(m.timeMs)}',
                          style: AppTheme.geist(
                            fontSize: 10,
                            color: AppTheme.amber,
                          ),
                        ),
                        onDeleted: () => _removeArtifact(m),
                      );
                    },
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
                            onTap: () => setState(() {
                              _windowSeconds = 2;
                              _zoomLevel = 1.0;
                              _panOffset = 0.0;
                            }),
                          ),
                          _WindowButton(
                            label: '4s',
                            active: _windowSeconds == 4,
                            onTap: () => setState(() {
                              _windowSeconds = 4;
                              _zoomLevel = 1.0;
                              _panOffset = 0.0;
                            }),
                          ),
                          _WindowButton(
                            label: '10s',
                            active: _windowSeconds == 10,
                            onTap: () => setState(() {
                              _windowSeconds = 10;
                              _zoomLevel = 1.0;
                              _panOffset = 0.0;
                            }),
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
  final List<_ArtifactMarker> artifacts;
  final ValueChanged<_ArtifactMarker>? onRemoveArtifact;

  const _ReplayChart({
    required this.samples,
    required this.channels,
    this.artifacts = const [],
    this.onRemoveArtifact,
  });

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
        painter: _ReplayPainter(
          samples: samples,
          channels: channels,
          artifacts: artifacts,
          windowStartTime: samples.first.time,
          windowEndTime: samples.last.time,
        ),
      ),
    );
  }
}

class _ReplayPainter extends CustomPainter {
  final List<SignalSample> samples;
  final List<ChannelDescriptor> channels;
  final List<_ArtifactMarker> artifacts;
  final DateTime windowStartTime;
  final DateTime windowEndTime;

  _ReplayPainter({
    required this.samples,
    required this.channels,
    this.artifacts = const [],
    required this.windowStartTime,
    required this.windowEndTime,
  });

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

    // ── Artifact markers (vertical lines + labels) ──────────────────────
    if (artifacts.isNotEmpty && samples.length >= 2) {
      final sessionStart = samples.first.time;
      final windowDurMs = windowEndTime
          .difference(windowStartTime)
          .inMilliseconds;
      if (windowDurMs > 0) {
        final windowStartMs = windowStartTime
            .difference(sessionStart)
            .inMilliseconds;

        final markerPaint = Paint()
          ..color = AppTheme.amber.withValues(alpha: 0.7)
          ..strokeWidth = 1.5;

        for (final m in artifacts) {
          final relMs = m.timeMs - windowStartMs;
          final frac = relMs / windowDurMs;
          if (frac < 0 || frac > 1) continue;
          final x = frac * size.width;

          // Vertical line
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), markerPaint);

          // Small diamond marker at top
          final diamondPath = Path()
            ..moveTo(x, 4)
            ..lineTo(x + 4, 8)
            ..lineTo(x, 12)
            ..lineTo(x - 4, 8)
            ..close();
          canvas.drawPath(diamondPath, Paint()..color = AppTheme.amber);

          // Type label
          final tp = TextPainter(
            text: TextSpan(
              text: m.type,
              style: const TextStyle(
                fontSize: 9,
                color: AppTheme.amber,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: ui.TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(x + 6, 2));
        }
      }
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

// ─────────────────────────────────────────────────────────────────────────────
// Artifact marker data class
// ─────────────────────────────────────────────────────────────────────────────

class _ArtifactMarker {
  final int timeMs;
  final String type;
  const _ArtifactMarker({required this.timeMs, required this.type});
}
