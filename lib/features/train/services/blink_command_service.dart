import 'dart:async';

import 'package:flutter/services.dart';

import '../models/blink_profile.dart';
import 'blink_detector_service.dart';

/// Action types that blink commands can trigger.
enum BlinkAction {
  markLap('Mark Lap', 'Record a split / lap marker'),
  toggleWorkout('Start / Pause', 'Toggle active workout'),
  voiceStatus('Voice Readout', 'Announce pace, HR, distance'),
  emergencyStop('Emergency Stop', 'Immediately end workout'),
  navigateBack('Navigate Back', 'Go to previous screen'),
  navigateForward('Navigate Forward', 'Go to next screen'),
  none('Disabled', 'No action assigned');

  const BlinkAction(this.label, this.description);
  final String label;
  final String description;
}

/// Maps blink events to app actions with safety features.
class BlinkCommandService {
  BlinkCommandService({required BlinkDetectorService detector})
      : _detector = detector;

  final BlinkDetectorService _detector;
  StreamSubscription<BlinkEvent>? _sub;

  // ── Command mapping ───────────────────────────────────────────────────────

  final Map<BlinkType, BlinkAction> _commandMap = {
    BlinkType.single: BlinkAction.markLap,
    BlinkType.double: BlinkAction.toggleWorkout,
    BlinkType.long: BlinkAction.voiceStatus,
    BlinkType.triple: BlinkAction.emergencyStop,
  };

  Map<BlinkType, BlinkAction> get commandMap => Map.unmodifiable(_commandMap);

  void setAction(BlinkType type, BlinkAction action) {
    _commandMap[type] = action;
  }

  // ── Configuration ─────────────────────────────────────────────────────────

  double confidenceGate = 0.8;
  bool hapticFeedback = true;
  bool audioFeedback = true;
  bool _enabled = false;

  bool get enabled => _enabled;

  // ── Callbacks ─────────────────────────────────────────────────────────────

  /// Called when a command is dispatched. The UI / workout notifier hooks here.
  void Function(BlinkAction action, BlinkEvent event)? onCommand;

  /// Called for every detected blink (even below confidence gate). For UI only.
  void Function(BlinkEvent event)? onBlinkDetected;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void start() {
    if (_enabled) return;
    _enabled = true;
    _sub = _detector.blinkStream.listen(_onBlink);
  }

  void stop() {
    _enabled = false;
    _sub?.cancel();
    _sub = null;
  }

  void _onBlink(BlinkEvent event) {
    onBlinkDetected?.call(event);

    // Emergency override: triple blink always works
    final isEmergency = event.type == BlinkType.triple;

    if (!isEmergency && event.confidence < confidenceGate) return;

    final action = _commandMap[event.type];
    if (action == null || action == BlinkAction.none) return;

    // Haptic feedback
    if (hapticFeedback) {
      HapticFeedback.mediumImpact();
    }

    onCommand?.call(action, event);
  }

  void dispose() {
    stop();
  }
}
