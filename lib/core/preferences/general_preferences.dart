import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeneralPreferences {
  GeneralPreferences._();
  static final GeneralPreferences instance = GeneralPreferences._();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void _notifyChanged() => revision.value++;

  static const _dateFormatKey = 'general_date_format';
  static const _weekStartKey = 'general_week_start';
  static const _numberFormatKey = 'general_number_format';
  static const _rememberWalletKey = 'general_remember_wallet';
  static const _defaultDateKey = 'general_default_date';
  static const _deleteConfirmKey = 'general_delete_confirmation';
  static const _hideBalancesKey = 'general_hide_balances';
  static const _hapticsKey = 'general_haptic_feedback';

  Future<String> get dateFormat async =>
      (await SharedPreferences.getInstance()).getString(_dateFormatKey) ?? 'dd/MM/yyyy';
  Future<void> setDateFormat(String value) async {
    await (await SharedPreferences.getInstance()).setString(_dateFormatKey, value);
    _notifyChanged();
  }

  Future<String> get weekStart async =>
      (await SharedPreferences.getInstance()).getString(_weekStartKey) ?? 'Monday';
  Future<void> setWeekStart(String value) async {
    await (await SharedPreferences.getInstance()).setString(_weekStartKey, value);
    _notifyChanged();
  }

  Future<String> get numberFormat async =>
      (await SharedPreferences.getInstance()).getString(_numberFormatKey) ?? '1,234.56';
  Future<void> setNumberFormat(String value) async {
    await (await SharedPreferences.getInstance()).setString(_numberFormatKey, value);
    _notifyChanged();
  }

  Future<bool> get rememberWallet async =>
      (await SharedPreferences.getInstance()).getBool(_rememberWalletKey) ?? true;
  Future<void> setRememberWallet(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_rememberWalletKey, value);
    _notifyChanged();
  }

  Future<String> get defaultDate async =>
      (await SharedPreferences.getInstance()).getString(_defaultDateKey) ?? 'Today';
  Future<void> setDefaultDate(String value) async {
    await (await SharedPreferences.getInstance()).setString(_defaultDateKey, value);
    _notifyChanged();
  }

  Future<bool> get deleteConfirmation async =>
      (await SharedPreferences.getInstance()).getBool(_deleteConfirmKey) ?? true;
  Future<void> setDeleteConfirmation(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_deleteConfirmKey, value);
    _notifyChanged();
  }

  Future<bool> get hideBalances async =>
      (await SharedPreferences.getInstance()).getBool(_hideBalancesKey) ?? false;
  Future<void> setHideBalances(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_hideBalancesKey, value);
    _notifyChanged();
  }

  Future<bool> get hapticFeedback async =>
      (await SharedPreferences.getInstance()).getBool(_hapticsKey) ?? true;
  Future<void> setHapticFeedback(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(_hapticsKey, value);
    _notifyChanged();
  }

  Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    for (final key in [_dateFormatKey,_weekStartKey,_numberFormatKey,_rememberWalletKey,_defaultDateKey,_deleteConfirmKey,_hideBalancesKey,_hapticsKey]) {
      await p.remove(key);
    }
    _notifyChanged();
  }
}
