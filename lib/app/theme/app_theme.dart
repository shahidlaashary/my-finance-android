import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:my_finance/core/theme/appearance_settings_service.dart';

/// Semantic colors used by finance-specific widgets in addition to Material
/// ColorScheme. Read these from Theme.of(context).extension<FinanceThemeColors>().
@immutable
class FinanceThemeColors extends ThemeExtension<FinanceThemeColors> {
  final Color income;
  final Color expense;
  final Color warning;
  final Color success;
  final Color muted;
  final Color subtleSurface;
  final Color cardBorder;

  const FinanceThemeColors({
    required this.income,
    required this.expense,
    required this.warning,
    required this.success,
    required this.muted,
    required this.subtleSurface,
    required this.cardBorder,
  });

  @override
  FinanceThemeColors copyWith({
    Color? income, Color? expense, Color? warning, Color? success,
    Color? muted, Color? subtleSurface, Color? cardBorder,
  }) => FinanceThemeColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    warning: warning ?? this.warning,
    success: success ?? this.success,
    muted: muted ?? this.muted,
    subtleSurface: subtleSurface ?? this.subtleSurface,
    cardBorder: cardBorder ?? this.cardBorder,
  );

  @override
  FinanceThemeColors lerp(ThemeExtension<FinanceThemeColors>? other, double t) {
    if (other is! FinanceThemeColors) return this;
    return FinanceThemeColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      subtleSurface: Color.lerp(subtleSurface, other.subtleSurface, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
    );
  }
}

class _AppThemePalette {
  final Color primary, secondary, background, surface, surfaceContainer;
  final Color text, input, onPrimary, outline, muted;
  final Color income, expense, warning, success;
  final Brightness brightness;

  const _AppThemePalette({
    required this.primary, required this.secondary,
    required this.background, required this.surface,
    required this.surfaceContainer, required this.text,
    required this.input, required this.onPrimary, required this.outline,
    required this.muted, required this.income, required this.expense,
    required this.warning, required this.success, required this.brightness,
  });
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => forPreset(AppThemePreset.emeraldGreen);

