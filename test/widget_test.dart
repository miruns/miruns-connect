// Smoke test — verifies Miruns can build without errors.
//
// Platform plugins (Health, GPS, Calendar, sqflite, etc.) are not available in
// the test environment, so we override the DB-dependent theme provider and
// platform-dependent services, then assert that the widget tree inflates.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miruns_flutter/core/models/body_blog_entry.dart';
import 'package:miruns_flutter/core/router/app_router.dart';
import 'package:miruns_flutter/core/services/body_blog_service.dart';
import 'package:miruns_flutter/core/services/local_db_service.dart';
import 'package:miruns_flutter/core/services/service_providers.dart';
import 'package:miruns_flutter/core/theme/theme_provider.dart';
import 'package:miruns_flutter/main.dart';

/// A test-only notifier that returns the default theme without touching the DB.
class _TestThemeModeNotifier extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.system; // no DB call
}

/// Stub [LocalDbService] — avoids sqflite platform channel.
class _TestLocalDbService extends LocalDbService {
  @override
  Future<bool> hasAnyEntries() async => false;

  @override
  Future<BodyBlogEntry?> loadEntry(DateTime date) async => null;

  @override
  Future<String?> getSetting(String key) async => null;

  @override
  Future<void> setSetting(String key, String value) async {}
}

/// Stub [BodyBlogService] — avoids Health / GPS / Calendar platform channels
/// and their lingering `.timeout()` timers.
class _TestBodyBlogService extends BodyBlogService {
  @override
  Future<BodyBlogEntry> refreshTodayEntry({String? tone}) async {
    final now = DateTime.now();
    return BodyBlogEntry(
      date: now,
      headline: 'Test',
      summary: 'Test summary',
      fullBody: 'Test body',
      mood: 'calm',
      moodEmoji: '😊',
      tags: const [],
      snapshot: const BodySnapshot(),
    );
  }
}

void main() {
  setUpAll(() {
    // Initialise the router the same way main() does.
    AppRouter.init(skipOnboarding: true);
  });

  testWidgets('MyApp builds and renders a MaterialApp', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeModeProvider.overrideWith(_TestThemeModeNotifier.new),
          localDbServiceProvider.overrideWithValue(_TestLocalDbService()),
          bodyBlogServiceProvider.overrideWithValue(_TestBodyBlogService()),
        ],
        child: const MyApp(),
      ),
    );

    // The MaterialApp.router should have mounted successfully.
    expect(find.byType(MaterialApp), findsOneWidget);

    // Drain lingering timers (e.g. WelcomeScreen animation sequence) so the
    // test framework doesn't complain about pending timers.
    // Can't use pumpAndSettle — the breathing animation repeats forever.
    await tester.pump(const Duration(seconds: 3));
  });
}
