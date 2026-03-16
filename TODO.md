# Sport Feature — TODO

> Remaining work to complete the sport/workout module.
> Items are ordered by priority within each category.

---

## Critical Bugs

- [ ] **HRV calculation broken** — `active_workout_screen.dart` computes mean RR instead of RMSSD (root mean square of successive differences). The `_computeHrv()` method needs the standard RMSSD formula.
- [x] **GPS samples never recorded** — Fixed: `_startGpsTracking()` now appends `WorkoutGpsSample` to the session on each position update (throttled by the 5 m distanceFilter). `GpsMetrics` carries `lat`/`lon` for this purpose.
- [ ] **EEG data never populated** — `_latestEeg` is declared but never receives data from any BLE source. Brain state UI is always hidden, and post-workout EEG analysis is always null. Need to subscribe to the BLE source stream and map channel data to `WorkoutEegSample`.

## High Priority

- [ ] **Pause doesn't pause data collection** — When workout is paused, HR and GPS streams keep running and AI insight generation continues. Should suspend all streams on pause and resume on unpause.
- [ ] **AI analysis has no timeout** — `analyzeWorkout()` and `generateRealtimeInsight()` can hang indefinitely if the AI service is slow or unresponsive. Add timeouts (e.g. 30s for real-time, 60s for post-workout).
- [ ] **Profile loading race condition** — `_initialize()` in `active_workout_screen.dart` loads the profile async, but timers and voice coach start immediately with the default profile. Should await profile load before starting workout services.
- [ ] **Zone time calculation off-by-one** — The first HR sample interval is never recorded in zone time tracking, losing approximately the first second of zone data.
- [ ] **Feedback screen WorkoutService instantiation** — `workout_feedback_screen.dart` still creates `WorkoutService` directly in some paths instead of using `ref.read(workoutServiceProvider)`. Verify all service access goes through providers.
- [ ] **WorkoutSession.decode() error handling** — If stored JSON is corrupted, the entire workout list fails to load. Need per-workout error isolation so one bad entry doesn't break history.
- [ ] **No data validation on profile save** — Age, weight, height, and HR fields accept any numeric input. Add sensible bounds (e.g. age 5–120, HR 30–220).

## Missing Features

- [ ] **Workout detail screen** — Tapping a workout card in history should open a detail view with full session review: HR chart, GPS map, EEG timeline, all insights, complete analysis.
- [ ] **Workout-to-capture linking** — Associate workout sessions with EEG capture sessions via `captureId` field. Allow starting a capture alongside a workout.
- [ ] **Edit/delete workouts** — History screen has no edit or delete capabilities. Need swipe-to-delete or long-press menu.
- [ ] **Workout export** — Share workout summaries as text or image (similar to journal entry sharing via `share_plus`).
- [ ] **Profile onboarding flow** — First-time sport users should be guided through profile setup before their first workout rather than starting with defaults.
- [ ] **Calorie estimation improvements** — Currently uses a basic formula. Should factor in workout type MET values, user weight, HR-based estimation, and activity intensity.
- [ ] **Workout type customization** — The "Custom" workout type has no way to set a name or icon. Let users define custom activity types.
- [ ] **Rest day / recovery tracking** — Track rest days and correlate with subsequent workout performance.
- [ ] **Weekly/monthly stats aggregation** — Summary view showing total distance, time, workouts per week, average performance score trends.
- [ ] **Goal setting** — User sets weekly targets (e.g. 3 runs, 20 km total) with progress tracking.

## EEG Integration

- [ ] **Wire BLE EEG source to workout** — Subscribe to the active `BleSourceService` stream during workouts. Map raw EEG channel data through the FFT engine to extract attention, relaxation, cognitive load, and mental fatigue metrics.
- [ ] **EEG-based voice alerts** — Voice coach should announce brain state changes (e.g. "Mental fatigue rising, consider slowing pace" or "Great focus, keep this intensity").
- [ ] **EEG correlation in analysis** — Post-workout AI analysis should correlate EEG patterns with HR zones and performance metrics for deeper insights.
- [ ] **EEG calibration per user** — Baseline EEG readings vary between users. Need a short calibration routine at first use to normalize metrics.

## Voice Coach

- [ ] **Language selection** — TTS language is hardcoded. Should respect device locale or offer language picker.
- [ ] **Volume control** — No way to adjust voice coach volume independently from media volume.
- [ ] **Custom prompts** — Let advanced users configure which metrics are announced and at what intervals.
- [ ] **Mute during calls** — Voice coach should detect active phone calls and mute automatically.

## Testing

- [ ] **Unit tests for WorkoutService** — CRUD operations, index management, profile load/save, edge cases (empty DB, corrupted data).
- [ ] **Unit tests for WorkoutAnalyticsService** — AI prompt construction, JSON response parsing, fallback on API failure.
- [ ] **Unit tests for VoiceCoachService** — Queue management, cooldown behavior, level-based timing, enable/disable.
- [ ] **Unit tests for sport models** — `SportProfile` serialization round-trip, HR zone calculation, `WorkoutSession` copyWith/decode.
- [ ] **Widget tests for sport screens** — SportHomeScreen, ActiveWorkoutScreen, WorkoutFeedbackScreen rendering and interaction.
- [ ] **Integration test** — Full workout cycle: start → record data → finish → submit feedback → verify analysis appears in history.

## Polish / UX

- [ ] **Animations on workout start** — Transition from home to active screen could use a more dramatic countdown (3-2-1-GO).
- [ ] **Haptic feedback on phase transitions** — Currently only on button taps. Add distinct haptic patterns for warmup→active→cooldown transitions.
- [ ] **Empty state illustrations** — History and prediction empty states use plain text. Add themed illustrations.
- [ ] **Accessibility** — Ensure all sport screens have proper semantics labels for screen readers. Large-text support for elderly users.
- [ ] **Landscape support** — Active workout screen should work in landscape for bike mounts.
- [ ] **Dark background during night workouts** — OLED-friendly pure black mode for outdoor night runs.
- [ ] **Post-workout celebration** — After finishing a personal best or completing a streak, show a brief confetti or glow animation.

## Performance

- [ ] **Debounce GPS updates** — GPS stream fires rapidly. Consider throttling to 1 Hz to reduce battery drain and UI rebuilds.
- [ ] **Limit insight history in memory** — `_recentInsights` list grows unbounded during long workouts. Cap at ~20 entries.
- [ ] **Dispose voice coach on screen exit** — Ensure TTS engine is properly released if the user force-closes the active workout screen.
- [ ] **Batch HR sample storage** — Currently builds a new list with spread operator every HR reading. For long workouts (1h+), use a growable buffer and batch-persist periodically.

## Documentation

- [ ] **SPORT_GUIDE.md** — User-facing guide explaining the workout flow, level system, and voice coach behavior (similar to existing CAPTURE_FEATURE_GUIDE.md).
- [ ] **EEG + Sport integration doc** — Technical doc explaining how EEG data flows from BLE source → FFT → metrics → workout insight → voice coach.
- [ ] **AI prompt documentation** — Document the system prompts used for real-time coaching, post-workout analysis, and pre-workout prediction.
