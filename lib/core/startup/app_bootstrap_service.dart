import 'package:flutter/widgets.dart';

import 'package:my_finance/core/database/database_platform.dart';
import 'package:my_finance/core/database/finance_database.dart';

/// Prepares Flutter and the database platform before the app is launched.
class AppBootstrapService {
  AppBootstrapService._();

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDatabasePlatform();
    await FinanceDB.instance.init();
  }
}
