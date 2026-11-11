import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite/sqflite.dart';

import '../main.dart';

class AppLockService {
  AppLockService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const LocalAuthentication _localAuth = LocalAuthentication();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const String _pinHashKey = 'my_finance_app_lock_pin_hash';
  static const String _pinSaltKey = 'my_finance_app_lock_pin_salt';

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

  static Future<bool> isEnabled() async =>
      (await _getSetting('app_lock_enabled')) == '1';

  static Future<void> setEnabled(bool enabled) =>
      _saveSetting('app_lock_enabled', enabled ? '1' : '0');

  static Future<bool> hasPin() async =>
      (await _secureStorage.read(key: _pinHashKey)) != null;

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

  static Future<bool> biometricEnabled() async =>
      (await _getSetting('app_lock_biometric')) == '1';

  static Future<void> setBiometricEnabled(bool enabled) =>
      _saveSetting('app_lock_biometric', enabled ? '1' : '0');

  static Future<int> autoLockSeconds() async =>
      int.tryParse(await _getSetting('app_lock_timeout') ?? '0') ?? 0;

  static Future<void> setAutoLockSeconds(int seconds) =>
      _saveSetting('app_lock_timeout', seconds.toString());

  static Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final available = await _localAuth.getAvailableBiometrics();
      return supported && canCheck && available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock My Finance',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
