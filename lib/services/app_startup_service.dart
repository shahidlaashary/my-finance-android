
import 'package:flutter/foundation.dart';

import 'transaction_service.dart';
import 'recurring_transaction_service.dart';

class AppStartupService {
  AppStartupService._();

  static Future<void> initialize() async {
    // Ensure category table and transaction category column exist.
    await TransactionService.database;

    // Process due recurring transactions without blocking app startup
    // if an individual recurring transaction encounters an error.
    try {
      final recurringService = RecurringTransactionService();

      final processedCount =
          await recurringService.processDueTransactions();

      debugPrint(
        'Recurring transactions processed: $processedCount',
      );
    } catch (error, stackTrace) {
      debugPrint('Recurring transaction startup error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
