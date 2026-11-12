import 'package:flutter/material.dart';

enum AppThemePreset {
  emeraldGreen,
  lightMode,
  darkMode,
  midnightGold,
  oceanBlue,
  carbonBlack,
}

class AppearanceSettingsService {
  AppearanceSettingsService._();

  static final AppearanceSettingsService instance =
      AppearanceSettingsService._();

  Future<String?> Function(String key)? _readSetting;
  Future<void> Function(String key, String value)? _writeSetting;

  final ValueNotifier<AppThemePreset> themePreset =
      ValueNotifier<AppThemePreset>(AppThemePreset.emeraldGreen);

  void configure({
    required Future<String?> Function(String key) readSetting,
    required Future<void> Function(String key, String value) writeSetting,
  }) {
    _readSetting = readSetting;
    _writeSetting = writeSetting;
  }

  Future<void> load() async {
    final read = _readSetting;
    if (read == null) return;

    final savedPreset = await read('app_theme_preset');
    if (savedPreset != null) {
      themePreset.value = switch (savedPreset) {
        'lightMode' => AppThemePreset.lightMode,
        'darkMode' => AppThemePreset.darkMode,
        'midnightGold' => AppThemePreset.midnightGold,
        'oceanBlue' => AppThemePreset.oceanBlue,
        'carbonBlack' => AppThemePreset.carbonBlack,
        'emeraldGreen' => AppThemePreset.emeraldGreen,
        _ => AppThemePreset.emeraldGreen,
      };
      return;
    }

    // Preserve the user's previously saved Light/Dark preference on upgrade.
    final oldMode = await read('theme_mode');
    themePreset.value = switch (oldMode) {
      'light' => AppThemePreset.lightMode,
      'dark' => AppThemePreset.darkMode,
      _ => AppThemePreset.emeraldGreen,
    };
  }

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
