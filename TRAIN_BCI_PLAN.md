# TRAIN — Blink-Controlled BCI Feature

> Control the Miruns app hands-free using intentional eye blinks.

---

## 1. Why This Works

Eye blinks produce a **massive, unmistakable signal** on frontal EEG channels (Fp1, Fp2). A voluntary blink generates a **50–200 µV peak** lasting ~200–400 ms — that's 5–10× larger than background EEG.

### Hardware fit

| Property           | Value                                  | Why it matters                                           |
| ------------------ | -------------------------------------- | -------------------------------------------------------- |
| Channels           | Fp1 + Fp2 (both 4-ch and 8-ch boards)  | #1 electrodes for EOG/blink detection in every BCI paper |
| Sample rate        | 250 Hz                                 | More than enough — blinks are <5 Hz events               |
| Existing detection | 35 µV threshold in `BciMonitoringView` | Already flags blinks in real-time                        |
| ADC resolution     | 24-bit ADS1299                         | Sub-µV precision, clean blink waveforms                  |

### Scientific basis

Classical EOG-based blink detection is well-established (Chambayil et al. 2010, Bulling et al. 2011). No ML needed for v1 — threshold + timing state machine achieves >95% accuracy when calibrated per-user.

---

## 2. Command Vocabulary

### Phase 1 (core)

| Command          | Gesture          | Detection Method                            |
| ---------------- | ---------------- | ------------------------------------------- |
| **Single Blink** | 1 firm blink     | 1 peak >50 µV, no second peak within 600 ms |
| **Double Blink** | 2 quick blinks   | 2 peaks >50 µV within 300–700 ms            |
| **Long Blink**   | Eyes closed ~1 s | Sustained deflection >50 µV for 600–1200 ms |

### Phase 2 (advanced)

| Command          | Gesture        | Detection Method                            |
| ---------------- | -------------- | ------------------------------------------- |
| **Triple Blink** | 3 quick blinks | 3 peaks within 1200 ms (safety/emergency)   |
| **Wink Left**    | Left eye only  | Fp1 peak >> Fp2 peak (asymmetry ratio >3:1) |
| **Wink Right**   | Right eye only | Fp2 peak >> Fp1 peak (asymmetry ratio >3:1) |

---

## 3. Architecture

### 3.1 Blink Detector Engine

**File:** `lib/features/train/services/blink_detector_service.dart`

Pure Dart signal processing pipeline:

```
Raw Fp1/Fp2 stream
    │
    ▼
┌──────────────────┐
│  Bandpass Filter  │  0.5–10 Hz IIR (remove high-freq EEG, keep blink waveform)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│    Rectify        │  Absolute value of filtered signal
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Adaptive Threshold│  mean + 3× std of last 5 seconds (handles electrode drift)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Peak Detection   │  Rising edge → onset; falling edge → offset
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  State Machine    │  Classify: single / double / long / triple
└────────┬─────────┘
         │
         ▼
Stream<BlinkEvent>  →  {type, timestamp, confidence, rawPeakAmplitude}
```

#### State Machine Logic

```
IDLE
  │
  ├── peak detected → PEAK_1, start 600ms timer
  │
PEAK_1
  │
  ├── duration > 600ms (still high) → emit LONG_BLINK → COOLDOWN
  ├── 2nd peak within 300–700ms → PEAK_2, restart timer
  ├── 600ms elapsed, no 2nd peak → emit SINGLE_BLINK → COOLDOWN
  │
PEAK_2
  │
  ├── 3rd peak within 500ms → emit TRIPLE_BLINK → COOLDOWN
  ├── 500ms elapsed, no 3rd peak → emit DOUBLE_BLINK → COOLDOWN
  │
COOLDOWN (1 second refractory period)
  │
  └── 1s elapsed → IDLE
```

#### Default Thresholds (overridden by calibration)

| Parameter                      | Default | Unit  |
| ------------------------------ | ------- | ----- |
| Blink peak amplitude           | 50      | µV    |
| Single blink max duration      | 400     | ms    |
| Long blink min duration        | 600     | ms    |
| Double blink inter-peak window | 300–700 | ms    |
| Wink asymmetry ratio           | 3.0     | ratio |
| Post-command cooldown          | 1000    | ms    |
| Confidence gate                | 80      | %     |
| Adaptive window                | 5       | s     |

---

### 3.2 Training / Calibration Flow

**Screens:** `lib/features/train/screens/calibration_screen.dart`

A 3-minute guided wizard that calibrates the detector to the user's unique blink signature.

#### Protocol

