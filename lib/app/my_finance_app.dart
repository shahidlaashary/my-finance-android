import 'package:flutter/material.dart';

import 'package:my_finance/app/theme/app_theme.dart';
import 'package:my_finance/core/security/widgets/app_lock_gate.dart';
import 'package:my_finance/core/theme/appearance_settings_service.dart';

/// Root Material application configuration.
class MyFinanceApp extends StatelessWidget {
  const MyFinanceApp({
    super.key,
    required this.home,
    required this.routes,
  });

  final Widget home;
  final Map<String, WidgetBuilder> routes;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemePreset>(
      valueListenable: AppearanceSettingsService.instance.themePreset,
      builder: (context, preset, _) {
        return MaterialApp(
          title: 'My Finance',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.forPreset(preset),
          themeMode: ThemeMode.light,
          routes: routes,
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
          home: home,
        );
      },
    );
  }
}
