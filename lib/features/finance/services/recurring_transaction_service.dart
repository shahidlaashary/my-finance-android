import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/features/finance/models/recurring_transaction_model.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';
class RecurringTransactionService {

  // Restore se pehle is service ka database connection band karta hai.
  static Future<void> closeDatabase() async {
    final currentDatabase = _databaseInstance;
    _databaseInstance = null;
    _databaseFuture = null;
    if (currentDatabase != null && currentDatabase.isOpen) {
      await currentDatabase.close();
    }
  }
  static const String _databaseName = 'my_finance.db';
  static const String _tableName = 'recurring_transactions';
  static Database? _databaseInstance;
  static Future<Database>? _databaseFuture;
  final List<String> lastProcessingErrors = [];
  Future<Database> get _database async {
    if (_databaseInstance != null && _databaseInstance!.isOpen) {
      return _databaseInstance!;
    }
    if (_databaseFuture != null) {
      return _databaseFuture!;
    }
    _databaseFuture = _openDatabase();
    try {
      _databaseInstance = await _databaseFuture!;
      return _databaseInstance!;
    } finally {
      _databaseFuture = null;
    }
  }
  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dbPath, _databaseName),
    );
    try {
      await _createTable(db);
      return db;
    } catch (_) {
      await db.close();
      rethrow;
    }
  }
  Future<void> _createTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        wallet_id INTEGER NOT NULL,
        to_wallet_id INTEGER,
        category TEXT,
        note TEXT,
        frequency TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        next_run_date TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

  }
  String _date(DateTime date) {
    final value = DateTime(date.year, date.month, date.day);
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
  DateTime _parseDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
  DateTime _nextDate(DateTime current, String frequency) {
    switch (frequency.toLowerCase()) {
      case 'daily':
        return current.add(const Duration(days: 1));
      case 'weekly':
        return current.add(const Duration(days: 7));
      case 'monthly':
        final nextMonth = current.month == 12
            ? DateTime(current.year + 1, 1, 1)
            : DateTime(current.year, current.month + 1, 1);
        final lastDay = DateTime(
          nextMonth.year,
          nextMonth.month + 1,
          0,
        ).day;
        return DateTime(
          nextMonth.year,
          nextMonth.month,
          current.day > lastDay ? lastDay : current.day,
        );
      case 'yearly':
        final year = current.year + 1;
        final lastDay = DateTime(
          year,
          current.month + 1,
          0,
        ).day;
        return DateTime(
          year,
          current.month,
          current.day > lastDay ? lastDay : current.day,
        );
      default:
        throw ArgumentError('Invalid frequency: $frequency');
    }
  }
  void _validateModel(RecurringTransactionModel model) {
    if (model.title.trim().isEmpty) {
      throw Exception('Transaction title is required.');
    }
    if (!model.amount.isFinite || model.amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
    final type = model.type.toLowerCase();
    if (!['income', 'expense', 'transfer'].contains(type)) {
      throw Exception('Invalid transaction type.');
    }
    final frequency = model.frequency.toLowerCase();
    if (!['daily', 'weekly', 'monthly', 'yearly']
        .contains(frequency)) {
      throw Exception('Invalid recurring frequency.');
    }
    if (model.walletId <= 0) {
      throw Exception('A valid account is required.');
    }
    if (type == 'transfer') {
      if (model.toWalletId == null ||
          model.toWalletId! <= 0 ||
          model.toWalletId == model.walletId) {
        throw Exception('A valid destination account is required.');
      }
    } else if (model.toWalletId != null) {
      throw Exception(
        'Destination account is only allowed for transfers.',
      );
    }
    final startDate = _parseDate(model.startDate);
    final nextRunDate = _parseDate(
      model.nextRunDate ?? model.startDate,
    );
    if (nextRunDate.isBefore(startDate)) {
      throw Exception('Next run date cannot be before start date.');
    }
    if (model.endDate != null) {
      final endDate = _parseDate(model.endDate!);
      if (endDate.isBefore(startDate)) {
        throw Exception('End date cannot be before start date.');
      }
      if (endDate.isBefore(nextRunDate)) {
        throw Exception('End date cannot be before next run date.');
      }
    }
  }
  Future<void> _validateAccounts(
    DatabaseExecutor db,
    RecurringTransactionModel model,
  ) async {
    final sourceAccounts = await db.query(
      'wallets',
      where: 'id = ?',
      whereArgs: [model.walletId],
      limit: 1,
    );
    if (sourceAccounts.isEmpty) {
      throw Exception('Selected account does not exist.');
    }
    if (model.type.toLowerCase() == 'transfer') {
      final destinationAccounts = await db.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [model.toWalletId],
        limit: 1,
      );
      if (destinationAccounts.isEmpty) {
        throw Exception('Destination account does not exist.');
      }
      final sourceCurrency =
          sourceAccounts.first['currency']?.toString();
      final destinationCurrency =
          destinationAccounts.first['currency']?.toString();
      if (sourceCurrency != destinationCurrency) {
        throw Exception(
          'Transfer wallets must have the same currency.',
        );
      }
    }
  }
  Map<String, Object?> _toMap(
    RecurringTransactionModel model,
  ) {
    return {
      'title': model.title.trim(),
      'type': model.type.toLowerCase(),
      'amount': model.amount,
      'wallet_id': model.walletId,
      'to_wallet_id': model.toWalletId,
      'category': model.category,
      'note': model.note,
      'frequency': model.frequency.toLowerCase(),
      'start_date': _date(model.startDate),
      'end_date': model.endDate == null
          ? null
          : _date(model.endDate!),
      'next_run_date': _date(
        model.nextRunDate ?? model.startDate,
      ),
      'is_active': model.isActive ? 1 : 0,
      'created_at':
          (model.createdAt ?? DateTime.now()).toIso8601String(),
    };
  }
  Future<int> addRecurringTransaction(
    RecurringTransactionModel model,
  ) async {
    _validateModel(model);
    final db = await _database;
    await _validateAccounts(db, model);
    final id = await db.insert(
      _tableName,
      _toMap(model),
    );
    AppRefreshController.notifyChanged();
    return id;
  }
  Future<List<RecurringTransactionModel>> getRecurringTransactions({
    bool activeOnly = false,
  }) async {
    final db = await _database;
    final rows = await db.query(
      _tableName,
      where: activeOnly ? 'is_active = ?' : null,
      whereArgs: activeOnly ? [1] : null,
      orderBy: 'next_run_date ASC',
    );
    return rows
        .map((row) => RecurringTransactionModel.fromMap(row))
        .toList();
  }
  Future<RecurringTransactionModel?> getRecurringTransactionById(
    int id,
  ) async {
    final db = await _database;
    final rows = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return RecurringTransactionModel.fromMap(rows.first);
  }
  Future<int> updateRecurringTransaction(
    RecurringTransactionModel model,
  ) async {
    if (model.id == null) {
      throw Exception('Recurring transaction ID is required.');
    }
    _validateModel(model);
    final db = await _database;
    await _validateAccounts(db, model);
    final count = await db.update(
      _tableName,
      _toMap(model),
      where: 'id = ?',
      whereArgs: [model.id],
    );
    if (count > 0) AppRefreshController.notifyChanged();
    return count;
  }
  Future<int> setRecurringTransactionStatus(
    int id,
    bool isActive,
  ) async {
    final db = await _database;
    final count = await db.update(
      _tableName,
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count > 0) AppRefreshController.notifyChanged();
    return count;
  }
  Future<int> deleteRecurringTransaction(int id) async {
    final db = await _database;
    final rows = await db.query(_tableName, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return 0;
    await RecycleBinService.archive(type: 'Recurring Transaction', title: rows.first['title']?.toString() ?? 'Recurring Transaction', table: _tableName, id: id, record: rows.first);
    final count = await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
    if (count > 0) AppRefreshController.notifyChanged();
    return count;
  }
  Future<void> _applyTransaction(
    Transaction txn,
    Map<String, Object?> recurring,
    DateTime transactionDate,
  ) async {
    final type = recurring['type'].toString().toLowerCase();
    final amount = (recurring['amount'] as num).toDouble();
    final walletId = recurring['wallet_id'] as int;
    final toWalletId = recurring['to_wallet_id'] as int?;
    final wallets = await txn.query(
      'wallets',
      where: 'id = ?',
      whereArgs: [walletId],
      limit: 1,
    );
    if (wallets.isEmpty) {
      throw Exception('Recurring transaction account not found.');
    }
    final account = wallets.first;
    final balance = (account['balance'] as num).toDouble();
    Map<String, Object?>? destination;
    if (type == 'transfer') {
      if (toWalletId == null || toWalletId == walletId) {
        throw Exception('Invalid destination account.');
      }
      final destinationAccounts = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [toWalletId],
        limit: 1,
      );
      if (destinationAccounts.isEmpty) {
        throw Exception('Destination account not found.');
      }
      destination = destinationAccounts.first;
      if (destination['currency'] != account['currency']) {
        throw Exception(
          'Transfer wallets must have the same currency.',
        );
      }
    }
    if (type == 'expense' || type == 'transfer') {
      if (balance < amount) {
        throw Exception(
          'Insufficient balance in account ${account['name']}.',
        );
      }
    }
    if (type == 'income') {
      await txn.update(
        'wallets',
        {'balance': balance + amount},
        where: 'id = ?',
        whereArgs: [walletId],
      );
    } else {
      await txn.update(
        'wallets',
        {'balance': balance - amount},
        where: 'id = ?',
        whereArgs: [walletId],
      );
    }
    if (type == 'transfer') {
      final destinationBalance =
          (destination!['balance'] as num).toDouble();
      await txn.update(
        'wallets',
        {'balance': destinationBalance + amount},
        where: 'id = ?',
        whereArgs: [toWalletId],
      );
    }
    await txn.insert('transactions', {
      'type': type == 'income' ? 'Income' : type == 'expense' ? 'Expense' : 'Transfer',
      'amount': amount,
      'wallet_id': walletId,
      'to_wallet_id': toWalletId,
      'to_amount': type == 'transfer' ? amount : null,
      'exchange_rate': type == 'transfer' ? 1.0 : null,
      'balance_delta': null,
      'category': type == 'transfer' ? '' : (recurring['category'] ?? ''),
      'note': recurring['note'] ?? recurring['title'],
      'date': _date(transactionDate),
      'created_at': DateTime.now().toIso8601String(),
    });
  }
  /// Jin recurring transactions ki date aa chuki ho un sab ko process karta hai.
  ///
  /// Banayi gayi transactions ki tadaad return karta hai.
  Future<int> processDueTransactions({
    DateTime? throughDate,
  }) async {
    final db = await _database;
    final referenceDate = throughDate ?? DateTime.now();
    final today = DateTime(referenceDate.year, referenceDate.month, referenceDate.day);
    lastProcessingErrors.clear();

    final dueRows = await db.query(
      _tableName,
      where: 'is_active = ? AND next_run_date <= ?',
      whereArgs: [1, _date(today)],
      orderBy: 'next_run_date ASC',
    );

    var processedCount = 0;
    for (final recurring in dueRows) {
      final id = recurring['id'] as int;
      try {
        final count = await db.transaction((txn) async {
          final currentRows = await txn.query(
            _tableName,
            where: 'id = ? AND is_active = ?',
            whereArgs: [id, 1],
            limit: 1,
          );
          if (currentRows.isEmpty) return 0;

          final current = currentRows.first;
          final frequency = current['frequency'].toString();
          final endDate = current['end_date'] as String?;
          var nextDate = DateTime.parse(current['next_run_date'].toString());
          var scheduleCount = 0;

          while (!nextDate.isAfter(today)) {
            if (endDate != null && nextDate.isAfter(DateTime.parse(endDate))) {
              await txn.update(
                _tableName,
                {'is_active': 0},
                where: 'id = ?',
                whereArgs: [id],
              );
              break;
            }

            await _applyTransaction(txn, current, nextDate);
            scheduleCount++;
            nextDate = _nextDate(nextDate, frequency);

            if (endDate != null && nextDate.isAfter(DateTime.parse(endDate))) {
              await txn.update(
                _tableName,
                {'next_run_date': _date(nextDate), 'is_active': 0},
                where: 'id = ?',
                whereArgs: [id],
              );
              break;
            }

            await txn.update(
              _tableName,
              {'next_run_date': _date(nextDate)},
              where: 'id = ?',
              whereArgs: [id],
            );
          }
          return scheduleCount;
        });
        processedCount += count;
      } catch (error) {
        final title = recurring['title']?.toString() ?? 'Schedule #$id';
        final message = '$title: $error';
        lastProcessingErrors.add(message);

        // Ek schedule fail ho to doosre schedules rollback na hon.
        // Failed schedule pause hota hai taake har app launch par duplicate
        // retries/continuous errors na hon; user usay edit karke resume kar sakta hai.
        await db.update(
          _tableName,
          {'is_active': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }

    if (processedCount > 0 || lastProcessingErrors.isNotEmpty) {
      AppRefreshController.notifyChanged();
    }
    return processedCount;
  }
}
