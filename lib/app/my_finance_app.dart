import 'package:flutter/material.dart';

import 'package:my_finance/app/screens/more_features_screen.dart'
    show MoreFeaturesPage;
import 'package:my_finance/app/theme/app_theme.dart';
import 'package:my_finance/core/security/widgets/app_lock_gate.dart';

/// Root Material application configuration.
///
/// The home screen is injected by the entrypoint to keep app composition
/// separate from feature and navigation implementation details.
class MyFinanceApp extends StatelessWidget {
  const MyFinanceApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Finance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routes: {
        '/settings': (_) => const MoreFeaturesPage(),
      },
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
      home: home,
    );
  }
}
