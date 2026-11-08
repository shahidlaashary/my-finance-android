import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
class TransactionService {
  static Database? _database;
  static Future<Database>? _databaseFuture;
  // Normalize transaction types to lowercase.
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
  // Get the shared application database.
  static Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    // Prevent multiple simultaneous database openings.
    if (_databaseFuture != null) {
      return _databaseFuture!;
    }
    _databaseFuture = _openDatabase();
    try {
      _database = await _databaseFuture!;
      return _database!;
    } finally {
      _databaseFuture = null;
    }
  }
  // Close the service database connection before restoring a backup.
  static Future<void> closeDatabase() async {
    final pendingFuture = _databaseFuture;
    if (pendingFuture != null) {
      try {
        await pendingFuture;
      } catch (_) {
        // Ignore opening errors while preparing to close.
      }
    }
    final currentDatabase = _database;
    _database = null;
    if (currentDatabase != null && currentDatabase.isOpen) {
      await currentDatabase.close();
    }
    _databaseFuture = null;
  }
  static Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dbPath, 'my_finance.db'),
      version: 1,
    );
    try {
      await _ensureCategorySchema(db);
      return db;
    } catch (_) {
      await db.close();
      rethrow;
    }
  }
  // Ensure category table and transaction category column exist.
  static Future<void> _ensureCategorySchema(
    DatabaseExecutor db,
  ) async {
    final tables = await db.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
      AND name IN ('accounts', 'transactions')
      ''',
    );
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
  // Change an account balance.
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
  // Reverse the balance effect of an existing transaction.
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
  // Apply the balance effect of a transaction.
  static Future<void> _applyTransaction(
    Transaction txn, {
    required String type,
    required double amount,
    required int accountId,
    int? toAccountId,
  }) async {
    final normalizedType = _normalizeType(type);
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
    if (normalizedType == 'income') {
      await _changeBalance(txn, accountId, amount);
    } else if (normalizedType == 'expense') {
      await _changeBalance(txn, accountId, -amount);
    } else if (normalizedType == 'transfer') {
      if (toAccountId == null || toAccountId == accountId) {
        throw Exception(
          'Select a different destination account.',
        );
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
          'Transfer accounts must use the same currency.',
        );
      }
      final balance =
          (source['balance'] as num).toDouble();
      if (balance < amount) {
        throw Exception('Insufficient account balance.');
      }
      await _changeBalance(txn, accountId, -amount);
      await _changeBalance(txn, toAccountId, amount);
    }
  }
  // Validate that the selected category matches the transaction type.
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
    // Add a new transaction and update account balances.
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
  // Update an existing transaction and correct account balances.
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
      final oldItem = existing.first;
      await _reverseTransaction(txn, oldItem);
      await _validateCategory(
        txn,
        categoryId,
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
          'to_account_id': normalizedType == 'transfer'
              ? toAccountId
              : null,
          'category_id': categoryId,
          'note': note,
          'date': date,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
  // Delete a transaction and reverse its account balance effect.
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
  // Assign or change a category without changing account balances.
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
      await _validateCategory(
        txn,
        categoryId,
        type,
      );
      await txn.update(
        'transactions',
        {'category_id': categoryId},
        where: 'id = ?',
        whereArgs: [transactionId],
      );
    });
  }
  // Read transactions with their category names and icons.
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
  // Get accounts for transaction forms.
  static Future<List<Map<String, dynamic>>> getAccounts() async {
    final db = await database;
    return db.query(
      'accounts',
      columns: ['id', 'name', 'currency', 'balance'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }
}
