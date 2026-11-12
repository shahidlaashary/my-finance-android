
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/models/repayment_model.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

class LoansService {

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
    if (_databaseInstance != null && _databaseInstance!.isOpen) {
      return _databaseInstance!;
    }

    final pendingFuture = _databaseFuture;

    if (pendingFuture != null) {
      return pendingFuture;
    }

    final future = _openDatabase();
    _databaseFuture = future;

    try {
      return await future;
    } catch (_) {
      if (identical(_databaseFuture, future)) {
        _databaseFuture = null;
      }
      rethrow;
    }
  }

  static Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();

    // FinanceDB may already have this file open. In that case sqflite
    // reuses its connection and does not run this service's onOpen callback.
    // Create loan tables explicitly so they exist on fresh and existing DBs.
    final db = await openDatabase(
      p.join(databasePath, _databaseName),
    );

    await _createTables(db);

    _databaseInstance = db;
    return db;
  }



  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS loans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        borrower_name TEXT NOT NULL,
        borrower_phone TEXT,
        amount REAL NOT NULL,
        remaining_amount REAL NOT NULL,
        wallet_id INTEGER NOT NULL,
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
        wallet_id INTEGER NOT NULL,
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
    int walletId,
  ) async {
    final wallets = await txn.query(
      'wallets',
      columns: ['id', 'balance', 'currency'],
      where: 'id = ?',
      whereArgs: [walletId],
      limit: 1,
    );

    if (wallets.isEmpty) {
      throw Exception('Selected account was not found.');
    }

    return wallets.first;
  }

  static Future<double> _getAccountBalance(
    Transaction txn,
    int walletId,
  ) async {
    final account = await _getAccount(txn, walletId);
    return (account['balance'] as num).toDouble();
  }

  static Future<String> _getAccountCurrency(
    Transaction txn,
    int walletId,
  ) async {
    final account = await _getAccount(txn, walletId);

    return (account['currency']?.toString() ?? 'PKR')
        .trim()
        .toUpperCase();
  }

  static Future<void> _changeAccountBalance(
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
    AppRefreshController.notifyChanged();
  }

  /// Loan banata hai aur di jane wali raqam source account se minus karta hai.
  static Future<int> addLoan(LoansModel loan) async {
    final db = await _database;
    final borrower = loan.borrowerName.trim();

    if (borrower.isEmpty) {
      throw Exception('Borrower name is required.');
    }

    if (!loan.amount.isFinite || loan.amount <= 0) {
      throw Exception(
        'Loan amount must be a valid amount greater than zero.',
      );
    }

    if (loan.walletId <= 0) {
      throw Exception('Please select a valid account.');
    }

    return db.transaction((txn) async {
      final balance = await _getAccountBalance(
        txn,
        loan.walletId,
      );

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
        walletId: loan.walletId,
        amount: -loan.amount,
      );

      return loanId;
    });
  }

  /// Loan ki currency wale account mein repayment ka record banata hai.
  static Future<int> addRepayment(RepaymentModel repayment) async {
    final db = await _database;

    if (!repayment.amount.isFinite || repayment.amount <= 0) {
      throw Exception(
        'Repayment amount must be a valid amount greater than zero.',
      );
    }

    if (repayment.walletId <= 0) {
      throw Exception('Please select a valid receiving account.');
    }

    if (repayment.loanId <= 0) {
      throw Exception('Invalid loan selected.');
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

      final loan = LoansModel.fromMap(loans.first);

      if (loan.remainingAmount <= 0) {
        throw Exception('This loan has already been fully repaid.');
      }

      if (repayment.amount > loan.remainingAmount + 0.000001) {
        throw Exception(
          'Repayment cannot exceed the outstanding balance.',
        );
      }

      final loanCurrency =
          await _getAccountCurrency(txn, loan.walletId);

      final receivingCurrency =
          await _getAccountCurrency(txn, repayment.walletId);

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
        walletId: repayment.walletId,
        amount: repayment.amount,
      );

      return repaymentId;
    });
  }

  /// Tamam loans naye se purane order mein deta hai.
  static Future<List<LoansModel>> getLoans() async {
    final db = await _database;

    final rows = await db.query(
      'loans',
      orderBy: 'lending_date DESC, id DESC',
    );

    return rows.map(LoansModel.fromMap).toList();
  }

  /// ID ki madad se aik loan hasil karta hai.
  static Future<LoansModel?> getLoanById(int loanId) async {
    final db = await _database;

    final rows = await db.query(
      'loans',
      where: 'id = ?',
      whereArgs: [loanId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return LoansModel.fromMap(rows.first);
  }

  /// Kisi loan ki tamam repayments deta hai.
  static Future<List<RepaymentModel>> getRepayments(
    int loanId,
  ) async {
    final db = await _database;

    final rows = await db.query(
      'loan_repayments',
      where: 'loan_id = ?',
      whereArgs: [loanId],
      orderBy: 'repayment_date DESC, id DESC',
    );

    return rows.map(RepaymentModel.fromMap).toList();
  }

  /// Source account ki currency ke mutabiq baqi loan amounts deta hai.
  static Future<Map<String, double>>
      getTotalOutstandingByCurrency() async {
    final db = await _database;

    final rows = await db.rawQuery('''
      SELECT
        UPPER(TRIM(COALESCE(wallets.currency, 'PKR'))) AS currency,
        COALESCE(SUM(loans.remaining_amount), 0) AS total
      FROM loans
      INNER JOIN wallets
        ON wallets.id = loans.wallet_id
      WHERE loans.remaining_amount > 0
      GROUP BY UPPER(TRIM(COALESCE(wallets.currency, 'PKR')))
      ORDER BY currency ASC
    ''');

    return {
      for (final row in rows)
        row['currency'].toString(): (row['total'] as num).toDouble(),
    };
  }

  /// Un loans ki list deta hai jin ki due date guzar chuki aur raqam baqi hai.
  static Future<List<LoansModel>> getOverdueLoans() async {
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

    return rows.map(LoansModel.fromMap).toList();
  }

  /// Repayment delete karta hai aur account aur loan balances ko pehli halat mein lata hai.
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

      final loan = LoansModel.fromMap(loanRows.first);

      await _getAccount(txn, repayment.walletId);

      final restoredRemaining =
          (loan.remainingAmount + repayment.amount)
              .clamp(0.0, loan.amount)
              .toDouble();

      await _changeAccountBalance(
        txn,
        walletId: repayment.walletId,
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

  /// Loan delete karta hai aur us se mutaliq account balance changes wapas karta hai.
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

      final loan = LoansModel.fromMap(loanRows.first);

      await _getAccount(txn, loan.walletId);

      final repayments = await txn.query(
        'loan_repayments',
        where: 'loan_id = ?',
        whereArgs: [loanId],
      );

      // Sab se pehle har repayment ka jama hua amount wapas minus karta hai.
      for (final row in repayments) {
        final repayment = RepaymentModel.fromMap(row);

        await _getAccount(txn, repayment.walletId);

        await _changeAccountBalance(
          txn,
          walletId: repayment.walletId,
          amount: -repayment.amount,
        );
      }

      // Di gayi asal loan raqam account mein wapas jama karta hai.
      await _changeAccountBalance(
        txn,
        walletId: loan.walletId,
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
