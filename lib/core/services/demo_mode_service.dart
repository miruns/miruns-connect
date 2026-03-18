import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ble_heart_rate_service.dart';
import 'ble_source_provider.dart';
import 'local_db_service.dart';
import 'service_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Demo Mode Service — single source of truth for hardware simulation.
//
// Consolidates the scattered `eeg_demo_mode` flag into a reactive Riverpod
// notifier. When enabled, both BLE services emit synthetic data through
// their normal streams so the entire pipeline (workout, EEG metrics, sport
// home sensor cards, live signal screen) works identically to real hardware.
//
// Toggle from any screen via `ref.read(demoModeProvider.notifier).toggle()`.
// ─────────────────────────────────────────────────────────────────────────────

/// Persisted key in the settings table.
const _kDemoModeKey = 'eeg_demo_mode';

class DemoModeNotifier extends StateNotifier<bool> {
  DemoModeNotifier({
    required LocalDbService db,
    required BleSourceService bleSource,
    required BleHeartRateService bleHr,
  }) : _db = db,
       _bleSource = bleSource,
       _bleHr = bleHr,
       super(false) {
    _loadPersisted();
  }

  final LocalDbService _db;
  final BleSourceService _bleSource;
  final BleHeartRateService _bleHr;

  Future<void> _loadPersisted() async {
    final raw = await _db.getSetting(_kDemoModeKey);
    final enabled = raw == 'true';
    if (enabled) {
      _startServices();
    }
    state = enabled;
  }

  /// Toggle demo mode on/off.
  Future<void> toggle() async {
    final next = !state;
    state = next;
    await _db.setSetting(_kDemoModeKey, next.toString());
    if (next) {
      _startServices();
    } else {
      _stopServices();
    }
  }

  /// Enable demo mode programmatically (e.g. from onboarding).
  Future<void> enable() async {
    if (state) return;
    state = true;
    await _db.setSetting(_kDemoModeKey, 'true');
    _startServices();
  }

  /// Disable demo mode programmatically (e.g. when real hardware pairs).
  Future<void> disable() async {
    if (!state) return;
    state = false;
    await _db.setSetting(_kDemoModeKey, 'false');
    _stopServices();
  }

  void _startServices() {
    // Only start if not already streaming from real hardware.
    if (!_bleSource.isStreaming) {
      _bleSource.startDemo();
      debugPrint('[DemoMode] EEG synthetic stream started');
    }
    if (!_bleHr.isStreaming) {
      _bleHr.startDemo();
      debugPrint('[DemoMode] HR synthetic stream started');
    }
  }

  void _stopServices() {
    if (_bleSource.isDemoMode) _bleSource.stopDemo();
    if (_bleHr.isDemoMode) _bleHr.stopDemo();
    debugPrint('[DemoMode] all synthetic streams stopped');
  }
}

/// Global reactive demo-mode state. `true` when demo mode is active.
///
/// Usage:
/// ```dart
/// // Read current state
/// final isDemo = ref.watch(demoModeProvider);
///
/// // Toggle
/// ref.read(demoModeProvider.notifier).toggle();
/// ```
final demoModeProvider = StateNotifierProvider<DemoModeNotifier, bool>((ref) {
  return DemoModeNotifier(
    db: ref.read(localDbServiceProvider),
    bleSource: ref.read(bleSourceServiceProvider),
    bleHr: ref.read(bleHeartRateServiceProvider),
  );
});
