import 'package:flutter/material.dart';

import 'package:my_finance/app/theme/app_theme.dart';
import 'package:my_finance/core/security/widgets/app_lock_gate.dart';

/// Root Material application configuration.
///
/// Feature routes and the home screen are injected by the entrypoint so this
/// app layer does not depend on screen implementations in main.dart.
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
    return MaterialApp(
      title: 'My Finance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routes: routes,
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
      home: home,
    );
  }
}
