import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Selected app language save karta hai aur localization aur voice settings
/// ke liye mushtarka language catalogue provide karta hai.
class LanguageSettingsService {
  LanguageSettingsService._();
  static final LanguageSettingsService instance = LanguageSettingsService._();

  static const languageNames = <String, String>{
    'en': 'English',
    'ur': 'اردو',
    'ar': 'العربية',
    'hi': 'हिन्दी',
    'pa': 'پنجابی',
    'skr': 'سرائیکی',
    'sd': 'سنڌي',
    'bal': 'بلوچی',
    'ps': 'پښتو',
  };

  static final supportedLanguageCodes = languageNames.keys.toSet();

  static const _key = 'app_language_code';

  final ValueNotifier<Locale> locale = ValueNotifier<Locale>(const Locale('en'));

  bool get isRightToLeft => const {'ur', 'ar', 'pa', 'skr', 'sd', 'bal', 'ps'}
      .contains(locale.value.languageCode);

  /// Saved language code load karke active locale set karta hai.
  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final code = preferences.getString(_key) ?? 'en';
    locale.value = Locale(
      supportedLanguageCodes.contains(code) ? code : 'en',
    );
  }

  /// Supported language set karta hai; save fail ho to pehli locale restore karta hai.
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
