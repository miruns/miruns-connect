import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/ble_heart_rate_service.dart';
import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../models/sport_profile.dart';
import '../models/workout_session.dart';
import '../services/workout_service.dart';

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
  StreamSubscription<List<BleSourceDevice>>? _devicesScanSub;
  String? _pairedDeviceName;
  String? _pairedDeviceId;
  bool _isDemoMode = false;
  Timer? _reconnectTimer;
  bool _autoConnecting = false;

  // Heart rate sensor state
  BleConnectionState _hrState = BleConnectionState.idle;
  StreamSubscription<BleConnectionState>? _hrSub;

  // GPS sensor state
  _SensorStatus _gpsStatus = _SensorStatus.unknown;

  // Health service state
  _SensorStatus _healthStatus = _SensorStatus.unknown;

  // Pre-workout insight: CTA-driven (not auto)
  bool _insightAvailable = false;

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
      if (!mounted) return;
      final prev = _bleState;
      setState(() => _bleState = s);
      // Auto-reconnect: if we lost connection, schedule a re-scan.
      if (prev == BleSourceState.streaming && s == BleSourceState.idle) {
        _scheduleReconnect();
      }
    });

    // Track HR sensor state
    final hrService = ref.read(bleHeartRateServiceProvider);
    _hrState = hrService.state;
    _hrSub = hrService.stateStream.listen((s) {
      if (mounted) setState(() => _hrState = s);
    });

    _loadData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _bleSub?.cancel();
    _hrSub?.cancel();
    _devicesScanSub?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  bool get _isConnected => _bleState == BleSourceState.streaming;

  Future<void> _loadData() async {
    // Load headset prefs
    final db = ref.read(localDbServiceProvider);
    final name = await db.getSetting('eeg_paired_device_name');
    final id = await db.getSetting('eeg_paired_device_id');
    final demo = await db.getSetting('eeg_demo_mode');

    final profile = await _workoutService.loadProfile();
    final workouts = await _workoutService.loadWorkouts(limit: 5);
    if (mounted) {
      setState(() {
        _pairedDeviceName = name;
        _pairedDeviceId = id;
        _isDemoMode = demo == 'true';
        _profile = profile;
        _recentWorkouts = workouts;
        _selectedType = profile.preferredWorkouts.isNotEmpty
            ? profile.preferredWorkouts.first
            : WorkoutType.running;
      });
    }

    // Auto-scan for headset on open (like Garmin looking for its watch).
    _tryAutoConnect();

    // Check sensor statuses
    _checkGpsStatus();
    _checkHealthStatus();

    // Mark insight available if enough data (but don't auto-load)
    if (workouts.where((w) => w.feedback != null).length >= 3) {
      if (mounted) setState(() => _insightAvailable = true);
    }
  }

  /// Scan for the paired headset and auto-connect if found.
  Future<void> _tryAutoConnect() async {
    // Skip if already connected, in demo mode, or no paired device.
    final bleService = ref.read(bleSourceServiceProvider);
    if (bleService.isStreaming) return;
    if (_isDemoMode) return;
    if (_pairedDeviceId == null && _pairedDeviceName == null) return;

    final registry = ref.read(bleSourceRegistryProvider);
    final eegProvider = registry.getById('ads1299');
    if (eegProvider == null) return;

    // Don't double-scan.
    if (_bleState == BleSourceState.scanning ||
        _bleState == BleSourceState.connecting) {
      return;
    }

    _autoConnecting = true;

    // Listen for scan results and auto-connect to the paired device.
    _devicesScanSub?.cancel();
    _devicesScanSub = bleService.devicesStream.listen((devices) {
      if (!_autoConnecting) return;
      for (final d in devices) {
        final matchesId =
            _pairedDeviceId != null && d.device.remoteId.str == _pairedDeviceId;
        final matchesName =
            _pairedDeviceName != null &&
            d.name.toUpperCase().contains(_pairedDeviceName!.toUpperCase());
        if (matchesId || matchesName) {
          _autoConnecting = false;
          _devicesScanSub?.cancel();
          bleService.connectAndStream(d.device, eegProvider).catchError((_) {
            // Connection failed — will auto-retry via _scheduleReconnect.
          });
          return;
        }
      }
    });

    try {
      await bleService.startScan(eegProvider);
    } catch (_) {}

    // If scan finished without finding the device, clean up.
    if (_autoConnecting) {
      _autoConnecting = false;
      _devicesScanSub?.cancel();
    }
  }

  /// Schedule a background re-scan after a delay (like Garmin retry loop).
  void _scheduleReconnect() {
    if (_isDemoMode) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _bleState == BleSourceState.idle) {
        _tryAutoConnect();
      }
    });
  }

  Future<void> _checkGpsStatus() async {
    try {
      final permission = await Geolocator.checkPermission();
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        setState(() => _gpsStatus = _SensorStatus.off);
      } else if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _gpsStatus = _SensorStatus.noPermission);
      } else {
        setState(() => _gpsStatus = _SensorStatus.ready);
      }
    } catch (_) {
      if (mounted) setState(() => _gpsStatus = _SensorStatus.unavailable);
    }
  }

  Future<void> _checkHealthStatus() async {
    try {
      final healthService = ref.read(healthServiceProvider);
      final available = await healthService.isHealthAvailable();
      if (!mounted) return;
      if (!available) {
        setState(() => _healthStatus = _SensorStatus.unavailable);
        return;
      }
      final hasPerms = await healthService.hasPermissionsProbe();
      if (mounted) {
        setState(
          () => _healthStatus = hasPerms
              ? _SensorStatus.ready
              : _SensorStatus.noPermission,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _healthStatus = _SensorStatus.unavailable);
    }
  }

  Future<void> _enableGps() async {
    HapticFeedback.selectionClick();
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    } else if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    } else {
      await Geolocator.openLocationSettings();
    }
    await _checkGpsStatus();
  }

  Future<void> _enableHealth() async {
    HapticFeedback.selectionClick();
    final healthService = ref.read(healthServiceProvider);
    await healthService.requestAuthorization();
    await _checkHealthStatus();
  }

  void _scanHr() {
    HapticFeedback.selectionClick();
    final hrService = ref.read(bleHeartRateServiceProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HrScanSheet(hrService: hrService),
    );
  }

  Future<void> _requestInsight() async {
    if (_profile == null || _recentWorkouts == null) return;
    setState(() => _loadingPrediction = true);
    try {
      final analytics = ref.read(workoutAnalyticsServiceProvider);
      final prediction = await analytics.generatePreWorkoutPrediction(
        profile: _profile!,
        history: _recentWorkouts!,
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
    final bottom = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.void_,
        body: Stack(
          children: [
            // ── Background radial glow ──────────────────────────────────
            Positioned(
              top: -80,
              left: 0,
              right: 0,
              height: 400,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.3),
                      radius: 1.2,
                      colors: [
                        AppTheme.cyan.withValues(
                          alpha: 0.06 + _pulseAnim.value * 0.03,
                        ),
                        AppTheme.void_.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Scrollable content ──────────────────────────────────────
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── Top bar ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, top + 20, 24, 0),
                    child: Row(
                      children: [
                        // Brand
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'miruns',
                              style: AppTheme.geist(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.moonbeam,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'sport',
                              style: AppTheme.geist(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.fog,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // History
                        GestureDetector(
                          onTap: _openHistory,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.tidePool,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.shimmer.withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Icon(
                              Icons.bar_chart_rounded,
                              size: 18,
                              color: AppTheme.fog,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Profile
                        GestureDetector(
                          onTap: _openProfile,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.tidePool,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.shimmer.withValues(alpha: 0.5),
                              ),
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

                // ── Sensor status pills (compact horizontal row) ───────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: _SensorPillRow(
                      eegState: _bleState,
                      eegDeviceName: _isConnected
                          ? (ref
                                    .read(bleSourceServiceProvider)
                                    .connectedDevice
                                    ?.platformName ??
                                _pairedDeviceName)
                          : _pairedDeviceName,
                      isDemoMode: _isDemoMode,
                      onEegTap: _bleState == BleSourceState.idle && !_isDemoMode
                          ? _tryAutoConnect
                          : _openHeadsetScanner,
                      hrState: _hrState,
                      onHrTap: _scanHr,
                      gpsStatus: _gpsStatus,
                      onGpsTap: _enableGps,
                      healthStatus: _healthStatus,
                      onHealthTap: _enableHealth,
                    ),
                  ),
                ),

                // ── Hero: selected activity ─────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                    child: Center(
                      child: Column(
                        children: [
                          // Large icon with glow
                          AnimatedBuilder(
                            animation: _pulseAnim,
                            builder: (context, _) {
                              final glow = _pulseAnim.value * 0.12;
                              return Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.cyan.withValues(
                                    alpha: 0.06 + glow,
                                  ),
                                  border: Border.all(
                                    color: AppTheme.cyan.withValues(
                                      alpha: 0.15 + glow,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.cyan.withValues(
                                        alpha: 0.08 + glow * 0.5,
                                      ),
                                      blurRadius: 40,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: Icon(
                                    _selectedType.icon,
                                    key: ValueKey(_selectedType),
                                    size: 42,
                                    color: AppTheme.cyan,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          // Activity name — big and bold
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              _selectedType.label,
                              key: ValueKey(_selectedType.label),
                              style: AppTheme.geist(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.moonbeam,
                                letterSpacing: -1.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Select activity below',
                            style: AppTheme.geist(
                              fontSize: 13,
                              color: AppTheme.fog,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Activity type selector (horizontal scroll) ─────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: WorkoutType.values.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final type = WorkoutType.values[index];
                          final isSelected = type == _selectedType;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedType = type);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                              width: 76,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.cyan.withValues(alpha: 0.10)
                                    : AppTheme.tidePool.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.cyan.withValues(alpha: 0.6)
                                      : AppTheme.shimmer.withValues(alpha: 0.3),
                                  width: isSelected ? 1.5 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.cyan.withValues(
                                            alpha: 0.08,
                                          ),
                                          blurRadius: 16,
                                          spreadRadius: 0,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    type.icon,
                                    size: 26,
                                    color: isSelected
                                        ? AppTheme.cyan
                                        : AppTheme.fog,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    type.label,
                                    style: AppTheme.geist(
                                      fontSize: 10,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? AppTheme.cyan
                                          : AppTheme.fog,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // ── AI Prediction (CTA-driven) ─────────────────────────
                if (_insightAvailable ||
                    _loadingPrediction ||
                    _prediction != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                      child: _prediction != null
                          ? Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppTheme.cyan.withValues(alpha: 0.06),
                                    AppTheme.tidePool,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.cyan.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.cyan.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.auto_awesome_rounded,
                                              size: 12,
                                              color: AppTheme.cyan,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'AI INSIGHT',
                                              style: AppTheme.geist(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.cyan,
                                                letterSpacing: 1.0,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _prediction!,
                                    style: AppTheme.geist(
                                      fontSize: 13,
                                      color: AppTheme.moonbeam,
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : GestureDetector(
                              onTap: _loadingPrediction
                                  ? null
                                  : _requestInsight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.tidePool,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppTheme.cyan.withValues(
                                      alpha: 0.15,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 18,
                                      color: _loadingPrediction
                                          ? AppTheme.fog
                                          : AppTheme.cyan,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _loadingPrediction
                                            ? 'Generating insight…'
                                            : 'Get pre-workout insight',
                                        style: AppTheme.geist(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: _loadingPrediction
                                              ? AppTheme.fog
                                              : AppTheme.cyan,
                                        ),
                                      ),
                                    ),
                                    if (_loadingPrediction)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: AppTheme.cyan,
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 13,
                                        color: AppTheme.cyan,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ),

                // ── Recent Sessions ─────────────────────────────────────
                if (_recentWorkouts != null && _recentWorkouts!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'RECENT',
                                style: AppTheme.geist(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.fog,
                                  letterSpacing: 1.5,
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
                          const SizedBox(height: 12),
                          ..._recentWorkouts!
                              .take(3)
                              .map((w) => _RecentWorkoutCard(session: w)),
                        ],
                      ),
                    ),
                  ),

                // ── Empty state ─────────────────────────────────────────
                if (_recentWorkouts != null && _recentWorkouts!.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.shimmer.withValues(alpha: 0.2),
                            ),
                            child: const Icon(
                              Icons.directions_run_outlined,
                              size: 32,
                              color: AppTheme.fog,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Ready when you are',
                            style: AppTheme.geist(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.moonbeam,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pick your activity and tap Start.\nmiruns handles the rest.',
                            textAlign: TextAlign.center,
                            style: AppTheme.geist(
                              fontSize: 13,
                              color: AppTheme.fog,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom padding for fixed bar
                SliverToBoxAdapter(child: SizedBox(height: 140 + bottom)),
              ],
            ),

            // ── Fixed bottom Start bar ──────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _FixedStartBar(
                selectedType: _selectedType,
                pulseAnim: _pulseAnim,
                onStart: _startWorkout,
                bottomPadding: bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sensor status enum for non-BLE sensors
// ─────────────────────────────────────────────────────────────────────────────

enum _SensorStatus { unknown, ready, noPermission, off, unavailable }

// ─────────────────────────────────────────────────────────────────────────────
// Fixed bottom Start bar — always visible, glassmorphism effect
// ─────────────────────────────────────────────────────────────────────────────

class _FixedStartBar extends StatelessWidget {
  final WorkoutType selectedType;
  final Animation<double> pulseAnim;
  final VoidCallback onStart;
  final double bottomPadding;

  const _FixedStartBar({
    required this.selectedType,
    required this.pulseAnim,
    required this.onStart,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.void_.withValues(alpha: 0),
            AppTheme.void_.withValues(alpha: 0.85),
            AppTheme.void_,
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding + 20),
      child: GestureDetector(
        onTap: onStart,
        child: AnimatedBuilder(
          animation: pulseAnim,
          builder: (context, _) {
            final glow = pulseAnim.value * 0.1;
            return Container(
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    AppTheme.cyan,
                    AppTheme.cyan.withValues(alpha: 0.85),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.cyan.withValues(alpha: 0.25 + glow),
                    blurRadius: 32,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: AppTheme.cyan.withValues(alpha: 0.08 + glow * 0.5),
                    blurRadius: 64,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selectedType.icon, size: 22, color: AppTheme.void_),
                  const SizedBox(width: 12),
                  Text(
                    'Start ${selectedType.label}',
                    style: AppTheme.geist(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.void_,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact sensor pill row — minimal horizontal indicators
// ─────────────────────────────────────────────────────────────────────────────

class _SensorPillRow extends StatelessWidget {
  final BleSourceState eegState;
  final String? eegDeviceName;
  final bool isDemoMode;
  final VoidCallback onEegTap;
  final BleConnectionState hrState;
  final VoidCallback onHrTap;
  final _SensorStatus gpsStatus;
  final VoidCallback onGpsTap;
  final _SensorStatus healthStatus;
  final VoidCallback onHealthTap;

  const _SensorPillRow({
    required this.eegState,
    this.eegDeviceName,
    required this.isDemoMode,
    required this.onEegTap,
    required this.hrState,
    required this.onHrTap,
    required this.gpsStatus,
    required this.onGpsTap,
    required this.healthStatus,
    required this.onHealthTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildPill(
            icon: Icons.headphones_rounded,
            label: 'EEG',
            state: _eegPillState(),
            onTap: onEegTap,
          ),
          const SizedBox(width: 8),
          _buildPill(
            icon: Icons.favorite_rounded,
            label: 'HR',
            state: _hrPillState(),
            onTap: onHrTap,
          ),
          const SizedBox(width: 8),
          _buildPill(
            icon: Icons.gps_fixed_rounded,
            label: 'GPS',
            state: _gpsPillState(),
            onTap: onGpsTap,
          ),
          const SizedBox(width: 8),
          _buildPill(
            icon: Icons.monitor_heart_outlined,
            label: 'Health',
            state: _healthPillState(),
            onTap: onHealthTap,
          ),
        ],
      ),
    );
  }

  _PillState _eegPillState() {
    if (eegState == BleSourceState.streaming) return _PillState.ready;
    if (isDemoMode) return _PillState.warning;
    if (eegState == BleSourceState.scanning ||
        eegState == BleSourceState.connecting)
      return _PillState.busy;
    if (eegState == BleSourceState.error) return _PillState.error;
    return _PillState.idle;
  }

  _PillState _hrPillState() {
    if (hrState == BleConnectionState.streaming) return _PillState.ready;
    if (hrState == BleConnectionState.scanning ||
        hrState == BleConnectionState.connecting)
      return _PillState.busy;
    if (hrState == BleConnectionState.error) return _PillState.error;
    return _PillState.idle;
  }

  _PillState _gpsPillState() {
    switch (gpsStatus) {
      case _SensorStatus.ready:
        return _PillState.ready;
      case _SensorStatus.noPermission:
      case _SensorStatus.off:
        return _PillState.warning;
      case _SensorStatus.unavailable:
        return _PillState.error;
      case _SensorStatus.unknown:
        return _PillState.busy;
    }
  }

  _PillState _healthPillState() {
    switch (healthStatus) {
      case _SensorStatus.ready:
        return _PillState.ready;
      case _SensorStatus.noPermission:
        return _PillState.warning;
      case _SensorStatus.off:
      case _SensorStatus.unavailable:
        return _PillState.error;
      case _SensorStatus.unknown:
        return _PillState.busy;
    }
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required _PillState state,
    required VoidCallback onTap,
  }) {
    final Color dotColor;
    switch (state) {
      case _PillState.ready:
        dotColor = AppTheme.seaGreen;
      case _PillState.busy:
        dotColor = AppTheme.cyan;
      case _PillState.warning:
        dotColor = AppTheme.amber;
      case _PillState.error:
        dotColor = AppTheme.crimson;
      case _PillState.idle:
        dotColor = AppTheme.fog;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.tidePool,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dotColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status dot
            if (state == _PillState.busy)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: dotColor,
                ),
              )
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  boxShadow: state == _PillState.ready
                      ? [
                          BoxShadow(
                            color: dotColor.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            const SizedBox(width: 6),
            Icon(icon, size: 13, color: AppTheme.fog),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTheme.geist(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.fog,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PillState { ready, busy, warning, error, idle }

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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.shimmer.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          // Activity icon with subtle background
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.cyan.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              session.workoutType.icon,
              size: 22,
              color: AppTheme.cyan,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.workoutType.label,
                  style: AppTheme.geist(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.moonbeam,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$when  ·  ${duration.inMinutes} min${session.totalDistanceKm != null ? '  ·  ${session.totalDistanceKm!.toStringAsFixed(1)} km' : ''}',
                  style: AppTheme.geistMono(fontSize: 11, color: AppTheme.fog),
                ),
              ],
            ),
          ),
          if (session.analysis != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${session.analysis!.performanceScore}',
                style: AppTheme.geistMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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

// ─────────────────────────────────────────────────────────────────────────────
// HR scan bottom sheet — scan and connect to BLE Heart Rate monitors
// ─────────────────────────────────────────────────────────────────────────────

class _HrScanSheet extends StatefulWidget {
  final BleHeartRateService hrService;

  const _HrScanSheet({required this.hrService});

  @override
  State<_HrScanSheet> createState() => _HrScanSheetState();
}

class _HrScanSheetState extends State<_HrScanSheet> {
  List<BleHrDevice> _devices = [];
  BleConnectionState _state = BleConnectionState.idle;
  StreamSubscription<List<BleHrDevice>>? _devicesSub;
  StreamSubscription<BleConnectionState>? _stateSub;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _state = widget.hrService.state;
    _stateSub = widget.hrService.stateStream.listen((s) {
      if (mounted) {
        setState(() => _state = s);
        if (s == BleConnectionState.streaming) {
          Navigator.of(context).pop();
        }
      }
    });
    _devicesSub = widget.hrService.devicesStream.listen((d) {
      if (mounted) setState(() => _devices = d);
    });

    if (_state != BleConnectionState.streaming) {
      _startScan();
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _devicesSub?.cancel();
    if (_state == BleConnectionState.scanning) {
      widget.hrService.stopScan();
    }
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _devices = []);
    try {
      await widget.hrService.startScan();
    } catch (_) {}
  }

  Future<void> _connectDevice(BleHrDevice device) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    HapticFeedback.mediumImpact();
    try {
      await widget.hrService.connectAndStream(device.device);
    } catch (_) {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isScanning = _state == BleConnectionState.scanning;
    final isConnecting = _connecting || _state == BleConnectionState.connecting;

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
              color: AppTheme.fog.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const Icon(
                Icons.favorite_rounded,
                size: 20,
                color: AppTheme.crimson,
              ),
              const SizedBox(width: 10),
              Text(
                'Heart Rate Monitor',
                style: AppTheme.geist(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.moonbeam,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Scanning for BLE Heart Rate devices…',
              style: AppTheme.geist(fontSize: 13, color: AppTheme.fog),
            ),
          ),
          const SizedBox(height: 16),

          if (isConnecting)
            _hrStatusTile(
              Icons.bluetooth_connected_rounded,
              'Connecting…',
              'Please wait',
            )
          else if (_devices.isEmpty && !isScanning)
            _hrStatusTile(
              Icons.bluetooth_searching_rounded,
              'No HR devices found',
              'Make sure your sensor is nearby and active',
            )
          else ...[
            for (final device in _devices)
              _HrDeviceTile(
                device: device,
                onTap: () => _connectDevice(device),
              ),
          ],

          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.tidePool,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.shimmer),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Close',
                      style: AppTheme.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.fog,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: isScanning ? null : _startScan,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: isScanning
                          ? AppTheme.tidePool
                          : AppTheme.cyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isScanning
                            ? AppTheme.shimmer
                            : AppTheme.cyan.withValues(alpha: 0.3),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.cyan,
                            ),
                          )
                        : Text(
                            'Re-scan',
                            style: AppTheme.geist(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.cyan,
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

  Widget _hrStatusTile(IconData icon, String title, String subtitle) {
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

class _HrDeviceTile extends StatelessWidget {
  final BleHrDevice device;
  final VoidCallback onTap;

  const _HrDeviceTile({required this.device, required this.onTap});

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
            const Icon(
              Icons.favorite_rounded,
              size: 20,
              color: AppTheme.crimson,
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
