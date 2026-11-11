import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class TransactionsService {
  static Database? _database;
  static Future<Database>? _databaseFuture;

  static String _normalizeType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'income': return 'Income';
      case 'expense': return 'Expense';
      case 'transfer': return 'Transfer';
      default: throw Exception('Unknown transaction type: $type');
    }
  }

  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    if (_databaseFuture != null) return _databaseFuture!;
    final future = _openDatabase();
    _databaseFuture = future;
    try {
      _database = await future;
      return _database!;
    } finally {
      _databaseFuture = null;
    }
  }

  static Future<Database> _openDatabase() async {
    final path = await getDatabasesPath();
    return openDatabase(p.join(path, 'my_finance.db'));
  }



  static Future<void> _changeBalance(Transaction txn, int walletId, double change) async {
    final changed = await txn.rawUpdate(
      'UPDATE wallets SET balance = balance + ? WHERE id = ?',
      [change, walletId],
    );
    if (changed == 0) throw Exception('Wallet not found: $walletId');
  }

  static Future<void> _reverse(Transaction txn, Map<String, dynamic> row) async {
    final rawType = row['type'].toString().trim().toLowerCase();
    final amount = (row['amount'] as num).toDouble();
    final walletId = (row['wallet_id'] as num).toInt();
    final toWalletId = (row['to_wallet_id'] as num?)?.toInt();
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
      if (toWalletId == null) throw Exception('Transfer destination is missing.');
      final destinationAmount = (row['to_amount'] as num?)?.toDouble() ?? amount;
      await _changeBalance(txn, walletId, amount);
      await _changeBalance(txn, toWalletId, -destinationAmount);
    }
  }

  static Future<void> _apply(
    Transaction txn, {
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    double? toAmount,
  }) async {
    if (!amount.isFinite || amount <= 0) throw Exception('Amount must be greater than zero.');
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
    if ((source['balance'] as num).toDouble() < amount) throw Exception('Insufficient wallet balance.');
    await _changeBalance(txn, walletId, -amount);
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
  }) async {
    final db = await database;
    final normalized = _normalizeType(type);
    return db.transaction((txn) async {
      await _apply(txn, type: normalized, amount: amount, walletId: walletId,
        toWalletId: normalized == 'Transfer' ? toWalletId : null, toAmount: toAmount);
      final now = DateTime.now().toIso8601String();
      return txn.insert('transactions', {
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
    });
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
  }) async {
    final db = await database;
    final normalized = _normalizeType(type);
    await db.transaction((txn) async {
      final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw Exception('Transaction not found.');
      await _reverse(txn, rows.first);
      await _apply(txn, type: normalized, amount: amount, walletId: walletId,
        toWalletId: normalized == 'Transfer' ? toWalletId : null, toAmount: toAmount);
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
    });
  }

  static Future<void> deleteTransaction(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw Exception('Transaction not found.');
      await _reverse(txn, rows.first);
      await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<void> setCategory({required int transactionId, required String? category}) async {
    final db = await database;
    await db.update('transactions', {'category': category ?? ''},
      where: "id = ? AND type IN ('Income', 'Expense')", whereArgs: [transactionId]);
  }

  static Future<List<Map<String, dynamic>>> getTransactions() async {
    final db = await database;
    return db.rawQuery("SELECT t.*, t.category AS category_name FROM transactions t ORDER BY t.date DESC, t.id DESC");
  }

  static Future<List<Map<String, dynamic>>> getAccounts() async {
    final db = await database;
    return db.query('wallets', columns: ['id', 'name', 'currency', 'balance'],
      orderBy: 'name COLLATE NOCASE ASC');
  }
}
