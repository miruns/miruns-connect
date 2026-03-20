# Lab Feature — TODO

> Session library, signal replay, and BCI analysis pipeline.
> Items ordered by priority within each category.

---

## Done (v1.0.24)

- [x] **Lab tab replaces EEG tab** — Tab 1 (`/lab`) with `science` icon, removes old EEG Home
- [x] **LabHomeScreen** — Title bar with status dot, demo toggle, nav menu. "Start Session" button routes to live signal screen. "Recordings" list loaded from DB via `loadSignalSessions()`
- [x] **SessionCard widget** — Source name, duration badge, mini sparkline (ch 1, ~100 pts), date, channel/rate metadata
- [x] **SessionDetailScreen** — Stats row (duration, channels, rate, device), multi-channel replay chart with CustomPainter, scrubber slider (0–1), window selector (2s/4s/10s), band power bars (delta/theta/alpha/beta/gamma)
- [x] **Router wiring** — `/lab` tab branch, `/lab/session/:id` standalone route with slide transition, CaptureEntry via `state.extra`
- [x] **DB queries** — `loadSignalSessions()` and `countSignalSessions()` in LocalDbService
- [x] **Demo mode integration** — Purple status dot, DEMO ON/OFF toggle pill, "Demo Session" button label, demo stream persists across back navigation
- [x] **Recording in demo mode** — Record button now visible in both demo and real hardware modes
- [x] **Back button fix** — No longer kills demo stream on pop; Lab manages demo lifecycle via demoModeProvider
- [x] **All `/eeg-home` references updated** — Onboarding, permissions, capture screens all route to `/lab`
- [x] **BLE scan skip when streaming** — LiveSignalScreen skips auto-scan if already in streaming state (demo or reconnect)
- [x] **Save recording to DB** — `_stopRecording()` constructs `SignalSession`, wraps in `CaptureEntry`, calls `db.saveCapture()`. Snackbar confirmation with sample count and duration.
- [x] **Refresh session list on return** — `_startSession()` uses `context.push().then(() => _loadSessions())` to auto-reload when popping back from live signal screen.
- [x] **Session deletion** — Swipe-to-delete on SessionCard with confirmation dialog. Delete button in session detail screen. Calls `db.deleteCapture(id)`.
- [x] **Session export** — Share button in session detail top bar opens `ResearchExportSheet` (CSV / EDF+ / JSON format picker, stream toggles, native share sheet).

---

## High Priority — This Release

- [ ] **Recording indicator on Lab** — Show a red dot or pulse when actively recording in the live signal screen, visible even on the Lab tab.
- [ ] **Real FFT for band power** — SessionDetailScreen uses a variance-based proxy for band power. Integrate the real `CooleyTukeyFFT` from `spectral_engine.dart` for accurate frequency decomposition.
- [ ] **Channel selector in session detail** — Band power bars are hardcoded to channel 0. Add a chip row to select which channel's spectral data to display.
- [ ] **Empty state CTA** — "No recordings yet" empty state should have a direct "Start Demo" button for first-time users.

---

## Medium Priority — Next Release

- [ ] **Session rename / notes** — Let user add a title and notes to a session (stored in CaptureEntry `userNote` field).
- [ ] **Recording duration counter** — Show elapsed time in the app bar while recording (mm:ss).
- [ ] **Auto-save on disconnect** — If recording is active and BLE disconnects unexpectedly, auto-save whatever samples were collected.
- [ ] **Source browser entry** — "Start Session" currently hardcodes `/sources/ads1299`. Should route to `/sources` (source browser) to support multiple source types.
- [ ] **Session comparison** — Select 2 sessions, overlay their spectral profiles side by side.
- [ ] **Waveform zoom/pan** — Pinch-to-zoom on the replay chart time axis. Pan within the zoomed window.
- [ ] **Artifact marking** — Tap on the waveform to mark artifacts (blinks, jaw clench, movement) with timestamps.

---

## Future — miruns-lab (Next App / Phase 2+)

- [ ] **Protocol engine** — Define multi-step timed protocols (e.g. "Eyes open 2 min → Eyes closed 2 min → Task 3 min"). Protocol runs, auto-segments recording, tags each segment.
- [ ] **Protocol library** — Pre-built protocols: Alpha training, P300 oddball, SSVEP, relaxation baseline, meditation, focus task.
- [ ] **Sharable session links** — Upload session to miruns-lab (Next.js), generate a public URL with embedded replay viewer.
- [ ] **Topographic maps** — 2D head map with electrode positions, color-coded by band power or amplitude. Requires standard electrode montage.
- [ ] **Event markers** — Hardware or software triggers that mark specific moments in the recording (e.g. stimulus onset, button press).
- [ ] **Real-time neurofeedback** — Audio/visual feedback based on live band power targets (e.g. "increase alpha at O1"). Requires threshold engine + feedback UI.
- [ ] **Multi-session analysis** — Aggregate metrics across sessions: trend lines for band power ratios, session-over-session changes, sleep/wake patterns.
- [ ] **Community protocols** — Share protocols with other users. Import from a protocol marketplace.
- [ ] **Developer API** — Expose recorded sessions via a REST/GraphQL API from miruns-lab for third-party analysis tools.
- [ ] **EDF/BDF export** — Export to standard EEG file formats (European Data Format) for compatibility with MNE-Python, EEGLAB, BrainVision.
- [ ] **Impedance check** — Pre-recording electrode impedance measurement (requires ADS1299 lead-off detection config).
- [ ] **Session tagging + search** — Tags (e.g. "meditation", "focus", "sleep"), full-text search across session notes.

---

## Dead Code Cleanup

- [ ] **Remove EegHomeScreen** — `lib/features/eeg/screens/eeg_home_screen.dart` is no longer routed. Only `EegOnboardingScreen` is still used (from `/eeg-onboarding`). Can delete the file.
- [ ] **Remove MSignalLogo import** — Was only used by EegHomeScreen. Check if used elsewhere before removing.
