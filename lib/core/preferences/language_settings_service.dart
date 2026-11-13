import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the selected application language and notifies the root app.
class LanguageSettingsService {
  LanguageSettingsService._();
  static final LanguageSettingsService instance = LanguageSettingsService._();

  static const _key = 'app_language_code';
  static const supportedLanguageCodes = <String>{
    'en', 'ur', 'ar', 'hi', 'pa', 'skr', 'sd', 'bal', 'ps',
  };

  final ValueNotifier<Locale> locale = ValueNotifier<Locale>(const Locale('en'));

  bool get isRightToLeft => const {'ur', 'ar', 'pa', 'skr', 'sd', 'bal', 'ps'}
      .contains(locale.value.languageCode);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final code = preferences.getString(_key) ?? 'en';
    locale.value = Locale(
      supportedLanguageCodes.contains(code) ? code : 'en',
    );
  }

  Future<void> setLanguage(String languageCode) async {
    if (!supportedLanguageCodes.contains(languageCode)) return;
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
