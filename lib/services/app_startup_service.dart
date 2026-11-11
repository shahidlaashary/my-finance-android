
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
    // Transaction database aur zaroori category structure ko tayyar karta hai.
    await TransactionsService.database;

    // Jin recurring transactions ki date aa chuki ho unhein process karta hai.
    // Kisi bhi error ko log karta hai taake baad mein uski jaanch ho sake.
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
