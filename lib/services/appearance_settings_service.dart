
import 'package:flutter/material.dart';

class AppearanceSettingsService {
  AppearanceSettingsService._();

  static final AppearanceSettingsService instance =
      AppearanceSettingsService._();

  Future<String?> Function(String key)? _readSetting;
  Future<void> Function(String key, String value)? _writeSetting;

  // Theme Mode
  final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  // Color Theme
  final ValueNotifier<String> colorTheme =
      ValueNotifier<String>('Green');

  void configure({
    required Future<String?> Function(String key) readSetting,
    required Future<void> Function(String key, String value) writeSetting,
  }) {
    _readSetting = readSetting;
    _writeSetting = writeSetting;
  }

  // Load saved appearance settings
  Future<void> load() async {
    final read = _readSetting;
    if (read == null) return;

    final savedMode = await read('theme_mode');
    final savedColor = await read('color_theme');

    switch (savedMode) {
      case 'light':
        themeMode.value = ThemeMode.light;
        break;
      case 'dark':
        themeMode.value = ThemeMode.dark;
        break;
      default:
        themeMode.value = ThemeMode.system;
    }

    const availableColors = [
      'Green',
      'Blue',
      'Purple',
      'Teal',
      'Orange',
      'Red',
    ];

    if (savedColor != null &&
        availableColors.contains(savedColor)) {
      colorTheme.value = savedColor;
    }
  }

  // Save Theme Mode
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

  // Save Color Theme
  Future<void> setColorTheme(String color) async {
    const availableColors = [
      'Green',
      'Blue',
      'Purple',
      'Teal',
      'Orange',
      'Red',
    ];

    if (!availableColors.contains(color)) return;

    colorTheme.value = color;

    final write = _writeSetting;
    if (write != null) {
      await write('color_theme', color);
    }
  }

  // Selected Theme Color
  Color get seedColor {
    switch (colorTheme.value) {
      case 'Blue':
        return const Color(0xFF2563EB);

      case 'Purple':
        return const Color(0xFF7C3AED);

      case 'Teal':
        return const Color(0xFF0F766E);

      case 'Orange':
        return const Color(0xFFEA580C);

      case 'Red':
        return const Color(0xFFDC2626);

      case 'Green':
      default:
        return const Color(0xFF147D59);
    }
  }
}