| Step                | Duration   | Instructions                               | Data collected                          |
| ------------------- | ---------- | ------------------------------------------ | --------------------------------------- |
| 1. Baseline         | 10 s       | "Sit still, eyes open, relax"              | Resting Fp1/Fp2 amplitude → noise floor |
| 2. Single Blink ×10 | ~30 s      | Visual cue "BLINK" every 3 s               | 10 labeled single blink events          |
| 3. Rest             | 5 s        | "Relax, look at screen"                    | False-positive baseline                 |
| 4. Double Blink ×10 | ~40 s      | Audio beep pattern + visual "DOUBLE BLINK" | 10 labeled double blink events          |
| 5. Rest             | 5 s        | "Relax"                                    | False-positive baseline                 |
| 6. Long Blink ×10   | ~40 s      | "CLOSE EYES" for 1s, then "OPEN"           | 10 labeled long blink events            |
| 7. Rest             | 5 s        | Natural behavior                           | False-positive baseline                 |
| **Total**           | **~3 min** |                                            |                                         |

#### Calibration Output

From collected data, compute:

- Per-user amplitude threshold (mean peak − 2σ)
- Per-user timing windows (mean duration ± 1σ)
- Per-command accuracy (detected / cued)
- False positive rate (detections during rest periods)

---

### 3.3 Blink Profile (Data Model)

**File:** `lib/features/train/models/blink_profile.dart`

```dart
class BlinkProfile {
  final String id;
  final DateTime createdAt;
  final String? deviceId;

  // Adaptive thresholds (µV)
  final double fp1Threshold;
  final double fp2Threshold;

  // Timing windows (ms)
  final double singleBlinkMaxDuration;    // ~400
  final double longBlinkMinDuration;      // ~600
  final double doubleBlinkWindow;         // ~700

  // Asymmetry for winks
  final double winkAsymmetryRatio;        // ~3.0

  // Quality metrics from calibration
  final double singleBlinkAccuracy;       // 0.0–1.0
  final double doubleBlinkAccuracy;
  final double longBlinkAccuracy;
  final double falsePositiveRate;
}
```

Stored in `LocalDbService` as a JSON column (same pattern as `CaptureEntry` tags).

---

### 3.4 Command Executor

**File:** `lib/features/train/services/blink_command_service.dart`

Maps detected blink events to app actions.

#### Default Command Map

| Blink Command | Default Action               | Integration Point       |
| ------------- | ---------------------------- | ----------------------- |
| Single Blink  | Mark lap / Acknowledge alert | `ActiveWorkoutNotifier` |
| Double Blink  | Start/Pause workout          | `ActiveWorkoutNotifier` |
| Long Blink    | Voice status readout         | `TtsService`            |
| Triple Blink  | Emergency stop / SOS         | `ActiveWorkoutNotifier` |
| Wink Left     | Navigate back                | `GoRouter`              |
| Wink Right    | Navigate forward             | `GoRouter`              |

#### Safety features

- **Cooldown**: 1-second refractory period after each command
- **Confidence gate**: Only act if detection confidence >80%
- **Audio feedback**: Short haptic + optional beep on command detection
- **Visual feedback**: Transient overlay showing detected command icon
- **Emergency override**: Triple blink always works (no confidence gate)

---

## 4. File Structure

```
lib/features/train/
├── screens/
│   ├── train_home_screen.dart          # Dashboard: status, commands, start training
│   ├── calibration_screen.dart         # Guided 3-min calibration wizard
│   ├── calibration_result_screen.dart  # Results, accuracy, save profile
│   ├── command_map_screen.dart         # Assign blink commands to app actions
│   └── live_test_screen.dart           # Free-run testing & validation
├── widgets/
│   ├── blink_waveform_monitor.dart     # Real-time Fp1/Fp2 mini chart
│   ├── command_feedback_overlay.dart   # Transient "command detected" overlay
│   ├── calibration_cue_widget.dart     # Visual/audio cue for "BLINK NOW"
│   └── blink_command_tile.dart         # Command config tile
├── models/
│   └── blink_profile.dart             # BlinkProfile data model
└── services/
    ├── blink_detector_service.dart     # Core detection engine (signal processing)
    └── blink_command_service.dart      # Command mapping & dispatch
```

---

## 5. Navigation Integration

### Option A: New tab in bottom nav

Add "Train" as a 5th tab (replacing More button position, More moves to nav sheet only):

```
Sport | Lab | Patterns | Capture | Train
```

### Option B: Entry in More overflow sheet

Lower commitment — add Train alongside Journal, Sensors, etc.:

```
More → Train (brain icon)
```

