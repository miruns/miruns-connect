import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/capture_entry.dart';
import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/nav_menu_button.dart';
import '../widgets/session_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Lab Home — session library & quick-start surface
//
// Layout:
//   · Top bar    : "Lab" title, device status, nav menu
//   · Hero       : Start Session button (connects to source browser)
//   · Sessions   : scrollable list of past signal recordings
// ─────────────────────────────────────────────────────────────────────────────

class LabHomeScreen extends ConsumerStatefulWidget {
  const LabHomeScreen({super.key});

  @override
  ConsumerState<LabHomeScreen> createState() => _LabHomeScreenState();
}

class _LabHomeScreenState extends ConsumerState<LabHomeScreen> {
  List<CaptureEntry>? _sessions;
  bool _loading = true;

  // Live BLE state
  BleSourceState _bleState = BleSourceState.idle;
  StreamSubscription<BleSourceState>? _bleSub;

  @override
  void initState() {
    super.initState();
    _loadSessions();

    final bleService = ref.read(bleSourceServiceProvider);
    _bleState = bleService.state;
    _bleSub = bleService.stateStream.listen((s) {
      if (mounted) setState(() => _bleState = s);
    });
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final db = ref.read(localDbServiceProvider);
    final sessions = await db.loadSignalSessions();
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  bool get _isConnected => _bleState == BleSourceState.streaming;

  void _startSession() {
    HapticFeedback.mediumImpact();
    context.push('/sources/ads1299');
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
          padding: EdgeInsets.fromLTRB(20, top + 14, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top bar ───────────────────────────────────────────────
              Row(
                children: [
                  Text(
                    'Lab',
                    style: AppTheme.geist(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.moonbeam,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusDot(connected: _isConnected),
                  const Spacer(),
                  const NavMenuButton(),
                ],
              ),

              const SizedBox(height: 24),

              // ── Start session button ──────────────────────────────────
              _StartSessionButton(
                isConnected: _isConnected,
                onTap: _startSession,
              ),

              const SizedBox(height: 28),

              // ── Sessions header ───────────────────────────────────────
              Row(
                children: [
                  Text(
                    'Recordings',
                    style: AppTheme.geist(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.fog,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  if (_sessions != null)
                    Text(
                      '${_sessions!.length}',
                      style: AppTheme.geist(fontSize: 13, color: AppTheme.mist),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Session list ──────────────────────────────────────────
              Expanded(child: _buildSessionList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionList() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppTheme.glow,
          ),
        ),
      );
    }

    final sessions = _sessions;
    if (sessions == null || sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 40, color: AppTheme.shimmer),
            const SizedBox(height: 12),
            Text(
              'No recordings yet',
              style: AppTheme.geist(fontSize: 15, color: AppTheme.fog),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a session to record EEG signals',
              style: AppTheme.geist(fontSize: 13, color: AppTheme.mist),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.glow,
      backgroundColor: AppTheme.tidePool,
      onRefresh: _loadSessions,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entry = sessions[index];
          return SessionCard(
            entry: entry,
            onTap: () => context.push('/lab/session/${entry.id}', extra: entry),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status dot — green when streaming, gray otherwise
// ─────────────────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final bool connected;
  const _StatusDot({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected ? AppTheme.seaGreen : AppTheme.shimmer,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Start session button
// ─────────────────────────────────────────────────────────────────────────────

class _StartSessionButton extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onTap;

  const _StartSessionButton({required this.isConnected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.glow.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: AppTheme.glow.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sensors_rounded, size: 20, color: AppTheme.glow),
            const SizedBox(width: 10),
            Text(
              isConnected ? 'Continue Session' : 'Start Session',
              style: AppTheme.geist(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.moonbeam,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
