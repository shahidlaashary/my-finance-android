
import 'package:flutter/foundation.dart';

import 'transactions_service.dart';
import 'recurring_transaction_service.dart';

class AppStartupService {
  AppStartupService._();

  static bool _initialized = false;
  static Future<void>? _initializationFuture;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (_initializationFuture != null) {
      return _initializationFuture!;
    }

    _initializationFuture = _initializeServices();

    try {
      await _initializationFuture;
      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('App startup initialization error: $error');
      debugPrintStack(stackTrace: stackTrace);

      rethrow;
    } finally {
      _initializationFuture = null;
    }
  }

  static Future<void> _initializeServices() async {
    // Initialize the transaction database and required category schema.
    await TransactionsService.database;

    // Process recurring transactions that are due.
    // Any processing error is logged so it can be investigated.
    try {
      final recurringService = RecurringTransactionService();

      final processedCount =
          await recurringService.processDueTransactions();

      debugPrint(
        'Recurring transactions processed: $processedCount',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Recurring transaction processing error: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
