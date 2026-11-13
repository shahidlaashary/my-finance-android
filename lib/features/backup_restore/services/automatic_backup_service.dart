import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/backup_restore/services/backup_service.dart';

/// Daily local backups are checked on app launch; no background job is claimed.
class AutomaticBackupService {
  AutomaticBackupService._();
  static const _enabledKey = 'automatic_backup_enabled';
  static const _lastKey = 'automatic_backup_last_success';
  static const _statusKey = 'automatic_backup_last_status';
  static const _keep = 7;
  static bool _running = false;
  static Future<bool> isEnabled() async => (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? false;
  static Future<DateTime?> lastSuccessfulBackup() async {
    final value = (await SharedPreferences.getInstance()).getString(_lastKey);
    return value == null ? null : DateTime.tryParse(value);
  }
  static Future<String?> lastStatus() async => (await SharedPreferences.getInstance()).getString(_statusKey);
  static Future<void> setEnabled(bool enabled) async {
    await (await SharedPreferences.getInstance()).setBool(_enabledKey, enabled);
    if (enabled) await createBackupNow();
  }
  static Future<void> runIfDue() async {
    if (_running || !await isEnabled()) return;
    final last = await lastSuccessfulBackup();
    if (last != null && DateTime.now().difference(last).inHours < 24) return;
    try { await createBackupNow(); } catch (error, stack) { debugPrint('Automatic backup failed: $error'); debugPrintStack(stackTrace: stack); }
  }
  static Future<void> createBackupNow() async {
    if (_running) return;
    _running = true;
    try {
      final bytes = await BackupService.createBackup(database: FinanceDB.instance.db);
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'automatic_backups'));
      await dir.create(recursive: true);
      final now = DateTime.now();
      final stamp = now.toIso8601String().replaceAll(':', '-');
      final file = File(p.join(dir.path, 'My_Finance_Auto_$stamp.zip'));
      final temp = File(file.path + '.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastKey, now.toIso8601String());
      await prefs.setString(_statusKey, 'success');
      final files = await dir.list().where((e) => e is File && e.path.endsWith('.zip')).cast<File>().toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final old in files.skip(_keep)) { await old.delete(); }
    } catch (_) {
      await (await SharedPreferences.getInstance()).setString(_statusKey, 'failed');
      rethrow;
    } finally { _running = false; }
  }
}