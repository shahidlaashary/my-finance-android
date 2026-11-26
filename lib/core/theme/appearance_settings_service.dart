import 'package:flutter/material.dart';

/// App mein available theme presets ki list.
enum AppThemePreset {
  emeraldGreen,
  lightMode,
  darkMode,
  midnightGold,
}

/// Selected theme preset load, apply aur persist karta hai.
class AppearanceSettingsService {
  AppearanceSettingsService._();

  static final AppearanceSettingsService instance =
      AppearanceSettingsService._();

  Future<String?> Function(String key)? _readSetting;
  Future<void> Function(String key, String value)? _writeSetting;

  final ValueNotifier<AppThemePreset> themePreset =
      ValueNotifier<AppThemePreset>(AppThemePreset.emeraldGreen);

  /// Theme service ko settings read aur write callbacks ke sath connect karta hai.
  void configure({
    required Future<String?> Function(String key) readSetting,
    required Future<void> Function(String key, String value) writeSetting,
  }) {
    _readSetting = readSetting;
    _writeSetting = writeSetting;
  }

  /// Saved theme preset load karta hai aur purani light/dark setting ko samajhta hai.
  Future<void> load() async {
    final read = _readSetting;
    if (read == null) return;

    final savedPreset = await read('app_theme_preset');
    if (savedPreset != null) {
      themePreset.value = switch (savedPreset) {
        'lightMode' => AppThemePreset.lightMode,
        'darkMode' => AppThemePreset.darkMode,
        'midnightGold' => AppThemePreset.midnightGold,
        'emeraldGreen' => AppThemePreset.emeraldGreen,
        _ => AppThemePreset.emeraldGreen,
      };
      return;
    }

    // Upgrade ke baad user ki pehle se saved Light/Dark preference barqarar rakhta hai.
    final oldMode = await read('theme_mode');
    themePreset.value = switch (oldMode) {
      'light' => AppThemePreset.lightMode,
      'dark' => AppThemePreset.darkMode,
      _ => AppThemePreset.emeraldGreen,
    };
  }

  /// Naya theme foran apply karta hai aur configured storage mein save karta hai.
  Future<void> setThemePreset(AppThemePreset preset) async {
    final previous = themePreset.value;
    themePreset.value = preset;

    final write = _writeSetting;
    if (write == null) return;

    try {
      await write('app_theme_preset', preset.name);
    } catch (_) {
      themePreset.value = previous;
      rethrow;
    }
  }
}
