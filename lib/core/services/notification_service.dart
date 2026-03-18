import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_content_service.dart';

/// Manages local notifications for Miruns.
///
/// Two hardcoded daily pushes:
/// - **Morning** at 08:30 — start-of-day motivation.
/// - **Evening** at 20:00 — end-of-day reflection.
///
/// Plus a **Smart Insights** channel for data-driven notifications
/// triggered from background captures.
///
/// All messaging uses sport & fitness language (activity, training,
/// recovery, performance).
class NotificationService {
  static final NotificationService _instance = NotificationService._();

  factory NotificationService() => _instance;

  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;

  // ── Hardcoded schedule ──────────────────────────────────────────────────

  /// Morning push: 08:30
  static const morningHour = 8;
  static const morningMinute = 30;

  /// Evening push: 20:00
  static const eveningHour = 20;
  static const eveningMinute = 0;

  // ── Channel IDs ─────────────────────────────────────────────────────────

  static const _dailyChannelId = 'miruns_daily_reminder';
  static const _dailyChannelName = 'Daily Activity Recap';
  static const _dailyChannelDescription =
      'Morning and evening recaps of your training and recovery';

  static const _smartChannelId = 'miruns_smart_insights';
  static const _smartChannelName = 'Smart Fitness Insights';
  static const _smartChannelDescription =
      'Data-driven notifications based on your real activity and biometrics';

  static const persistentChannelId = 'miruns_persistent';
  static const _persistentChannelName = 'Activity Monitoring';
  static const _persistentChannelDescription =
      'Keeps Miruns tracking your activity in the background';

  static const _morningNotifId = 9001;
  static const _eveningNotifId = 9002;
  static const _smartNotifId = 9003;
  static const persistentNotifId = 9004;

  // ── Morning messages (08:30 — motivational, forward-looking) ────────────

  static const morningMessages = <({String title, String body})>[
    (
      title: '☀️ Good morning — your overnight stats are in',
      body:
          'Sleep, recovery, resting heart rate — see how your night set up today →',
    ),
    (
      title: '🌅 Rise & check your recovery',
      body: 'Miruns tracked your night. See your sleep and readiness score →',
    ),
    (
      title: '🧬 Your overnight recovery report is ready',
      body:
          'Sleep quality, heart rate, rest — everything you need to plan your day →',
    ),
    (
      title: '⚡ How\'s your energy level this morning?',
      body:
          'Sleep quality + overnight vitals = your readiness forecast. Check it →',
    ),
    (
      title: '🫀 Morning briefing: recovery & readiness',
      body:
          'Heart, sleep, readiness — one tap to see how you\'re starting the day →',
    ),
    (
      title: '📖 New day, fresh training data',
      body:
          'Yesterday\'s activity is logged. Today\'s starts now — check your baseline →',
    ),
    (
      title: '🎯 Morning check-in: how rested are you?',
      body: 'Your overnight data is ready. See the recovery summary →',
    ),
    (
      title: '🔬 Your morning recovery report is in',
      body: 'Real sleep data from last night. See your readiness →',
    ),
    (
      title: '💡 Miruns knows how you slept',
      body: 'And it has insights. See your overnight recovery data →',
    ),
    (
      title: '🌟 Morning insight: today\'s baseline',
      body:
          'Sleep, recovery, resting heart rate — you\'re ready to train. See the data →',
    ),
    (
      title: '🏃 Ready to train today?',
      body: 'Your recovery score is in. See how your night went →',
    ),
    (
      title: '🧘 Pre-workout awareness',
      body: 'Before you train — check your recovery and readiness →',
    ),
  ];

  // ── Evening messages (20:00 — reflective, summary-focused) ─────────────

  static const eveningMessages = <({String title, String body})>[
    (
      title: '🌙 Your daily activity wrap-up',
      body:
          'Steps, heart rate, movement, training — today\'s full recap is ready →',
    ),
    (
      title: '📊 End-of-day performance report',
      body: 'Miruns tracked your entire day. See the complete picture →',
    ),
    (
      title: '🔥 What did you accomplish today?',
      body: 'Steps, calories burned, heart patterns — all compiled for you →',
    ),
    (
      title: '📝 Today\'s activity summary is ready',
      body: 'A complete account of your day — movement, training, recovery →',
    ),
    (
      title: '🧠 Miruns spotted patterns today',
      body: 'Trends, anomalies, streaks — check what it found →',
    ),
    (
      title: '💬 Your evening recap is waiting',
      body: 'Real data. Real insights from your day. Open it →',
    ),
    (
      title: '🫀 Pulse. Steps. Performance.',
      body: 'Today\'s numbers are in. See your evening activity recap →',
    ),
    (
      title: '🪞 Day in review: the full picture',
      body: 'Training, recovery, movement — see what really happened today →',
    ),
    (
      title: '🌊 Today\'s activity overview',
      body: 'Energy, recovery, movement — the full picture before you rest →',
    ),
    (
      title: '🏅 Here\'s how you performed today',
      body: 'Steps, training, heart rate — all in your evening recap →',
    ),
    (
      title: '🚀 End-of-day fitness update',
      body:
          'Steps, rest, intensity — all logged. See your complete daily summary →',
    ),
    (
      title: '🎯 One tap. Your whole day.',
      body:
          'Miruns summarised all your activity. Don\'t miss tonight\'s recap →',
    ),
  ];