  static ThemeData forPreset(AppThemePreset preset, {String? fontFamily}) {
    final p = switch (preset) {
      AppThemePreset.emeraldGreen => const _AppThemePalette(
        primary: Color(0xFF087A55), secondary: Color(0xFFB5DCC9),
        background: Color(0xFFF1F7F3), surface: Color(0xFFFFFFFF),
        surfaceContainer: Color(0xFFE7F1EA), text: Color(0xFF183328),
        input: Color(0xFFF6FAF7), onPrimary: Colors.white,
        outline: Color(0xFFB8CEC1), muted: Color(0xFF687A70),
        income: Color(0xFF16865B), expense: Color(0xFFD9534F),
        warning: Color(0xFFB7791F), success: Color(0xFF16865B),
        brightness: Brightness.light,
      ),
      AppThemePreset.lightMode => const _AppThemePalette(
        primary: Color(0xFF315FC4), secondary: Color(0xFFD9E4FF),
        background: Color(0xFFF3F6FC), surface: Color(0xFFFFFFFF),
        surfaceContainer: Color(0xFFE9EFF9), text: Color(0xFF202B40),
        input: Color(0xFFF8FAFE), onPrimary: Colors.white,
        outline: Color(0xFFC7D1E2), muted: Color(0xFF68758B),
        income: Color(0xFF16865B), expense: Color(0xFFD64D55),
        warning: Color(0xFFAA6A12), success: Color(0xFF16865B),
        brightness: Brightness.light,
      ),
      AppThemePreset.darkMode => const _AppThemePalette(
        primary: Color(0xFF8AB4F8), secondary: Color(0xFF354B68),
        background: Color(0xFF101419), surface: Color(0xFF1A2129),
        surfaceContainer: Color(0xFF242D37), text: Color(0xFFEAF0F6),
        input: Color(0xFF252E38), onPrimary: Color(0xFF10243D),
        outline: Color(0xFF3C4855), muted: Color(0xFFA1ADBA),
        income: Color(0xFF5DD39E), expense: Color(0xFFFF7777),
        warning: Color(0xFFF2C46D), success: Color(0xFF5DD39E),
        brightness: Brightness.dark,
      ),
      AppThemePreset.midnightGold => const _AppThemePalette(
        primary: Color(0xFFE0BC63), secondary: Color(0xFF695832),
        background: Color(0xFF0D1420), surface: Color(0xFF172231),
        surfaceContainer: Color(0xFF202D3D), text: Color(0xFFF6F1E5),
        input: Color(0xFF243141), onPrimary: Color(0xFF17130A),
        outline: Color(0xFF4B4A40), muted: Color(0xFFB7B2A5),
        income: Color(0xFF66C99B), expense: Color(0xFFFF8580),
        warning: Color(0xFFE0BC63), success: Color(0xFF66C99B),
        brightness: Brightness.dark,
      ),
    };

    final scheme = ColorScheme.fromSeed(
      seedColor: p.primary, brightness: p.brightness,
      surface: p.surface,
    ).copyWith(
      primary: p.primary, onPrimary: p.onPrimary,
      secondary: p.secondary, onSecondary: p.text,
      surface: p.surface, onSurface: p.text,
      surfaceContainer: p.surfaceContainer,
      surfaceContainerHighest: p.surfaceContainer,
      outline: p.outline, outlineVariant: p.outline.withOpacity(.55),
      error: p.expense, onError: Colors.white,
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: p.outline),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      brightness: p.brightness,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.surface,
      cardColor: p.surface,
      dividerColor: p.outline.withOpacity(.55),
      hintColor: p.muted,
      extensions: <ThemeExtension<dynamic>>[
        FinanceThemeColors(
          income: p.income, expense: p.expense, warning: p.warning,
          success: p.success, muted: p.muted,
          subtleSurface: p.surfaceContainer, cardBorder: p.outline,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface, foregroundColor: p.text,
        surfaceTintColor: Colors.transparent, elevation: 0,
        centerTitle: false, iconTheme: IconThemeData(color: p.primary),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: p.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: p.background,
          systemNavigationBarIconBrightness: p.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        ),
        titleTextStyle: TextStyle(color: p.text, fontSize: 20,
          fontWeight: FontWeight.w700, fontFamily: fontFamily),
      ),
      cardTheme: CardThemeData(
        color: p.surface, surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(p.brightness == Brightness.dark ? .16 : .045),
        elevation: p.brightness == Brightness.dark ? 0 : 1.2,
        margin: const EdgeInsets.symmetric(vertical: 5),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.outline.withOpacity(.45)),
        ),
      ),
      textTheme: Typography.material2021().black.apply(
        bodyColor: p.text, displayColor: p.text, fontFamily: fontFamily,
      ),
      iconTheme: IconThemeData(color: p.primary),
      listTileTheme: ListTileThemeData(
        iconColor: p.primary, textColor: p.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        shape: shape,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceContainer,
        selectedColor: p.primary.withOpacity(.18),
        side: BorderSide(color: p.outline.withOpacity(.65)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(color: p.text, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: p.input,
        border: border, enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: p.primary, width: 1.7),
        ),
        labelStyle: TextStyle(color: p.muted),
        hintStyle: TextStyle(color: p.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface, modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface, surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(color: p.text, fontSize: 20,
          fontWeight: FontWeight.w700, fontFamily: fontFamily),
        contentTextStyle: TextStyle(color: p.text, fontFamily: fontFamily),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface, surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: p.text, fontFamily: fontFamily),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: p.surface),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.primary.withOpacity(.14),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: p.text, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface, selectedItemColor: p.primary,
        unselectedItemColor: p.muted, type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary, unselectedLabelColor: p.muted,
        indicatorColor: p.primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? p.onPrimary : p.muted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? p.primary : p.surfaceContainer),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? p.primary : Colors.transparent),
        checkColor: WidgetStatePropertyAll(p.onPrimary),
        side: BorderSide(color: p.outline),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStatePropertyAll(p.primary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary, foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.surfaceContainer,
          disabledForegroundColor: p.muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          minimumSize: const Size(0, 46),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary, foregroundColor: p.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          minimumSize: const Size(0, 46),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary, minimumSize: const Size(0, 46),
          side: BorderSide(color: p.primary.withOpacity(.45)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.primary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary, foregroundColor: p.onPrimary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceContainer, contentTextStyle: TextStyle(color: p.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary, linearTrackColor: p.surfaceContainer,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.text, borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(color: p.surface),
      ),
      dividerTheme: DividerThemeData(color: p.outline.withOpacity(.55), thickness: 1),

    );
  }
}
