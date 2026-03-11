import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/m_signal_logo.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EEG Onboarding — first-run experience for the miruns EEG headset companion
//
// Pages:
//   0 · Welcome      — animated M logo + tagline + "Begin"
//   1 · Features     — three value-prop cards
//   2 · Pair          — BLE scan for EAREEG, demo-mode escape hatch
//   3 · Signal check — animated electrode quality grid (or demo waveform)
//   4 · Ready        — confirmation + enter app
// ─────────────────────────────────────────────────────────────────────────────

class EegOnboardingScreen extends ConsumerStatefulWidget {
  const EegOnboardingScreen({super.key});

  @override
  ConsumerState<EegOnboardingScreen> createState() =>
      _EegOnboardingScreenState();
}

class _EegOnboardingScreenState extends ConsumerState<EegOnboardingScreen>
    with TickerProviderStateMixin {
  static const _totalPages = 5;

  final _pageCtrl = PageController();
  int _page = 0;

  // ── BLE scan ───────────────────────────────────────────────────────────────
  late final BleSourceService _bleService;
  BleSourceProvider? _eegProvider;

  List<BleSourceDevice> _foundDevices = [];
  BleSourceState _bleState = BleSourceState.idle;
  BleSourceDevice? _selectedDevice;

  StreamSubscription<List<BleSourceDevice>>? _devicesSub;
  StreamSubscription<BleSourceState>? _bleStateSub;

  // ── Pairing / demo state ───────────────────────────────────────────────────
  bool _isDemoMode = false;

  // ── Electrode simulation (page 3) ─────────────────────────────────────────
  static const _electrodeLabels = [
    'Fp1',
    'Fp2',
    'C3',
    'C4',
    'P3',
    'P4',
    'O1',
    'O2',
  ];
  final List<int> _electrodeQuality = List.filled(
    8,
    0,
  ); // 0=checking 1=good 2=fair 3=poor
  Timer? _simTimer;
  int _simStep = 0;
  bool _signalCheckDone = false;

  // ── Welcome staggered fade-ins ─────────────────────────────────────────────
  bool _showTagline = false;
  bool _showBegin = false;

  // ── Demo waveform ticker (page 3 demo mode) ────────────────────────────────
  Timer? _waveTimer;
  final List<double> _wavePoints = List.filled(40, 0);
  int _waveTick = 0;
  final _rng = Random();

  // ── Real-mode signal subscription (page 3) ───────────────────────────────
  StreamSubscription<SignalSample>? _signalSub;

  @override
  void initState() {
    super.initState();

    _bleService = ref.read(bleSourceServiceProvider);
    _eegProvider = ref.read(bleSourceRegistryProvider).getById('ads1299');

    _bleStateSub = _bleService.stateStream.listen((s) {
      if (mounted) setState(() => _bleState = s);
    });
    _devicesSub = _bleService.devicesStream.listen((d) {
      if (mounted) setState(() => _foundDevices = d);
    });

    // Stagger welcome-page text.
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _showTagline = true);
    });
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _showBegin = true);
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _bleStateSub?.cancel();
    _devicesSub?.cancel();
    _simTimer?.cancel();
    _waveTimer?.cancel();
    _signalSub?.cancel();
    _bleService.stopScan();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goNext() {
    if (_page >= _totalPages - 1) return;
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    if (page == 2) _beginScan();
    if (page == 3) _startSignalSimulation();
  }

  // ── BLE scanning ───────────────────────────────────────────────────────────

  Future<void> _beginScan() async {
    if (_eegProvider == null) return;
    setState(() => _foundDevices = []);
    try {
      await _bleService.startScan(_eegProvider!);
    } catch (_) {
      // BT off or permission denied — the UI already shows "No headset found".
    }
  }

  void _pairDevice(BleSourceDevice device) async {
    setState(() => _selectedDevice = device);
    HapticFeedback.mediumImpact();

    final db = ref.read(localDbServiceProvider);
    await db.setSetting('eeg_paired_device_id', device.device.remoteId.str);
    await db.setSetting('eeg_paired_device_name', device.name);
    await db.setSetting('eeg_demo_mode', 'false');
    await _bleService.stopScan();
    _goNext();
  }

  void _useDemoMode() async {
    setState(() => _isDemoMode = true);
    HapticFeedback.lightImpact();
    final db = ref.read(localDbServiceProvider);
    await db.setSetting('eeg_demo_mode', 'true');
    await _bleService.stopScan();
    _goNext();
  }

  // ── Signal simulation ───────────────────────────────────────────────────────

  void _startSignalSimulation() {
    _simStep = 0;
    _signalCheckDone = false;
    for (var i = 0; i < 8; i++) {
      _electrodeQuality[i] = 0;
    }

    _simTimer?.cancel();
    _waveTimer?.cancel();

    if (_isDemoMode) {
      // Demo: reveal all electrodes as "good" fast, then animate a waveform.
      _simTimer = Timer.periodic(const Duration(milliseconds: 220), (_) {
        if (!mounted) return;
        setState(() {
          if (_simStep < 8) {
            _electrodeQuality[_simStep] = 1;
            _simStep++;
          } else {
            _signalCheckDone = true;
            _simTimer?.cancel();
          }
        });
      });
      // Also drive the demo wave.
      _waveTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (!mounted) return;
        setState(() {
          _wavePoints.removeAt(0);
          final v =
              sin(_waveTick * 0.18) * 0.45 +
              sin(_waveTick * 0.43) * 0.20 +
              (_rng.nextDouble() - 0.5) * 0.15;
          _wavePoints.add(v.clamp(-1.0, 1.0));
          _waveTick++;
        });
      });
    } else {
      // Real device: derive quality from actual live signal (RMS per channel).
      _signalSub?.cancel();
      final channelData = List.generate(8, (_) => <double>[]);
      int nextElectrode = 0;
      const samplesPerElectrode = 25; // ~100 ms window per reveal at 250 Hz

      _signalSub = _bleService.signalStream.listen((sample) {
        if (!mounted) return;

        for (var ch = 0; ch < 8 && ch < sample.channels.length; ch++) {
          channelData[ch].add(sample.channels[ch]);
        }

        bool needsRebuild = false;

        // Score electrodes one by one as data accumulates.
        while (nextElectrode < 8 &&
            channelData[0].length >=
                samplesPerElectrode * (nextElectrode + 1)) {
          _electrodeQuality[nextElectrode] = _classifyChannel(
            channelData[nextElectrode],
          );
          nextElectrode++;
          needsRebuild = true;
          if (nextElectrode == 8) _signalCheckDone = true;
        }

        // Feed waveform at ~25 Hz (every 10th sample).
        if (channelData[0].length % 10 == 0) {
          _wavePoints.removeAt(0);
          _wavePoints.add((sample.channels[0] / 50.0).clamp(-1.0, 1.0));
          needsRebuild = true;
        }

        if (needsRebuild) setState(() {});

        if (_signalCheckDone) _signalSub?.cancel();
      });
    }
  }

  // ── Channel quality heuristic ──────────────────────────────────────────────

  /// Classifies a channel's signal quality from its RMS amplitude (µV).
  /// Typical EEG: 5–100 µV RMS. Near-zero = disconnected; very high = artifact.
  int _classifyChannel(List<double> samples) {
    if (samples.isEmpty) return 0;
    double sumSq = 0;
    for (final v in samples) {
      sumSq += v * v;
    }
    final rms = sqrt(sumSq / samples.length);
    if (rms < 1.0 || rms > 300.0) return 3; // poor — flat or saturated
    if (rms < 5.0 || rms > 150.0) return 2; // fair
    return 1; // good
  }

  // ── Finish ─────────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    HapticFeedback.heavyImpact();
    final db = ref.read(localDbServiceProvider);
    await db.setSetting('eeg_onboarding_done', 'true');
    if (mounted) context.go('/eeg-home');
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    return Scaffold(
      backgroundColor: AppTheme.void_,
      body: Stack(
        children: [
          PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: _onPageChanged,
            children: [
              _WelcomePage(
                showTagline: _showTagline,
                showBegin: _showBegin,
                onBegin: _goNext,
              ),
              _FeaturesPage(onContinue: _goNext),
              _PairPage(
                bleState: _bleState,
                foundDevices: _foundDevices,
                selectedDevice: _selectedDevice,
                onPair: _pairDevice,
                onRescan: _beginScan,
                onDemoMode: _useDemoMode,
              ),
              _SignalCheckPage(
                isDemoMode: _isDemoMode,
                electrodeQuality: _electrodeQuality,
                electrodeLabels: _electrodeLabels,
                wavePoints: _wavePoints,
                checkDone: _signalCheckDone,
                onContinue: _goNext,
              ),
              _ReadyPage(
                isDemoMode: _isDemoMode,
                deviceName: _selectedDevice?.name,
                onStart: _finish,
              ),
            ],
          ),

          // ── Progress pill (hidden on welcome + ready) ───────────────────────
          if (_page > 0 && _page < _totalPages - 1)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 18,
              left: 0,
              right: 0,
              child: _ProgressDots(current: _page - 1, total: _totalPages - 2),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 0 — Welcome
// ─────────────────────────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final bool showTagline;
  final bool showBegin;
  final VoidCallback onBegin;

  const _WelcomePage({
    required this.showTagline,
    required this.showBegin,
    required this.onBegin,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // M logo draws itself, then glows + rotates
            const MSignalLogo(size: 96),
            const SizedBox(height: 28),
            // App name
            Text(
              'miruns',
              style: GoogleFonts.inter(
                fontSize: 40,
                fontWeight: FontWeight.w300,
                color: AppTheme.moonbeam,
                letterSpacing: -1.8,
              ),
            ),
            // Tagline — fades in after logo finishes drawing
            AnimatedOpacity(
              opacity: showTagline ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 700),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Your brain, live.',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.fog,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 64),
            // Begin — slides up and fades in
            AnimatedOpacity(
              opacity: showBegin ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: AnimatedSlide(
                offset: showBegin ? Offset.zero : const Offset(0, 0.5),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                child: _PrimaryButton(label: 'Begin', onTap: onBegin),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 1 — Features
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturesPage extends StatelessWidget {
  final VoidCallback onContinue;
  const _FeaturesPage({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(28, top + 80, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What miruns\nsees in you',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: AppTheme.moonbeam,
              letterSpacing: -1.0,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'EEG monitoring for athletes\nand curious minds.',
            style: GoogleFonts.inter(
              fontSize: 15,
              color: AppTheme.fog,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 36),
          _FeatureCard(
            icon: Icons.sensors_rounded,
            color: AppTheme.glow,
            title: 'Live EEG',
            subtitle: '8 channels · 250 Hz · real-time brain activity',
          ),
          const SizedBox(height: 14),
          _FeatureCard(
            icon: Icons.radio_button_checked_rounded,
            color: AppTheme.aurora,
            title: 'Capture sessions',
            subtitle: 'Record any mental state — focus, rest, flow',
          ),
          const SizedBox(height: 14),
          _FeatureCard(
            icon: Icons.auto_graph_rounded,
            color: AppTheme.starlight,
            title: 'Find your patterns',
            subtitle: 'AI reads trends across sessions and time',
          ),
          const Spacer(),
          _PrimaryButton(label: 'Continue', onTap: onContinue),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 2 — Pair headset
// ─────────────────────────────────────────────────────────────────────────────

class _PairPage extends StatelessWidget {
  final BleSourceState bleState;
  final List<BleSourceDevice> foundDevices;
  final BleSourceDevice? selectedDevice;
  final ValueChanged<BleSourceDevice> onPair;
  final VoidCallback onRescan;
  final VoidCallback onDemoMode;

  const _PairPage({
    required this.bleState,
    required this.foundDevices,
    required this.selectedDevice,
    required this.onPair,
    required this.onRescan,
    required this.onDemoMode,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(28, top + 80, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find your\nheadset',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: AppTheme.moonbeam,
              letterSpacing: -1.0,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Put on your EAREEG and power it on.',
            style: GoogleFonts.inter(fontSize: 15, color: AppTheme.fog),
          ),
          const SizedBox(height: 36),

          // Scan animation
          Center(child: _ScanRipple(state: bleState)),
          const SizedBox(height: 28),

          // Device list / status
          Expanded(
            child: foundDevices.isNotEmpty
                ? ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: foundDevices.length,
                    itemBuilder: (_, i) => _DeviceRow(
                      device: foundDevices[i],
                      isSelected:
                          selectedDevice?.device.remoteId ==
                          foundDevices[i].device.remoteId,
                      onTap: () => onPair(foundDevices[i]),
                    ),
                  )
                : _ScanStatus(state: bleState, onRescan: onRescan),
          ),

          // Demo mode escape hatch
          Center(
            child: TextButton(
              onPressed: onDemoMode,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.fog,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(
                'Use Demo Mode',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.fog,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 3 — Signal check
// ─────────────────────────────────────────────────────────────────────────────

class _SignalCheckPage extends StatelessWidget {
  final bool isDemoMode;
  final List<int> electrodeQuality;
  final List<String> electrodeLabels;
  final List<double> wavePoints;
  final bool checkDone;
  final VoidCallback onContinue;

  const _SignalCheckPage({
    required this.isDemoMode,
    required this.electrodeQuality,
    required this.electrodeLabels,
    required this.wavePoints,
    required this.checkDone,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(28, top + 80, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDemoMode ? 'Demo mode' : 'Signal check',
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: AppTheme.moonbeam,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isDemoMode
                ? 'Exploring without a headset.\nYou can pair one anytime from Settings.'
                : 'Adjust your headset until\nall electrodes are green.',
            style: GoogleFonts.inter(
              fontSize: 15,
              color: AppTheme.fog,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 44),

          // ── Electrode quality grid (4 × 2) ──────────────────────────────────
          Center(
            child: SizedBox(
              width: 300,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 18,
                  childAspectRatio: 0.85,
                ),
                itemCount: 8,
                itemBuilder: (_, i) => _ElectrodeIndicator(
                  label: electrodeLabels[i],
                  quality: electrodeQuality[i],
                ),
              ),
            ),
          ),

          // ── Waveform preview ─────────────────────────────────────────────────
          if (checkDone) ...[
            const SizedBox(height: 28),
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.deepSea,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.shimmer, width: 0.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CustomPaint(
                  painter: _WavePainter(points: wavePoints),
                  size: Size.infinite,
                ),
              ),
            ),
          ],

          const Spacer(),
          AnimatedOpacity(
            opacity: checkDone ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 400),
            child: _PrimaryButton(
              label: isDemoMode ? 'Continue' : 'Looks good',
              onTap: checkDone ? onContinue : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 4 — Ready
// ─────────────────────────────────────────────────────────────────────────────

class _ReadyPage extends StatelessWidget {
  final bool isDemoMode;
  final String? deviceName;
  final VoidCallback onStart;

  const _ReadyPage({
    required this.isDemoMode,
    required this.deviceName,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final label = isDemoMode ? 'Demo Mode' : (deviceName ?? 'Your EAREEG');
    final labelColor = isDemoMode ? AppTheme.amber : AppTheme.seaGreen;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Checkmark circle
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.seaGreen.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 36,
                color: AppTheme.seaGreen,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              "You're ready.",
              style: GoogleFonts.inter(
                fontSize: 34,
                fontWeight: FontWeight.w600,
                color: AppTheme.moonbeam,
                letterSpacing: -1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: labelColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pair a headset anytime\nfrom Settings.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.fog,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 56),
            _PrimaryButton(label: 'Start exploring', onTap: onStart),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

// ── Progress dots ──────────────────────────────────────────────────────────────

class _ProgressDots extends StatelessWidget {
  final int current; // 0-based index within pages 1..3
  final int total;

  const _ProgressDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? AppTheme.glow
                : AppTheme.fog.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ── Feature card ───────────────────────────────────────────────────────────────

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _FeatureCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.tidePool,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.shimmer, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.moonbeam,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.fog,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan ripple animation ──────────────────────────────────────────────────────

class _ScanRipple extends StatefulWidget {
  final BleSourceState state;
  const _ScanRipple({required this.state});

  @override
  State<_ScanRipple> createState() => _ScanRippleState();
}

class _ScanRippleState extends State<_ScanRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanning = widget.state == BleSourceState.scanning;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => SizedBox(
        width: 130,
        height: 130,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (scanning)
              Opacity(
                opacity: (1 - _anim.value) * 0.35,
                child: Container(
                  width: 115 + _anim.value * 22,
                  height: 115 + _anim.value * 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.glow, width: 1),
                  ),
                ),
              ),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.glow.withValues(
                  alpha: 0.07 + (scanning ? _anim.value * 0.06 : 0),
                ),
                border: Border.all(
                  color: AppTheme.glow.withValues(alpha: scanning ? 0.5 : 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.headset_rounded,
                size: 38,
                color: AppTheme.glow.withValues(
                  alpha: 0.55 + (scanning ? _anim.value * 0.45 : 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Scan status text ──────────────────────────────────────────────────────────

class _ScanStatus extends StatelessWidget {
  final BleSourceState state;
  final VoidCallback onRescan;

  const _ScanStatus({required this.state, required this.onRescan});

  @override
  Widget build(BuildContext context) {
    if (state == BleSourceState.scanning) {
      return Center(
        child: Text(
          'Scanning for EAREEG…',
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.fog),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No headset found.',
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.fog),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRescan,
            child: Text(
              'Try again',
              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.glow),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Device row ────────────────────────────────────────────────────────────────

class _DeviceRow extends StatelessWidget {
  final BleSourceDevice device;
  final bool isSelected;
  final VoidCallback onTap;

  const _DeviceRow({
    required this.device,
    required this.isSelected,
    required this.onTap,
  });

  int get _bars {
    final r = device.rssi;
    if (r >= -60) return 4;
    if (r >= -70) return 3;
    if (r >= -80) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.glow.withValues(alpha: 0.08)
              : AppTheme.tidePool,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppTheme.glow.withValues(alpha: 0.5)
                : AppTheme.shimmer,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.headset_rounded,
              size: 22,
              color: isSelected ? AppTheme.glow : AppTheme.fog,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                device.name,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.moonbeam,
                ),
              ),
            ),
            // RSSI signal bars
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(4, (i) {
                final active = i < _bars;
                return Container(
                  width: 3,
                  height: 6.0 + i * 3.5,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: active
                        ? AppTheme.seaGreen
                        : AppTheme.fog.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Electrode quality indicator ───────────────────────────────────────────────

class _ElectrodeIndicator extends StatelessWidget {
  final String label;
  final int quality; // 0=checking 1=good 2=fair 3=poor

  const _ElectrodeIndicator({required this.label, required this.quality});

  Color get _color => switch (quality) {
    1 => AppTheme.seaGreen,
    2 => AppTheme.amber,
    3 => AppTheme.crimson,
    _ => AppTheme.fog.withValues(alpha: 0.22),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _color.withValues(alpha: quality == 0 ? 0.0 : 0.14),
            shape: BoxShape.circle,
            border: Border.all(
              color: _color.withValues(alpha: quality == 0 ? 0.18 : 0.75),
              width: 1.5,
            ),
          ),
          child: Center(
            child: quality == 0
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppTheme.fog.withValues(alpha: 0.28),
                    ),
                  )
                : Icon(
                    switch (quality) {
                      1 => Icons.check_rounded,
                      2 => Icons.remove_rounded,
                      _ => Icons.close_rounded,
                    },
                    size: 20,
                    color: _color,
                  ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppTheme.fog,
          ),
        ),
      ],
    );
  }
}

// ── Demo waveform painter ─────────────────────────────────────────────────────

class _WavePainter extends CustomPainter {
  final List<double> points;
  const _WavePainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.glow.withValues(alpha: 0.7);

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height * 0.5 - points[i] * size.height * 0.40;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

// ── Primary action button ─────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.35 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            color: AppTheme.moonbeam,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.void_,
            ),
          ),
        ),
      ),
    );
  }
}
