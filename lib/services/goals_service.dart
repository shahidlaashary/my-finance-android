import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/goals_model.dart';
class GoalsService {

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
    return openDatabase(
      p.join(databasePath, _databaseName),
      onOpen: (db) async {
        await _createTables(db);
      },
    );
  }
  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        saved_amount REAL NOT NULL DEFAULT 0,
        start_date TEXT,
        target_date TEXT,
        wallet_id INTEGER,
        notes TEXT NOT NULL DEFAULT '',
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    final goalColumns = await db.rawQuery('PRAGMA table_info(goals)');
    final hasStartDate = goalColumns.any(
      (column) => column['name'] == 'start_date',
    );
    if (!hasStartDate) {
      await db.execute('ALTER TABLE goals ADD COLUMN start_date TEXT');
      await db.execute(
        "UPDATE goals SET start_date = COALESCE(created_at, date('now')) "
        "WHERE start_date IS NULL",
      );
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS goal_contributions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        goal_id INTEGER NOT NULL,
        wallet_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL DEFAULT 'contribution',
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_goal_contributions_goal
      ON goal_contributions(goal_id)
    ''');
  }
  static Future<Map<String, dynamic>> _getAccount(
    Transaction txn,
    int walletId,
  ) async {
    final rows = await txn.query(
      'wallets',
      columns: ['id', 'balance', 'currency'],
      where: 'id = ?',
      whereArgs: [walletId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('Selected account was not found.');
    }
    return rows.first;
  }
  static Future<void> _changeBalance(
    Transaction txn, {
    required int walletId,
    required double amount,
  }) async {
    await txn.rawUpdate(
      '''
      UPDATE wallets
      SET balance = balance + ?
      WHERE id = ?
      ''',
      [amount, walletId],
    );
  }
  static void _validateGoal(GoalsModel goal) {
    if (goal.name.trim().isEmpty) {
      throw Exception('Savings goal name is required.');
    }
    if (!goal.targetAmount.isFinite || goal.targetAmount <= 0) {
      throw Exception('Target amount must be greater than zero.');
    }
    if (!goal.savedAmount.isFinite || goal.savedAmount < 0) {
      throw Exception('Saved amount cannot be negative.');
    }
    if (goal.startDate != null &&
        goal.targetDate != null &&
        goal.startDate!.isAfter(goal.targetDate!)) {
      throw Exception('Start date cannot be after target date.');
    }
  }
  /// Naya savings goal banata hai.
  static Future<int> addGoal(GoalsModel goal) async {
    final db = await _database;
    _validateGoal(goal);
    if (goal.savedAmount > 0) {
      throw Exception(
        'Create the goal first, then add contributions.',
      );
    }
    return db.transaction((txn) async {
      if (goal.walletId != null) {
        await _getAccount(txn, goal.walletId!);
      }
      final now = DateTime.now();
      return txn.insert(
        'goals',
        goal.copyWith(
          name: goal.name.trim(),
          savedAmount: 0,
          isCompleted: false,
          createdAt: goal.createdAt ?? now,
        ).toMap()
          ..remove('id'),
      );
    });
  }
  /// Tamam savings goals hasil karta hai.
  static Future<List<GoalsModel>> getGoals({
    bool includeCompleted = true,
  }) async {
    final db = await _database;
    // Ensure the goals table exists on this connection without changing
    // database versions or migrating existing records.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        saved_amount REAL NOT NULL DEFAULT 0,
        start_date TEXT,
        target_date TEXT,
        wallet_id INTEGER,
        notes TEXT NOT NULL DEFAULT '',
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    final rows = await db.query(
      'goals',
      where: includeCompleted ? null : 'is_completed = 0',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(GoalsModel.fromMap).toList();
  }
  /// ID ki madad se aik savings goal hasil karta hai.
  static Future<GoalsModel?> getGoalById(int goalId) async {
    final db = await _database;
    final rows = await db.query(
      'goals',
      where: 'id = ?',
      whereArgs: [goalId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GoalsModel.fromMap(rows.first);
  }
  /// Savings goal mein raqam jama karta hai aur selected account se minus karta hai.
  static Future<int> addContribution({
    required int goalId,
    required int walletId,
    required double amount,
    DateTime? date,
    String note = '',
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw Exception('Contribution must be greater than zero.');
    }
    final db = await _database;
    return db.transaction((txn) async {
      final goalRows = await txn.query(
        'goals',
        where: 'id = ?',
        whereArgs: [goalId],
        limit: 1,
      );
      if (goalRows.isEmpty) {
        throw Exception('Savings goal was not found.');
      }
      final goal = GoalsModel.fromMap(goalRows.first);
      if (goal.isCompleted) {
        throw Exception('This savings goal is already completed.');
      }
      final account = await _getAccount(txn, walletId);
      if (goal.walletId != null &&
          goal.walletId != walletId) {
        throw Exception(
          'Please use the account linked to this savings goal.',
        );
      }
      final balance = (account['balance'] as num).toDouble();
      if (balance < amount) {
        throw Exception('Insufficient account balance.');
      }
      final newSavedAmount = goal.savedAmount + amount;
      final now = DateTime.now();
      final contributionDate = date ?? now;
      final contributionId = await txn.insert(
        'goal_contributions',
        {
          'goal_id': goalId,
          'wallet_id': walletId,
          'amount': amount,
          'type': 'contribution',
          'date': contributionDate.toIso8601String(),
          'note': note.trim(),
          'created_at': now.toIso8601String(),
        },
      );
      await _changeBalance(
        txn,
        walletId: walletId,
        amount: -amount,
      );
      await txn.update(
        'goals',
        {
          'saved_amount': newSavedAmount,
          'wallet_id': goal.walletId ?? walletId,
          'is_completed': newSavedAmount >= goal.targetAmount ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [goalId],
      );
      return contributionId;
    });
  }
  /// Savings goal se raqam nikal kar account mein jama karta hai.
  static Future<int> withdraw({
    required int goalId,
    required double amount,
    DateTime? date,
    String note = '',
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw Exception('Withdrawal must be greater than zero.');
    }
    final db = await _database;
    return db.transaction((txn) async {
      final goalRows = await txn.query(
        'goals',
        where: 'id = ?',
        whereArgs: [goalId],
        limit: 1,
      );
      if (goalRows.isEmpty) {
        throw Exception('Savings goal was not found.');
      }
      final goal = GoalsModel.fromMap(goalRows.first);
      if (amount > goal.savedAmount + 0.000001) {
        throw Exception(
          'Withdrawal cannot exceed the saved amount.',
        );
      }
      if (goal.walletId == null) {
        throw Exception(
          'No account is linked to this savings goal.',
        );
      }
      await _getAccount(txn, goal.walletId!);
      final newSavedAmount =
          (goal.savedAmount - amount).clamp(0.0, goal.targetAmount).toDouble();
      final now = DateTime.now();
      final withdrawalId = await txn.insert(
        'goal_contributions',
        {
          'goal_id': goalId,
          'wallet_id': goal.walletId,
          'amount': amount,
          'type': 'withdrawal',
          'date': (date ?? now).toIso8601String(),
          'note': note.trim(),
          'created_at': now.toIso8601String(),
        },
      );
      await _changeBalance(
        txn,
        walletId: goal.walletId!,
        amount: amount,
      );
      await txn.update(
        'goals',
        {
          'saved_amount': newSavedAmount,
          'is_completed': newSavedAmount >= goal.targetAmount ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [goalId],
      );
      return withdrawalId;
    });
  }
  /// Goal ki contributions aur withdrawals ki history deta hai.
  static Future<List<Map<String, dynamic>>> getHistory(
    int goalId,
  ) async {
    final db = await _database;
    return db.query(
      'goal_contributions',
      where: 'goal_id = ?',
      whereArgs: [goalId],
      orderBy: 'date DESC, id DESC',
    );
  }
  /// Jama shuda raqam ko badle baghair goal ki details update karta hai.
  static Future<void> updateGoal(
    GoalsModel updatedGoal,
  ) async {
    if (updatedGoal.id == null) {
      throw Exception('Goal ID is required.');
    }
    _validateGoal(updatedGoal);
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'goals',
        where: 'id = ?',
        whereArgs: [updatedGoal.id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw Exception('Savings goal was not found.');
      }
      final oldGoal = GoalsModel.fromMap(rows.first);
      if (updatedGoal.targetAmount < oldGoal.savedAmount) {
        throw Exception(
          'Target amount cannot be less than the saved amount.',
        );
      }
      if (updatedGoal.walletId != oldGoal.walletId) {
        throw Exception(
          'The linked account cannot be changed after contributions.',
        );
      }
      if (updatedGoal.savedAmount != oldGoal.savedAmount) {
        throw Exception(
          'Saved amount can only be changed through contributions or withdrawals.',
        );
      }
      await txn.update(
        'goals',
        {
          'name': updatedGoal.name.trim(),
          'target_amount': updatedGoal.targetAmount,
          'start_date': updatedGoal.startDate?.toIso8601String(),
          'target_date': updatedGoal.targetDate?.toIso8601String(),
          'notes': updatedGoal.notes,
          'is_completed':
              oldGoal.savedAmount >= updatedGoal.targetAmount ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [updatedGoal.id],
      );
    });
  }
  /// Goal delete karta hai aur contributions ya withdrawals ke balance changes wapas karta hai.
  static Future<void> deleteGoal(int goalId) async {
    final db = await _database;
    await db.transaction((txn) async {
      final goalRows = await txn.query(
        'goals',
        where: 'id = ?',
        whereArgs: [goalId],
        limit: 1,
      );
      if (goalRows.isEmpty) return;
      final history = await txn.query(
        'goal_contributions',
        where: 'goal_id = ?',
        whereArgs: [goalId],
      );
      for (final row in history) {
        final walletId = (row['wallet_id'] as num).toInt();
        final amount = (row['amount'] as num).toDouble();
        final type = row['type']?.toString();
        await _getAccount(txn, walletId);
        await _changeBalance(
          txn,
          walletId: walletId,
          amount: type == 'withdrawal' ? -amount : amount,
        );
      }
      await txn.delete(
        'goal_contributions',
        where: 'goal_id = ?',
        whereArgs: [goalId],
      );
      await txn.delete(
        'goals',
        where: 'id = ?',
        whereArgs: [goalId],
      );
    });
  }
  /// Account currency ke mutabiq jama shuda raqam ka total deta hai.
  /// Jin goals ke sath account link nahi, unhein Unassigned mein rakhta hai.
  static Future<Map<String, double>> getTotalSavedByCurrency() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(NULLIF(TRIM(wallets.currency), ''), 'Unassigned') AS currency,
        COALESCE(SUM(goals.saved_amount), 0) AS total
      FROM goals
      LEFT JOIN wallets
        ON wallets.id = goals.wallet_id
      GROUP BY currency
      ORDER BY currency ASC
    ''');
    return {
      for (final row in rows)
        row['currency'].toString(): (row['total'] as num).toDouble(),
    };
  }
  /// Account currency ke mutabiq target amounts ka total deta hai.
  /// Jin goals ke sath account link nahi, unhein Unassigned mein rakhta hai.
  static Future<Map<String, double>> getTotalTargetByCurrency() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(NULLIF(TRIM(wallets.currency), ''), 'Unassigned') AS currency,
        COALESCE(SUM(goals.target_amount), 0) AS total
      FROM goals
      LEFT JOIN wallets
        ON wallets.id = goals.wallet_id
      GROUP BY currency
      ORDER BY currency ASC
    ''');
    return {
      for (final row in rows)
        row['currency'].toString(): (row['total'] as num).toDouble(),
    };
  }
  /// Un goals ki list deta hai jin ki target date guzar chuki ho.
  static Future<List<GoalsModel>> getOverdueGoals() async {
    final db = await _database;
    final today = DateTime.now();
    final todayString =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final rows = await db.query(
      'goals',
      where: '''
        is_completed = 0
        AND target_date IS NOT NULL
        AND date(target_date) < date(?)
      ''',
      whereArgs: [todayString],
      orderBy: 'target_date ASC',
    );
    return rows.map(GoalsModel.fromMap).toList();
  }
}
