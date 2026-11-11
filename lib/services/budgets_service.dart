import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/budgets_model.dart';
class BudgetsService {
  static const String _databaseName = 'my_finance.db';
  static Database? _databaseInstance;
  static Future<Database>? _databaseFuture;
  static Future<Database> get _database async {
    if (_databaseInstance != null &&
        _databaseInstance!.isOpen) {
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
  static Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    final db = await openDatabase(
      p.join(databasePath, _databaseName),
      onOpen: (db) async {
        await _createTables(db);
      },
    );
    return db;
  }
  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT,
        limit_amount REAL NOT NULL,
        spent_amount REAL NOT NULL DEFAULT 0,
        period TEXT NOT NULL DEFAULT 'Monthly',
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'PKR',
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_budgets_active
      ON budgets(is_active)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_budgets_dates
      ON budgets(start_date, end_date)
    ''');
  }
  static void _validateBudget(BudgetsModel budget) {
    if (budget.name.trim().isEmpty) {
      throw Exception('Budget name is required.');
    }
    if (!budget.limitAmount.isFinite ||
        budget.limitAmount <= 0) {
      throw Exception('Budget limit must be greater than zero.');
    }
    if (budget.startDate.isAfter(budget.endDate)) {
      throw Exception('Start date cannot be after end date.');
    }
    if (budget.currency.trim().isEmpty) {
      throw Exception('Budget currency is required.');
    }
    const validPeriods = [
      'Daily',
      'Weekly',
      'Monthly',
      'Yearly',
      'Custom',
    ];
    if (!validPeriods.any(
      (period) =>
          period.toLowerCase() == budget.period.toLowerCase(),
    )) {
      throw Exception('Invalid budget period.');
    }
  }
  /// Creates a new budget.
  static Future<int> addBudget(BudgetsModel budget) async {
    final db = await _database;
    _validateBudget(budget);
    final now = DateTime.now();
    return db.insert(
      'budgets',
      budget.copyWith(
        name: budget.name.trim(),
        spentAmount: 0,
        currency: budget.currency.trim().toUpperCase(),
        createdAt: budget.createdAt ?? now,
      ).toMap()
        ..remove('id'),
    );
  }
  /// Returns all budgets.
  static Future<List<BudgetsModel>> getBudgets({
    bool activeOnly = false,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'budgets',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'start_date DESC, id DESC',
    );
    final budgets = rows.map(BudgetsModel.fromMap).toList();
    final result = <BudgetsModel>[];
    for (final budget in budgets) {
      result.add(await _refreshBudget(db, budget));
    }
    return result;
  }
  /// Returns a single budget by ID.
  static Future<BudgetsModel?> getBudgetById(int budgetId) async {
    final db = await _database;
    final rows = await db.query(
      'budgets',
      where: 'id = ?',
      whereArgs: [budgetId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _refreshBudget(
      db,
      BudgetsModel.fromMap(rows.first),
    );
  }
  /// Recalculates actual expenses for a budget.
  static Future<BudgetsModel> _refreshBudget(
    DatabaseExecutor db,
    BudgetsModel budget,
  ) async {
    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(t.amount), 0) AS total
      FROM transactions t
      INNER JOIN wallets a ON a.id = t.wallet_id
      WHERE LOWER(t.type) = 'expense'
        AND UPPER(a.currency) = ?
        AND date(t.date) >= date(?)
        AND date(t.date) <= date(?)
        AND (? IS NULL OR t.category = ?)
      ''',
      [
        budget.currency.toUpperCase(),
        budget.startDate.toIso8601String(),
        budget.endDate.toIso8601String(),
        budget.category,
        budget.category,
      ],
    );
    final spent = (result.first['total'] as num).toDouble();
    await db.update(
      'budgets',
      {'spent_amount': spent},
      where: 'id = ?',
      whereArgs: [budget.id],
    );
    return budget.copyWith(spentAmount: spent);
  }
  /// Manually refreshes one budget's spending.
  static Future<BudgetsModel> refreshBudget(int budgetId) async {
    final budget = await getBudgetById(budgetId);
    if (budget == null) {
      throw Exception('Budget was not found.');
    }
    return budget;
  }
  /// Updates budget details.
  static Future<void> updateBudget(BudgetsModel budget) async {
    if (budget.id == null) {
      throw Exception('Budget ID is required.');
    }
    _validateBudget(budget);
    final db = await _database;
    final existing = await db.query(
      'budgets',
      where: 'id = ?',
      whereArgs: [budget.id],
      limit: 1,
    );
    if (existing.isEmpty) {
      throw Exception('Budget was not found.');
    }
    final oldBudget = BudgetsModel.fromMap(existing.first);
    await db.update(
      'budgets',
      {
        'name': budget.name.trim(),
        'category': budget.category,
        'limit_amount': budget.limitAmount,
        'period': budget.period,
        'start_date': budget.startDate.toIso8601String(),
        'end_date': budget.endDate.toIso8601String(),
        'currency': budget.currency.trim().toUpperCase(),
        'is_active': budget.isActive ? 1 : 0,
        'spent_amount': oldBudget.spentAmount,
      },
      where: 'id = ?',
      whereArgs: [budget.id],
    );
  }
  /// Activates or deactivates a budget.
  static Future<void> setBudgetStatus(
    int budgetId,
    bool isActive,
  ) async {
    final db = await _database;
    final count = await db.update(
      'budgets',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [budgetId],
    );
    if (count == 0) {
      throw Exception('Budget was not found.');
    }
  }
  /// Deletes a budget.
  static Future<void> deleteBudget(int budgetId) async {
    final db = await _database;
    await db.delete(
      'budgets',
      where: 'id = ?',
      whereArgs: [budgetId],
    );
  }
  /// Returns budgets that have exceeded their limits.
  static Future<List<BudgetsModel>> getExceededBudgets() async {
    final budgets = await getBudgets(activeOnly: true);
    return budgets.where((budget) {
      return budget.spentAmount > budget.limitAmount;
    }).toList();
  }
  /// Returns budgets that have reached at least 80% of their limit.
  static Future<List<BudgetsModel>> getNearLimitBudgets({
    double threshold = 0.8,
  }) async {
    if (threshold <= 0 || threshold > 1) {
      throw Exception(
        'Threshold must be greater than 0 and at most 1.',
      );
    }
    final budgets = await getBudgets(activeOnly: true);
    return budgets.where((budget) {
      return budget.progress >= threshold &&
          !budget.isExceeded;
    }).toList();
  }
  /// Total budget limit grouped by currency.
  static Future<Map<String, double>> getTotalLimitsByCurrency() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT currency, COALESCE(SUM(limit_amount), 0) AS total
      FROM budgets
      WHERE is_active = 1
      GROUP BY currency
    ''');
    return {
      for (final row in rows)
        row['currency'].toString():
            (row['total'] as num).toDouble(),
    };
  }
  /// Actual spending grouped by currency.
  static Future<Map<String, double>> getTotalSpendingByCurrency() async {
    final budgets = await getBudgets(activeOnly: true);
    final totals = <String, double>{};
    for (final budget in budgets) {
      final currency = budget.currency.toUpperCase();
      totals[currency] =
          (totals[currency] ?? 0) + budget.spentAmount;
    }
    return totals;
  }
  /// Returns budgets for a particular category.
  static Future<List<BudgetsModel>> getBudgetsByCategory(
    String category,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'budgets',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'start_date DESC',
    );
    final result = <BudgetsModel>[];
    for (final row in rows) {
      result.add(
        await _refreshBudget(
          db,
          BudgetsModel.fromMap(row),
        ),
      );
    }
    return result;
  }
}
