import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/services/recycle_bin_archive_service.dart';
import 'package:my_finance/modules/staff/services/staff_service.dart';

class TransactionsService {
  /// Inserts a ledger row inside the caller's database transaction.
  /// Module services may coordinate their own records while ledger writes
  /// remain centralized here; the caller retains atomic transaction control.
  static Future<int> insertLedgerEntry(
    Transaction txn,
    Map<String, Object?> entry,
  ) async {
    return txn.insert('transactions', entry);
  }

  /// Applies a wallet balance change through the central finance service.
  static Future<void> applyWalletBalanceDelta(
    Transaction txn, {
    required int walletId,
    required double delta,
  }) async {
    if (!delta.isFinite) throw Exception('Invalid wallet balance change.');
    final rows = await txn.query('wallets', columns: ['balance'],
      where: 'id = ?', whereArgs: [walletId], limit: 1);
    if (rows.isEmpty) throw Exception('Wallet not found: $walletId');
    final balance = (rows.first['balance'] as num).toDouble();
    if (delta < 0 && balance + delta < -0.000001) {
      throw Exception('Insufficient wallet balance.');
    }
    await _changeBalance(txn, walletId, delta);
  }

  /// Creates a module-owned ledger row and applies wallet effects atomically.
  static Future<int> createModuleLedgerEntry(
    Transaction txn, {
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    double? toAmount,
    double transferFee = 0,
    String? category,
    required String note,
    required String date,
  }) async {
    final normalized = _normalizeType(type);
    await _apply(txn, type: normalized, amount: amount, walletId: walletId,
      toWalletId: normalized == 'Transfer' ? toWalletId : null,
      toAmount: toAmount, transferFee: transferFee);
    final id = await insertLedgerEntry(txn, {
      'type': normalized, 'amount': amount, 'wallet_id': walletId,
      'to_wallet_id': normalized == 'Transfer' ? toWalletId : null,
      'to_amount': normalized == 'Transfer' ? (toAmount ?? amount) : null,
      'exchange_rate': normalized == 'Transfer' ? ((toAmount ?? amount) / amount) : null,
      'balance_delta': null,
      'category': normalized == 'Transfer' ? '' : (category ?? ''),
      'note': note, 'date': date,
      'created_at': DateTime.now().toIso8601String(),
    });
    if (normalized == 'Transfer' && transferFee > 0) {
      await txn.insert('app_settings', {
        'setting_key': 'transaction_transfer_fee_$id',
        'setting_value': transferFee.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return id;
  }

  /// Reverses and removes module-owned ledger rows inside the caller transaction.
  static Future<void> deleteModuleLedgerEntries(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final archived in rows) {
      final row = Map<String, dynamic>.from(archived);
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      await _reverse(txn, row);
      await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
      await txn.delete('app_settings', where: 'setting_key = ?',
        whereArgs: ['transaction_transfer_fee_$id']);
    }
  }

  /// Restores module-owned ledger rows and wallet effects atomically.
  static Future<void> restoreModuleLedgerEntries(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final archived in rows) {
      final row = Map<String, dynamic>.from(archived);
      row.remove('_related_table');
      final id = (row['id'] as num?)?.toInt();
      if (id == null) throw Exception('Archived transaction ID is missing.');
      final fee = (row.remove('_transfer_fee') as num?)?.toDouble() ?? 0.0;
      final type = _normalizeType(row['type']?.toString() ?? '');
      await _apply(txn, type: type, amount: (row['amount'] as num).toDouble(),
        walletId: (row['wallet_id'] as num).toInt(),
        toWalletId: (row['to_wallet_id'] as num?)?.toInt(),
        toAmount: (row['to_amount'] as num?)?.toDouble(), transferFee: fee);
      await txn.insert('transactions', row);
      if (fee > 0) {
        await txn.insert('app_settings', {
          'setting_key': 'transaction_transfer_fee_$id',
          'setting_value': fee.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  /// Checks whether the transaction ledger contains entries for a wallet.
  static Future<bool> hasWalletReferences(
    DatabaseExecutor db,
    int walletId,
  ) async {
    final rows = await db.query(
      'transactions',
      columns: ['id'],
      where: 'wallet_id = ? OR to_wallet_id = ?',
      whereArgs: [walletId, walletId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Adds a wallet balance adjustment to the transaction ledger.
  static Future<void> addWalletBalanceAdjustment(
    Transaction txn, {
    required int walletId,
    required double difference,
    required DateTime date,
  }) async {
    final now = date.toIso8601String();
    await txn.insert('transactions', {
      'type': 'Adjustment',
      'amount': difference.abs(),
      'wallet_id': walletId,
      'to_wallet_id': null,
      'to_amount': null,
      'exchange_rate': null,
      'balance_delta': difference,
      'category': 'Balance Adjustment',
      'note': 'Manual wallet balance adjustment',
      'date': now,
      'created_at': now,
    });
  }

  /// Loads transaction-ledger rows for a set of IDs.
  static Future<List<Map<String, Object?>>> getLedgerEntriesByIds(
    DatabaseExecutor db,
    List<int> ids,
  ) async {
    if (ids.isEmpty) return [];
    return db.query(
      'transactions',
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  /// Reverses and removes committee-owned ledger rows inside the caller transaction.
  static Future<void> deleteCommitteeLedgerEntries(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = <int>[];
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      if (id != null) ids.add(id);
      final walletId = (row['wallet_id'] as num?)?.toInt();
      final delta = (row['balance_delta'] as num?)?.toDouble() ?? 0;
      if (walletId != null && delta != 0) {
        final changed = await txn.rawUpdate(
          'UPDATE wallets SET balance = balance - ? WHERE id = ?',
          [delta, walletId],
        );
        if (changed == 0) throw Exception('A committee wallet no longer exists.');
      }
    }
    if (ids.isNotEmpty) {
      await txn.delete(
        'transactions',
        where: 'id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
      );
    }
  }

  /// Restores archived committee ledger rows and their wallet balance effects.
  static Future<void> restoreCommitteeLedgerEntries(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final archived in rows) {
      final row = Map<String, dynamic>.from(archived)..remove('_related_table');
      final walletId = (row['wallet_id'] as num?)?.toInt();
      final delta = (row['balance_delta'] as num?)?.toDouble() ?? 0;
      if (walletId != null && delta != 0) {
        final wallets = await txn.query(
          'wallets',
          columns: ['balance'],
          where: 'id = ?',
          whereArgs: [walletId],
          limit: 1,
        );
        if (wallets.isEmpty) throw Exception('A committee wallet no longer exists.');
        if (delta < 0 && (wallets.first['balance'] as num).toDouble() < -delta) {
          throw Exception('Insufficient wallet balance to restore committee activity.');
        }
        await txn.rawUpdate(
          'UPDATE wallets SET balance = balance + ? WHERE id = ?',
          [delta, walletId],
        );
      }
      await insertLedgerEntry(txn, Map<String, Object?>.from(row));
    }
  }

  /// Creates a module-owned expense while keeping ledger and wallet balance atomic.
  static Future<int> createExpenseLedgerEntry(
    Transaction txn, {
    required double amount,
    required int walletId,
    required String category,
    required String note,
    required String date,
  }) async {
    if (!amount.isFinite || amount <= 0) throw Exception('Enter a valid expense amount.');
    final wallets = await txn.query('wallets',
      columns: ['balance'], where: 'id = ?', whereArgs: [walletId], limit: 1);
    if (wallets.isEmpty) throw Exception('Selected wallet was not found.');
    final balance = (wallets.first['balance'] as num).toDouble();
    if (balance < amount) throw Exception('Insufficient wallet balance.');
    await txn.rawUpdate('UPDATE wallets SET balance = balance - ? WHERE id = ?', [amount, walletId]);
    return insertLedgerEntry(txn, {
      'type': 'Expense', 'amount': amount, 'wallet_id': walletId,
      'to_wallet_id': null, 'to_amount': null, 'exchange_rate': null,
      'balance_delta': null, 'category': category, 'note': note,
      'date': date, 'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Updates an existing module-owned expense and reverses/reapplies its balance effect.
  static Future<void> updateExpenseLedgerEntry(
    Transaction txn, {
    required int id,
    required double amount,
    required int walletId,
    required String category,
    required String note,
    required String date,
  }) async {
    if (!amount.isFinite || amount <= 0) throw Exception('Enter a valid expense amount.');
    final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty || rows.first['type']?.toString().toLowerCase() != 'expense') {
      throw Exception('Linked expense transaction was not found.');
    }
    final oldAmount = (rows.first['amount'] as num).toDouble();
    final oldWalletId = (rows.first['wallet_id'] as num).toInt();
    final oldWallet = await txn.query('wallets', columns: ['balance'],
      where: 'id = ?', whereArgs: [oldWalletId], limit: 1);
    if (oldWallet.isEmpty) throw Exception('Original wallet was not found.');
    await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id = ?', [oldAmount, oldWalletId]);
    final newWallet = await txn.query('wallets', columns: ['balance'],
      where: 'id = ?', whereArgs: [walletId], limit: 1);
    if (newWallet.isEmpty) throw Exception('Selected wallet was not found.');
    if ((newWallet.first['balance'] as num).toDouble() < amount) {
      throw Exception('Insufficient wallet balance.');
    }
    await txn.rawUpdate('UPDATE wallets SET balance = balance - ? WHERE id = ?', [amount, walletId]);
    await txn.update('transactions', {
      'type': 'Expense', 'amount': amount, 'wallet_id': walletId,
      'to_wallet_id': null, 'to_amount': null, 'exchange_rate': null,
      'balance_delta': null, 'category': category, 'note': note, 'date': date,
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Removes a module-owned expense after restoring its wallet balance.
  static Future<void> deleteExpenseLedgerEntry(Transaction txn, int id) async {
    final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    if (rows.first['type']?.toString().toLowerCase() != 'expense') {
      throw Exception('Linked transaction is not an expense.');
    }
    final walletId = (rows.first['wallet_id'] as num).toInt();
    final amount = (rows.first['amount'] as num).toDouble();
    final changed = await txn.rawUpdate(
      'UPDATE wallets SET balance = balance + ? WHERE id = ?', [amount, walletId]);
    if (changed == 0) throw Exception('Linked wallet was not found.');
    await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  /// Converts all ledger-owned values affected by a wallet currency change.
  /// Must run inside the caller's transaction to keep balances and history atomic.
  static Future<void> convertWalletCurrencyAmounts(
    Transaction txn,
    int walletId,
    double factor,
  ) async {
    await txn.rawUpdate('''
      UPDATE transactions
      SET amount = amount * ?
      WHERE wallet_id = ?
        AND type IN ('Income', 'Expense', 'Transfer')
    ''', [factor, walletId]);

    final feeTransactions = await txn.query(
      'transactions',
      columns: ['id'],
      where: "wallet_id = ? AND type = 'Transfer'",
      whereArgs: [walletId],
    );
    for (final transaction in feeTransactions) {
      final transactionId = transaction['id'] as int;
      final feeRows = await txn.query(
        'app_settings',
        columns: ['setting_value'],
        where: 'setting_key = ?',
        whereArgs: ['transaction_transfer_fee_$transactionId'],
        limit: 1,
      );
      if (feeRows.isNotEmpty) {
        final oldFee = double.tryParse(
          feeRows.first['setting_value']?.toString() ?? '',
        ) ?? 0;
        await txn.update(
          'app_settings',
          {'setting_value': (oldFee * factor).toString()},
          where: 'setting_key = ?',
          whereArgs: ['transaction_transfer_fee_$transactionId'],
        );
      }
    }

    await txn.rawUpdate('''
      UPDATE transactions
      SET to_amount = COALESCE(to_amount, amount) * ?
      WHERE to_wallet_id = ?
        AND type = 'Transfer'
    ''', [factor, walletId]);

    await txn.rawUpdate('''
      UPDATE transactions
      SET exchange_rate = CASE
        WHEN to_amount IS NULL OR amount = 0 THEN NULL
        ELSE to_amount / amount
      END
      WHERE type = 'Transfer'
        AND (wallet_id = ? OR to_wallet_id = ?)
    ''', [walletId, walletId]);

    await txn.rawUpdate('''
      UPDATE transactions
      SET balance_delta = balance_delta * ?
      WHERE wallet_id = ?
        AND type = 'Transfer'
        AND category = 'Committee Transfer'
        AND balance_delta IS NOT NULL
    ''', [factor, walletId]);

    await txn.rawUpdate('''
      UPDATE transactions
      SET amount = amount * ?,
          balance_delta = balance_delta * ?
      WHERE wallet_id = ?
        AND type = 'Adjustment'
    ''', [factor, factor, walletId]);
  }

  static String _normalizeType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'income': return 'Income';
      case 'expense': return 'Expense';
      case 'transfer': return 'Transfer';
      default: throw Exception('Transaction type must be Income, Expense, or Transfer.');
    }
  }


  static Future<Database> get _database async =>
      DatabaseManager.instance.database;

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
    final db = await _database;
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
    final db = await _database;
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
    final db = await _database;
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
    final db = await _database;
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
    final recycleId = await RecycleBinArchiveService.archive(type: 'Transaction',
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
      await RecycleBinArchiveService.discardArchive(recycleId);
      rethrow;
    }
    AppRefreshController.notifyChanged();
  }


  static Future<List<Map<String, dynamic>>> getTransactions({int? walletId}) async {
    final db = await _database;
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

  /// Restores the archived transactions record and related ledger entries atomically.
  static Future<void> restoreArchivedTransaction(
    Transaction txn, {
    required Map<String, dynamic> record,
    String? relatedPayload,
  }) async {
        final type = (record['type'] ?? '').toString().toLowerCase();
        final amount = (record['amount'] as num).toDouble();
        final walletId = (record['wallet_id'] as num).toInt();
        final fee = (record.remove('_transfer_fee') as num?)?.toDouble() ?? 0.0;
        Future<void> change(int id, double delta) async {
          final changed = await txn.rawUpdate('UPDATE wallets SET balance = balance + ? WHERE id = ?', [delta, id]);
          if (changed == 0) throw Exception('A linked wallet no longer exists. Restore the wallet first.');
        }
        if (type == 'income') {
          await change(walletId, amount);
        } else if (type == 'expense') {
          final wallets = await txn.query('wallets', columns: ['balance'], where: 'id = ?', whereArgs: [walletId], limit: 1);
          if (wallets.isEmpty) throw Exception('The linked wallet no longer exists.');
          if ((wallets.first['balance'] as num).toDouble() < amount) throw Exception('Insufficient wallet balance to restore this expense.');
          await change(walletId, -amount);
        } else if (type == 'transfer') {
          final toId = (record['to_wallet_id'] as num?)?.toInt();
          if (toId == null) throw Exception('Transfer destination is missing.');
          final received = (record['to_amount'] as num?)?.toDouble() ?? amount;
          final wallets = await txn.query('wallets', columns: ['id','balance'], where: 'id = ? OR id = ?', whereArgs: [walletId,toId]);
          if (wallets.length < 2) throw Exception('Both linked wallets must exist before restoring this transfer.');
          final source = wallets.firstWhere((w) => w['id'] == walletId);
          if ((source['balance'] as num).toDouble() < amount + fee) throw Exception('Insufficient source wallet balance to restore this transfer.');
          await change(walletId, -(amount + fee));
          await change(toId, received);
        } else if (type == 'adjustment') {
          final delta = (record['balance_delta'] as num?)?.toDouble();
          if (delta == null) throw Exception('Adjustment balance change is missing.');
          await change(walletId, delta);
        } else {
          throw Exception('Unknown transaction type.');
        }
        await txn.insert('transactions', record);
        final salaryRaw = relatedPayload;
        if (salaryRaw != null && salaryRaw.isNotEmpty) {
          final salaryRows = (jsonDecode(salaryRaw) as List).whereType<Map>();
          for (final row in salaryRows) {
            await StaffService.restoreArchivedSalary(
              txn,
              Map<String, dynamic>.from(row),
            );
          }
        }
        if (fee > 0) {
          await txn.insert('app_settings', {'setting_key':'transaction_transfer_fee_${record['id']}','setting_value':fee.toString()}, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return;
  }

}
