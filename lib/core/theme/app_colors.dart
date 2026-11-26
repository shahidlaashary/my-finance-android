import 'package:flutter/material.dart';
import 'package:my_finance/app/theme/app_theme.dart';

/// Purane defaults aur feature widgets ke liye theme-aware semantic colors.
/// Naye UI mein legacy constants ke bajaye AppColors.primaryOf(context) use karein.
class AppColors {
  AppColors._();

  // Purane call sites ki compatibility ke liye defaults. Naye UI mein neeche
  // diye theme-aware helpers use karein taake preset change par har section recolor ho.
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
