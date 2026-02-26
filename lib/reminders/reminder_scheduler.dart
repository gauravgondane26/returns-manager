import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../items/domain/deadline_engine.dart';
import '../items/domain/item_enums.dart';
import '../items/domain/return_item.dart';

class ReminderScheduler {
  ReminderScheduler({FlutterLocalNotificationsPlugin? notificationsPlugin})
    : _notificationsPlugin =
          notificationsPlugin ?? FlutterLocalNotificationsPlugin();

  static const reminderOffsetsDays = <int>[7, 3, 1];
  static const reminderHourLocal = 10;

  static const _channelId = 'returns_reminders';
  static const _channelName = 'Returns reminders';
  static const _channelDescription = 'Reminders for upcoming return deadlines.';

  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  bool _isInitialized = false;
  bool _permissionGranted = false;
  bool _useExactAlarms = false;
  final Set<String> _sentImmediateReminderKeys = <String>{};

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    tz.initializeTimeZones();
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      final location = tz.getLocation(timezoneName);
      tz.setLocalLocation(location);
    } catch (_) {
      // Keep default location if timezone lookup fails.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _notificationsPlugin.initialize(settings);
    _permissionGranted = await _requestPermissions();
    _isInitialized = true;
  }

  Future<void> syncForItems(List<ReturnItem> items) async {
    await initialize();
    if (!_permissionGranted) {
      return;
    }

    for (final item in items) {
      await _rescheduleItem(item);
    }
  }

  Future<void> cancelForItem(String itemId) async {
    await initialize();
    for (final offset in reminderOffsetsDays) {
      await _notificationsPlugin.cancel(_notificationId(itemId, offset));
    }
    _sentImmediateReminderKeys.removeWhere((key) => key.startsWith('$itemId|'));
  }

  Future<void> _rescheduleItem(ReturnItem item) async {
    await cancelForItem(item.id);
    if (item.effectiveStatus != ItemStatus.pending) {
      return;
    }

    final now = DateTime.now();
    final today = DeadlineEngine.atStartOfDay(now);
    final deadlineDay = DeadlineEngine.atStartOfDay(item.returnDeadline);

    for (final offset in reminderOffsetsDays) {
      final triggerDay = deadlineDay.subtract(Duration(days: offset));
      final triggerLocal = DateTime(
        triggerDay.year,
        triggerDay.month,
        triggerDay.day,
        reminderHourLocal,
      );
      if (triggerDay.isBefore(today)) {
        continue;
      }

      final title = 'Return deadline in $offset day${offset == 1 ? '' : 's'}';
      final body =
          '${item.title} (${item.store.label}) has a return deadline on '
          '${_formatDate(deadlineDay)}.';

      if (triggerLocal.isAfter(now)) {
        await _notificationsPlugin.zonedSchedule(
          _notificationId(item.id, offset),
          title,
          body,
          tz.TZDateTime.from(triggerLocal, tz.local),
          _notificationDetails,
          androidScheduleMode: _useExactAlarms
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        continue;
      }

      if (triggerDay == today) {
        await _sendImmediateReminderOnce(
          itemId: item.id,
          offset: offset,
          triggerDay: triggerDay,
          title: title,
          body: body,
        );
      }
    }
  }

  Future<void> _sendImmediateReminderOnce({
    required String itemId,
    required int offset,
    required DateTime triggerDay,
    required String title,
    required String body,
  }) async {
    final triggerKey = '$itemId|$offset|${_formatDate(triggerDay)}';
    if (_sentImmediateReminderKeys.contains(triggerKey)) {
      return;
    }

    await _notificationsPlugin.show(
      _notificationId(itemId, offset),
      title,
      body,
      _notificationDetails,
    );
    _sentImmediateReminderKeys.add(triggerKey);
  }

  Future<bool> _requestPermissions() async {
    var granted = true;

    final android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final androidGranted = await android.requestNotificationsPermission();
      granted = granted && (androidGranted ?? false);
      _useExactAlarms = await _enableExactAlarmsIfPossible(android);
    }

    final ios = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final iosGranted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = granted && (iosGranted ?? false);
    }

    return granted;
  }

  Future<bool> _enableExactAlarmsIfPossible(
    AndroidFlutterLocalNotificationsPlugin android,
  ) async {
    try {
      final dynamic androidDynamic = android;
      final bool currentlyAllowed =
          await androidDynamic.canScheduleExactNotifications() as bool? ??
          false;
      if (currentlyAllowed) {
        return true;
      }

      await androidDynamic.requestExactAlarmsPermission();
      final bool allowedAfterRequest =
          await androidDynamic.canScheduleExactNotifications() as bool? ??
          false;
      return allowedAfterRequest;
    } catch (_) {
      return false;
    }
  }

  int _notificationId(String itemId, int offsetDays) {
    const int prime = 0x01000193;
    var hash = 0x811c9dc5;
    final key = '$itemId|$offsetDays';

    for (final codeUnit in key.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & 0x7fffffff;
    }

    return hash;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  NotificationDetails get _notificationDetails {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }
}
