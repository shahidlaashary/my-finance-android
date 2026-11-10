import 'package:flutter/material.dart';

class AppearanceSettingsService {
  AppearanceSettingsService._();

  static final AppearanceSettingsService instance =
      AppearanceSettingsService._();

  Future<String?> Function(String key)? _readSetting;
  Future<void> Function(String key, String value)? _writeSetting;

  /// Available theme modes: System, Light and Dark.
  final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  void configure({
    required Future<String?> Function(String key) readSetting,
    required Future<void> Function(String key, String value) writeSetting,
  }) {
    _readSetting = readSetting;
    _writeSetting = writeSetting;
  }

  /// Load the saved theme mode.
  Future<void> load() async {
    final read = _readSetting;
    if (read == null) return;

    final savedMode = await read('theme_mode');

    switch (savedMode) {
      case 'light':
        themeMode.value = ThemeMode.light;
        break;

      case 'dark':
        themeMode.value = ThemeMode.dark;
        break;

      case 'system':
      default:
        themeMode.value = ThemeMode.system;
        break;
    }
  }

  /// Save the selected theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;

    final write = _writeSetting;
    if (write == null) return;

    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    await write('theme_mode', value);
  }
}
