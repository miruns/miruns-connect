import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../../../../../../../core/theme/app_theme.dart';
import '../../../core/models/capture_entry.dart';
import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/widgets/bci_decoding_view.dart';
import '../../../core/widgets/bci_monitoring_view.dart';
import '../../../core/widgets/live_signal_chart.dart';
import '../../../core/widgets/spectral_analysis_chart.dart';

/// Signal visualisation modes available during streaming.
enum SignalViewMode {
  timeDomain('Waveform', Icons.timeline_rounded, AppTheme.glow),
  spectral('Spectral', Icons.graphic_eq_rounded, AppTheme.aurora),
  decoding('Decoding', Icons.psychology_rounded, Color(0xFFFF9800)),
  monitoring('Monitor', Icons.monitor_heart_rounded, AppTheme.starlight);

  final String label;
  final IconData icon;
  final Color color;

  const SignalViewMode(this.label, this.icon, this.color);

  SignalViewMode get next =>
      SignalViewMode.values[(index + 1) % SignalViewMode.values.length];
}

/// Full-screen live signal monitor for a specific BLE source.
///
/// Flow: **Scan → Pick device → Connect → Stream + live chart**.
///
/// Reached via `/sources/:sourceId` — the source id is looked up in the
/// [BleSourceRegistry].
class LiveSignalScreen extends ConsumerStatefulWidget {
  final String sourceId;

  const LiveSignalScreen({super.key, required this.sourceId});

  @override
  ConsumerState<LiveSignalScreen> createState() => _LiveSignalScreenState();
}

class _LiveSignalScreenState extends ConsumerState<LiveSignalScreen> {
  late final BleSourceService _service;
  BleSourceProvider? _provider;

  // Discovered devices during scan.
  List<BleSourceDevice> _devices = [];
  StreamSubscription<List<BleSourceDevice>>? _devicesSub;
  StreamSubscription<BleSourceState>? _stateSub;

  BleSourceState _state = BleSourceState.idle;
  String? _errorMessage;

  // Recording
  final List<SignalSample> _recordedSamples = [];
  StreamSubscription<SignalSample>? _recordSub;
  bool _isRecording = false;
  Timer? _recordingUiTimer;
  DateTime? _recordingStartTime;

  // Event markers placed during live recording.
  final List<_LiveEventMarker> _eventMarkers = [];

  // Active visualisation mode.
  SignalViewMode _viewMode = SignalViewMode.timeDomain;

