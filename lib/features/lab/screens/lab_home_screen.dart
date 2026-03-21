import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/capture_entry.dart';
import '../../../core/services/ble_source_provider.dart';
import '../../../core/services/demo_mode_service.dart';
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

  // Comparison mode
  bool _compareMode = false;
  final Set<String> _selectedIds = {};

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
    context.push('/sources').then((_) => _loadSessions());
  }

  Future<bool> _confirmDeleteSession(CaptureEntry entry) async {
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
    return confirmed == true;
  }

  Future<void> _deleteSession(CaptureEntry entry) async {
    await ref.read(localDbServiceProvider).deleteCapture(entry.id);
    _loadSessions();
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
                  _StatusDot(
                    connected: _isConnected,
                    isDemoMode: ref.watch(demoModeProvider),
                    isRecording: ref.watch(isRecordingSignalProvider),
                  ),
                  const Spacer(),
                  // Demo toggle
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(demoModeProvider.notifier).toggle();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: ref.watch(demoModeProvider)
                            ? AppTheme.aurora.withValues(alpha: 0.12)
                            : AppTheme.tidePool,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusFull,
                        ),
                        border: Border.all(
                          color: ref.watch(demoModeProvider)
                              ? AppTheme.aurora.withValues(alpha: 0.4)
                              : AppTheme.shimmer,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'DEMO',
                            style: AppTheme.geistMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: ref.watch(demoModeProvider)
                                  ? AppTheme.aurora
                                  : AppTheme.mist,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            width: 26,
                            height: 14,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              color: ref.watch(demoModeProvider)
                                  ? AppTheme.aurora.withValues(alpha: 0.4)
                                  : AppTheme.mist.withValues(alpha: 0.2),
                            ),
                            alignment: ref.watch(demoModeProvider)
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ref.watch(demoModeProvider)
                                    ? AppTheme.aurora
                                    : AppTheme.mist,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const NavMenuButton(),
                ],
              ),

              const SizedBox(height: 24),

              // ── Start session button ──────────────────────────────────
              _StartSessionButton(
                isConnected: _isConnected,
                isDemoMode: ref.watch(demoModeProvider),
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
                  if (_sessions != null && _sessions!.length >= 2)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _compareMode = !_compareMode;
                          _selectedIds.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _compareMode
                              ? AppTheme.glow.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSm,
                          ),
                          border: Border.all(
                            color: _compareMode
                                ? AppTheme.glow.withValues(alpha: 0.4)
                                : AppTheme.shimmer,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.compare_arrows_rounded,
                              size: 14,
                              color: _compareMode
                                  ? AppTheme.glow
                                  : AppTheme.mist,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _compareMode ? 'Cancel' : 'Compare',
                              style: AppTheme.geist(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _compareMode
                                    ? AppTheme.glow
                                    : AppTheme.mist,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_sessions != null && !_compareMode)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '${_sessions!.length}',
                        style: AppTheme.geist(
                          fontSize: 13,
                          color: AppTheme.mist,
                        ),
                      ),
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
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                if (!ref.read(demoModeProvider)) {
                  ref.read(demoModeProvider.notifier).toggle();
                }
                _startSession();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.aurora.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(
                    color: AppTheme.aurora.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_circle_outline_rounded,
                      size: 18,
                      color: AppTheme.aurora,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Start Demo',
                      style: AppTheme.geist(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.aurora,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.glow,
      backgroundColor: AppTheme.tidePool,
      onRefresh: _loadSessions,
      child: Column(
        children: [
          // Compare action bar
          if (_compareMode && _selectedIds.length == 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final selected = sessions
                        .where((e) => _selectedIds.contains(e.id))
                        .toList();
                    if (selected.length == 2) {
                      context.push('/lab/compare', extra: selected).then((_) {
                        setState(() {
                          _compareMode = false;
                          _selectedIds.clear();
                        });
                      });
                    }
                  },
                  icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                  label: Text(
                    'Compare selected',
                    style: AppTheme.geist(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.glow.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.glow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    ),
                  ),
                ),
              ),
            ),
          if (_compareMode && _selectedIds.length < 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Select ${2 - _selectedIds.length} session${_selectedIds.isEmpty ? "s" : ""} to compare',
                style: AppTheme.geist(fontSize: 12, color: AppTheme.mist),
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = sessions[index];
                final isSelected = _selectedIds.contains(entry.id);

                if (_compareMode) {
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (isSelected) {
                          _selectedIds.remove(entry.id);
                        } else if (_selectedIds.length < 2) {
                          _selectedIds.add(entry.id);
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: isSelected
                            ? Border.all(
                                color: AppTheme.glow.withValues(alpha: 0.6),
                                width: 2,
                              )
                            : null,
                      ),
                      child: SessionCard(entry: entry),
                    ),
                  );
                }

                return Dismissible(
                  key: ValueKey(entry.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: AppTheme.crimson.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.crimson,
                      size: 22,
                    ),
                  ),
                  confirmDismiss: (_) => _confirmDeleteSession(entry),
                  onDismissed: (_) => _deleteSession(entry),
                  child: SessionCard(
                    entry: entry,
                    onTap: () => context
                        .push('/lab/session/${entry.id}', extra: entry)
                        .then((_) => _loadSessions()),
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

// ─────────────────────────────────────────────────────────────────────────────
// Status dot — green when streaming, gray otherwise
// ─────────────────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  final bool connected;
  final bool isDemoMode;
  final bool isRecording;
  const _StatusDot({
    required this.connected,
    this.isDemoMode = false,
    this.isRecording = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isRecording) {
      return _PulsingDot(color: AppTheme.crimson);
    }

    final Color color;
    if (isDemoMode && connected) {
      color = AppTheme.aurora;
    } else if (connected) {
      color = AppTheme.seaGreen;
    } else {
      color = AppTheme.shimmer;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Animated pulsing red dot for active recording.
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.5 + _ctrl.value * 0.5),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.3 * _ctrl.value),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Start session button
// ─────────────────────────────────────────────────────────────────────────────

class _StartSessionButton extends StatelessWidget {
  final bool isConnected;
  final bool isDemoMode;
  final VoidCallback onTap;

  const _StartSessionButton({
    required this.isConnected,
    this.isDemoMode = false,
    required this.onTap,
  });

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
              isDemoMode
                  ? 'Demo Session'
                  : isConnected
                  ? 'Continue Session'
                  : 'Start Session',
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
