import 'package:flutter/material.dart';
import 'package:my_finance/app/theme/app_theme.dart';

/// Legacy defaults plus theme-aware semantic colors for feature widgets.
/// Prefer AppColors.primaryOf(context) over the legacy static constants.
class AppColors {
  AppColors._();

  // Backward-compatible defaults for older call sites. New UI should use the
  // theme-aware helpers below so changing the preset recolors every section.
  static const Color primary = Color(0xFF087A55);
  static const Color background = Color(0xFFF1F7F3);
  static const Color income = Color(0xFF16865B);
  static const Color expense = Color(0xFFD9534F);
  static const Color text = Color(0xFF183328);
  static const Color muted = Color(0xFF687A70);

  static Color primaryOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
  static Color backgroundOf(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;
  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color textOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color mutedOf(BuildContext context) =>
      Theme.of(context).extension<FinanceThemeColors>()?.muted ??
      Theme.of(context).hintColor;
  static Color incomeOf(BuildContext context) =>
      Theme.of(context).extension<FinanceThemeColors>()?.income ??
      Theme.of(context).colorScheme.primary;
  static Color expenseOf(BuildContext context) =>
      Theme.of(context).extension<FinanceThemeColors>()?.expense ??
      Theme.of(context).colorScheme.error;
  static Color warningOf(BuildContext context) =>
      Theme.of(context).extension<FinanceThemeColors>()?.warning ??
      Theme.of(context).colorScheme.tertiary;
}
