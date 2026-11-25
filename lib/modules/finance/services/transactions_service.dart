import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

class TransactionsService {

  static Future<void> _changeBalance(Transaction txn, int walletId, double change) async {
    final changed = await txn.rawUpdate(
      'UPDATE wallets SET balance = balance + ? WHERE id = ?',
      [change, walletId],
    );
    if (changed == 0) throw Exception('Wallet not found: $walletId');
  }

  // Edit ya delete se pehle purani transaction ka balance impact reverse karta hai.
  static Future<void> _reverse(Transaction txn, Map<String, dynamic> row) async {
    final rawType = row['type'].toString().trim().toLowerCase();
    final amount = (row['amount'] as num).toDouble();
    final walletId = (row['wallet_id'] as num).toInt();
    final toWalletId = (row['to_wallet_id'] as num?)?.toInt();
    final feeRows = await txn.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['transaction_transfer_fee_${row['id']}'],
      limit: 1,
    );
    final transferFee = feeRows.isEmpty
        ? 0.0
        : (double.tryParse(feeRows.first['setting_value']?.toString() ?? '') ?? 0.0);
    if (rawType == 'adjustment') {
      final delta = (row['balance_delta'] as num?)?.toDouble();
      if (delta == null) throw Exception('Adjustment balance change is missing.');
      await _changeBalance(txn, walletId, -delta);
      return;
    }
    final type = _normalizeType(rawType);
    if (type == 'Income') {
      await _changeBalance(txn, walletId, -amount);
    } else if (type == 'Expense') {
      await _changeBalance(txn, walletId, amount);
    } else if (type == 'Transfer') {
      if (toWalletId == null && row['category']?.toString() == 'Committee Transfer') {
        final delta = (row['balance_delta'] as num?)?.toDouble();
        if (delta == null || delta == 0) throw Exception('Committee transfer balance change is missing.');
        await _changeBalance(txn, walletId, -delta);
        return;
      }
      if (toWalletId == null) throw Exception('Transfer destination is missing.');
      final destinationAmount = (row['to_amount'] as num?)?.toDouble() ?? amount;
      await _changeBalance(txn, walletId, amount + transferFee);
      await _changeBalance(txn, toWalletId, -destinationAmount);
    }
  }

  // Nayi transaction validate karke wallet balances ko database transaction mein update karta hai.
  static Future<void> _apply(
    Transaction txn, {
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    double? toAmount,
    double transferFee = 0,
  }) async {
    if (!amount.isFinite || amount <= 0) throw Exception('Amount must be greater than zero.');
    if (!transferFee.isFinite || transferFee < 0 ||
        (type != 'Transfer' && transferFee > 0)) {
      throw Exception('Invalid transfer fee.');
    }
    final wallets = await txn.query(
      'wallets',
      where: 'id = ? OR id = ?',
      whereArgs: [walletId, toWalletId ?? -1],
    );
    final sourceRows = wallets.where((w) => w['id'] == walletId).toList();
    if (sourceRows.isEmpty) throw Exception('Selected wallet was not found.');
    final source = sourceRows.first;
    if (type == 'Income') {
      await _changeBalance(txn, walletId, amount);
      return;
    }
    if (type == 'Expense') {
      if ((source['balance'] as num).toDouble() < amount) throw Exception('Insufficient wallet balance.');
      await _changeBalance(txn, walletId, -amount);
      return;
    }
    if (toWalletId == null || toWalletId == walletId) throw Exception('Select a different destination wallet.');
    final destRows = wallets.where((w) => w['id'] == toWalletId).toList();
    if (destRows.isEmpty) throw Exception('Destination wallet was not found.');
    final destination = destRows.first;
    final received = toAmount ?? amount;
    if (!received.isFinite || received <= 0) throw Exception('Enter a valid destination amount.');

    // Aik currency ke wallets mein transfer amount dono taraf barabar rehni chahiye.
    // Mukhtalif currencies hon to user ka diya hua received amount aur exchange rate use hota hai.
    final sourceCurrency = (source['currency'] ?? 'PKR').toString().toUpperCase();
    final destinationCurrency = (destination['currency'] ?? 'PKR').toString().toUpperCase();
    if (sourceCurrency == destinationCurrency && received != amount) {
      throw Exception('Same-currency transfers must use the same sent and received amount.');
    }

    if ((source['balance'] as num).toDouble() < amount + transferFee) throw Exception('Insufficient wallet balance.');
    await _changeBalance(txn, walletId, -(amount + transferFee));
    await _changeBalance(txn, toWalletId, received);
  }

  static Future<int> addTransaction({
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    double? toAmount,
    double? exchangeRate,
    String? category,
    required String note,
    required String date,
    double transferFee = 0,
  }) async {
    final db = await database;
    final normalized = _normalizeType(type);
    final transactionId = await db.transaction((txn) async {
      await _apply(txn, type: normalized, amount: amount, walletId: walletId,
        toWalletId: normalized == 'Transfer' ? toWalletId : null, toAmount: toAmount,
        transferFee: transferFee);
      final now = DateTime.now().toIso8601String();
      final transactionId = await txn.insert('transactions', {
        'type': normalized,
        'amount': amount,
        'wallet_id': walletId,
        'to_wallet_id': normalized == 'Transfer' ? toWalletId : null,
        'to_amount': normalized == 'Transfer' ? (toAmount ?? amount) : null,
        'exchange_rate': normalized == 'Transfer' ? (exchangeRate ?? ((toAmount ?? amount) / amount)) : null,
        'balance_delta': null,
        'category': normalized == 'Transfer' ? '' : (category ?? ''),
        'note': note,
        'date': date,
        'created_at': now,
      });
      if (normalized == 'Transfer' && transferFee > 0) {
        await txn.insert('app_settings', {
          'setting_key': 'transaction_transfer_fee_$transactionId',
          'setting_value': transferFee.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return transactionId;
    });
    AppRefreshController.notifyChanged();
    return transactionId;
  }

  static Future<void> updateTransaction({
    required int id,
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    double? toAmount,
    double? exchangeRate,
    String? category,
    required String note,
    required String date,
    double? transferFee,
  }) async {
    final db = await database;
    final normalized = _normalizeType(type);
    await db.transaction((txn) async {
      final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw Exception('Transaction not found.');
      if (rows.first['category']?.toString() == 'Committee Transfer') {
        throw Exception('Manage this transfer from the Committee module.');
      }
      final oldFeeRows = await txn.query('app_settings', columns: ['setting_value'],
        where: 'setting_key = ?', whereArgs: ['transaction_transfer_fee_$id'], limit: 1);
      final oldFee = oldFeeRows.isEmpty ? 0.0 :
        (double.tryParse(oldFeeRows.first['setting_value']?.toString() ?? '') ?? 0.0);
      final effectiveFee = normalized == 'Transfer' ? (transferFee ?? oldFee) : 0.0;
      await _reverse(txn, rows.first);
      await _apply(txn, type: normalized, amount: amount, walletId: walletId,
        toWalletId: normalized == 'Transfer' ? toWalletId : null, toAmount: toAmount,
        transferFee: effectiveFee);
      await txn.update('transactions', {
        'type': normalized,
        'amount': amount,
        'wallet_id': walletId,
        'to_wallet_id': normalized == 'Transfer' ? toWalletId : null,
        'to_amount': normalized == 'Transfer' ? (toAmount ?? amount) : null,
        'exchange_rate': normalized == 'Transfer' ? (exchangeRate ?? ((toAmount ?? amount) / amount)) : null,
        'category': normalized == 'Transfer' ? '' : (category ?? ''),
        'note': note,
        'date': date,
      }, where: 'id = ?', whereArgs: [id]);
      if (effectiveFee > 0) {
        await txn.insert('app_settings', {
          'setting_key': 'transaction_transfer_fee_$id',
          'setting_value': effectiveFee.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await txn.delete('app_settings', where: 'setting_key = ?',
          whereArgs: ['transaction_transfer_fee_$id']);
      }
    });
    AppRefreshController.notifyChanged();
  }

  static Future<void> updateAdjustmentTransaction({
    required int id,
    required double balanceDelta,
    required String note,
    required String date,
  }) async {
    if (!balanceDelta.isFinite || balanceDelta == 0) {
      throw Exception('Balance change must be a non-zero amount.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: "id = ? AND LOWER(type) = 'adjustment'",
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw Exception('Adjustment transaction not found.');
      final row = rows.first;
      final walletId = (row['wallet_id'] as num).toInt();
      final oldDelta = (row['balance_delta'] as num?)?.toDouble();
      if (oldDelta == null) throw Exception('Adjustment balance change is missing.');
      await _changeBalance(txn, walletId, -oldDelta);
      await _changeBalance(txn, walletId, balanceDelta);
      await txn.update('transactions', {
        'amount': balanceDelta.abs(),
        'balance_delta': balanceDelta,
        'note': note,
        'date': date,
      }, where: 'id = ?', whereArgs: [id]);
    });
    AppRefreshController.notifyChanged();
  }

  static Future<void> deleteTransaction(int id) async {
    final db = await database;
    final existing = await db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isEmpty) throw Exception('Transaction not found.');
    if (existing.first['category']?.toString() == 'Committee Transfer') {
      throw Exception('Manage this transfer from the Committee module.');
    }
    final feeRows = await db.query('app_settings', columns: ['setting_value'],
      where: 'setting_key = ?', whereArgs: ['transaction_transfer_fee_$id'], limit: 1);
    final fee = feeRows.isEmpty ? 0.0 :
      (double.tryParse(feeRows.first['setting_value']?.toString() ?? '') ?? 0.0);
    final archived = Map<String, dynamic>.from(existing.first)..['_transfer_fee'] = fee;
    final recycleId = await RecycleBinService.archive(type: 'Transaction',
      title: '${existing.first['type']} • ${existing.first['amount']}',
      table: 'transactions', id: id, record: archived);
    try {
      await db.transaction((txn) async {
        final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) return;
        await _reverse(txn, rows.first);
        await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
        await txn.delete('app_settings', where: 'setting_key = ?',
          whereArgs: ['transaction_transfer_fee_$id']);
      });
    } catch (_) {
      await RecycleBinService.discardArchive(recycleId);
      rethrow;
    }
    AppRefreshController.notifyChanged();
  }


  static Future<List<Map<String, dynamic>>> getTransactions({int? walletId}) async {
    final db = await database;
    final walletFilter = walletId == null ? '' : 'WHERE t.wallet_id = ? OR t.to_wallet_id = ?';
    final args = walletId == null ? <Object>[] : <Object>[walletId, walletId];
    return db.rawQuery("""
      SELECT t.*, t.category AS category_name,
        source.currency AS wallet_currency,
        COALESCE((SELECT CAST(s.setting_value AS REAL)
          FROM app_settings s
          WHERE s.setting_key = 'transaction_transfer_fee_' || t.id
          LIMIT 1), 0) AS transfer_fee
      FROM transactions t
      LEFT JOIN wallets AS source ON source.id = t.wallet_id
      $walletFilter
      ORDER BY t.date DESC, t.id DESC
    """, args);
  }

  static Future<List<Map<String, dynamic>>> getWallets() async {
    final db = await database;
    return db.query('wallets', columns: ['id', 'name', 'currency', 'balance'],
      orderBy: 'name COLLATE NOCASE ASC');
  }
}
