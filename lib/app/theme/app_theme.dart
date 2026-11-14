import 'package:flutter/material.dart';

import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/core/theme/appearance_settings_service.dart';

class _AppThemePalette {
  final Color primary;
  final Color background;
  final Color surface;
  final Color text;
  final Color input;
  final Color onPrimary;
  final Brightness brightness;

  const _AppThemePalette({
    required this.primary,
    required this.background,
    required this.surface,
    required this.text,
    required this.input,
    required this.onPrimary,
    required this.brightness,
  });
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => forPreset(AppThemePreset.emeraldGreen);

  static ThemeData forPreset(
    AppThemePreset preset, {
    String? fontFamily,
  }) {
    final palette = switch (preset) {
      AppThemePreset.emeraldGreen => const _AppThemePalette(
          primary: Color(0xFF147D59),
          background: Color(0xFFF0F6F2),
          surface: Color(0xFFFFFFFF),
          text: Color(0xFF183328),
          input: Color(0xFFF6FAF7),
          onPrimary: Colors.white,
          brightness: Brightness.light,
        ),
      AppThemePreset.lightMode => const _AppThemePalette(
          primary: Color(0xFF4268C7),
          background: Color(0xFFF3F5FB),
          surface: Color(0xFFFFFFFF),
          text: Color(0xFF20283A),
          input: Color(0xFFF7F8FC),
          onPrimary: Colors.white,
          brightness: Brightness.light,
        ),
      AppThemePreset.darkMode => const _AppThemePalette(
          primary: Color(0xFF8AB4F8),
          background: Color(0xFF121519),
          surface: Color(0xFF1D232A),
          text: Color(0xFFF1F3F5),
          input: Color(0xFF272E36),
          onPrimary: Color(0xFF10243D),
          brightness: Brightness.dark,
        ),
      AppThemePreset.midnightGold => const _AppThemePalette(
          primary: Color(0xFFE0BC63),
          background: Color(0xFF101722),
          surface: Color(0xFF192433),
          text: Color(0xFFF6F1E5),
          input: Color(0xFF243141),
          onPrimary: Color(0xFF17130A),
          brightness: Brightness.dark,
        ),
      AppThemePreset.oceanBlue => const _AppThemePalette(
          primary: Color(0xFF176FAE),
          background: Color(0xFFEDF4F9),
          surface: Color(0xFFFFFFFF),
          text: Color(0xFF173247),
          input: Color(0xFFF4F8FC),
          onPrimary: Colors.white,
          brightness: Brightness.light,
        ),
      AppThemePreset.carbonBlack => const _AppThemePalette(
          primary: Color(0xFFFFA34D),
          background: Color(0xFF101010),
          surface: Color(0xFF1D1D1D),
          text: Color(0xFFF2F2F2),
          input: Color(0xFF292929),
          onPrimary: Color(0xFF201307),
          brightness: Brightness.dark,
        ),
    };

    final scheme = ColorScheme.fromSeed(
      seedColor: palette.primary,
      brightness: palette.brightness,
    ).copyWith(
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      surface: palette.surface,
      onSurface: palette.text,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      brightness: palette.brightness,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.surface,
      cardColor: palette.surface,
      dividerColor: palette.text.withOpacity(0.10),
      hintColor: palette.text.withOpacity(0.58),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.text.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.onPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
      ),
    );
  }
}
