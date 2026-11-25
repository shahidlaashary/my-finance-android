import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

extension FinanceTransactionOperations on FinanceDB {
  // Transaction save karna aur linked wallet ka balance update karna.
  Future<int> addTransaction({
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    double? toAmount,
    double? exchangeRate,
    String category = '',
    String note = '',
    DateTime? date,
    double transferFee = 0,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount zero se zyada hona chahiye.');
    }
    if (!transferFee.isFinite || transferFee < 0 ||
        (type != 'Transfer' && transferFee > 0)) {
      throw Exception('Transfer fee durust nahi hai.');
    }

    final transactionDate = date ?? DateTime.now();
    final now = DateTime.now().toIso8601String();

    final transactionId = await db.transaction((txn) async {
      final sourceRows = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
        limit: 1,
      );

      if (sourceRows.isEmpty) {
        throw Exception('Selected wallet nahi mila.');
      }

      final source = sourceRows.first;
      final sourceBalance = (source['balance'] as num).toDouble();

      final totalSourceDeduction = amount + (type == 'Transfer' ? transferFee : 0);
      if (type == 'Expense' || type == 'Transfer') {
        if (sourceBalance < totalSourceDeduction) {
          throw Exception('Wallet mein itna balance available nahi hai.');
        }
      }

      double? finalToAmount;
      double? finalRate;

      if (type == 'Transfer') {
        if (toWalletId == null || toWalletId == walletId) {
          throw Exception('Do different wallets select karein.');
        }

        final destinationRows = await txn.query(
          'wallets',
          where: 'id = ?',
          whereArgs: [toWalletId],
          limit: 1,
        );

        if (destinationRows.isEmpty) {
          throw Exception('Destination wallet nahi mila.');
        }

        final destination = destinationRows.first;
        final sourceCurrency = source['currency'] as String;
        final destinationCurrency = destination['currency'] as String;

        if (sourceCurrency == destinationCurrency) {
          finalToAmount = amount;
          finalRate = 1;
        } else {
          if (toAmount == null || toAmount <= 0) {
            throw Exception(
              'Different currencies ke transfer ke liye '
              'destination amount enter karein.',
            );
          }

          finalToAmount = toAmount;
          finalRate = finalToAmount / amount;
        }

        final destinationBalance =
            (destination['balance'] as num).toDouble();

        // Dono wallets ke balances aik hi database transaction mein update hote hain.
        await txn.update(
          'wallets',
          {'balance': sourceBalance - totalSourceDeduction},
          where: 'id = ?',
          whereArgs: [walletId],
        );

        await txn.update(
          'wallets',
          {'balance': destinationBalance + finalToAmount},
          where: 'id = ?',
          whereArgs: [toWalletId],
        );
      } else if (type == 'Income') {
        await txn.update(
          'wallets',
          {'balance': sourceBalance + amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      } else if (type == 'Expense') {
        await txn.update(
          'wallets',
          {'balance': sourceBalance - amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      } else {
        throw Exception('Transaction type valid nahi hai.');
      }

      final transactionId = await txn.insert('transactions', {
        'type': type,
        'amount': amount,
        'wallet_id': walletId,
        'to_wallet_id': toWalletId,
        'to_amount': finalToAmount,
        'exchange_rate': finalRate,
        'balance_delta': null,
        'category': category,
        'note': note,
        'date': transactionDate.toIso8601String(),
        'created_at': now,
      });

      if (type == 'Transfer' && transferFee > 0) {
        await txn.insert(
          'app_settings',
          {
            'setting_key': 'transaction_transfer_fee_$transactionId',
            'setting_value': transferFee.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      return transactionId;
    });
    AppRefreshController.notifyChanged();
    return transactionId;
  }
}
