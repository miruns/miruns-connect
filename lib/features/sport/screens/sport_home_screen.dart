import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';
import '../services/workout_service.dart';
import '../widgets/sport_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sport Home — primary landing screen
//
// Layout:
//   · Top bar    : headset status icon (left) · "miruns" wordmark · profile (right)
//   · Activity   : workout type selector
//   · Start      : pill-shaped launch button (triggers BLE scan + workout)
//   · Insight    : AI prediction card (after 3+ sessions)
//   · Recent     : last workout summaries
// ─────────────────────────────────────────────────────────────────────────────

class SportHomeScreen extends ConsumerStatefulWidget {
  const SportHomeScreen({super.key});

  @override
  ConsumerState<SportHomeScreen> createState() => _SportHomeScreenState();
}

class _SportHomeScreenState extends ConsumerState<SportHomeScreen>
    with SingleTickerProviderStateMixin {
  late final WorkoutService _workoutService;

  SportProfile? _profile;
  List<WorkoutSession>? _recentWorkouts;
  String? _prediction;
  bool _loadingPrediction = false;
  WorkoutType _selectedType = WorkoutType.running;

  // BLE headset connection state
  BleSourceState _bleState = BleSourceState.idle;
  StreamSubscription<BleSourceState>? _bleSub;
  String? _pairedDeviceName;
  bool _isDemoMode = false;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _workoutService = ref.read(workoutServiceProvider);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    // Track BLE headset state
    final bleService = ref.read(bleSourceServiceProvider);
    _bleState = bleService.state;
    _bleSub = bleService.stateStream.listen((s) {
      if (mounted) setState(() => _bleState = s);
    });

    _loadData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _bleSub?.cancel();
    super.dispose();
  }

  bool get _isConnected => _bleState == BleSourceState.streaming;

  Future<void> _loadData() async {
    // Load headset prefs
    final db = ref.read(localDbServiceProvider);
    final name = await db.getSetting('eeg_paired_device_name');
    final demo = await db.getSetting('eeg_demo_mode');

    final profile = await _workoutService.loadProfile();
    final workouts = await _workoutService.loadWorkouts(limit: 5);
    if (mounted) {
      setState(() {
        _pairedDeviceName = name;
        _isDemoMode = demo == 'true';
        _profile = profile;
        _recentWorkouts = workouts;
        _selectedType = profile.preferredWorkouts.isNotEmpty
            ? profile.preferredWorkouts.first
            : WorkoutType.running;
      });
    }

    if (workouts.where((w) => w.feedback != null).length >= 3) {
      _loadPrediction(profile, workouts);
    }
  }

  Future<void> _loadPrediction(
    SportProfile profile,
    List<WorkoutSession> history,
  ) async {
    setState(() => _loadingPrediction = true);
    try {
      final analytics = ref.read(workoutAnalyticsServiceProvider);
      final prediction = await analytics.generatePreWorkoutPrediction(
        profile: profile,
        history: history,
        plannedType: _selectedType,
      );
      if (mounted) setState(() => _prediction = prediction);
    } catch (_) {}
    if (mounted) setState(() => _loadingPrediction = false);
  }

  void _startWorkout() {
    HapticFeedback.mediumImpact();

    // Already connected → go straight to workout.
    if (_isConnected) {
      context.push('/sport/active', extra: _selectedType);
      return;
    }

    // Demo mode → skip headset, go to workout.
    if (_isDemoMode) {
      context.push('/sport/active', extra: _selectedType);
      return;
    }

    // Show headset connection sheet (auto-scans if paired device exists).
    _showHeadsetConnectionSheet();
  }

  void _showHeadsetConnectionSheet() {
    final bleService = ref.read(bleSourceServiceProvider);
    final registry = ref.read(bleSourceRegistryProvider);
    final eegProvider = registry.getById('ads1299');

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HeadsetScanSheet(
        bleService: bleService,
        provider: eegProvider,
        pairedDeviceName: _pairedDeviceName,
        onConnected: () {
          Navigator.of(context).pop(); // close sheet
          context.push('/sport/active', extra: _selectedType);
        },
        onSkip: () {
          Navigator.of(context).pop(); // close sheet
          context.push('/sport/active', extra: _selectedType);
        },
      ),
    );
  }

  void _openHistory() {
    HapticFeedback.selectionClick();
    context.push('/sport/history');
  }

  void _openProfile() {
    HapticFeedback.selectionClick();
    context.push('/sport/profile');
  }

  void _openHeadsetScanner() {
    HapticFeedback.selectionClick();
    context.push('/sources');
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.midnight,
        body: CustomScrollView(
          slivers: [
            // ── Top bar ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, top + 16, 20, 8),
                child: Row(
                  children: [
                    // Headset icon with connection dot
                    _HeadsetStatusIcon(
                      isConnected: _isConnected,
                      isDemoMode: _isDemoMode,
                      deviceName: _pairedDeviceName,
                      onTap: _openHeadsetScanner,
                    ),
                    const SizedBox(width: 14),
                    // miruns wordmark
                    Text(
                      'miruns',
                      style: AppTheme.geist(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: AppTheme.moonbeam,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    // Profile button
                    GestureDetector(
                      onTap: _openProfile,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.tidePool,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.shimmer, width: 1),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          size: 18,
                          color: AppTheme.fog,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Activity selector ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activity',
                      style: AppTheme.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.fog,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    WorkoutTypeSelector(
                      selected: _selectedType,
                      onSelect: (type) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedType = type);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── Start button ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 32,
                ),
                child: Center(
                  child: GestureDetector(
                    onTap: _startWorkout,
                    child: AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (context, child) {
                        final glow = _pulseAnim.value * 0.15;
                        return Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9999),
                            color: AppTheme.cyan.withValues(alpha: 0.12 + glow),
                            border: Border.all(
                              color: AppTheme.cyan.withValues(alpha: 0.5),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.cyan.withValues(
                                  alpha: 0.08 + glow * 0.4,
                                ),
                                blurRadius: 24,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _selectedType.icon,
                                size: 22,
                                color: AppTheme.cyan,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Start',
                                style: AppTheme.geist(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.moonbeam,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // ── AI Prediction ──────────────────────────────────────────────
            if (_loadingPrediction || _prediction != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.tidePool,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.shimmer),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppTheme.cyan,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Pre-workout insight',
                              style: AppTheme.geist(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.cyan,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_loadingPrediction)
                          const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppTheme.cyan,
                              ),
                            ),
                          )
                        else
                          Text(
                            _prediction!,
                            style: AppTheme.geist(
                              fontSize: 13,
                              color: AppTheme.moonbeam,
                              height: 1.55,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Recent Sessions ────────────────────────────────────────────
            if (_recentWorkouts != null && _recentWorkouts!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent',
                            style: AppTheme.geist(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.fog,
                              letterSpacing: 0.5,
                            ),
                          ),
                          GestureDetector(
                            onTap: _openHistory,
                            child: Text(
                              'View all',
                              style: AppTheme.geist(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.cyan,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._recentWorkouts!
                          .take(3)
                          .map((w) => _RecentWorkoutCard(session: w)),
                    ],
                  ),
                ),
              ),

            // ── Empty state ────────────────────────────────────────────────
            if (_recentWorkouts != null && _recentWorkouts!.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.directions_run_outlined,
                        size: 48,
                        color: AppTheme.shimmer,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ready when you are',
                        style: AppTheme.geist(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.moonbeam,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pick your activity and tap Start.\nFocus on your sport — miruns handles the rest.',
                        textAlign: TextAlign.center,
                        style: AppTheme.geist(
                          fontSize: 13,
                          color: AppTheme.fog,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom safe area padding
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Headset status icon — top-left, shows connection as colored dot
// ─────────────────────────────────────────────────────────────────────────────

class _HeadsetStatusIcon extends StatelessWidget {
  final bool isConnected;
  final bool isDemoMode;
  final String? deviceName;
  final VoidCallback onTap;

  const _HeadsetStatusIcon({
    required this.isConnected,
    required this.isDemoMode,
    required this.deviceName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor = isConnected
        ? AppTheme.seaGreen
        : isDemoMode
        ? AppTheme.amber
        : AppTheme.fog;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(
                Icons.headphones_outlined,
                size: 24,
                color: isConnected ? AppTheme.moonbeam : AppTheme.fog,
              ),
            ),
            // Status dot
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.midnight, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent workout card
// ─────────────────────────────────────────────────────────────────────────────

class _RecentWorkoutCard extends StatelessWidget {
  final WorkoutSession session;

  const _RecentWorkoutCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final duration = session.duration;
    final daysAgo = DateTime.now().difference(session.startTime).inDays;
    final when = daysAgo == 0
        ? 'Today'
        : daysAgo == 1
        ? 'Yesterday'
        : '$daysAgo days ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.shimmer),
      ),
      child: Row(
        children: [
          Icon(session.workoutType.icon, size: 24, color: AppTheme.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.workoutType.label,
                  style: AppTheme.geist(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.moonbeam,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$when  ·  ${duration.inMinutes} min${session.totalDistanceKm != null ? '  ·  ${session.totalDistanceKm!.toStringAsFixed(1)} km' : ''}',
                  style: AppTheme.geistMono(fontSize: 11, color: AppTheme.fog),
                ),
              ],
            ),
          ),
          if (session.analysis != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                '${session.analysis!.performanceScore}',
                style: AppTheme.geistMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.cyan,
                ),
              ),
            ),
          if (session.feedback != null && session.analysis == null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'E ${session.feedback!.energyLevel}',
                  style: AppTheme.geistMono(fontSize: 11, color: AppTheme.fog),
                ),
                const SizedBox(width: 8),
                Text(
                  'F ${session.feedback!.fatigueLevel}',
                  style: AppTheme.geistMono(fontSize: 11, color: AppTheme.fog),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Headset scan bottom sheet — shown before starting a workout
// ─────────────────────────────────────────────────────────────────────────────

class _HeadsetScanSheet extends StatefulWidget {
  final BleSourceService bleService;
  final BleSourceProvider? provider;
  final String? pairedDeviceName;
  final VoidCallback onConnected;
  final VoidCallback onSkip;

  const _HeadsetScanSheet({
    required this.bleService,
    required this.provider,
    required this.pairedDeviceName,
    required this.onConnected,
    required this.onSkip,
  });

  @override
  State<_HeadsetScanSheet> createState() => _HeadsetScanSheetState();
}

class _HeadsetScanSheetState extends State<_HeadsetScanSheet> {
  List<BleSourceDevice> _devices = [];
  BleSourceState _state = BleSourceState.idle;
  StreamSubscription<List<BleSourceDevice>>? _devicesSub;
  StreamSubscription<BleSourceState>? _stateSub;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _state = widget.bleService.state;
    _stateSub = widget.bleService.stateStream.listen((s) {
      if (mounted) {
        setState(() => _state = s);
        if (s == BleSourceState.streaming) {
          widget.onConnected();
        }
      }
    });
    _devicesSub = widget.bleService.devicesStream.listen((d) {
      if (mounted) setState(() => _devices = d);
    });

    // Auto-start scan.
    if (widget.provider != null && _state != BleSourceState.streaming) {
      _startScan();
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _devicesSub?.cancel();
    // Don't stop scan on dispose — let connection continue if in progress.
    if (_state == BleSourceState.scanning) {
      widget.bleService.stopScan();
    }
    super.dispose();
  }

  Future<void> _startScan() async {
    if (widget.provider == null) return;
    setState(() => _devices = []);
    try {
      await widget.bleService.startScan(widget.provider!);
    } catch (_) {}
  }

  Future<void> _connectDevice(BleSourceDevice device) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    HapticFeedback.mediumImpact();
    try {
      await widget.bleService.connectAndStream(device.device, widget.provider!);
      // stateStream listener will call onConnected.
    } catch (e) {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isScanning = _state == BleSourceState.scanning;
    final isConnecting = _connecting || _state == BleSourceState.connecting;
    final noProvider = widget.provider == null;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.current,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.shimmer,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const Icon(
                Icons.headphones_outlined,
                color: AppTheme.cyan,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Connect headset',
                style: AppTheme.geist(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.moonbeam,
                ),
              ),
              const Spacer(),
              if (isScanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppTheme.cyan,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.pairedDeviceName != null
                  ? 'Looking for ${widget.pairedDeviceName}…'
                  : 'Scanning for nearby headsets…',
              style: AppTheme.geist(fontSize: 13, color: AppTheme.fog),
            ),
          ),
          const SizedBox(height: 16),

          // Device list or status
          if (noProvider)
            _statusTile(
              Icons.bluetooth_disabled_rounded,
              'No EEG source configured',
              'You can still start without a headset.',
            )
          else if (isConnecting)
            _statusTile(
              Icons.bluetooth_searching_rounded,
              'Connecting…',
              'Setting up headset link',
            )
          else if (_devices.isEmpty && !isScanning)
            _statusTile(
              Icons.search_off_rounded,
              'No headset found',
              'Make sure the headset is on and nearby.',
            )
          else ...[
            for (final device in _devices)
              _DeviceTile(device: device, onTap: () => _connectDevice(device)),
          ],

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              // Re-scan
              if (!isScanning && !isConnecting && !noProvider)
                Expanded(
                  child: GestureDetector(
                    onTap: _startScan,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.tidePool,
                        borderRadius: BorderRadius.circular(9999),
                        border: Border.all(color: AppTheme.shimmer),
                      ),
                      child: Center(
                        child: Text(
                          'Scan again',
                          style: AppTheme.geist(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.fog,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (!isScanning && !isConnecting && !noProvider)
                const SizedBox(width: 12),

              // Skip → start without headset
              Expanded(
                child: GestureDetector(
                  onTap: isConnecting ? null : widget.onSkip,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9999),
                      color: AppTheme.cyan.withValues(alpha: 0.12),
                      border: Border.all(
                        color: AppTheme.cyan.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Start without',
                        style: AppTheme.geist(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.cyan,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusTile(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 28, color: AppTheme.fog),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.geist(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.moonbeam,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTheme.geist(fontSize: 12, color: AppTheme.fog),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final BleSourceDevice device;
  final VoidCallback onTap;

  const _DeviceTile({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.tidePool,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.shimmer),
        ),
        child: Row(
          children: [
            const Icon(Icons.bluetooth_rounded, size: 20, color: AppTheme.cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: AppTheme.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.moonbeam,
                    ),
                  ),
                  Text(
                    'RSSI: ${device.rssi} dBm',
                    style: AppTheme.geistMono(
                      fontSize: 11,
                      color: AppTheme.fog,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppTheme.fog,
            ),
          ],
        ),
      ),
    );
  }
}
