import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/database_manager.dart';

/// Owns app_settings persistence in the shared finance database.
class AppSettingsService {
  AppSettingsService._();

  static Future<String?> get(String key) async {
    final rows = await DatabaseManager.instance.database.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['setting_value']?.toString();
  }

  static Future<void> set(String key, String value) async {
    await DatabaseManager.instance.database.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
