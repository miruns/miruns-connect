import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_settings/screens/ai_settings_screen.dart';
import '../../features/capture/screens/capture_screen.dart';
import '../../features/eeg/screens/eeg_onboarding_screen.dart';
import '../../features/environment/screens/environment_screen.dart';
import '../../features/journal/screens/journal_screen.dart';
import '../../features/lab/screens/lab_home_screen.dart';
import '../../features/lab/screens/session_comparison_screen.dart';
import '../../features/lab/screens/session_detail_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/patterns/screens/patterns_screen.dart';
import '../../features/sensors/screens/sensors_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/shell/debug_screen.dart';
import '../../features/sources/screens/live_signal_screen.dart';
import '../../features/sources/screens/source_browser_screen.dart';
import '../../features/sport/models/sport_profile.dart';
import '../../features/sport/models/workout_session.dart';
import '../../features/sport/screens/active_workout_screen.dart';
import '../../features/sport/screens/sport_home_screen.dart';
import '../../features/sport/screens/sport_profile_screen.dart';
import '../../features/sport/screens/workout_feedback_screen.dart';
import '../../features/sport/screens/workout_history_screen.dart';
import '../../features/welcome/screens/welcome_screen.dart';
import '../models/capture_entry.dart';

class AppRouter {
  static late final GoRouter router;

  /// Call once before [runApp] to set the initial route based on user prefs.
  static void init({bool skipOnboarding = false}) {
    router = GoRouter(
      initialLocation: '/welcome',
      routes: [
        // ── Welcome / splash screen ──────────────────────────────────────
        GoRoute(
          path: '/welcome',
          name: 'welcome',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const WelcomeScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
          ),
        ),
        // ── EEG onboarding (kept for headset pairing flow) ──────────────
        GoRoute(
          path: '/eeg-onboarding',
          name: 'eeg-onboarding',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const EegOnboardingScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
          ),
        ),
        // ── Legacy onboarding (kept for backward-compat) ────────────────
        GoRoute(
          path: '/onboarding',
          name: 'onboarding',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const OnboardingScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
          ),
        ),

        // ── Main shell with bottom navigation ──────────────────────────
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            // Tab 0 — Sport (primary)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/sport',
                  name: 'sport-home',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: SportHomeScreen()),
                ),
              ],
            ),
            // Tab 1 — Lab (session library)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/lab',
                  name: 'lab-home',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: LabHomeScreen()),
                ),
              ],
            ),
            // Tab 2 — Patterns
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/patterns',
                  name: 'patterns',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: PatternsScreen()),
                ),
              ],
            ),
            // Tab 2 — Capture
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/capture',
                  name: 'capture',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: CaptureScreen()),
                ),
              ],
            ),
          ],
        ),

        // ── Standalone routes (no bottom nav) ───────────────────────────
        GoRoute(
          path: '/journal',
          name: 'journal',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const JournalScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
          ),
        ),
        GoRoute(
          path: '/environment',
          name: 'environment',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const EnvironmentScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
          ),
        ),
        GoRoute(
          path: '/sensors',
          name: 'sensors',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const SensorsScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
          ),
        ),
        GoRoute(
          path: '/ai-settings',
          name: 'ai-settings',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const AiSettingsScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
          ),
        ),
        GoRoute(
          path: '/debug',
          name: 'debug',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const DebugScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
          ),
        ),

        // ── Sport / Workout ─────────────────────────────────────────────
        GoRoute(
          path: '/sport/active',
          name: 'sport-active',
          pageBuilder: (context, state) {
            final workoutType =
                state.extra as WorkoutType? ?? WorkoutType.running;
            return CustomTransitionPage(
              key: state.pageKey,
              child: ActiveWorkoutScreen(workoutType: workoutType),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) =>
                      FadeTransition(opacity: animation, child: child),
            );
          },
        ),
        GoRoute(
          path: '/sport/feedback',
          name: 'sport-feedback',
          pageBuilder: (context, state) {
            final session = state.extra as WorkoutSession;
            return CustomTransitionPage(
              key: state.pageKey,
              child: WorkoutFeedbackScreen(session: session),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) =>
                      SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, 1),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      ),
            );
          },
        ),
        GoRoute(
          path: '/sport/history',
          name: 'sport-history',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const WorkoutHistoryScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
          ),
        ),
        GoRoute(
          path: '/sport/profile',
          name: 'sport-profile',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const SportProfileScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
          ),
        ),

        // ── Lab session detail ────────────────────────────────────────
        GoRoute(
          path: '/lab/session/:id',
          name: 'session-detail',
          pageBuilder: (context, state) {
            final entry = state.extra as CaptureEntry;
            return CustomTransitionPage(
              key: state.pageKey,
              child: SessionDetailScreen(entry: entry),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) =>
                      SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(1, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      ),
            );
          },
        ),

        // ── Session comparison (expects List<CaptureEntry> via extra) ──
        GoRoute(
          path: '/lab/compare',
          name: 'session-compare',
          pageBuilder: (context, state) {
            final entries = state.extra as List<CaptureEntry>;
            return CustomTransitionPage(
              key: state.pageKey,
              child: SessionComparisonScreen(
                entryA: entries[0],
                entryB: entries[1],
              ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) =>
                      SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(1, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      ),
            );
          },
        ),

        // ── Signal sources ──────────────────────────────────────────────
        GoRoute(
          path: '/sources',
          name: 'sources',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const SourceBrowserScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(1, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
          ),
        ),
        GoRoute(
          path: '/sources/:sourceId',
          name: 'live-signal',
          pageBuilder: (context, state) {
            final sourceId = state.pathParameters['sourceId']!;
            return CustomTransitionPage(
              key: state.pageKey,
              child: LiveSignalScreen(sourceId: sourceId),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) =>
                      SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(1, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                        child: child,
                      ),
            );
          },
        ),
      ],
    );
  }
}