  // ── Lifecycle ───────────────────────────────────────────────────────────

  /// Initialise the notification plugin and create Android channels.
  ///
  /// Safe to call more than once — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialised) return;

    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Create Android notification channels (no-op on iOS).
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _dailyChannelId,
          _dailyChannelName,
          description: _dailyChannelDescription,
          importance: Importance.high,
        ),
      );
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _smartChannelId,
          _smartChannelName,
          description: _smartChannelDescription,
          importance: Importance.high,
        ),
      );
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          persistentChannelId,
          _persistentChannelName,
          description: _persistentChannelDescription,
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    }

    _initialised = true;
  }

  // ── Public helpers ────────────────────────────────────────────────────

  /// Request notification permission on Android 13+ / iOS.
  Future<bool> requestPermission() async {
    // Android 13+
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    // iOS
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return false;
  }

  // ── Daily reminder scheduling ─────────────────────────────────────────

  /// Schedule the two hardcoded daily pushes (morning 08:30 + evening 20:00).
  ///
  /// Replaces any previously scheduled reminders. Each picks a random
  /// message from the appropriate pool — re-scheduled on every app launch
  /// so the messages rotate.
  Future<void> scheduleDailyReminders() async {
    await _ensureInitialised();

    // Cancel any existing daily reminders first.
    await _plugin.cancel(_morningNotifId);
    await _plugin.cancel(_eveningNotifId);

    await _scheduleOne(
      id: _morningNotifId,
      hour: morningHour,
      minute: morningMinute,
      messages: morningMessages,
    );
    await _scheduleOne(
      id: _eveningNotifId,
      hour: eveningHour,
      minute: eveningMinute,
      messages: eveningMessages,
    );

    debugPrint(
      '[NotificationService] Scheduled morning ($morningHour:$morningMinute) '
      '+ evening ($eveningHour:$eveningMinute) reminders.',
    );
  }

  /// Cancel both daily reminders.
  Future<void> cancelDailyReminders() async {
    await _ensureInitialised();
    await _plugin.cancel(_morningNotifId);
    await _plugin.cancel(_eveningNotifId);
  }

  /// Legacy single-reminder cancel (for migration).
  Future<void> cancelDailyReminder() async {
    await _ensureInitialised();
    await _plugin.cancel(_morningNotifId);
  }

  Future<void> _scheduleOne({
    required int id,
    required int hour,
    required int minute,
    required List<({String title, String body})> messages,
  }) async {
    final msg = messages[Random().nextInt(messages.length)];

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    // Use exact alarms when the permission is granted; fall back to inexact
    // scheduling otherwise so that reminders are still registered even when
    // the user hasn't allowed exact alarms (Android 12+).
    final exactAllowed = await Permission.scheduleExactAlarm.status.then(
      (s) => s.isGranted,
    );
    final scheduleMode = exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    debugPrint(
      '[NotificationService] Scheduling id=$id at $hour:$minute '
      '(mode: ${scheduleMode.name})',
    );

    await _plugin.zonedSchedule(
      id,
      msg.title,
      msg.body,
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _dailyChannelId,
          _dailyChannelName,
          channelDescription: _dailyChannelDescription,
          icon: '@drawable/ic_notification',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          styleInformation: BigTextStyleInformation(msg.body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ── Smart data-driven notification ──────────────────────────────────────

  /// Show a data-driven notification with real biometric content.
  ///
  /// Called from the background capture executor (once per day) with a
  /// [NotifContent] produced by [NotificationContentService].
  Future<void> showSmartNotification(NotifContent content) async {
    await _ensureInitialised();

    await _plugin.show(
      _smartNotifId,
      content.title,
      content.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _smartChannelId,
          _smartChannelName,
          channelDescription: _smartChannelDescription,
          icon: '@drawable/ic_notification',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          styleInformation: BigTextStyleInformation(content.body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Show a test daily notification immediately (for the debug panel).
  Future<void> showTestDailyReminder() async {
    await _ensureInitialised();

    final allMessages = [...morningMessages, ...eveningMessages];
    final msg = allMessages[Random().nextInt(allMessages.length)];

    await _plugin.show(
      _morningNotifId + 100, // unique test ID
      msg.title,
      msg.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _dailyChannelId,
          _dailyChannelName,
          channelDescription: _dailyChannelDescription,
          icon: '@drawable/ic_notification',
          importance: Importance.high,
          priority: Priority.high,
          showWhen: true,
          styleInformation: BigTextStyleInformation(msg.body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ── Internals ─────────────────────────────────────────────────────────

  Future<void> _ensureInitialised() async {
    if (!_initialised) await initialize();
  }
}
