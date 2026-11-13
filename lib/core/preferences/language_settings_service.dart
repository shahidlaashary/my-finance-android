import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the selected application language and notifies the root app.
class LanguageSettingsService {
  LanguageSettingsService._();
  static final LanguageSettingsService instance = LanguageSettingsService._();

  static const _key = 'app_language_code';
  final ValueNotifier<Locale> locale = ValueNotifier<Locale>(const Locale('en'));

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final code = preferences.getString(_key) ?? 'en';
    locale.value = code == 'ur' ? const Locale('ur') : const Locale('en');
  }

  Future<void> setLanguage(String languageCode) async {
    if (languageCode != 'en' && languageCode != 'ur') return;
    final previous = locale.value;
    locale.value = Locale(languageCode);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_key, languageCode);
    } catch (_) {
      locale.value = previous;
      rethrow;
    }
  }
}
