import 'package:flutter_test/flutter_test.dart';
import 'package:miruns_flutter/core/models/body_blog_entry.dart';
import 'package:miruns_flutter/core/models/capture_entry.dart';
import 'package:miruns_flutter/core/services/local_db_service.dart';
import 'package:miruns_flutter/core/services/notification_content_service.dart';

/// Stub [LocalDbService] for testing notification content generation.
class _TestLocalDbService extends LocalDbService {
  List<CaptureEntry> capturesForToday = [];
  BodyBlogEntry? blogEntry;
  final Map<String, String> _settings = {};
  List<List<CaptureEntry>> capturesByDay = [];

  @override
  Future<bool> hasAnyEntries() async => false;

  @override
  Future<BodyBlogEntry?> loadEntry(DateTime date) async => blogEntry;

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String value) async =>
      _settings[key] = value;

  @override
  Future<List<CaptureEntry>> loadCapturesForDate(DateTime date) async {
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    if (isToday) return capturesForToday;
    // For streak calculation: days before today
    final daysAgo = DateTime(today.year, today.month, today.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (daysAgo > 0 && daysAgo <= capturesByDay.length) {
      return capturesByDay[daysAgo - 1];
    }
    return [];
  }
}

void main() {
  // ── Static message pools ───────────────────────────────────────────────

  group('NotificationContentService static pools', () {
    test('nudgeMessages are non-empty', () {
      expect(NotificationContentService.nudgeMessages, isNotEmpty);
    });

    test('every nudge message has non-empty title and body', () {
      for (final msg in NotificationContentService.nudgeMessages) {
        expect(msg.title.isNotEmpty, isTrue);
        expect(msg.body.isNotEmpty, isTrue);
      }
    });

    test('engagingFallbacks are non-empty', () {
      expect(NotificationContentService.engagingFallbacks, isNotEmpty);
    });

    test('every fallback message has non-empty title and body', () {
      for (final msg in NotificationContentService.engagingFallbacks) {
        expect(msg.title.isNotEmpty, isTrue);
        expect(msg.body.isNotEmpty, isTrue);
      }
    });
  });

  // ── buildSmartNotification integration ─────────────────────────────────

  group('NotificationContentService.buildSmartNotification', () {
    late _TestLocalDbService db;
    late NotificationContentService svc;

    setUp(() {
      db = _TestLocalDbService();
      svc = NotificationContentService(db: db);
    });

    test('returns a nudge message when no data available', () async {
      db.capturesForToday = [];
      db.blogEntry = null;

      final result = await svc.buildSmartNotification();
      expect(result.title.isNotEmpty, isTrue);
      expect(result.body.isNotEmpty, isTrue);
    });

    test('returns steps-related notification when steps data present',
        () async {
      final now = DateTime.now();
      db.capturesForToday = [
        CaptureEntry(
          id: 'test-1',
          timestamp: now,
          healthData: const CaptureHealthData(steps: 12000),
        ),
      ];
      db.blogEntry = null;

      final result = await svc.buildSmartNotification();
      expect(result.title.isNotEmpty, isTrue);
      expect(result.body.isNotEmpty, isTrue);
    });

    test('returns sleep-related notification when sleep data present',
        () async {
      final now = DateTime.now();
      db.capturesForToday = [
        CaptureEntry(
          id: 'test-2',
          timestamp: now,
          healthData: const CaptureHealthData(sleepHours: 7.5),
        ),
      ];
      db.blogEntry = null;

      final result = await svc.buildSmartNotification();
      expect(result.title.isNotEmpty, isTrue);
    });

    test('returns blog notification when blog entry present', () async {
      final now = DateTime.now();
      db.capturesForToday = [];
      db.blogEntry = BodyBlogEntry(
        date: now,
        headline: 'A great day',
        summary: 'Excellent activity levels throughout the day.',
        fullBody: 'Full report.',
        mood: 'energized',
        moodEmoji: '⚡',
        tags: const ['active'],
        snapshot: const BodySnapshot(),
      );

      final result = await svc.buildSmartNotification();
      expect(result.title.isNotEmpty, isTrue);
      expect(result.body.isNotEmpty, isTrue);
    });

    test('handles multiple data sources and returns one notification',
        () async {
      final now = DateTime.now();
      db.capturesForToday = [
        CaptureEntry(
          id: 'test-3',
          timestamp: now,
          healthData: const CaptureHealthData(
            steps: 8000,
            sleepHours: 8.2,
            heartRate: 65,
            workouts: 1,
            calories: 450.0,
          ),
          environmentData: const CaptureEnvironmentData(
            temperature: 22.0,
            weatherDescription: 'Sunny',
            aqi: 42,
          ),
          locationData: const CaptureLocationData(
            latitude: 48.8,
            longitude: 2.3,
            city: 'Paris',
          ),
        ),
      ];
      db.blogEntry = null;

      final result = await svc.buildSmartNotification();
      expect(result.title.isNotEmpty, isTrue);
      expect(result.body.isNotEmpty, isTrue);
    });
  });

  // ── wasSmartNotifShownToday / markSmartNotifShown ───────────────────────

  group('NotificationContentService smart notif tracking', () {
    late _TestLocalDbService db;
    late NotificationContentService svc;

    setUp(() {
      db = _TestLocalDbService();
      svc = NotificationContentService(db: db);
    });

    test('wasSmartNotifShownToday returns false initially', () async {
      expect(await svc.wasSmartNotifShownToday(), isFalse);
    });

    test('wasSmartNotifShownToday returns true after marking', () async {
      await svc.markSmartNotifShown();
      expect(await svc.wasSmartNotifShownToday(), isTrue);
    });

    test('wasSmartNotifShownToday returns false for old date', () async {
      // Manually set yesterday's date
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final key =
          '${yesterday.year}-'
          '${yesterday.month.toString().padLeft(2, '0')}-'
          '${yesterday.day.toString().padLeft(2, '0')}';
      await db.setSetting('last_smart_notif_date', key);
      expect(await svc.wasSmartNotifShownToday(), isFalse);
    });
  });
}