  @override
  void initState() {
    super.initState();
    _service = ref.read(bleSourceServiceProvider);
    _provider = ref.read(bleSourceRegistryProvider).getById(widget.sourceId);

    // Pick up current state (may already be streaming in demo mode).
    _state = _service.state;

    _stateSub = _service.stateStream.listen((s) {
      if (mounted) {
        // Auto-save on unexpected disconnect while recording.
        if (_isRecording &&
            s != BleSourceState.streaming &&
            s != BleSourceState.connecting) {
          _autoSaveOnDisconnect();
        }
        setState(() => _state = s);
      }
    });
    _devicesSub = _service.devicesStream.listen((d) {
      if (mounted) setState(() => _devices = d);
    });

    // Auto-start scan only if not already streaming (e.g. demo mode).
    if (_provider != null && _state != BleSourceState.streaming) {
      Future.microtask(() => _startScan());
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _devicesSub?.cancel();
    _recordSub?.cancel();
    _recordingUiTimer?.cancel();
    // Don't dispose the service — it's owned by the provider.
    super.dispose();
  }

  Future<void> _startScan() async {
    _errorMessage = null;
    setState(() => _devices = []);
    try {
      await _service.startScan(_provider!);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _connectTo(BleSourceDevice dev) async {
    _errorMessage = null;
    try {
      await _service.connectAndStream(dev.device, _provider!);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _disconnect() async {
    _stopRecording();
    await _service.disconnect();
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  void _startRecording() {
    _recordedSamples.clear();
    _eventMarkers.clear();
    _recordingStartTime = DateTime.now();
    _recordSub = _service.signalStream.listen((s) {
      _recordedSamples.add(s);
    });
    // Refresh the recording indicator every 500ms.
    _recordingUiTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    setState(() => _isRecording = true);
    ref.read(isRecordingSignalProvider.notifier).state = true;
  }

  bool _isSaving = false;

  void _stopRecording() {
    _recordSub?.cancel();
    _recordSub = null;
    _recordingUiTimer?.cancel();
    _recordingUiTimer = null;

    final hadSamples = _recordedSamples.isNotEmpty && _provider != null;

    if (hadSamples) {
      // Grab the samples and clear immediately so memory is freed.
      final session = SignalSession(
        sourceId: _provider!.id,
        sourceName: _provider!.displayName,
        deviceName: _service.connectedDevice?.platformName,
        channels: _provider!.channelDescriptors,
        samples: List.of(_recordedSamples),
        sampleRateHz: _provider!.sampleRateHz,
      );
      final eventTags = _eventMarkers
          .map((m) => 'event:${m.timeMs}:${m.label}')
          .toList();

      _recordedSamples.clear();
      _eventMarkers.clear();

      // Save asynchronously with proper error handling.
      _saveSession(session, eventTags);
    } else {
      _recordedSamples.clear();
      _eventMarkers.clear();
    }

    setState(() => _isRecording = false);
    _recordingStartTime = null;
    ref.read(isRecordingSignalProvider.notifier).state = false;
  }

  Future<void> _saveSession(
    SignalSession session,
    List<String> eventTags,
  ) async {
    setState(() => _isSaving = true);

    try {
      final capture = CaptureEntry(
        id: 'sig_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        source: CaptureSource.manual,
        signalSession: session,
        tags: eventTags,
      );

      await ref.read(localDbServiceProvider).saveCapture(capture);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Session saved to Lab · ${session.samples.length} samples '
              '(${session.duration.inSeconds}s)',
            ),
            backgroundColor: AppTheme.seaGreen,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                if (mounted) context.go('/lab');
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[LiveSignal] Failed to save session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save session (${session.samples.length} samples). '
              'Try a shorter recording.',
            ),
            backgroundColor: AppTheme.crimson,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Called automatically when BLE disconnects while recording.
  void _autoSaveOnDisconnect() {
    if (!_isRecording) return;
    _stopRecording();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connection lost — session auto-saved',
            style: AppTheme.geist(fontSize: 13, color: Colors.white),
          ),
          backgroundColor: AppTheme.amber,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'VIEW',
            textColor: Colors.white,
            onPressed: () {
              if (mounted) context.go('/lab');
            },
          ),
        ),
      );
    }
  }

  // ── Demo mode ───────────────────────────────────────────────────────

  void _startDemo() {
    if (_provider == null) return;
    _service.startDemo(
      channelCount: _provider!.channelCount,
      sampleRateHz: _provider!.sampleRateHz,
    );
    // State listener will pick up the streaming state.
  }

  void _stopDemo() {
    _service.stopDemo();
  }

  bool get _isDemoMode => _service.isDemoMode;

  // ── Event markers ──────────────────────────────────────────────────

  static const _eventTypes = [
    ('Stimulus', Icons.flash_on_rounded),
    ('Response', Icons.touch_app_rounded),
    ('Eyes open', Icons.visibility_rounded),
    ('Eyes closed', Icons.visibility_off_rounded),
    ('Task start', Icons.play_arrow_rounded),
    ('Task end', Icons.stop_rounded),
    ('Custom', Icons.flag_rounded),
  ];

  void _addEventMarker() {
    if (_recordingStartTime == null) return;
    final elapsedMs = DateTime.now()
        .difference(_recordingStartTime!)
        .inMilliseconds;
    HapticFeedback.mediumImpact();

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
              'Mark Event at ${_formatElapsed(elapsedMs)}',
              style: AppTheme.geist(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.moonbeam,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _eventTypes.length,
                itemBuilder: (_, i) {
                  final (label, icon) = _eventTypes[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      icon,
                      color: const Color(0xFF00BCD4),
                      size: 20,
                    ),
                    title: Text(
                      label,
                      style: AppTheme.geist(
                        fontSize: 14,
                        color: AppTheme.moonbeam,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _persistEventMarker(elapsedMs, label);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _persistEventMarker(int timeMs, String label) {
    setState(() {
      _eventMarkers.add(_LiveEventMarker(timeMs: timeMs, label: label));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '⚡ $label at ${_formatElapsed(timeMs)}',
          style: AppTheme.geist(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF00838F),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatElapsed(int ms) {
    final s = (ms / 1000).toStringAsFixed(1);
    return '${s}s';
  }

  /// Formatted recording elapsed time (mm:ss).
  String get _recordingElapsedStr {
    if (_recordingStartTime == null) return '00:00';
    final elapsed = DateTime.now().difference(_recordingStartTime!);
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (elapsed.inHours > 0) {
      final h = elapsed.inHours.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_provider == null) {
      return Scaffold(
        backgroundColor: AppTheme.midnight,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppTheme.moonbeam,
              size: 20,
            ),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Text(
            'Source "${widget.sourceId}" not found.',
            style: AppTheme.geist(fontSize: 16, color: AppTheme.fog),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.midnight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _provider!.displayName,
          style: AppTheme.geist(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.moonbeam,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.moonbeam,
            size: 20,
          ),
          onPressed: () {
            if (!_isDemoMode) _disconnect();
            _stopRecording();
            context.pop();
          },
        ),
        actions: [
          if (_isDemoMode)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.aurora.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'DEMO',
                style: AppTheme.geistMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.aurora,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          if (_state == BleSourceState.streaming) _buildModeSwitcher(),
          if (_state == BleSourceState.streaming && _isRecording)
            IconButton(
              icon: const Icon(
                Icons.flag_rounded,
                color: Color(0xFF00BCD4),
                size: 22,
              ),
              tooltip: 'Add event marker',
              onPressed: _addEventMarker,
            ),
          if (_state == BleSourceState.streaming)
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.glow,
                      ),
                    ),
                  )
                : IconButton(
                    icon: Icon(
                      _isRecording
                          ? Icons.stop_circle_rounded
                          : Icons.fiber_manual_record_rounded,
                      color: _isRecording ? AppTheme.crimson : AppTheme.glow,
                      size: 22,
                    ),
                    tooltip: _isRecording
                        ? 'Stop recording'
                        : 'Start recording',
                    onPressed: _toggleRecording,
                  ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case BleSourceState.idle:
        return _buildScanResults();
      case BleSourceState.scanning:
        return _buildScanning();
      case BleSourceState.connecting:
        return _buildConnecting();
      case BleSourceState.streaming:
        return _buildStreaming();
      case BleSourceState.error:
        return _buildError();
    }
  }

  // ── Scan phase ────────────────────────────────────────────────────────

  Widget _buildScanning() {
    return Column(
      children: [
        const LinearProgressIndicator(
          color: AppTheme.glow,
          backgroundColor: AppTheme.deepSea,
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Scanning for ${_provider!.displayName} devices…',
            style: AppTheme.geist(fontSize: 14, color: AppTheme.fog),
          ),
        ),
        if (_devices.isNotEmpty) Expanded(child: _buildDeviceList()),
      ],
    );
  }

  Widget _buildScanResults() {
    return Column(
      children: [
        if (_errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            decoration: BoxDecoration(
              color: AppTheme.crimson.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _errorMessage!,
              style: AppTheme.geist(fontSize: 12, color: AppTheme.crimson),
            ),
          ),
        if (_devices.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bluetooth_searching_rounded,
                    size: 48,
                    color: AppTheme.fog.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No devices found',
                    style: AppTheme.geist(fontSize: 16, color: AppTheme.fog),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure your ${_provider!.displayName} board is powered on.',
                    textAlign: TextAlign.center,
                    style: AppTheme.geist(
                      fontSize: 13,
                      color: AppTheme.fog.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildScanButton(),
                  const SizedBox(height: 12),
                  _buildDemoButton(),
                ],
              ),
            ),
          )
        else
          Expanded(child: _buildDeviceList()),
        if (_devices.isNotEmpty)
          Padding(padding: const EdgeInsets.all(16), child: _buildScanButton()),
      ],
    );
  }

  Widget _buildDeviceList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _DeviceTile(
        device: _devices[i],
        onTap: () => _connectTo(_devices[i]),
      ),
    );
  }

  Widget _buildScanButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _startScan,
            onLongPress: _showDiagnosticScan,
            icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
            label: Text(
              'Scan for devices',
              style: AppTheme.geist(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.glow.withValues(alpha: 0.15),
              foregroundColor: AppTheme.glow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _showDiagnosticScan,
          child: Text(
            'Long-press for BLE diagnostic',
            style: AppTheme.geist(
              fontSize: 11,
              color: AppTheme.fog.withValues(alpha: 0.35),
            ),
          ),
        ),
      ],
    );
  }

  // ── Diagnostic scan (long-press on Scan button) ─────────────────────

  void _showDiagnosticScan() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.deepSea,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _DiagnosticSheet(service: _service, provider: _provider!),
    );
  }

  Widget _buildDemoButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _startDemo,
        icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
        label: Text(
          'Try demo mode',
          style: AppTheme.geist(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.aurora,
          side: BorderSide(color: AppTheme.aurora.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  // ── Connecting phase ──────────────────────────────────────────────────

  Widget _buildConnecting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: AppTheme.glow,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Connecting…',
            style: AppTheme.geist(fontSize: 16, color: AppTheme.moonbeam),
          ),
        ],
      ),
    );
  }

  // ── Streaming phase ───────────────────────────────────────────────────

  Widget _buildStreaming() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          // Recording indicator
          if (_isRecording)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppTheme.crimson.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.crimson,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recording — $_recordingElapsedStr — ${_recordedSamples.length} samples',
                    style: AppTheme.geistMono(
                      fontSize: 11,
                      color: AppTheme.crimson,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_eventMarkers.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${_eventMarkers.length} event${_eventMarkers.length == 1 ? '' : 's'}',
                        style: AppTheme.geistMono(
                          fontSize: 10,
                          color: const Color(0xFF00BCD4),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Active visualisation — animated crossfade between modes.
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _buildActiveView(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mode switcher (AppBar action) ───────────────────────────────────

  Widget _buildModeSwitcher() {
    return PopupMenuButton<SignalViewMode>(
      icon: Icon(_viewMode.icon, color: _viewMode.color, size: 20),
      tooltip: 'Switch view mode',
      color: AppTheme.deepSea,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      onSelected: (mode) => setState(() => _viewMode = mode),
      itemBuilder: (_) => SignalViewMode.values.map((mode) {
        final isActive = mode == _viewMode;
        return PopupMenuItem<SignalViewMode>(
          value: mode,
          child: Row(
            children: [
              Icon(
                mode.icon,
                color: isActive ? mode.color : AppTheme.fog,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                mode.label,
                style: AppTheme.geist(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  color: isActive ? mode.color : AppTheme.moonbeam,
                ),
              ),
              if (mode == SignalViewMode.decoding ||
                  mode == SignalViewMode.monitoring) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.aurora.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'DEMO',
                    style: AppTheme.geistMono(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.aurora,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Active view builder ───────────────────────────────────────────────

  Widget _buildActiveView() {
    final stream = _service.signalStream;
    final descriptors = _provider!.channelDescriptors;
    final deviceName = _isDemoMode
        ? 'Demo'
        : _service.connectedDevice?.platformName;
    final sourceName = _isDemoMode
        ? '${_provider!.displayName} (Demo)'
        : _provider!.displayName;

    switch (_viewMode) {
      case SignalViewMode.timeDomain:
        return LiveSignalChart(
          key: const ValueKey('timedomain'),
          signalStream: stream,
          channelDescriptors: descriptors,
          deviceName: deviceName,
          sourceName: sourceName,
          onDisconnect: _isDemoMode ? _stopDemo : _disconnect,
        );
      case SignalViewMode.spectral:
        return SpectralAnalysisChart(
          key: const ValueKey('spectral'),
          signalStream: stream,
          channelDescriptors: descriptors,
          sampleRateHz: _provider!.sampleRateHz,
          deviceName: deviceName,
          sourceName: sourceName,
          onSwitchToTimeDomain: () =>
              setState(() => _viewMode = SignalViewMode.timeDomain),
        );
      case SignalViewMode.decoding:
        return BciDecodingView(
          key: const ValueKey('decoding'),
          signalStream: stream,
          channelDescriptors: descriptors,
        );
      case SignalViewMode.monitoring:
        return BciMonitoringView(
          key: const ValueKey('monitoring'),
          signalStream: stream,
          channelDescriptors: descriptors,
        );
    }
  }

  // ── Error state ───────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppTheme.crimson.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'Connection error',
            style: AppTheme.geist(fontSize: 16, color: AppTheme.crimson),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: AppTheme.geist(fontSize: 12, color: AppTheme.fog),
              ),
            ),
          const SizedBox(height: 24),
          _buildScanButton(),
          const SizedBox(height: 12),
          _buildDemoButton(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final BleSourceDevice device;
  final VoidCallback onTap;

  const _DeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.tidePool,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.bluetooth_rounded,
              color: AppTheme.glow.withValues(alpha: 0.6),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: AppTheme.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.moonbeam,
                    ),
                  ),
                  Text(
                    device.device.remoteId.str,
                    style: AppTheme.geistMono(
                      fontSize: 10,
                      color: AppTheme.fog.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            // RSSI badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _rssiColor(device.rssi).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${device.rssi} dBm',
                style: AppTheme.geistMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _rssiColor(device.rssi),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return AppTheme.seaGreen;
    if (rssi >= -80) return AppTheme.amber;
    return AppTheme.crimson;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Event marker recorded during live signal capture.
// ─────────────────────────────────────────────────────────────────────────────

class _LiveEventMarker {
  final int timeMs;
  final String label;
  const _LiveEventMarker({required this.timeMs, required this.label});
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic bottom sheet — unfiltered BLE scan for remote debugging.
// ─────────────────────────────────────────────────────────────────────────────

class _DiagnosticSheet extends StatefulWidget {
  final BleSourceService service;
  final BleSourceProvider provider;

  const _DiagnosticSheet({required this.service, required this.provider});

  @override
  State<_DiagnosticSheet> createState() => _DiagnosticSheetState();
}

class _DiagnosticSheetState extends State<_DiagnosticSheet> {
  List<DiagnosticDevice>? _results;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  Future<void> _runScan() async {
    setState(() {
      _scanning = true;
      _results = null;
    });
    final devices = await widget.service.runDiagnosticScan(timeoutSeconds: 10);
    if (mounted) {
      setState(() {
        _scanning = false;
        _results = devices;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetUuid = widget.provider.serviceUuid.toLowerCase();
    final targetNames = widget.provider.advertisedNames
        .map((n) => n.toUpperCase())
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.fog.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.bug_report_rounded,
                  color: AppTheme.amber,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'BLE Diagnostic Scan',
                    style: AppTheme.geist(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.moonbeam,
                    ),
                  ),
                ),
                if (!_scanning)
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: AppTheme.glow,
                      size: 20,
                    ),
                    onPressed: _runScan,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Shows ALL nearby BLE devices (no filters). '
              'Looking for service ${widget.provider.serviceUuid} '
              'or name "${widget.provider.advertisedNames.join(', ')}".',
              style: AppTheme.geist(
                fontSize: 11,
                color: AppTheme.fog.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_scanning)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.glow),
                    SizedBox(height: 12),
                    Text(
                      'Scanning all BLE devices…',
                      style: TextStyle(color: AppTheme.fog, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (_results == null || _results!.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No BLE devices found at all.\n'
                  'Check Bluetooth & location are enabled.',
                  textAlign: TextAlign.center,
                  style: AppTheme.geist(fontSize: 14, color: AppTheme.fog),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: _results!.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final d = _results![i];
                  final nameMatch = targetNames.any(
                    (n) => d.name.toUpperCase().contains(n),
                  );
                  final uuidMatch = d.serviceUuids.any(
                    (u) => u.toLowerCase() == targetUuid,
                  );
                  final isMatch = nameMatch || uuidMatch;

                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMatch
                          ? AppTheme.glow.withValues(alpha: 0.08)
                          : AppTheme.tidePool,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isMatch
                            ? AppTheme.glow.withValues(alpha: 0.5)
                            : AppTheme.shimmer.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isMatch)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.glow,
                                  size: 16,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                d.name,
                                style: AppTheme.geist(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isMatch
                                      ? AppTheme.glow
                                      : AppTheme.moonbeam,
                                ),
                              ),
                            ),
                            Text(
                              '${d.rssi} dBm',
                              style: AppTheme.geistMono(
                                fontSize: 10,
                                color: AppTheme.fog,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${d.remoteId}',
                          style: AppTheme.geistMono(
                            fontSize: 9,
                            color: AppTheme.fog.withValues(alpha: 0.5),
                          ),
                        ),
                        if (d.localName.isNotEmpty)
                          Text(
                            'advName: "${d.localName}"',
                            style: AppTheme.geistMono(
                              fontSize: 9,
                              color: nameMatch
                                  ? AppTheme.glow
                                  : AppTheme.fog.withValues(alpha: 0.5),
                            ),
                          ),
                        if (d.serviceUuids.isNotEmpty)
                          Text(
                            'services: ${d.serviceUuids.join(', ')}',
                            style: AppTheme.geistMono(
                              fontSize: 9,
                              color: uuidMatch
                                  ? AppTheme.glow
                                  : AppTheme.fog.withValues(alpha: 0.5),
                            ),
                          )
                        else
                          Text(
                            'services: (none advertised)',
                            style: AppTheme.geistMono(
                              fontSize: 9,
                              color: AppTheme.fog.withValues(alpha: 0.35),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
