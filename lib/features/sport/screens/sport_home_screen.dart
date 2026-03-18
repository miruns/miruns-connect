import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../../../../../../../core/theme/app_theme.dart';
import '../../../core/services/ambient_scan_service.dart';
import '../../../core/services/ble_heart_rate_service.dart';
import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../shared/widgets/nav_menu_button.dart';
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

  // Environment sensor state
  _SensorStatus _envStatus = _SensorStatus.unknown;
  AmbientScanData? _ambientData;

  // Pre-workout insight: CTA-driven (not auto)
  bool _insightAvailable = false;

  // Live sensor data for hero slider
  final List<double> _hrBuffer = [];
  final List<double> _rrBuffer = [];
  final List<List<double>> _eegBuffer = [];
  int? _currentBpm;
  double? _currentRmssd;
  StreamSubscription<BleHrReading>? _hrDataSub;
  StreamSubscription<SignalSample>? _eegDataSub;
  final PageController _sensorPageCtrl = PageController();
  int _sensorPage = 0;
  static const int _maxBuffer = 60;

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

    // Live HR data for slider graphs
    _hrDataSub = hrService.hrStream.listen((reading) {
      if (!mounted) return;
      setState(() {
        _currentBpm = reading.bpm;
        _hrBuffer.add(reading.bpm.toDouble());
        if (_hrBuffer.length > _maxBuffer) _hrBuffer.removeAt(0);
        if (reading.rrMs.isNotEmpty) {
          _rrBuffer.addAll(reading.rrMs);
          if (_rrBuffer.length > _maxBuffer) {
            _rrBuffer.removeRange(0, _rrBuffer.length - _maxBuffer);
          }
          final hrv = BleHrvMetrics.compute(_rrBuffer);
          _currentRmssd = hrv?.rmssd;
        }
      });
    });

    // Live EEG data for slider graph
    _eegDataSub = bleService.signalStream.listen((sample) {
      if (!mounted) return;
      setState(() {
        _eegBuffer.add(sample.channels);
        if (_eegBuffer.length > _maxBuffer) _eegBuffer.removeAt(0);
      });
    });

    _loadData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _bleSub?.cancel();
    _hrSub?.cancel();
    _hrDataSub?.cancel();
    _eegDataSub?.cancel();
    _devicesScanSub?.cancel();
    _reconnectTimer?.cancel();
    _sensorPageCtrl.dispose();
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
    _checkEnvStatus();

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

  Future<void> _checkEnvStatus() async {
    if (mounted) setState(() => _envStatus = _SensorStatus.unknown);
    try {
      final ambientService = ref.read(ambientScanServiceProvider);
      // Try GPS-based scan first, fall back to GeoIP
      AmbientScanData? data;
      final permission = await Geolocator.checkPermission();
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled &&
          permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          data = await ambientService.scanByCoordinates(
            pos.latitude,
            pos.longitude,
          );
        }
      }
      data ??= await ambientService.scanByGeoIp();
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _ambientData = data;
          _envStatus = _SensorStatus.ready;
        });
      } else {
        setState(() => _envStatus = _SensorStatus.unavailable);
      }
    } catch (_) {
      if (mounted) setState(() => _envStatus = _SensorStatus.unavailable);
    }
  }

  void _openEnvironment() {
    HapticFeedback.selectionClick();
    context.push('/environment');
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
                        Text(
                          'miruns',
                          style: AppTheme.geist(
                            fontSize: 20,
                            fontWeight: FontWeight.w300,
                            color: AppTheme.moonbeam,
                            letterSpacing: -0.5,
                          ),
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
                        const SizedBox(width: 10),
                        // Navigation menu
                        const NavMenuButton(),
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
                      envStatus: _envStatus,
                      envSummary: _ambientData != null
                          ? '${_ambientData!.temperature.currentC.round()}°'
                          : null,
                      onEnvTap: _envStatus == _SensorStatus.unavailable
                          ? _checkEnvStatus
                          : _openEnvironment,
                    ),
                  ),
                ),

                // ── Live sensor slider ──────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 130,
                          child: PageView(
                            controller: _sensorPageCtrl,
                            onPageChanged: (i) =>
                                setState(() => _sensorPage = i),
                            children: [
                              _LiveSensorCard(
                                label: 'HEART RATE',
                                value: _currentBpm != null
                                    ? '$_currentBpm bpm'
                                    : '-- bpm',
                                color: AppTheme.crimson,
                                icon: Icons.favorite_rounded,
                                child: _MiniWaveGraph(
                                  data: _hrBuffer,
                                  color: AppTheme.crimson,
                                  maxBuffer: _maxBuffer,
                                  baselineMin: 40,
                                  baselineMax: 200,
                                ),
                              ),
                              _LiveSensorCard(
                                label: 'HRV  (RMSSD)',
                                value: _currentRmssd != null
                                    ? '${_currentRmssd!.toStringAsFixed(0)} ms'
                                    : '-- ms',
                                color: AppTheme.seaGreen,
                                icon: Icons.timeline_rounded,
                                child: _MiniBarGraph(
                                  data: _rrBuffer,
                                  color: AppTheme.seaGreen,
                                  maxBuffer: _maxBuffer,
                                ),
                              ),
                              _LiveSensorCard(
                                label: 'EEG',
                                value: _eegBuffer.isNotEmpty
                                    ? '${_eegBuffer.last.length}ch live'
                                    : '-- idle',
                                color: AppTheme.cyan,
                                icon: Icons.waves_rounded,
                                child: _MiniMultiChannelGraph(
                                  data: _eegBuffer,
                                  color: AppTheme.cyan,
                                  maxBuffer: _maxBuffer,
                                ),
                              ),
                              _LiveSensorCard(
                                label: 'ENVIRONMENT',
                                value: _ambientData != null
                                    ? '${_ambientData!.temperature.currentC.round()}° · AQI ${_ambientData!.airQuality.usAqi}'
                                    : '-- loading',
                                color: AppTheme.amber,
                                icon: Icons.cloud_outlined,
                                child: _EnvSummaryWidget(data: _ambientData),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Page dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (i) {
                            final active = i == _sensorPage;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                color: active
                                    ? AppTheme.cyan
                                    : AppTheme.shimmer,
                              ),
                            );
                          }),
                        ),
                      ],
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
                                borderRadius: BorderRadius.circular(8),
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
                                borderRadius: BorderRadius.circular(8),
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
                                  borderRadius: BorderRadius.circular(8),
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
            AppTheme.void_.withValues(alpha: 0.92),
            AppTheme.void_,
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
      padding: EdgeInsets.fromLTRB(24, 32, 24, bottomPadding + 20),
      child: GestureDetector(
        onTap: onStart,
        child: AnimatedBuilder(
          animation: pulseAnim,
          builder: (context, _) {
            final pulse = pulseAnim.value;
            return Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppTheme.moonbeam,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
                boxShadow: [
                  // Tight inner glow
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.06 + pulse * 0.04),
                    blurRadius: 1,
                    spreadRadius: 0,
                  ),
                  // Medium halo
                  BoxShadow(
                    color: AppTheme.moonbeam.withValues(
                      alpha: 0.15 + pulse * 0.05,
                    ),
                    blurRadius: 24,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                  // Wide ambient glow
                  BoxShadow(
                    color: AppTheme.moonbeam.withValues(
                      alpha: 0.06 + pulse * 0.03,
                    ),
                    blurRadius: 48,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(selectedType.icon, size: 20, color: AppTheme.void_),
                    const SizedBox(width: 10),
                    Text(
                      'Start ${selectedType.label}',
                      style: AppTheme.geist(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.void_,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
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
  final _SensorStatus envStatus;
  final String? envSummary;
  final VoidCallback onEnvTap;

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
    required this.envStatus,
    this.envSummary,
    required this.onEnvTap,
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
          const SizedBox(width: 8),
          _buildPill(
            icon: Icons.cloud_outlined,
            label: envSummary ?? 'Env',
            state: _envPillState(),
            onTap: onEnvTap,
          ),
        ],
      ),
    );
  }

  _PillState _eegPillState() {
    if (eegState == BleSourceState.streaming) return _PillState.ready;
    if (isDemoMode) return _PillState.warning;
    if (eegState == BleSourceState.scanning ||
        eegState == BleSourceState.connecting) {
      return _PillState.busy;
    }
    if (eegState == BleSourceState.error) return _PillState.error;
    return _PillState.idle;
  }

  _PillState _hrPillState() {
    if (hrState == BleConnectionState.streaming) return _PillState.ready;
    if (hrState == BleConnectionState.scanning ||
        hrState == BleConnectionState.connecting) {
      return _PillState.busy;
    }
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

  _PillState _envPillState() {
    switch (envStatus) {
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
          borderRadius: BorderRadius.circular(8),
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
        borderRadius: BorderRadius.circular(8),
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
              borderRadius: BorderRadius.circular(6),
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
                borderRadius: BorderRadius.circular(6),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
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
                      borderRadius: BorderRadius.circular(8),
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
                      borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(8),
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

// ─────────────────────────────────────────────────────────────────────────────
// Live sensor card — single page in the sensor slider
// ─────────────────────────────────────────────────────────────────────────────

class _LiveSensorCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final Widget child;

  const _LiveSensorCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.tidePool,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Graph fills backdrop
            Positioned.fill(child: child),
            // Labels overlay
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: AppTheme.geist(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    value,
                    style: AppTheme.geist(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.moonbeam,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini wave graph — smooth line chart for HR data
// ─────────────────────────────────────────────────────────────────────────────

class _MiniWaveGraph extends StatelessWidget {
  final List<double> data;
  final Color color;
  final int maxBuffer;
  final double baselineMin;
  final double baselineMax;

  const _MiniWaveGraph({
    required this.data,
    required this.color,
    required this.maxBuffer,
    this.baselineMin = 0,
    this.baselineMax = 100,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WavePainter(
        data: data,
        color: color,
        maxBuffer: maxBuffer,
        baselineMin: baselineMin,
        baselineMax: baselineMax,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final int maxBuffer;
  final double baselineMin;
  final double baselineMax;

  _WavePainter({
    required this.data,
    required this.color,
    required this.maxBuffer,
    required this.baselineMin,
    required this.baselineMax,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) {
      _paintPlaceholder(canvas, size);
      return;
    }

    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final minV = data.reduce(math.min).clamp(baselineMin, baselineMax);
    final maxV = data.reduce(math.max).clamp(baselineMin, baselineMax);
    final range = (maxV - minV).clamp(10.0, double.infinity);

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (maxBuffer - 1);

    for (var i = 0; i < data.length; i++) {
      final x = (maxBuffer - data.length + i) * stepX;
      final y =
          size.height -
          ((data[i] - minV) / range) * size.height * 0.7 -
          size.height * 0.15;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo((maxBuffer - 1) * stepX, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  void _paintPlaceholder(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final path = Path();
    final midY = size.height * 0.5;
    path.moveTo(0, midY);
    for (var x = 0.0; x < size.width; x += 4) {
      path.lineTo(x, midY + math.sin(x * 0.05) * 8);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini bar graph — RR interval variability for HRV
// ─────────────────────────────────────────────────────────────────────────────

class _MiniBarGraph extends StatelessWidget {
  final List<double> data;
  final Color color;
  final int maxBuffer;

  const _MiniBarGraph({
    required this.data,
    required this.color,
    required this.maxBuffer,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarPainter(data: data, color: color, maxBuffer: maxBuffer),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final int maxBuffer;

  _BarPainter({
    required this.data,
    required this.color,
    required this.maxBuffer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) {
      _paintPlaceholder(canvas, size);
      return;
    }

    final barWidth = (size.width / maxBuffer).clamp(2.0, 6.0);
    const gap = 1.0;
    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV).clamp(50.0, double.infinity);

    for (var i = 0; i < data.length; i++) {
      final x = (maxBuffer - data.length + i) * (barWidth + gap);
      if (x > size.width) continue;
      final norm = ((data[i] - minV) / range).clamp(0.1, 1.0);
      final h = norm * size.height * 0.6;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h - size.height * 0.1, barWidth, h),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = color.withValues(alpha: 0.15 + norm * 0.4),
      );
    }
  }

  void _paintPlaceholder(Canvas canvas, Size size) {
    final rng = math.Random(42);
    const barW = 3.0;
    const gap = 2.0;
    final count = (size.width / (barW + gap)).floor();
    for (var i = 0; i < count; i++) {
      final h = 8.0 + rng.nextDouble() * 20;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (barW + gap), size.height - h - 10, barW, h),
          const Radius.circular(1.5),
        ),
        Paint()..color = color.withValues(alpha: 0.06),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini multi-channel graph — overlapping EEG channels
// ─────────────────────────────────────────────────────────────────────────────

class _MiniMultiChannelGraph extends StatelessWidget {
  final List<List<double>> data;
  final Color color;
  final int maxBuffer;

  const _MiniMultiChannelGraph({
    required this.data,
    required this.color,
    required this.maxBuffer,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MultiChannelPainter(
        data: data,
        color: color,
        maxBuffer: maxBuffer,
      ),
    );
  }
}

class _MultiChannelPainter extends CustomPainter {
  final List<List<double>> data;
  final Color color;
  final int maxBuffer;

  _MultiChannelPainter({
    required this.data,
    required this.color,
    required this.maxBuffer,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) {
      _paintPlaceholder(canvas, size);
      return;
    }

    final nCh = data.first.length.clamp(1, 8);
    final stepX = size.width / (maxBuffer - 1);
    final bandH = size.height / nCh;

    for (var ch = 0; ch < nCh; ch++) {
      final paint = Paint()
        ..color = color.withValues(alpha: 0.25 + (ch % 3) * 0.15)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // Find channel range
      double cMin = double.infinity, cMax = double.negativeInfinity;
      for (final s in data) {
        if (ch < s.length) {
          if (s[ch] < cMin) cMin = s[ch];
          if (s[ch] > cMax) cMax = s[ch];
        }
      }
      final range = (cMax - cMin).clamp(1.0, double.infinity);
      final midY = bandH * (ch + 0.5);

      final path = Path();
      for (var i = 0; i < data.length; i++) {
        if (ch >= data[i].length) continue;
        final x = (maxBuffer - data.length + i) * stepX;
        final norm = (data[i][ch] - cMin) / range - 0.5;
        final y = midY + norm * bandH * 0.7;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintPlaceholder(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.06)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (var ch = 0; ch < 4; ch++) {
      final midY = size.height * (ch + 0.5) / 4;
      final path = Path();
      path.moveTo(0, midY);
      for (var x = 0.0; x < size.width; x += 3) {
        path.lineTo(x, midY + math.sin(x * 0.08 + ch * 1.5) * 6);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MultiChannelPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Environment summary widget — compact conditions display for sensor slider
// ─────────────────────────────────────────────────────────────────────────────

class _EnvSummaryWidget extends StatelessWidget {
  final AmbientScanData? data;

  const _EnvSummaryWidget({this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Center(
        child: Text(
          'Fetching conditions…',
          style: AppTheme.geist(fontSize: 11, color: AppTheme.fog),
        ),
      );
    }

    final d = data!;
    final items = <_EnvItem>[
      _EnvItem(
        Icons.thermostat_rounded,
        '${d.temperature.currentC.round()}°C',
        'Feels ${d.temperature.feelsLikeC.round()}°',
      ),
      _EnvItem(
        Icons.air_rounded,
        '${d.wind.speedKmh.round()} km/h',
        d.wind.directionLabel,
      ),
      _EnvItem(
        Icons.water_drop_outlined,
        '${d.humidity.relativePercent}%',
        'Humidity',
      ),
      _EnvItem(
        _aqiIcon(d.airQuality.usAqi),
        'AQI ${d.airQuality.usAqi}',
        d.airQuality.level,
      ),
      _EnvItem(
        Icons.wb_sunny_outlined,
        'UV ${d.uvIndex.current.round()}',
        d.uvIndex.level,
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items
          .map(
            (item) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 14, color: AppTheme.amber),
                const SizedBox(height: 3),
                Text(
                  item.value,
                  style: AppTheme.geist(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.moonbeam,
                  ),
                ),
                Text(
                  item.detail,
                  style: AppTheme.geist(fontSize: 9, color: AppTheme.fog),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  IconData _aqiIcon(int aqi) {
    if (aqi <= 50) return Icons.eco_rounded;
    if (aqi <= 100) return Icons.cloud_outlined;
    return Icons.masks_rounded;
  }
}

class _EnvItem {
  final IconData icon;
  final String value;
  final String detail;
  const _EnvItem(this.icon, this.value, this.detail);
}
