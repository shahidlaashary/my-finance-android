import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/database_platform.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/theme/appearance_settings_service.dart';
import 'package:my_finance/core/preferences/language_settings_service.dart';

/// Prepares Flutter, the database platform and saved app preferences.
class AppBootstrapService {
  AppBootstrapService._();

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDatabasePlatform();
    await FinanceDB.instance.init();

    final appearance = AppearanceSettingsService.instance;
    appearance.configure(
      readSetting: (key) async {
        final rows = await FinanceDB.instance.db.query(
          'app_settings',
          columns: ['setting_value'],
          where: 'setting_key = ?',
          whereArgs: [key],
          limit: 1,
        );
        return rows.isEmpty ? null : rows.first['setting_value']?.toString();
      },
      writeSetting: (key, value) async {
        await FinanceDB.instance.db.insert(
          'app_settings',
          {'setting_key': key, 'setting_value': value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      },
    );
    await appearance.load();
    await LanguageSettingsService.instance.load();
  }
}