### Routes

```
/train              → TrainHomeScreen
/train/calibrate    → CalibrationScreen
/train/results      → CalibrationResultScreen
/train/commands     → CommandMapScreen
/train/test         → LiveTestScreen
```

---

## 6. Implementation Roadmap

### Step 1 — Blink Detector Engine ⚙️

Build `BlinkDetectorService` with:

- IIR bandpass filter (0.5–10 Hz)
- Adaptive threshold (rolling 5-second window)
- Peak detection (onset/offset)
- State machine (single / double / long classification)
- `Stream<BlinkEvent>` output

**Test:** Connect headset, run detector, print events to debug console.
**Human task:** Wear headset, perform 20 blinks, validate detection rate.

### Step 2 — Calibration Screen 🎯

Build guided wizard with:

- Live Fp1/Fp2 waveform display (reuse `LiveSignalChart` for 2 channels)
- Countdown timer + visual/audio cues
- Blink event collection with labels
- Progress indicator (step N of 7)

**Human task:** Run calibration 3× to validate consistency.

### Step 3 — Blink Profile + Persistence 💾

- `BlinkProfile` data model
- Threshold computation from calibration data
- Save/load from `LocalDbService`
- Profile selection (multiple profiles for different electrode placements)

### Step 4 — Train Home Screen + Routing 🏠

- Dashboard showing calibration status
- Connection status indicator
- Command list with assigned actions
- "Start Training" hero button
- Wire up `AppRouter` + nav entry

### Step 5 — Live Test Screen 🧪

- Free-run mode with real-time command detection
- Confidence bar per command
- Detection history log
- Accuracy counter (correct / false positive / missed)

**Human task:** 5-minute free-form testing session, report accuracy.

### Step 6 — Command Service + Action Dispatch 🎮

- `BlinkCommandService` Riverpod provider
- Command → action mapping with cooldown
- Haptic + audio feedback
- Integration with `ActiveWorkoutNotifier`
- Integration with `TtsService`

### Step 7 — Command Map Screen ⚙️

- User-configurable command → action assignments
- Enable/disable individual commands
- Sensitivity slider per command
- Reset to defaults

### Step 8 — Workout Integration 🏃

- Blink commands active during workout
- Double blink → pause/resume
- Single blink → mark lap
- Long blink → TTS readout of pace/HR/distance/time
- Visual confirmation overlay

### Step 9 — Background Mode + Polish 🔋

- Always-on blink detection as background service
- Floating status indicator (like workout banner)
- Battery optimization (process only Fp1+Fp2)
- Conflict resolution with Lab recording annotations

---

## 7. What We Need From The Human Colleague

| When              | Task                                                                                                                 | Why                                         |
| ----------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| **Before Step 1** | Record a 60s Lab session with ~10 single blinks, ~5 double blinks, ~5 long blinks. Label them with artifact markers. | Calibrate default thresholds from real data |
| **After Step 1**  | Wear headset, run detector, perform 20 blinks. Report: false positives? missed? timing?                              | Validate core detection engine              |
| **After Step 2**  | Run calibration wizard 3×. Report: consistent? confusing UX?                                                         | Validate calibration flow                   |
| **After Step 5**  | 5-minute free testing session. Report accuracy numbers.                                                              | Validate end-to-end pipeline                |
| **After Step 6**  | Test during a real workout. Report: useful? annoying? dangerous?                                                     | Validate practical value                    |

---

## 8. Future Extensions

- **SSVEP (Steady-State Visual Evoked Potentials)**: Flash a button at 12 Hz on screen, detect 12 Hz peak in O1/O2. Enables "look at button to select" without any physical movement.
- **Motor imagery**: C3/C4 alpha desynchronization for left/right hand imagination. Requires ML but the 8-ch board has these channels.
- **Jaw clench**: Already detected in `BciMonitoringView` (50–80 µV on temporal channels). Could be a 4th command type.
- **Attention-adaptive UI**: Use alpha/beta ratio to detect focus level, auto-simplify UI when user is fatigued.
- **Shared profiles**: Export/import calibration profiles between users/devices.

---

## References

- Chambayil, B., Singla, R., & Jha, R. (2010). EEG eye blink classification using neural network. _Proceedings of the World Congress on Engineering._
- Bulling, A., Ward, J. A., Gellersen, H., & Tröster, G. (2011). Eye movement analysis for activity recognition using electrooculography. _IEEE TPAMI._
- Usakli, A. B., & Gurkan, S. (2010). Design of a novel efficient human–computer interface: An electrooculagram based virtual keyboard. _IEEE TIM._
