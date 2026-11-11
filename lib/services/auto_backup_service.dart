import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

import 'backup_service.dart';
import 'google_drive_backup_service.dart';

class AutoBackupService {
  AutoBackupService._();

  static const String taskName = 'myFinanceAutomaticDriveBackup';

  static Future<void> initialize() async {
    await Workmanager().initialize(
      autoBackupCallbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> configure({
    required bool enabled,
    required String frequency,
  }) async {
    await Workmanager().cancelByUniqueName(taskName);
    if (!enabled) return;

    final days = frequency == 'weekly' ? 7 : 1;
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: Duration(days: days),
      initialDelay: Duration(days: days),
    );
  }

  static Future<void> runNow() async {
    final account = await GoogleDriveBackupService.signInSilently();
    if (account == null) {
      throw Exception('Connect your Google Drive account first.');
    }

    final database = await openDatabase(
      p.join(await getDatabasesPath(), 'my_finance.db'),
    );
    try {
      final bytes = await BackupService.createBackup(database: database);
      final now = DateTime.now();
      final fileName =
          'My_Finance_Auto_Backup_${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}.zip';

      await GoogleDriveBackupService.uploadBackup(
        account: account,
        bytes: bytes,
        fileName: fileName,
      );

      await database.insert(
        'app_settings',
        {
          'setting_key': 'auto_backup_last_success',
          'setting_value': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } finally {
      await database.close();
    }
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

@pragma('vm:entry-point')
void autoBackupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task != AutoBackupService.taskName) return true;

    Database? database;
    try {
      database = await openDatabase(
        p.join(await getDatabasesPath(), 'my_finance.db'),
      );

      final settings = await database.query(
        'app_settings',
        columns: ['setting_value'],
        where: 'setting_key = ?',
        whereArgs: ['auto_backup_enabled'],
        limit: 1,
      );
      if (settings.isEmpty || settings.first['setting_value'] != '1') {
        return true;
      }

      final account = await GoogleDriveBackupService.signInSilently();
      if (account == null) return false;

      final bytes = await BackupService.createBackup(database: database);
      final now = DateTime.now();
      final fileName =
          'My_Finance_Auto_Backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.zip';

      await GoogleDriveBackupService.uploadBackup(
        account: account,
        bytes: bytes,
        fileName: fileName,
      );

      await database.insert(
        'app_settings',
        {
          'setting_key': 'auto_backup_last_success',
          'setting_value': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      await database?.close();
    }
  });
}
