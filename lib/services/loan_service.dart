import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/loan_model.dart';
import '../models/repayment_model.dart';

class LoanService {
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
      CREATE TABLE IF NOT EXISTS loans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        borrower_name TEXT NOT NULL,
        borrower_phone TEXT,
        amount REAL NOT NULL,
        remaining_amount REAL NOT NULL,
        account_id INTEGER NOT NULL,
        lending_date TEXT NOT NULL,
        due_date TEXT,
        notes TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_repayments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        loan_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        account_id INTEGER NOT NULL,
        repayment_date TEXT NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (loan_id) REFERENCES loans(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_loans_status
      ON loans(status)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_repayments_loan
      ON loan_repayments(loan_id)
    ''');
  }

  static Future<Map<String, dynamic>> _getAccount(
    Transaction txn,
    int accountId,
  ) async {
    final accounts = await txn.query(
      'accounts',
      columns: ['id', 'balance', 'currency'],
      where: 'id = ?',
      whereArgs: [accountId],
      limit: 1,
    );

    if (accounts.isEmpty) {
      throw Exception('Selected account was not found.');
    }

    return accounts.first;
  }

  static Future<double> _getAccountBalance(
    Transaction txn,
    int accountId,
  ) async {
    final account = await _getAccount(txn, accountId);
    return (account['balance'] as num).toDouble();
  }

  static Future<String> _getAccountCurrency(
    Transaction txn,
    int accountId,
  ) async {
    final account = await _getAccount(txn, accountId);
    return (account['currency'] as String).trim().toUpperCase();
  }

  static Future<void> _changeAccountBalance(
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

  /// Creates a loan and deducts the lending amount from the source account.
  static Future<int> addLoan(LoanModel loan) async {
    final db = await _database;
    final borrower = loan.borrowerName.trim();

    if (borrower.isEmpty) {
      throw Exception('Borrower name is required.');
    }

    if (!loan.amount.isFinite || loan.amount <= 0) {
      throw Exception('Loan amount must be a valid amount greater than zero.');
    }

    if (loan.accountId <= 0) {
      throw Exception('Please select a valid account.');
    }

    return db.transaction((txn) async {
      final balance = await _getAccountBalance(txn, loan.accountId);

      if (balance < loan.amount) {
        throw Exception('Insufficient account balance.');
      }

      final loanId = await txn.insert(
        'loans',
        loan.copyWith(
          borrowerName: borrower,
          remainingAmount: loan.amount,
          status: 'active',
        ).toMap()..remove('id'),
      );

      await _changeAccountBalance(
        txn,
        accountId: loan.accountId,
        amount: -loan.amount,
      );

      return loanId;
    });
  }

  /// Records a partial or full repayment and updates the receiving account.
  /// The receiving account must use the same currency as the original loan.
  static Future<int> addRepayment(RepaymentModel repayment) async {
    final db = await _database;

    if (!repayment.amount.isFinite || repayment.amount <= 0) {
      throw Exception(
        'Repayment amount must be a valid amount greater than zero.',
      );
    }

    if (repayment.accountId <= 0) {
      throw Exception('Please select a valid receiving account.');
    }

    return db.transaction((txn) async {
      final loans = await txn.query(
        'loans',
        where: 'id = ?',
        whereArgs: [repayment.loanId],
        limit: 1,
      );

      if (loans.isEmpty) {
        throw Exception('Loan was not found.');
      }

      final loan = LoanModel.fromMap(loans.first);

      if (loan.remainingAmount <= 0) {
        throw Exception('This loan has already been fully repaid.');
      }

      if (repayment.amount > loan.remainingAmount + 0.000001) {
        throw Exception(
          'Repayment cannot exceed the outstanding balance.',
        );
      }

      final loanCurrency =
          await _getAccountCurrency(txn, loan.accountId);
      final receivingCurrency =
          await _getAccountCurrency(txn, repayment.accountId);

      if (loanCurrency != receivingCurrency) {
        throw Exception(
          'The receiving account must use the same currency as the loan '
          'source account ($loanCurrency).',
        );
      }

      final newRemaining = (loan.remainingAmount - repayment.amount)
          .clamp(0.0, loan.amount)
          .toDouble();

      final repaymentId = await txn.insert(
        'loan_repayments',
        repayment.toMap()..remove('id'),
      );

      await txn.update(
        'loans',
        {
          'remaining_amount': newRemaining,
          'status': newRemaining <= 0 ? 'paid' : 'active',
        },
        where: 'id = ?',
        whereArgs: [repayment.loanId],
      );

      await _changeAccountBalance(
        txn,
        accountId: repayment.accountId,
        amount: repayment.amount,
      );

      return repaymentId;
    });
  }

  /// Returns all loans, newest first.
  static Future<List<LoanModel>> getLoans() async {
    final db = await _database;
    final rows = await db.query(
      'loans',
      orderBy: 'lending_date DESC, id DESC',
    );

    return rows.map(LoanModel.fromMap).toList();
  }

  /// Returns one loan by its ID.
  static Future<LoanModel?> getLoanById(int loanId) async {
    final db = await _database;
    final rows = await db.query(
      'loans',
      where: 'id = ?',
      whereArgs: [loanId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return LoanModel.fromMap(rows.first);
  }

  /// Returns repayments belonging to a loan.
  static Future<List<RepaymentModel>> getRepayments(int loanId) async {
    final db = await _database;
    final rows = await db.query(
      'loan_repayments',
      where: 'loan_id = ?',
      whereArgs: [loanId],
      orderBy: 'repayment_date DESC, id DESC',
    );

    return rows.map(RepaymentModel.fromMap).toList();
  }

  /// Returns the total outstanding amount across all loans.
  static Future<double> getTotalOutstanding() async {
    final db = await _database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(remaining_amount), 0) AS total
      FROM loans
      WHERE remaining_amount > 0
    ''');

