import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:my_finance/core/preferences/language_settings_service.dart';

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
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageSettingsService.instance.locale,
      builder: (context, locale, _) => ValueListenableBuilder<AppThemePreset>(
        valueListenable: AppearanceSettingsService.instance.themePreset,
        builder: (context, preset, _) {
          final isUrduScript = const {'ur', 'pa', 'skr', 'sd'}
              .contains(locale.languageCode);
          return MaterialApp(
            title: 'My Finance',
            locale: locale.languageCode == 'pa'
                ? const Locale.fromSubtags(languageCode: 'pa', scriptCode: 'Arab')
                : locale,
            supportedLocales: const [
              Locale('en'),
              Locale('ur'),
              Locale('ar'),
              Locale('hi'),
              Locale.fromSubtags(languageCode: 'pa', scriptCode: 'Arab'),
              Locale('skr'),
              Locale('sd'),
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.forPreset(
              preset,
              fontFamily: isUrduScript ? 'JameelNooriNastaleeq' : null,
            ),
            themeMode: ThemeMode.light,
            routes: routes,
            builder: (context, child) => Directionality(
              textDirection: const {'ur', 'ar', 'pa', 'skr', 'sd'}
                      .contains(locale.languageCode)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: AppLockGate(child: child ?? const SizedBox.shrink()),
            ),
            home: home,
          );
        },
      ),
    );
  }
}
