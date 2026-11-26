import 'dart:convert';

import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/services/recycle_bin_archive_service.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Local reminders schedule, save, delete aur restore karne ki service hai.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const _storageKey = 'finance_reminders_v1';
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;

  /// Timezone aur local notifications ko sirf aik martaba initialize karta hai.
  Future<void> initialize() => _initializing ??= _initialize();

  /// Pakistan timezone set karke Android/iOS notification permissions tayyar karta hai.
  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(settings);
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  /// Saved reminders load karke due time ke mutabiq sort karta hai.
  Future<List<Map<String, dynamic>>> getReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
        ..sort((a, b) => DateTime.parse(a['when'] as String)
            .compareTo(DateTime.parse(b['when'] as String)));
    } catch (_) {
      return [];
    }
  }

  /// Reminder list ko local preferences mein JSON format mein save karta hai.
  Future<void> _save(List<Map<String, dynamic>> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(reminders));
  }

  /// Future reminder validate, schedule aur local storage mein save karta hai.
  Future<int> addReminder({
    required String title,
    required String note,
    required DateTime when,
    required String category,
  }) async {
    await initialize();
    if (title.trim().isEmpty) throw ArgumentError('Reminder title is required.');
    if (!when.isAfter(DateTime.now())) {
      throw ArgumentError('Reminder time must be in the future.');
    }
    final id = DateTime.now().microsecondsSinceEpoch.remainder(2147483647);
    final reminders = await getReminders();
    final item = <String, dynamic>{
      'id': id,
      'title': title.trim(),
      'note': note.trim(),
      'category': category,
      'when': when.toIso8601String(),
    };
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'finance_reminders',
        'Finance reminders',
        channelDescription: 'Bills, loans and personal finance reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    await _notifications.zonedSchedule(
      id,
      item['title'] as String,
      (item['note'] as String).isEmpty
          ? 'My Finance reminder'
          : item['note'] as String,
      tz.TZDateTime.from(when, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    reminders.add(item);
    await _save(reminders);
    AppRefreshController.notifyChanged();
    return id;
  }


  /// Module-linked reminders ko idempotently sync karta hai. Existing personal
  /// reminders ko touch nahi karta; stale linked notifications cancel ho jati hain.
  Future<void> syncLinkedReminders({
    required String sourcePrefix,
    required List<Map<String, dynamic>> desired,
  }) async {
    await initialize();
    final reminders = await getReminders();
    final wanted = <String, Map<String, dynamic>>{};
    for (final item in desired) {
      final key = item['source_key']?.toString() ?? '';
      final when = item['when'];
      if (!key.startsWith(sourcePrefix) || when is! DateTime ||
          !when.isAfter(DateTime.now())) continue;
      wanted[key] = item;
    }
    var changed = false;
    final retained = <Map<String, dynamic>>[];
    for (final existing in reminders) {
      final key = existing['source_key']?.toString() ?? '';
      if (!key.startsWith(sourcePrefix)) {
        retained.add(existing);
        continue;
      }
      final target = wanted.remove(key);
      final same = target != null &&
          existing['title'] == target['title'] &&
          existing['note'] == target['note'] &&
          existing['category'] == target['category'] &&
          existing['when'] == (target['when'] as DateTime).toIso8601String();
      if (same) {
        retained.add(existing);
      } else {
        await _notifications.cancel((existing['id'] as num).toInt());
        changed = true;
      }
    }
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'finance_reminders', 'Finance reminders',
        channelDescription: 'Bills, loans and personal finance reminders',
        importance: Importance.high, priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    for (final entry in wanted.entries) {
      final item = entry.value;
      final when = item['when'] as DateTime;
      final id = DateTime.now().microsecondsSinceEpoch.remainder(2147483647);
      final record = <String, dynamic>{
        'id': id, 'source_key': entry.key,
        'title': item['title'].toString(),
        'note': item['note']?.toString() ?? '',
        'category': item['category']?.toString() ?? 'General',
        'when': when.toIso8601String(),
      };
      await _notifications.zonedSchedule(
        id, record['title'] as String,
        (record['note'] as String).isEmpty ? 'My Finance reminder' : record['note'] as String,
        tz.TZDateTime.from(when, tz.local), details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      retained.add(record);
      changed = true;
    }
    if (changed) {
      await _save(retained);
      AppRefreshController.notifyChanged();
    }
  }

  /// Reminder ko archive karke scheduled notification cancel aur record delete karta hai.
  Future<void> deleteReminder(int id) async {
    await initialize();
    final reminders = await getReminders();
    final index = reminders.indexWhere((item) => (item['id'] as num?)?.toInt() == id);
    if (index < 0) return;
    final record = reminders[index];
    await RecycleBinArchiveService.archive(
      type: 'Reminder',
      title: record['title']?.toString() ?? 'Reminder',
      table: 'finance_reminders_v1',
      id: id,
      record: record,
    );
    await _notifications.cancel(id);
    reminders.removeAt(index);
    await _save(reminders);
    AppRefreshController.notifyChanged();
  }

  /// Archived reminder restore karta hai aur future time ho to notification dobara schedule karta hai.
  Future<void> restoreReminder(Map<String, dynamic> record) async {
    await initialize();
    final id = (record['id'] as num).toInt();
    final reminders = await getReminders();
    if (reminders.any((item) => (item['id'] as num?)?.toInt() == id)) {
      throw StateError('A reminder with this ID already exists.');
    }
    final when = DateTime.parse(record['when'].toString());
    if (when.isAfter(DateTime.now())) {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'finance_reminders', 'Finance reminders',
          channelDescription: 'Bills, loans and personal finance reminders',
          importance: Importance.high, priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      );
      await _notifications.zonedSchedule(
        id, record['title']?.toString() ?? 'Reminder',
        (record['note'] ?? '').toString().isEmpty
            ? 'My Finance reminder' : record['note'].toString(),
        tz.TZDateTime.from(when, tz.local), details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    reminders.add(record);
    await _save(reminders);
    AppRefreshController.notifyChanged();
  }
}
