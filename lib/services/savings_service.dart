import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/savings_goal_model.dart';

class SavingsService {
  static const String _databaseName = 'my_finance.db';

  static Future<Database> get _database async {
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
      CREATE TABLE IF NOT EXISTS savings_goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        saved_amount REAL NOT NULL DEFAULT 0,
        target_date TEXT,
        account_id INTEGER,
        notes TEXT NOT NULL DEFAULT '',
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS savings_contributions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        goal_id INTEGER NOT NULL,
        account_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL DEFAULT 'contribution',
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_savings_contributions_goal
      ON savings_contributions(goal_id)
    ''');
  }

  static Future<Map<String, dynamic>> _getAccount(
    Transaction txn,
    int accountId,
  ) async {
    final rows = await txn.query(
      'accounts',
      columns: ['id', 'balance', 'currency'],
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw Exception('Selected account was not found.');
    }

    return rows.first;
  }

  static Future<void> _changeBalance(
    Transaction txn, {
    required int accountId,
    required double amount,
  }) async {
    await txn.rawUpdate(
      '''
      UPDATE accounts
      SET balance = balance + ?
      WHERE id = ?
      ''',
      [amount, accountId],
    );
  }

  static void _validateGoal(SavingsGoalModel goal) {
    if (goal.name.trim().isEmpty) {
      throw Exception('Savings goal name is required.');
    }

    if (!goal.targetAmount.isFinite || goal.targetAmount <= 0) {
      throw Exception('Target amount must be greater than zero.');
    }

    if (!goal.savedAmount.isFinite || goal.savedAmount < 0) {
      throw Exception('Saved amount cannot be negative.');
    }
  }

  /// Creates a new savings goal.
  static Future<int> addGoal(SavingsGoalModel goal) async {
    final db = await _database;

    _validateGoal(goal);

    if (goal.savedAmount > 0) {
      throw Exception(
        'Create the goal first, then add contributions.',
      );
    }

    return db.transaction((txn) async {
      if (goal.accountId != null) {
        await _getAccount(txn, goal.accountId!);
      }

      final now = DateTime.now();

      return txn.insert(
        'savings_goals',
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

  /// Returns all savings goals.
  static Future<List<SavingsGoalModel>> getGoals({
    bool includeCompleted = true,
  }) async {
    final db = await _database;

    final rows = await db.query(
      'savings_goals',
      where: includeCompleted ? null : 'is_completed = 0',
      orderBy: 'created_at DESC, id DESC',
    );

    return rows.map(SavingsGoalModel.fromMap).toList();
  }

  /// Returns one savings goal by ID.
  static Future<SavingsGoalModel?> getGoalById(int goalId) async {
    final db = await _database;

    final rows = await db.query(
      'savings_goals',
      where: 'id = ?',
      whereArgs: [goalId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return SavingsGoalModel.fromMap(rows.first);
  }

  /// Adds money to a savings goal and deducts it from the account.
  static Future<int> addContribution({
    required int goalId,
    required int accountId,
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
        'savings_goals',
        where: 'id = ?',
        whereArgs: [goalId],
        limit: 1,
      );

      if (goalRows.isEmpty) {
        throw Exception('Savings goal was not found.');
      }

      final goal = SavingsGoalModel.fromMap(goalRows.first);

      if (goal.isCompleted) {
        throw Exception('This savings goal is already completed.');
      }

      final account = await _getAccount(txn, accountId);

      if (goal.accountId != null &&
          goal.accountId != accountId) {
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
        'savings_contributions',
        {
          'goal_id': goalId,
          'account_id': accountId,
          'amount': amount,
          'type': 'contribution',
          'date': contributionDate.toIso8601String(),
          'note': note.trim(),
          'created_at': now.toIso8601String(),
        },
      );

      await _changeBalance(
        txn,
        accountId: accountId,
        amount: -amount,
      );

      await txn.update(
        'savings_goals',
        {
          'saved_amount': newSavedAmount,
          'account_id': goal.accountId ?? accountId,
          'is_completed': newSavedAmount >= goal.targetAmount ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [goalId],
      );

      return contributionId;
    });
  }

  /// Withdraws money from a savings goal and credits the account.
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
        'savings_goals',
        where: 'id = ?',
        whereArgs: [goalId],
        limit: 1,
      );

      if (goalRows.isEmpty) {
        throw Exception('Savings goal was not found.');
      }

      final goal = SavingsGoalModel.fromMap(goalRows.first);

      if (amount > goal.savedAmount + 0.000001) {
        throw Exception(
          'Withdrawal cannot exceed the saved amount.',
        );
      }

      if (goal.accountId == null) {
        throw Exception(
          'No account is linked to this savings goal.',
        );
      }

      await _getAccount(txn, goal.accountId!);

      final newSavedAmount =
          (goal.savedAmount - amount).clamp(0.0, goal.targetAmount).toDouble();

      final now = DateTime.now();

      final withdrawalId = await txn.insert(
        'savings_contributions',
        {
          'goal_id': goalId,
          'account_id': goal.accountId,
          'amount': amount,
          'type': 'withdrawal',
          'date': (date ?? now).toIso8601String(),
          'note': note.trim(),
          'created_at': now.toIso8601String(),
        },
      );

      await _changeBalance(
        txn,
        accountId: goal.accountId!,
        amount: amount,
      );

      await txn.update(
        'savings_goals',
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

  /// Returns contribution and withdrawal history for a goal.
  static Future<List<Map<String, dynamic>>> getHistory(
    int goalId,
  ) async {
    final db = await _database;

    return db.query(
      'savings_contributions',
      where: 'goal_id = ?',
      whereArgs: [goalId],
      orderBy: 'date DESC, id DESC',
    );
  }

  /// Updates goal details without changing its saved amount.
  static Future<void> updateGoal(
    SavingsGoalModel updatedGoal,
  ) async {
    if (updatedGoal.id == null) {
      throw Exception('Goal ID is required.');
    }

    _validateGoal(updatedGoal);

    final db = await _database;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'savings_goals',
        where: 'id = ?',
        whereArgs: [updatedGoal.id],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw Exception('Savings goal was not found.');
      }

      final oldGoal = SavingsGoalModel.fromMap(rows.first);

      if (updatedGoal.targetAmount < oldGoal.savedAmount) {
        throw Exception(
          'Target amount cannot be less than the saved amount.',
        );
      }

      if (updatedGoal.accountId != oldGoal.accountId) {
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
        'savings_goals',
        {
          'name': updatedGoal.name.trim(),
          'target_amount': updatedGoal.targetAmount,
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

  /// Deletes a goal and reverses its contribution/withdrawal balance changes.
  static Future<void> deleteGoal(int goalId) async {
    final db = await _database;

    await db.transaction((txn) async {
      final goalRows = await txn.query(
        'savings_goals',
        where: 'id = ?',
        whereArgs: [goalId],
        limit: 1,
      );

      if (goalRows.isEmpty) return;

      final history = await txn.query(
        'savings_contributions',
        where: 'goal_id = ?',
        whereArgs: [goalId],
      );

      for (final row in history) {
        final accountId = (row['account_id'] as num).toInt();
        final amount = (row['amount'] as num).toDouble();
        final type = row['type']?.toString();

        await _getAccount(txn, accountId);

        await _changeBalance(
          txn,
          accountId: accountId,
          amount: type == 'withdrawal' ? -amount : amount,
        );
      }

      await txn.delete(
        'savings_contributions',
        where: 'goal_id = ?',
        whereArgs: [goalId],
      );

      await txn.delete(
        'savings_goals',
        where: 'id = ?',
        whereArgs: [goalId],
      );
    });
  }

  /// Total saved amount across all goals.
  static Future<double> getTotalSaved() async {
    final db = await _database;

    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(saved_amount), 0) AS total
      FROM savings_goals
    ''');

    return (result.first['total'] as num).toDouble();
  }

  /// Total target amount across all goals.
  static Future<double> getTotalTarget() async {
    final db = await _database;

    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(target_amount), 0) AS total
      FROM savings_goals
    ''');

    return (result.first['total'] as num).toDouble();
  }

  /// Returns goals that have passed their target date.
  static Future<List<SavingsGoalModel>> getOverdueGoals() async {
    final db = await _database;

    final today = DateTime.now();
    final todayString =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    final rows = await db.query(
      'savings_goals',
      where: '''
        is_completed = 0
        AND target_date IS NOT NULL
        AND date(target_date) < date(?)
      ''',
      whereArgs: [todayString],
      orderBy: 'target_date ASC',
    );

    return rows.map(SavingsGoalModel.fromMap).toList();
  }
}
