import 'package:flutter/material.dart';

import 'package:my_finance/app/my_finance_app.dart';
import 'package:my_finance/app/screens/main_screen.dart' show MainScreen;
import 'package:my_finance/app/screens/more_features_page.dart' show MoreFeaturesPage;
import 'package:my_finance/core/startup/app_bootstrap_service.dart';

Future<void> main() async {
  await AppBootstrapService.initialize();

  runApp(
    MyFinanceApp(
      home: const MainScreen(),
      routes: {'/settings': (_) => const MoreFeaturesPage()},
    ),
  );
}
