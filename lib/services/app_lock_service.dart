import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../main.dart';

class AppLockService {
  AppLockService._();

  static final FlutterSecureStorage _secureStorage =
      FlutterSecureStorage();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // Versioned keys prevent old, previously tested settings from unexpectedly
  // locking the app after this feature is re-enabled.
  static const String _enabledKey = 'app_lock_pin_enabled_v1';
  static const String _timeoutKey = 'app_lock_pin_timeout_v1';
  static const String _pinHashKey = 'my_finance_app_lock_pin_hash_v1';
  static const String _pinSaltKey = 'my_finance_app_lock_pin_salt_v1';

  static Future<String?> _getSetting(String key) async {
    final rows = await FinanceDB.instance.db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['setting_value']?.toString();
  }

  static Future<void> _saveSetting(String key, String value) async {
    await FinanceDB.instance.db.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    revision.value++;
  }

  static Future<bool> isEnabled() async {
    // Important: do not access Android secure storage on normal startup
    // unless the user has explicitly enabled this version of App Lock.
    if (await _getSetting(_enabledKey) != '1') return false;
    return hasPin();
  }

  static Future<void> setEnabled(bool enabled) =>
      _saveSetting(_enabledKey, enabled ? '1' : '0');

  static Future<bool> hasPin() async {
    final hash = await _secureStorage.read(key: _pinHashKey);
    final salt = await _secureStorage.read(key: _pinSaltKey);
    return hash != null && salt != null;
  }

  static Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw ArgumentError('PIN must contain 4 to 8 digits.');
    }

    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final salt = base64UrlEncode(saltBytes);
    final hash = sha256.convert(utf8.encode('$salt:$pin')).toString();

    await _secureStorage.write(key: _pinSaltKey, value: salt);
    await _secureStorage.write(key: _pinHashKey, value: hash);
    revision.value++;
  }

  static Future<bool> verifyPin(String pin) async {
    final salt = await _secureStorage.read(key: _pinSaltKey);
    final storedHash = await _secureStorage.read(key: _pinHashKey);
    if (salt == null || storedHash == null) return false;

    final candidate = sha256.convert(utf8.encode('$salt:$pin')).toString();
    return candidate == storedHash;
  }

  static Future<int> autoLockSeconds() async {
    final saved = int.tryParse(await _getSetting(_timeoutKey) ?? '0') ?? 0;
    return [0, 30, 60, 300].contains(saved) ? saved : 0;
  }

  static Future<void> setAutoLockSeconds(int seconds) {
    if (![0, 30, 60, 300].contains(seconds)) {
      throw ArgumentError('Unsupported auto-lock timeout.');
    }
    return _saveSetting(_timeoutKey, seconds.toString());
  }
}