    return (result.first['total'] as num).toDouble();
  }

  /// Returns loans whose due date has passed and balance is outstanding.
  static Future<List<LoanModel>> getOverdueLoans() async {
    final db = await _database;
    final today = DateTime.now();
    final todayString =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    final rows = await db.query(
      'loans',
      where: '''
        remaining_amount > 0
        AND due_date IS NOT NULL
        AND due_date != ''
        AND date(due_date) < date(?)
      ''',
      whereArgs: [todayString],
      orderBy: 'due_date ASC',
    );

    return rows.map(LoanModel.fromMap).toList();
  }

  /// Deletes a repayment and reverses its account and loan balances.
  static Future<void> deleteRepayment(int repaymentId) async {
    final db = await _database;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'loan_repayments',
        where: 'id = ?',
        whereArgs: [repaymentId],
        limit: 1,
      );

      if (rows.isEmpty) return;

      final repayment = RepaymentModel.fromMap(rows.first);
      final loanRows = await txn.query(
        'loans',
        where: 'id = ?',
        whereArgs: [repayment.loanId],
        limit: 1,
      );

      if (loanRows.isEmpty) {
        throw Exception('Related loan was not found.');
      }

      final loan = LoanModel.fromMap(loanRows.first);
      await _getAccount(txn, repayment.accountId);

      final restoredRemaining =
          (loan.remainingAmount + repayment.amount)
              .clamp(0.0, loan.amount)
              .toDouble();

      await _changeAccountBalance(
        txn,
        accountId: repayment.accountId,
        amount: -repayment.amount,
      );

      await txn.update(
        'loans',
        {
          'remaining_amount': restoredRemaining,
          'status': restoredRemaining <= 0 ? 'paid' : 'active',
        },
        where: 'id = ?',
        whereArgs: [repayment.loanId],
      );

      await txn.delete(
        'loan_repayments',
        where: 'id = ?',
        whereArgs: [repaymentId],
      );
    });
  }

  /// Deletes a loan and reverses all related account balance changes.
  static Future<void> deleteLoan(int loanId) async {
    final db = await _database;

    await db.transaction((txn) async {
      final loanRows = await txn.query(
        'loans',
        where: 'id = ?',
        whereArgs: [loanId],
        limit: 1,
      );

      if (loanRows.isEmpty) return;

      final loan = LoanModel.fromMap(loanRows.first);
      await _getAccount(txn, loan.accountId);

      final repayments = await txn.query(
        'loan_repayments',
        where: 'loan_id = ?',
        whereArgs: [loanId],
      );

      // Reverse every repayment credit first.
      for (final row in repayments) {
        final repayment = RepaymentModel.fromMap(row);
        await _getAccount(txn, repayment.accountId);

        await _changeAccountBalance(
          txn,
          accountId: repayment.accountId,
          amount: -repayment.amount,
        );
      }

      // Restore the original lending amount.
      await _changeAccountBalance(
        txn,
        accountId: loan.accountId,
        amount: loan.amount,
      );

      await txn.delete(
        'loan_repayments',
        where: 'loan_id = ?',
        whereArgs: [loanId],
      );

      await txn.delete(
        'loans',
        where: 'id = ?',
        whereArgs: [loanId],
      );
    });
  }
}
