
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/models/repayment_model.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

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
        party_id INTEGER,
        loan_type TEXT NOT NULL DEFAULT 'given',
        amount REAL NOT NULL,
        remaining_amount REAL NOT NULL,
        wallet_id INTEGER NOT NULL,
        currency TEXT NOT NULL DEFAULT 'PKR',
        source_type TEXT,
        source_id INTEGER,
        lending_date TEXT NOT NULL,
        due_date TEXT,
        notes TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT NOT NULL DEFAULT '',
        currency TEXT NOT NULL DEFAULT 'PKR',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''' );

    final loanColumns = await db.rawQuery('PRAGMA table_info(loans)');
    if (!loanColumns.any((column) => column['name'] == 'currency')) {
      await db.execute("ALTER TABLE loans ADD COLUMN currency TEXT NOT NULL DEFAULT 'PKR'");
      await db.execute("UPDATE loans SET currency = COALESCE((SELECT currency FROM wallets WHERE wallets.id = loans.wallet_id), 'PKR')");
    }
    if (!loanColumns.any((column) => column['name'] == 'source_type')) {
      await db.execute("ALTER TABLE loans ADD COLUMN source_type TEXT");
    }
    if (!loanColumns.any((column) => column['name'] == 'source_id')) {
      await db.execute("ALTER TABLE loans ADD COLUMN source_id INTEGER");
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_loans_source ON loans(source_type, source_id)');

    final partyColumns = await db.rawQuery('PRAGMA table_info(loan_parties)');
    if (!partyColumns.any((column) => column['name'] == 'currency')) {
      await db.execute("ALTER TABLE loan_parties ADD COLUMN currency TEXT NOT NULL DEFAULT 'PKR'");
    }

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

  static Future<List<Map<String, dynamic>>> getParties() async {
    final db = await _database;
    return db.query('loan_parties', orderBy: 'name COLLATE NOCASE ASC');
  }

  static Future<int> addParty({
    required String name,
    String? phone,
    String address = '',
    String notes = '',
    String currency = 'PKR',
  }) async {
    final db = await _database;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw Exception('Party name is required.');
    final normalizedPhone = phone?.trim() ?? '';
    final existing = await db.query(
      'loan_parties',
      columns: ['id', 'currency'],
      where: normalizedPhone.isEmpty
          ? 'LOWER(TRIM(name)) = LOWER(?) AND COALESCE(phone, \'\') = \'\''
          : 'LOWER(TRIM(name)) = LOWER(?) AND phone = ?',
      whereArgs: normalizedPhone.isEmpty
          ? [normalizedName]
          : [normalizedName, normalizedPhone],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final existingCurrency = (existing.first['currency']?.toString() ?? 'PKR').toUpperCase();
      if (existingCurrency != currency.trim().toUpperCase()) {
        throw Exception('A party with this name and phone already exists in ' + existingCurrency + '. Edit that party to change its currency.');
      }
      return existing.first['id'] as int;
    }
    return db.insert('loan_parties', {
      'name': normalizedName,
      'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
      'address': address.trim(),
      'currency': currency.trim().toUpperCase(),
      'notes': notes.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> updateParty({
    required int id,
    required String name,
    String? phone,
    String address = '',
    String currency = 'PKR',
  }) async {
    final db = await _database;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw Exception('Party name is required.');
    final normalizedPhone = phone?.trim() ?? '';
    final duplicate = await db.query(
      'loan_parties',
      where: "id != ? AND LOWER(TRIM(name)) = LOWER(?) AND COALESCE(phone, '') = ?",
      whereArgs: [id, normalizedName, normalizedPhone],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw Exception('A party with this name and phone number already exists.');
    }
    final changed = await db.update(
      'loan_parties',
      {
        'name': normalizedName,
        'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
        'address': address.trim(),
        'currency': currency.trim().toUpperCase(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed == 0) throw Exception('Party was not found.');
  }

  /// Party sirf tab delete hoti hai jab us ke sath koi loan linked na ho.
  static Future<void> deleteParty(int partyId) async {
    final db = await _database;
    final linkedLoans = await db.query(
      'loans',
      columns: ['id'],
      where: 'party_id = ?',
      whereArgs: [partyId],
      limit: 1,
    );
    if (linkedLoans.isNotEmpty) {
      throw Exception(
        'This party has loan history. Delete is blocked to protect linked loans and ledger records.',
      );
    }
    final rows = await db.query(
      'loan_parties',
      where: 'id = ?',
      whereArgs: [partyId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    await RecycleBinService.archive(
      type: 'Loan Party',
      title: rows.first['name']?.toString() ?? 'Party',
      table: 'loan_parties',
      id: partyId,
      record: rows.first,
    );
    await db.delete('loan_parties', where: 'id = ?', whereArgs: [partyId]);
  }

  static Future<Map<String, dynamic>?> getPartyById(int id) async {
    final db = await _database;
    final rows = await db.query('loan_parties', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<LoansModel>> getLoansForParty(int partyId) async {
    final db = await _database;
    final rows = await db.query('loans', where: 'party_id = ?', whereArgs: [partyId], orderBy: 'lending_date DESC, id DESC');
    return rows.map(LoansModel.fromMap).toList();
  }

  static Future<Map<String, dynamic>> getPartySummary(int partyId) async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT
        UPPER(TRIM(COALESCE(loans.currency, wallets.currency, 'PKR'))) AS currency,
        loans.loan_type AS loan_type,
        COALESCE(SUM(loans.remaining_amount), 0) AS outstanding,
        COUNT(*) AS loan_count
      FROM loans
      INNER JOIN wallets ON wallets.id = loans.wallet_id
      WHERE loans.party_id = ?
      GROUP BY currency, loans.loan_type
      ORDER BY currency, loans.loan_type
    ''', [partyId]);
    return {
      'loan_count': rows.fold<int>(0, (sum, row) => sum + ((row['loan_count'] as num?)?.toInt() ?? 0)),
      'balances': rows.map((row) => {
        'currency': row['currency'],
        'loan_type': row['loan_type'],
        'outstanding': row['outstanding'],
      }).toList(),
    };
  }

  static Future<Map<String, dynamic>> _getWallet(
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
      throw Exception('Selected wallet was not found.');
    }

    return wallets.first;
  }

  static Future<double> _getWalletBalance(
    Transaction txn,
    int walletId,
  ) async {
    final wallet = await _getWallet(txn, walletId);
    return (wallet['balance'] as num).toDouble();
  }

  static Future<String> _getWalletCurrency(
    Transaction txn,
    int walletId,
  ) async {
    final wallet = await _getWallet(txn, walletId);

    return (wallet['currency']?.toString() ?? 'PKR')
        .trim()
        .toUpperCase();
  }

  static Future<void> _changeWalletBalance(
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

  /// Loan banata hai aur di jane wali raqam source wallet se minus karta hai.
  static Future<int> addLoan(LoansModel loan) async {
    final db = await _database;
    if (!loan.amount.isFinite || loan.amount <= 0) {
      throw Exception(
        'Loan amount must be a valid amount greater than zero.',
      );
    }

    if (loan.partyId == null || loan.partyId! <= 0) {
      throw Exception('Please select or create a party.');
    }

    if (loan.walletId <= 0) {
      throw Exception('Please select a valid wallet.');
    }

    return db.transaction((txn) async {
      final party = await txn.query(
        'loan_parties',
        columns: ['id', 'currency'],
        where: 'id = ?',
        whereArgs: [loan.partyId],
        limit: 1,
      );
      if (party.isEmpty) {
        throw Exception('Selected party was not found.');
      }
      final partyCurrency = (party.first['currency']?.toString() ?? 'PKR').trim().toUpperCase();
      final walletCurrency = await _getWalletCurrency(txn, loan.walletId);
      if (partyCurrency != walletCurrency) {
        throw Exception('Selected wallet currency ($walletCurrency) does not match this party currency ($partyCurrency).');
      }

      final balance = await _getWalletBalance(
        txn,
        loan.walletId,
      );

      if (loan.loanType == 'given' && balance < loan.amount) {
        throw Exception('Insufficient wallet balance.');
      }

      final loanId = await txn.insert(
        'loans',
        loan.copyWith(
          remainingAmount: loan.amount,
          status: 'active',
          currency: partyCurrency,
        ).toMap()..remove('id'),
      );

      await _changeWalletBalance(
        txn,
        walletId: loan.walletId,
        amount: loan.loanType == 'given' ? -loan.amount : loan.amount,
      );

      return loanId;
    });
  }

  /// Asset purchase/sale ke liye loan create karta hai, bina kisi wallet ko debit/credit kiye.
  /// Matching-currency wallet sirf repayment currency anchor hota hai.
  static Future<int> createAssetLinkedLoan({
    required int partyId,
    required String loanType,
    required double amount,
    required String lendingDate,
    required String sourceType,
    required int sourceId,
    String notes = '',
  }) async {
    if (!amount.isFinite || amount <= 0) throw Exception('Loan amount must be greater than zero.');
    if (sourceType != 'asset_purchase' && sourceType != 'asset_sale') {
      throw Exception('Invalid asset loan reference.');
    }
    final db = await _database;
    return db.transaction((txn) async {
      final parties = await txn.query('loan_parties', where: 'id = ?', whereArgs: [partyId], limit: 1);
      if (parties.isEmpty) throw Exception('Selected party was not found.');
      final currency = (parties.first['currency']?.toString() ?? 'PKR').toUpperCase();
      final wallets = await txn.query(
        'wallets',
        columns: ['id'],
        where: 'UPPER(TRIM(COALESCE(currency, \'PKR\'))) = ?',
        whereArgs: [currency],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (wallets.isEmpty) {
        throw Exception('Create a $currency wallet first. A matching-currency wallet is required for future repayments.');
      }
      final walletId = (wallets.first['id'] as num).toInt();
      return txn.insert('loans', {
        'party_id': partyId,
        'loan_type': loanType,
        'amount': amount,
        'remaining_amount': amount,
        'wallet_id': walletId,
        'currency': currency,
        'source_type': sourceType,
        'source_id': sourceId,
        'lending_date': lendingDate,
        'notes': notes,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  /// Asset-linked loan ko uski repayments ke baghair edit karta hai.
  static Future<void> updateAssetLinkedLoan({
    required int loanId,
    required int partyId,
    required String loanType,
    required double amount,
    required String lendingDate,
    required String notes,
  }) async {
    if (!amount.isFinite || amount <= 0) throw Exception('Loan amount must be greater than zero.');
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query('loans', where: 'id = ?', whereArgs: [loanId], limit: 1);
      if (rows.isEmpty || rows.first['source_type'] == null) throw Exception('Linked asset loan was not found.');
      final repayments = await txn.query('loan_repayments', columns: ['id'], where: 'loan_id = ?', whereArgs: [loanId], limit: 1);
      if (repayments.isNotEmpty) throw Exception('This asset already has loan repayments. Its linked loan details cannot be changed.');
      final parties = await txn.query('loan_parties', where: 'id = ?', whereArgs: [partyId], limit: 1);
      if (parties.isEmpty) throw Exception('Selected party was not found.');
      final currency = (parties.first['currency']?.toString() ?? 'PKR').toUpperCase();
      final wallets = await txn.query('wallets', columns: ['id'], where: 'UPPER(TRIM(COALESCE(currency, \'PKR\'))) = ?', whereArgs: [currency], limit: 1);
      if (wallets.isEmpty) throw Exception('Create a $currency wallet first for future repayments.');
      await txn.update('loans', {
        'party_id': partyId, 'loan_type': loanType, 'amount': amount,
        'remaining_amount': amount, 'wallet_id': wallets.first['id'],
        'currency': currency, 'lending_date': lendingDate,
        'notes': notes, 'status': 'active',
      }, where: 'id = ?', whereArgs: [loanId]);
    });
  }

  /// Loan ki currency wale wallet mein repayment ka record banata hai.
  static Future<int> addRepayment(RepaymentModel repayment) async {
    final db = await _database;

    if (!repayment.amount.isFinite || repayment.amount <= 0) {
      throw Exception(
        'Repayment amount must be a valid amount greater than zero.',
      );
    }

    if (repayment.walletId <= 0) {
      throw Exception('Please select a valid receiving wallet.');
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

      final loanCurrency = loan.currency.toUpperCase();

      final receivingCurrency =
          await _getWalletCurrency(txn, repayment.walletId);

      if (loanCurrency != receivingCurrency) {
        throw Exception(
          'The receiving wallet must use the same currency as the loan '
          'source wallet ($loanCurrency).',
        );
      }

      if (loan.loanType == 'taken' &&
          await _getWalletBalance(txn, repayment.walletId) < repayment.amount) {
        throw Exception('Insufficient wallet balance to pay this loan.');
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

      await _changeWalletBalance(
        txn,
        walletId: repayment.walletId,
        amount: loan.loanType == 'given' ? repayment.amount : -repayment.amount,
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

  /// Source wallet ki currency ke mutabiq baqi loan amounts deta hai.
  static Future<Map<String, double>>
      getTotalOutstandingByCurrency() async {
    final db = await _database;

    final rows = await db.rawQuery('''
      SELECT
        UPPER(TRIM(COALESCE(wallets.currency, 'PKR'))) AS currency,
        loans.loan_type AS loan_type,
        COALESCE(SUM(loans.remaining_amount), 0) AS total
      FROM loans
      INNER JOIN wallets
        ON wallets.id = loans.wallet_id
      WHERE loans.remaining_amount > 0
      GROUP BY UPPER(TRIM(COALESCE(loans.currency, wallets.currency, 'PKR'))), loans.loan_type
      ORDER BY currency ASC, loans.loan_type ASC
    ''');

    return {
      for (final row in rows)
        '${row['currency']} • ${row['loan_type'] == 'given' ? 'Receivable' : 'Payable'}': (row['total'] as num).toDouble(),
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

  /// Repayment delete karta hai aur wallet aur loan balances ko pehli halat mein lata hai.
  static Future<void> deleteRepayment(int repaymentId) async {
    final db = await _database;

    final repaymentSnapshot = await db.query('loan_repayments', where: 'id = ?', whereArgs: [repaymentId], limit: 1);
    if (repaymentSnapshot.isEmpty) return;
    await RecycleBinService.archive(type: 'Loan Repayment', title: 'Repayment • ${repaymentSnapshot.first['amount']}',
      table: 'loan_repayments', id: repaymentId, record: repaymentSnapshot.first);
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

      await _getWallet(txn, repayment.walletId);

      final restoredRemaining =
          (loan.remainingAmount + repayment.amount)
              .clamp(0.0, loan.amount)
              .toDouble();

      await _changeWalletBalance(
        txn,
        walletId: repayment.walletId,
        amount: loan.loanType == 'given' ? -repayment.amount : repayment.amount,
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

  /// Loan delete karta hai aur us se mutaliq wallet balance changes wapas karta hai.
  static Future<void> deleteLoan(int loanId) async {
    final db = await _database;

    final loanSnapshot = await db.query('loans', where: 'id = ?', whereArgs: [loanId], limit: 1);
    if (loanSnapshot.isEmpty) return;
    final repaymentSnapshot = await db.query('loan_repayments', where: 'loan_id = ?', whereArgs: [loanId]);
    final partyId = (loanSnapshot.first['party_id'] as num?)?.toInt();
    final party = partyId == null ? null : await getPartyById(partyId);
    await RecycleBinService.archive(
      type: 'Loan',
      title: party?['name']?.toString() ?? 'Loan',
      table: 'loans',
      id: loanId,
      record: loanSnapshot.first,
      related: repaymentSnapshot,
    );
    await db.transaction((txn) async {
      final loanRows = await txn.query(
        'loans',
        where: 'id = ?',
        whereArgs: [loanId],
        limit: 1,
      );

      if (loanRows.isEmpty) return;

      final loan = LoansModel.fromMap(loanRows.first);

      await _getWallet(txn, loan.walletId);

      final repayments = await txn.query(
        'loan_repayments',
        where: 'loan_id = ?',
        whereArgs: [loanId],
      );

      // Sab se pehle har repayment ka jama hua amount wapas minus karta hai.
      for (final row in repayments) {
        final repayment = RepaymentModel.fromMap(row);

        await _getWallet(txn, repayment.walletId);

        await _changeWalletBalance(
          txn,
          walletId: repayment.walletId,
          amount: loan.loanType == 'given' ? -repayment.amount : repayment.amount,
        );
      }

      // Asset-linked loans never moved their reference wallet on creation.
      if (!loan.isAssetLinked) {
        await _changeWalletBalance(
          txn,
          walletId: loan.walletId,
          amount: loan.loanType == 'given' ? loan.amount : -loan.amount,
        );
      }

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
