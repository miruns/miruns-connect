import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../../../../../../../../../../core/theme/app_theme.dart';
import '../../shared/widgets/nav_menu_button.dart';
import '../widgets/m_signal_logo.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EEG Home — primary landing screen after onboarding
//
// Layout:
//   · Top bar    : "miruns" wordmark, device status pill, Expert toggle
//   · Hero       : pulsing Start Session circle
//   · Expert bar : revealed when expert mode is on — shortcuts to power-user screens
// ─────────────────────────────────────────────────────────────────────────────

class EegHomeScreen extends ConsumerStatefulWidget {
  const EegHomeScreen({super.key});

  @override
  ConsumerState<EegHomeScreen> createState() => _EegHomeScreenState();
}

class _EegHomeScreenState extends ConsumerState<EegHomeScreen>
    with SingleTickerProviderStateMixin {
  // Loaded from DB on init
  String? _pairedDeviceName;
  bool _isDemoMode = false;

  // Expert mode toggle (local — no persistence needed between sessions)
  bool _expertMode = false;

  // Live BLE state listened via stream
  BleSourceState _bleState = BleSourceState.idle;
  StreamSubscription<BleSourceState>? _bleSub;

  // Hero pulse
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _loadPrefs();

    // Track BLE state so status pill updates live.
    final bleService = ref.read(bleSourceServiceProvider);
    _bleState = bleService.state;
    _bleSub = bleService.stateStream.listen((s) {
      if (mounted) setState(() => _bleState = s);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _bleSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final db = ref.read(localDbServiceProvider);
    final name = await db.getSetting('eeg_paired_device_name');
    final demo = await db.getSetting('eeg_demo_mode');
    if (mounted) {
      setState(() {
        _pairedDeviceName = name;
        _isDemoMode = demo == 'true';
      });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool get _isConnected => _bleState == BleSourceState.streaming;

  void _startSession() {
    HapticFeedback.mediumImpact();
    context.push('/sources/ads1299');
  }

  void _toggleExpert() {
    setState(() => _expertMode = !_expertMode);
    HapticFeedback.selectionClick();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.void_,
        body: Padding(
          padding: EdgeInsets.fromLTRB(24, top + 14, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Top bar ─────────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // M logo (small, always playing)
                  const MSignalLogo(size: 26),
                  const SizedBox(width: 8),
                  Text(
                    'miruns',
                    style: AppTheme.geist(
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      color: AppTheme.moonbeam,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const Spacer(),
                  // Device status pill
                  _StatusPill(
                    deviceName: _pairedDeviceName,
                    isDemoMode: _isDemoMode,
                    isConnected: _isConnected,
                  ),
                  const SizedBox(width: 10),
                  // Expert mode toggle
                  _ExpertToggle(active: _expertMode, onTap: _toggleExpert),
                  const SizedBox(width: 10),
                  // Navigation menu
                  const NavMenuButton(),
                ],
              ),

              const Spacer(),

              // ── Hero: pulsing start button ───────────────────────────────────
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outermost ring — slowest fade
                      Opacity(
                        opacity: (1 - _pulseAnim.value) * 0.18,
                        child: Container(
                          width: 186 + _pulseAnim.value * 28,
                          height: 186 + _pulseAnim.value * 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.glow, width: 1),
                          ),
                        ),
                      ),
                      // Middle ring
                      Opacity(
                        opacity: (1 - _pulseAnim.value) * 0.28,
                        child: Container(
                          width: 158 + _pulseAnim.value * 16,
                          height: 158 + _pulseAnim.value * 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.glow, width: 1),
                          ),
                        ),
                      ),
                      // Core action button
                      GestureDetector(
                        onTap: _startSession,
                        child: Container(
                          width: 138,
                          height: 138,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.glow.withValues(
                              alpha: 0.07 + _pulseAnim.value * 0.05,
                            ),
                            border: Border.all(
                              color: AppTheme.glow.withValues(alpha: 0.45),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.sensors_rounded,
                                size: 34,
                                color: AppTheme.glow,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Start',
                                style: AppTheme.geist(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.moonbeam,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              Text(
                                'session',
                                style: AppTheme.geist(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: AppTheme.fog,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 18),
              Text(
                _isConnected
                    ? 'Connected · ready to stream'
                    : 'Tap to scan & connect',
                style: AppTheme.geist(
                  fontSize: 13,
                  color: _isConnected ? AppTheme.seaGreen : AppTheme.fog,
                ),
              ),

              const Spacer(),

              // ── Expert panel (revealed on toggle) ────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOut,
                child: _expertMode
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 80),
                        child: _ExpertPanel(
                          onLiveSignals: () => context.push('/sources/ads1299'),
                          onSources: () => context.push('/sources'),
                          onSensors: () => context.push('/sensors'),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status pill
// ─────────────────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String? deviceName;
  final bool isDemoMode;
  final bool isConnected;

  const _StatusPill({
    this.deviceName,
    required this.isDemoMode,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final Color dot = isDemoMode
        ? AppTheme.amber
        : (isConnected ? AppTheme.seaGreen : AppTheme.fog);
    final String text = isDemoMode
        ? 'Demo'
        : (isConnected
              ? (deviceName ?? 'Connected')
              : (deviceName ?? 'No device'));

    return _PillContainer(
      color: dot,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: dot, active: isConnected || isDemoMode),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTheme.geist(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: dot,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillContainer extends StatelessWidget {
  final Color color;
  final Widget child;
  const _PillContainer({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 0.5),
      ),
      child: child,
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool active;
  const _PulseDot({required this.color, required this.active});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(
            alpha: widget.active ? (0.5 + _ctrl.value * 0.5) : 0.4,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expert mode toggle button
// ─────────────────────────────────────────────────────────────────────────────

class _ExpertToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _ExpertToggle({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.aurora : AppTheme.fog;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.aurora.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? AppTheme.aurora.withValues(alpha: 0.45)
                : AppTheme.shimmer,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.developer_mode_rounded, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              'Expert',
              style: AppTheme.geist(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expert panel — shortcuts to power-user views
// ─────────────────────────────────────────────────────────────────────────────

class _ExpertPanel extends StatelessWidget {
  final VoidCallback onLiveSignals;
  final VoidCallback onSources;
  final VoidCallback onSensors;

  const _ExpertPanel({
    required this.onLiveSignals,
    required this.onSources,
    required this.onSensors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.aurora.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.aurora.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXPERT MODE',
            style: AppTheme.geist(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.aurora.withValues(alpha: 0.7),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ExpertShortcut(
                  icon: Icons.timeline_rounded,
                  color: AppTheme.glow,
                  label: 'Live signals',
                  sublabel: 'EEG waveform',
                  onTap: onLiveSignals,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ExpertShortcut(
                  icon: Icons.psychology_alt,
                  color: AppTheme.aurora,
                  label: 'All sources',
                  sublabel: 'Manage devices',
                  onTap: onSources,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ExpertShortcut(
                  icon: Icons.sensors_rounded,
                  color: AppTheme.starlight,
                  label: 'Sensors',
                  sublabel: 'Device data',
                  onTap: onSensors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpertShortcut extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _ExpertShortcut({
    required this.icon,
    required this.color,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.tidePool,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.shimmer, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTheme.geist(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.moonbeam,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: AppTheme.geist(fontSize: 10, color: AppTheme.fog),
            ),
          ],
        ),
      ),
    );
  }
}
