
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class TransactionService {
  static const int _databaseVersion = 3;

  static Database? _database;
  static Future<Database>? _databaseFuture;

  static String _normalizeType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'income':
        return 'income';
      case 'expense':
        return 'expense';
      case 'transfer':
        return 'transfer';
      default:
        throw Exception('Unknown transaction type: $type');
    }
  }

  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    if (_databaseFuture != null) {
      return _databaseFuture!;
    }

    final future = _openDatabase();
    _databaseFuture = future;

    try {
      _database = await future;
      return _database!;
    } finally {
      _databaseFuture = null;
    }
  }

  static Future<void> closeDatabase() async {
    final pending = _databaseFuture;

    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }

    final db = _database;
    _database = null;
    _databaseFuture = null;

    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  static Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();

    final db = await openDatabase(
      p.join(dbPath, 'my_finance.db'),
      version: _databaseVersion,
      onOpen: (database) async {
        await _ensureCategorySchema(database);
      },
    );

    return db;
  }

  static Future<void> _ensureCategorySchema(
    DatabaseExecutor db,
  ) async {
    final tables = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
      AND name IN ('accounts', 'transactions')
    ''');

    final existingTables = tables
        .map((row) => row['name'] as String)
        .toSet();

    if (!existingTables.contains('accounts')) {
      throw Exception(
        'Accounts table is missing. Initialize FinanceDB first.',
      );
    }

    if (!existingTables.contains('transactions')) {
      throw Exception(
        'Transactions table is missing. Initialize FinanceDB first.',
      );
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS finance_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT 'category',
        parent_id INTEGER,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    final columns = await db.rawQuery(
      'PRAGMA table_info(transactions)',
    );

    final hasCategoryColumn = columns.any(
      (column) => column['name'] == 'category_id',
    );

    if (!hasCategoryColumn) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN category_id INTEGER',
      );
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_category_id
      ON transactions(category_id)
    ''');
  }

  static Future<void> _changeBalance(
    Transaction txn,
    int accountId,
    double change,
  ) async {
    final result = await txn.rawUpdate(
      'UPDATE accounts SET balance = balance + ? WHERE id = ?',
      [change, accountId],
    );

    if (result == 0) {
      throw Exception('Account not found: $accountId');
    }
  }

  static Future<void> _reverseTransaction(
    Transaction txn,
    Map<String, dynamic> item,
  ) async {
    final type = _normalizeType(item['type'] as String);
    final amount = (item['amount'] as num).toDouble();
    final accountId = item['account_id'] as int;
    final toAccountId = item['to_account_id'] as int?;

    if (type == 'income') {
      await _changeBalance(txn, accountId, -amount);
    } else if (type == 'expense') {
      await _changeBalance(txn, accountId, amount);
    } else if (type == 'transfer') {
      if (toAccountId == null) {
        throw Exception('Transfer destination is missing.');
      }

      await _changeBalance(txn, accountId, amount);
      await _changeBalance(txn, toAccountId, -amount);
    }
  }

  static Future<void> _applyTransaction(
    Transaction txn, {
    required String type,
    required double amount,
    required int accountId,
    int? toAccountId,
  }) async {
    final normalizedType = _normalizeType(type);

    if (!amount.isFinite || amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }

    if (normalizedType == 'income') {
      await _changeBalance(txn, accountId, amount);
      return;
    }

    if (normalizedType == 'expense') {
      await _changeBalance(txn, accountId, -amount);
      return;
    }

    if (toAccountId == null || toAccountId == accountId) {
      throw Exception('Select a different destination account.');
    }

    final accounts = await txn.query(
      'accounts',
      columns: ['id', 'currency', 'balance'],
      where: 'id IN (?, ?)',
      whereArgs: [accountId, toAccountId],
    );

    if (accounts.length != 2) {
      throw Exception('Transfer account not found.');
    }

    final source = accounts.firstWhere(
      (account) => account['id'] == accountId,
    );

    final destination = accounts.firstWhere(
      (account) => account['id'] == toAccountId,
    );

    if (source['currency'] != destination['currency']) {
      throw Exception(
        'Different currency transfers will be available '
        'after exchange rate support is added.',
      );
    }

    final balance = (source['balance'] as num).toDouble();

    if (balance < amount) {
      throw Exception('Insufficient account balance.');
    }

    await _changeBalance(txn, accountId, -amount);
    await _changeBalance(txn, toAccountId, amount);
  }

  static Future<void> _validateCategory(
    Transaction txn,
    int? categoryId,
    String type,
  ) async {
    if (categoryId == null) return;

    final normalizedType = _normalizeType(type);

    final rows = await txn.query(
      'finance_categories',
      where: 'id = ? AND LOWER(type) = ? AND is_deleted = 0',
      whereArgs: [categoryId, normalizedType],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw Exception('Selected category is not available.');
    }
  }

  static Future<int> addTransaction({
    required String type,
    required double amount,
    required int accountId,
    int? toAccountId,
    int? categoryId,
    required String note,
    required String date,
  }) async {
    final db = await database;
    final normalizedType = _normalizeType(type);

    if (!amount.isFinite || amount <= 0) {
      throw Exception('Enter a valid amount greater than zero.');
    }

    return db.transaction((txn) async {
      await _validateCategory(
        txn,
        normalizedType == 'transfer' ? null : categoryId,
        normalizedType,
      );

      await _applyTransaction(
        txn,
        type: normalizedType,
        amount: amount,
        accountId: accountId,
        toAccountId: toAccountId,
      );

      return txn.insert('transactions', {
        'type': normalizedType,
        'amount': amount,
        'account_id': accountId,
        'to_account_id':
            normalizedType == 'transfer' ? toAccountId : null,
        'category_id':
            normalizedType == 'transfer' ? null : categoryId,
        'note': note,
        'date': date,
      });
    });
  }

  static Future<void> updateTransaction({
    required int id,
    required String type,
    required double amount,
    required int accountId,
    int? toAccountId,
    int? categoryId,
    required String note,
    required String date,
  }) async {
    final db = await database;
    final normalizedType = _normalizeType(type);

    if (!amount.isFinite || amount <= 0) {
      throw Exception('Enter a valid amount greater than zero.');
    }

    await db.transaction((txn) async {
      final existing = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (existing.isEmpty) {
        throw Exception('Transaction not found.');
      }

      await _reverseTransaction(txn, existing.first);

      await _validateCategory(
        txn,
        normalizedType == 'transfer' ? null : categoryId,
        normalizedType,
      );

      await _applyTransaction(
        txn,
        type: normalizedType,
        amount: amount,
        accountId: accountId,
        toAccountId: toAccountId,
      );

      await txn.update(
        'transactions',
        {
          'type': normalizedType,
          'amount': amount,
          'account_id': accountId,
          'to_account_id':
              normalizedType == 'transfer' ? toAccountId : null,
          'category_id':
              normalizedType == 'transfer' ? null : categoryId,
          'note': note,
          'date': date,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  static Future<void> deleteTransaction(int id) async {
    final db = await database;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw Exception('Transaction not found.');
      }

      await _reverseTransaction(txn, rows.first);

      await txn.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  static Future<void> setCategory({
    required int transactionId,
    required int? categoryId,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: ['type'],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw Exception('Transaction not found.');
      }

      final type = _normalizeType(
        rows.first['type'] as String,
      );

      await _validateCategory(txn, categoryId, type);

      await txn.update(
        'transactions',
        {'category_id': categoryId},
        where: 'id = ?',
        whereArgs: [transactionId],
      );
    });
  }

  static Future<List<Map<String, dynamic>>> getTransactions() async {
    final db = await database;

    return db.rawQuery('''
      SELECT
        t.*,
        c.name AS category_name,
        c.icon AS category_icon
      FROM transactions t
      LEFT JOIN finance_categories c
        ON t.category_id = c.id
      ORDER BY t.id DESC
    ''');
  }

  static Future<List<Map<String, dynamic>>> getAccounts() async {
    final db = await database;

    return db.query(
      'accounts',
      columns: ['id', 'name', 'currency', 'balance'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }
}
