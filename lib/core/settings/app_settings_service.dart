import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/database_manager.dart';

/// Shared finance database mein app_settings ki persistence ka zimma rakhta hai.
class AppSettingsService {
  AppSettingsService._();

  /// Setting key ke zariye saved value hasil karta hai.
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

  /// Setting ko insert ya existing value ki jagah update karta hai.
  static Future<void> set(String key, String value) async {
    await DatabaseManager.instance.database.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
