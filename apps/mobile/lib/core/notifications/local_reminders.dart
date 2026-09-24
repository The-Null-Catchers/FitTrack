import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily reminders scheduled on the device.
///
/// These are genuinely local: the OS holds the schedule, so they fire with no
/// server, no account and no connection. Every entry point reports whether it
/// actually worked, because a reminder that was silently dropped — permission
/// refused, exact alarms disallowed — is worse than one the user knows failed.
class LocalReminders {
  LocalReminders(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const int workoutReminderId = 1001;

  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    'fittrack_reminders',
    'Reminders',
    channelDescription: 'Daily training and habit reminders',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Ask for permission. Returns false when the user declines, so the caller
  /// can say the reminder will not fire rather than implying it will.
  Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final IOSFlutterLocalNotificationsPlugin? ios =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
            alert: true, badge: true, sound: true) ??
        false;
  }

  /// Schedule a reminder that repeats every day at [hour]:[minute].
  ///
  /// Returns false if the OS refused. Android 12+ can withhold exact alarms,
  /// in which case this retries inexactly rather than failing outright — an
  /// approximate reminder is still a reminder.
  Future<bool> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    await init();
    final tz.TZDateTime when = _nextOccurrence(hour, minute);
    for (final AndroidScheduleMode mode in <AndroidScheduleMode>[
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ]) {
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          const NotificationDetails(
            android: _android,
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        return true;
      } on Object {
        // Fall through and try the inexact mode.
      }
    }
    return false;
  }

  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  Future<List<PendingNotificationRequest>> pending() async {
    await init();
    return _plugin.pendingNotificationRequests();
  }

  tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime next =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }
}

final Provider<LocalReminders> localRemindersProvider =
    Provider<LocalReminders>(
  (Ref ref) => LocalReminders(FlutterLocalNotificationsPlugin()),
);
