
import 'package:flutter/foundation.dart';

import 'package:my_finance/modules/finance/services/recurring_transaction_service.dart';

/// Ye service app start par zaroori background startup tasks chalati hai.
class AppStartupService {
  AppStartupService._();

  static bool _initialized = false;
  static Future<void>? _initializationFuture;

  /// Startup initialization ko duplicate calls se bachate hue aik martaba chalata hai.
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

  /// Due recurring transactions ko process karta hai; errors log karta hai.
  static Future<void> _initializeServices() async {
    // FinanceDB initialization is completed by AppBootstrapService before
    // startup services run. RecurringTransactionService owns its own queries.

    // Jin recurring transactions ki date aa chuki ho unhein process karta hai.
    // Kisi bhi error ko log karta hai taake baad mein uski jaanch ho sake.
    try {
      final recurringService = RecurringTransactionService();

      final processedCount =
          await recurringService.processDueTransactions();

      debugPrint(
        'Recurring transactions processed: $processedCount',
      );
      for (final error in recurringService.lastProcessingErrors) {
        debugPrint('Recurring schedule paused: $error');
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Recurring transaction processing error: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
