import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../items/domain/deadline_engine.dart';
import '../items/domain/item_enums.dart';
import '../items/domain/return_item.dart';

class CalendarExportService {
  CalendarExportService({
    DeviceCalendarPlugin? calendarPlugin,
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _calendarPlugin = calendarPlugin ?? DeviceCalendarPlugin(),
       _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  static const _mappingKeyPrefix = 'calendar_export_event_map_v1_';
  static const _calendarIdKey = 'calendar_export_calendar_id_v1';

  final DeviceCalendarPlugin _calendarPlugin;
  final Future<SharedPreferences> Function() _prefsFactory;

  SharedPreferences? _prefs;
  bool _isInitialized = false;
  bool _permissionGranted = false;
  String? _calendarId;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _prefs = await _prefsFactory();
    _permissionGranted = await _ensurePermissions();
    if (_permissionGranted) {
      _calendarId = await _resolveCalendarId();
    }
    _isInitialized = true;
  }

  Future<void> syncPendingItems({
    required String uid,
    required List<ReturnItem> items,
  }) async {
    await initialize();
    final calendarId = _calendarId;
    if (!_permissionGranted || calendarId == null) {
      return;
    }

    final pendingItems = items
        .where((item) => item.effectiveStatus == ItemStatus.pending)
        .toList();

    final eventMap = _readEventMap(uid);
    final pendingIds = pendingItems.map((item) => item.id).toSet();
    final staleItemIds = eventMap.keys
        .where((itemId) => !pendingIds.contains(itemId))
        .toList();

    for (final itemId in staleItemIds) {
      final eventId = eventMap[itemId];
      if (eventId != null && eventId.isNotEmpty) {
        await _calendarPlugin.deleteEvent(calendarId, eventId);
      }
      eventMap.remove(itemId);
    }

    for (final item in pendingItems) {
      final eventId = await _upsertEvent(
        calendarId: calendarId,
        item: item,
        eventId: eventMap[item.id],
      );
      if (eventId != null && eventId.isNotEmpty) {
        eventMap[item.id] = eventId;
      }
    }

    await _writeEventMap(uid, eventMap);
  }

  Future<void> clearExportedEvents({required String uid}) async {
    await initialize();
    final calendarId = _calendarId;
    if (calendarId == null) {
      return;
    }

    final eventMap = _readEventMap(uid);
    for (final eventId in eventMap.values) {
      if (eventId.isNotEmpty) {
        await _calendarPlugin.deleteEvent(calendarId, eventId);
      }
    }
    await _writeEventMap(uid, <String, String>{});
  }

  Future<bool> _ensurePermissions() async {
    final hasPermissionsResult = await _calendarPlugin.hasPermissions();
    final hasPermissions = hasPermissionsResult.isSuccess
        ? (hasPermissionsResult.data ?? false)
        : false;
    if (hasPermissions) {
      return true;
    }

    final requestResult = await _calendarPlugin.requestPermissions();
    return requestResult.isSuccess ? (requestResult.data ?? false) : false;
  }

  Future<String?> _resolveCalendarId() async {
    final prefs = _prefs;
    if (prefs == null) {
      return null;
    }

    final cachedId = prefs.getString(_calendarIdKey);
    if (cachedId != null && cachedId.isNotEmpty) {
      return cachedId;
    }

    final calendarsResult = await _calendarPlugin.retrieveCalendars();
    if (!calendarsResult.isSuccess) {
      return null;
    }

    final calendars = calendarsResult.data ?? const <Calendar>[];
    if (calendars.isEmpty) {
      return null;
    }

    Calendar? selected;
    for (final calendar in calendars) {
      if ((calendar.isReadOnly ?? false) == false &&
          (calendar.isDefault ?? false)) {
        selected = calendar;
        break;
      }
    }
    selected ??= calendars.firstWhere(
      (calendar) => (calendar.isReadOnly ?? false) == false,
      orElse: () => calendars.first,
    );

    final selectedId = selected.id;
    if (selectedId == null || selectedId.isEmpty) {
      return null;
    }
    await prefs.setString(_calendarIdKey, selectedId);
    return selectedId;
  }

  Future<String?> _upsertEvent({
    required String calendarId,
    required ReturnItem item,
    required String? eventId,
  }) async {
    final deadline = DeadlineEngine.atStartOfDay(item.returnDeadline);
    final event = Event(calendarId, eventId: eventId);
    event.title = 'Return deadline: ${item.title}';
    event.description = [
      'Store: ${item.store.label}',
      'Status: Pending',
      'Source: Returns Manager',
      'Item ID: ${item.id}',
    ].join('\n');
    event.start = tz.TZDateTime.from(deadline, tz.local);
    event.end = tz.TZDateTime.from(
      deadline.add(const Duration(days: 1)),
      tz.local,
    );
    event.allDay = true;

    final result = await _calendarPlugin.createOrUpdateEvent(event);
    if (result == null || !result.isSuccess) {
      return eventId;
    }
    final createdId = result.data;
    if (createdId == null || createdId.isEmpty) {
      return eventId;
    }
    return createdId;
  }

  Map<String, String> _readEventMap(String uid) {
    final raw = _prefs?.getString('$_mappingKeyPrefix$uid');
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, '$value'));
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeEventMap(String uid, Map<String, String> map) async {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }
    await prefs.setString('$_mappingKeyPrefix$uid', jsonEncode(map));
  }
}
