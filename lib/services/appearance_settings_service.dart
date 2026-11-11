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

  /// The selected visual theme for the whole application.
  final ValueNotifier<AppThemePreset> themePreset =
      ValueNotifier<AppThemePreset>(AppThemePreset.emeraldGreen);

  void configure({
    required Future<String?> Function(String key) readSetting,
    required Future<void> Function(String key, String value) writeSetting,
  }) {
    _readSetting = readSetting;
    _writeSetting = writeSetting;
  }

  /// Loads the saved theme from the existing app_settings table.
  Future<void> load() async {
    final read = _readSetting;
    if (read == null) return;

    final savedTheme = await read('app_theme_preset');
    themePreset.value = switch (savedTheme) {
      'lightMode' => AppThemePreset.lightMode,
      'darkMode' => AppThemePreset.darkMode,
      'midnightGold' => AppThemePreset.midnightGold,
      'oceanBlue' => AppThemePreset.oceanBlue,
      'carbonBlack' => AppThemePreset.carbonBlack,
      'emeraldGreen' => AppThemePreset.emeraldGreen,
      _ => AppThemePreset.emeraldGreen,
    };
  }

  /// Applies and persists the selected theme without changing finance data.
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
