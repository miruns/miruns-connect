import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_settings/screens/ai_settings_screen.dart';
import '../../features/capture/screens/capture_screen.dart';
import '../../features/eeg/screens/eeg_home_screen.dart';
import '../../features/eeg/screens/eeg_onboarding_screen.dart';
import '../../features/environment/screens/environment_screen.dart';
import '../../features/journal/screens/journal_screen.dart';
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

class AppRouter {
  static late final GoRouter router;

  /// Call once before [runApp] to set the initial route based on user prefs.
  static void init({bool skipOnboarding = false}) {
    router = GoRouter(
      initialLocation: skipOnboarding ? '/eeg-home' : '/eeg-onboarding',
      routes: [
        // ── EEG onboarding (first-run, no bottom nav) ───────────────────
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

        // ── Main shell with bottom navigation (3 tabs) ─────────────────
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            // Tab 0 — EEG Home
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/eeg-home',
                  name: 'eeg-home',
                  pageBuilder: (context, state) =>
                      const NoTransitionPage(child: EegHomeScreen()),
                ),
              ],
            ),
            // Tab 1 — Patterns
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
          path: '/sport',
          name: 'sport',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const SportHomeScreen(),
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
