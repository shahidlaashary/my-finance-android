import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const _storageKey = 'finance_reminders_v1';
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;

  Future<void> initialize() => _initializing ??= _initialize();

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

  Future<void> _save(List<Map<String, dynamic>> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(reminders));
  }

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
    return id;
  }

  Future<void> deleteReminder(int id) async {
    await initialize();
    await _notifications.cancel(id);
    final reminders = await getReminders();
    reminders.removeWhere((item) => item['id'] == id);
    await _save(reminders);
  }
}
