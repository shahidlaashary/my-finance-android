import 'package:flutter/material.dart';

import 'package:my_finance/app/my_finance_app.dart';
import 'package:my_finance/app/screens/main_screen.dart' show MainScreen;
import 'package:my_finance/app/screens/first_time_setup_screen.dart' show FirstTimeSetupScreen;
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/app/screens/more_features_page.dart' show MoreFeaturesPage;
import 'package:my_finance/core/startup/app_bootstrap_service.dart';

Future<void> main() async {
  await AppBootstrapService.initialize();

  final prefs = await SharedPreferences.getInstance();
  const setupCompletedKey = 'first_time_setup_completed';
  var setupCompleted = prefs.getBool(setupCompletedKey) ?? false;
  // Existing installations that already chose a header name skip onboarding.
  if (!setupCompleted && (await GeneralPreferences.instance.headerName).trim().isNotEmpty) {
    setupCompleted = true;
    await prefs.setBool(setupCompletedKey, true);
  }

  runApp(
    MyFinanceApp(
      home: setupCompleted ? const MainScreen() : const FirstTimeSetupScreen(),
      routes: {'/settings': (_) => const MoreFeaturesPage()},
    ),
  );
}
