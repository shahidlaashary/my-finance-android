import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/database_platform.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/theme/appearance_settings_service.dart';
import 'package:my_finance/core/preferences/language_settings_service.dart';
import 'package:my_finance/core/startup/app_startup_service.dart';

/// Prepares Flutter, the database platform and saved app preferences.
class AppBootstrapService {
  AppBootstrapService._();

  static const _testingDataResetKey = 'testing_fresh_data_reset_v1';

  /// Clears data from earlier test builds once, while allowing new test data
  /// to work normally until the app is uninstalled.
  static Future<void> _clearPreviousTestingDataIfNeeded() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_testingDataResetKey) == true) return;

    final databaseDirectory = Directory(await getDatabasesPath());
    if (await databaseDirectory.exists()) {
      await for (final entity in databaseDirectory.list()) {
        if (entity is File &&
            (p.basename(entity.path).startsWith('my_finance') ||
                p.basename(entity.path).startsWith('my_finance_restore_') ||
                p.basename(entity.path).startsWith('my_finance_previous_'))) {
          await entity.delete();
        } else if (entity is Directory &&
            (p.basename(entity.path).startsWith('my_finance_restore_') ||
                p.basename(entity.path).startsWith('my_finance_previous_'))) {
          await entity.delete(recursive: true);
        }
      }
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final attachments = Directory(
      p.join(documentsDirectory.path, 'my_finance_attachments'),
    );
    if (await attachments.exists()) {
      await attachments.delete(recursive: true);
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final automaticBackups = Directory(
      p.join(supportDirectory.path, 'automatic_backups'),
    );
    if (await automaticBackups.exists()) {
      await automaticBackups.delete(recursive: true);
    }

    final temporaryDirectory = await getTemporaryDirectory();
    if (await temporaryDirectory.exists()) {
      await for (final entity in temporaryDirectory.list()) {
        if (entity is File &&
            p.basename(entity.path).startsWith('my_finance_backup_')) {
          await entity.delete();
        }
      }
    }

    // Remove all previously stored app preferences and secure app-lock data.
    await preferences.clear();
    await const FlutterSecureStorage().deleteAll();
    await preferences.setBool(_testingDataResetKey, true);
  }

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDatabasePlatform();
    await _clearPreviousTestingDataIfNeeded();
    await FinanceDB.instance.init();

    // Database tayyar hone ke baad due recurring transactions process karta hai.
    // Is se app ke normal startup par scheduled income aur expenses miss nahi hote.
    await AppStartupService.initialize();

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
