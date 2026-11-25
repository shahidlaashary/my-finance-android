import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/modules/finance/models/loans_model.dart';
import 'package:my_finance/modules/finance/models/repayment_model.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

class LoansService {
  static void _validateLoanType(String loanType) {
    if (loanType != 'given' && loanType != 'taken') {
      throw Exception('Loan type must be either Loan Given or Loan Taken.');
    }
  }

  static Future<void> _validateLoanRepaymentReconciliation(
    Transaction txn,
    LoansModel loan,
  ) async {
    if (!loan.amount.isFinite ||
        loan.amount <= 0 ||
        !loan.remainingAmount.isFinite ||
        loan.remainingAmount < 0 ||
        loan.remainingAmount > loan.amount + 0.000001) {
      throw Exception(
        'Loan balance does not reconcile with its repayment history. This repayment operation was cancelled.',
      );
    }
    final rows = await txn.query(
      'loan_repayments',
      columns: ['amount'],
      where: 'loan_id = ?',
      whereArgs: [loan.id],
    );
    var repaidTotal = 0.0;
    for (final row in rows) {
      final amount = (row['amount'] as num?)?.toDouble();
      if (amount == null || !amount.isFinite || amount <= 0) {
        throw Exception(
          'Loan balance does not reconcile with its repayment history. This repayment operation was cancelled.',
        );
      }
      repaidTotal += amount;
    }
    if (!repaidTotal.isFinite ||
        (repaidTotal - (loan.amount - loan.remainingAmount)).abs() >
            0.000001) {
      throw Exception(
        'Loan balance does not reconcile with its repayment history. This repayment operation was cancelled.',
      );
    }
  }

  static double _validatedRepaymentWalletAmount(RepaymentModel repayment) {
    if (repayment.walletId <= 0 ||
        !repayment.amount.isFinite ||
        repayment.amount <= 0 ||
        !repayment.walletAmount.isFinite ||
        repayment.walletAmount <= 0) {
      throw Exception('Repayment contains an invalid wallet amount or wallet.');
    }
    return repayment.walletAmount;
  }

  static Future<void> _validateRepaymentWalletCurrency(
    Transaction txn,
    RepaymentModel repayment,
  ) async {
    final savedCurrency = repayment.walletCurrency.trim().toUpperCase();
    final currentCurrency = await _getWalletCurrency(txn, repayment.walletId);
    if (savedCurrency.isNotEmpty && savedCurrency != currentCurrency) {
      throw Exception(
        'The repayment wallet currency has changed. Correct the wallet currency before editing or deleting this repayment.',
      );
    }
  }

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

    // Testing-mode reset: discard old party test data and start with the current schema.
    const partyResetKey = 'party_archive_tabs_test_reset_v1';
    final partyResetRows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [partyResetKey],
      limit: 1,
    );
    if (partyResetRows.isEmpty) {
      await db.transaction((txn) async {
        await txn.execute('UPDATE loans SET party_id = NULL WHERE party_id IS NOT NULL');
        await txn.execute('DROP TABLE IF EXISTS loan_parties');
        await txn.insert('app_settings', {
          'setting_key': partyResetKey,
          'setting_value': '1',
        });
      });
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS loan_parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT NOT NULL DEFAULT '',
        currency TEXT NOT NULL DEFAULT 'PKR',
        notes TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        party_type TEXT NOT NULL DEFAULT 'Individual',
        country TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL DEFAULT '',
        postal_code TEXT NOT NULL DEFAULT '',
        opening_balance REAL NOT NULL DEFAULT 0,
        credit_limit REAL NOT NULL DEFAULT 0,
        payment_terms TEXT NOT NULL DEFAULT 'Due on Receipt',
        cnic TEXT NOT NULL DEFAULT '',
        business_name TEXT NOT NULL DEFAULT '',
        tax_number TEXT NOT NULL DEFAULT '',
        reference_person TEXT NOT NULL DEFAULT '',
        profile_image_path TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''' );

    await db.execute('CREATE INDEX IF NOT EXISTS idx_loans_source ON loans(source_type, source_id)');

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
        wallet_currency TEXT NOT NULL DEFAULT 'PKR',
        wallet_amount REAL NOT NULL DEFAULT 0,
        exchange_rate REAL NOT NULL DEFAULT 1,
        is_manual_rate INTEGER NOT NULL DEFAULT 0,
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

  static Future<List<Map<String, dynamic>>> getParties({bool includeArchived = false}) async {
    final db = await _database;
    return db.query(
      'loan_parties',
      where: includeArchived ? null : 'COALESCE(is_archived, 0) = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  static Future<void> setPartyArchived(int partyId, {required bool archived}) async {
    final db = await _database;
    final changed = await db.update(
      'loan_parties',
      {'is_archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [partyId],
    );
    if (changed != 1) throw Exception('Party was not found or could not be updated.');
    AppRefreshController.notifyChanged();
  }

  static Future<int> addParty({
    required String name,
    String? phone,
    String address = '',
    String notes = '',
    String currency = 'PKR',
    String email = '',
    String partyType = 'Individual',
    String country = '',
    String city = '',
    String postalCode = '',
    double openingBalance = 0,
    double creditLimit = 0,
    String paymentTerms = 'Due on Receipt',
    String cnic = '',
    String businessName = '',
    String taxNumber = '',
    String referencePerson = '',
    String profileImagePath = '',
  }) async {
    final db = await _database;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw Exception('Party name is required.');
    final normalizedPhone = phone?.trim() ?? '';
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty) throw Exception('Party currency is required.');

    final id = await db.transaction((txn) async {
      final existing = await txn.query(
        'loan_parties',
        columns: ['id'],
        where: 'LOWER(TRIM(name)) = LOWER(?) AND LOWER(TRIM(party_type)) = LOWER(?)',
        whereArgs: [normalizedName, partyType.trim()],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw Exception(
          'A party with this name already exists under $partyType type.',
        );
      }

      return txn.insert('loan_parties', {
        'name': normalizedName,
        'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
        'address': address.trim(),
        'currency': normalizedCurrency,
        'notes': notes.trim(),
        'email': email.trim(),
        'party_type': partyType,
        'country': country.trim(),
        'city': city.trim(),
        'postal_code': postalCode.trim(),
        'opening_balance': openingBalance,
        'credit_limit': creditLimit,
        'payment_terms': paymentTerms,
        'cnic': cnic.trim(),
        'business_name': businessName.trim(),
        'tax_number': taxNumber.trim(),
        'reference_person': referencePerson.trim(),
        'profile_image_path': profileImagePath,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    AppRefreshController.notifyChanged();
    return id;
  }

  static Future<void> updateParty({
    required int id,
    required String name,
    String? phone,
    String address = '',
    String currency = 'PKR',
    String notes = '',
    String email = '',
    String partyType = 'Individual',
    String country = '',
    String city = '',
    String postalCode = '',
    double openingBalance = 0,
    double creditLimit = 0,
    String paymentTerms = 'Due on Receipt',
    String cnic = '',
    String businessName = '',
    String taxNumber = '',
    String referencePerson = '',
    String profileImagePath = '',
  }) async {
    final db = await _database;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw Exception('Party name is required.');
    final normalizedPhone = phone?.trim() ?? '';
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty) throw Exception('Party currency is required.');

    await db.transaction((txn) async {
      final currentRows = await txn.query(
        'loan_parties',
        columns: ['id', 'currency'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (currentRows.isEmpty) throw Exception('Party was not found.');

      final currentCurrency =
          (currentRows.first['currency']?.toString() ?? 'PKR').toUpperCase();
      if (currentCurrency != normalizedCurrency) {
        final linkedLoans = await txn.query(
          'loans',
          columns: ['id'],
          where: 'party_id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (linkedLoans.isNotEmpty) {
          throw Exception(
            'Party currency cannot be changed while loan history is linked to this party.',
          );
        }
      }

      final duplicate = await txn.query(
        'loan_parties',
        columns: ['id'],
        where: 'id != ? AND LOWER(TRIM(name)) = LOWER(?) AND LOWER(TRIM(party_type)) = LOWER(?)',
        whereArgs: [id, normalizedName, partyType.trim()],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw Exception(
          'A party with this name already exists under $partyType type.',
        );
      }

      final changed = await txn.update(
        'loan_parties',
        {
          'name': normalizedName,
          'phone': normalizedPhone.isEmpty ? null : normalizedPhone,
          'address': address.trim(),
          'currency': normalizedCurrency,
          'notes': notes.trim(),
          'email': email.trim(),
          'party_type': partyType,
          'country': country.trim(),
          'city': city.trim(),
          'postal_code': postalCode.trim(),
          'opening_balance': openingBalance,
          'credit_limit': creditLimit,
          'payment_terms': paymentTerms,
          'cnic': cnic.trim(),
          'business_name': businessName.trim(),
          'tax_number': taxNumber.trim(),
          'reference_person': referencePerson.trim(),
          'profile_image_path': profileImagePath,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed != 1) throw Exception('Party could not be updated.');
    });
    AppRefreshController.notifyChanged();
  }

  /// Party sirf tab delete hoti hai jab us ke sath koi loan linked na ho.
  static Future<void> deleteParty(int partyId) async {
    final db = await _database;
    await RecycleBinService.ensureTable();

    await db.transaction((txn) async {
      final linkedLoans = await txn.query(
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

      final rows = await txn.query(
        'loan_parties',
        where: 'id = ?',
        whereArgs: [partyId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final now = DateTime.now();
      await txn.insert('recycle_bin', {
        'entity_type': 'Loan Party',
        'entity_title': rows.first['name']?.toString() ?? 'Party',
        'source_table': 'loan_parties',
        'source_id': partyId.toString(),
        'payload': jsonEncode(rows.first),
        'deleted_at': now.toIso8601String(),
        'expires_at': now
            .add(const Duration(days: RecycleBinService.retentionDays))
            .toIso8601String(),
      });
      final deleted = await txn.delete(
        'loan_parties',
        where: 'id = ?',
        whereArgs: [partyId],
      );
      if (deleted != 1) throw Exception('Party could not be deleted.');
    });
    AppRefreshController.notifyChanged();
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
      LEFT JOIN wallets ON wallets.id = loans.wallet_id AND loans.wallet_id > 0
      WHERE loans.party_id = ?
      GROUP BY
        UPPER(TRIM(COALESCE(loans.currency, wallets.currency, 'PKR'))),
        loans.loan_type
      ORDER BY
        UPPER(TRIM(COALESCE(loans.currency, wallets.currency, 'PKR'))),
        loans.loan_type
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
    if (!amount.isFinite) {
      throw Exception('Wallet balance change must be a valid number.');
    }
    final changed = await txn.rawUpdate(
      '''
      UPDATE wallets
      SET balance = balance + ?
      WHERE id = ?
      ''',
      [amount, walletId],
    );
    if (changed != 1) {
      throw Exception('The linked wallet no longer exists. Restore the wallet first.');
    }
  }

  static Future<void> _applyWalletDeltasSafely(
    Transaction txn,
    Map<int, double> deltas, {
    String insufficientBalanceMessage =
        'Insufficient wallet balance to reverse this repayment.',
  }) async {
    for (final entry in deltas.entries) {
      if (entry.key <= 0 || !entry.value.isFinite) {
        throw Exception('Wallet balance change contains invalid details.');
      }
      final rows = await txn.query(
        'wallets',
        columns: ['balance'],
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw Exception('The linked wallet no longer exists. Restore the wallet first.');
      }
      final balance = (rows.first['balance'] as num).toDouble();
      if (!balance.isFinite || balance + entry.value < -0.000001) {
        throw Exception(insufficientBalanceMessage);
      }
    }
    for (final entry in deltas.entries) {
      if (entry.value == 0) continue;
      await _changeWalletBalance(
        txn,
        walletId: entry.key,
        amount: entry.value,
      );
    }
  }

  /// Loan banata hai aur di jane wali raqam source wallet se minus karta hai.
  static Future<int> addLoan(LoansModel loan) async {
    final db = await _database;
    _validateLoanType(loan.loanType);
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

    final loanId = await db.transaction((txn) async {
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
    AppRefreshController.notifyChanged();
    return loanId;
  }

  static Future<double?> _getCurrencyRate(Transaction txn, String currency) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == 'PKR') return 1.0;
    final rows = await txn.query('exchange_rates', columns: ['rate'],
      where: 'UPPER(currency) = ?', whereArgs: [normalized], limit: 1);
    if (rows.isEmpty) return null;
    final rate = (rows.first['rate'] as num).toDouble();
    return rate.isFinite && rate > 0 ? rate : null;
  }

  static Future<RepaymentModel> _snapshotRepayment(
    Transaction txn, RepaymentModel repayment, String loanCurrency,
  ) async {
    final walletCurrency = await _getWalletCurrency(txn, repayment.walletId);
    double appliedRate;
    double walletAmount;
    if (repayment.isManualRate) {
      walletAmount = repayment.walletAmount;
      if (!walletAmount.isFinite || walletAmount <= 0) {
        throw Exception('Manual wallet amount must be greater than zero.');
      }
      appliedRate = walletAmount / repayment.amount;
    } else if (loanCurrency.trim().toUpperCase() == walletCurrency) {
      appliedRate = 1.0;
      walletAmount = repayment.amount;
    } else {
      final loanRate = await _getCurrencyRate(txn, loanCurrency);
      final walletRate = await _getCurrencyRate(txn, walletCurrency);
      if (loanRate == null || walletRate == null) {
        throw Exception('Exchange rate missing for $loanCurrency or $walletCurrency. Please set both currency rates first.');
      }
      appliedRate = loanRate / walletRate;
      walletAmount = repayment.amount * appliedRate;
    }
    if (!appliedRate.isFinite || appliedRate <= 0 ||
        !walletAmount.isFinite || walletAmount <= 0) {
      throw Exception('Converted wallet amount or exchange rate is invalid.');
    }
    return repayment.copyWith(
      walletCurrency: walletCurrency,
      walletAmount: walletAmount,
      exchangeRate: appliedRate,
    );
  }

  static Future<int> addRepayment(RepaymentModel repayment) async {
    final db = await _database;
    if (!repayment.amount.isFinite || repayment.amount <= 0) {
      throw Exception('Repayment amount must be a valid amount greater than zero.');
    }
    if (repayment.walletId <= 0 || repayment.loanId <= 0) {
      throw Exception('Please select a valid wallet and loan.');
    }
    final repaymentId = await db.transaction((txn) async {
      final loans = await txn.query('loans', where: 'id = ?', whereArgs: [repayment.loanId], limit: 1);
      if (loans.isEmpty) throw Exception('Loan was not found.');
      final loan = LoansModel.fromMap(loans.first);
      _validateLoanType(loan.loanType);
      await _validateLoanRepaymentReconciliation(txn, loan);
      if (loan.remainingAmount <= 0) throw Exception('This loan has already been fully repaid.');
      if (repayment.amount > loan.remainingAmount + 0.000001) {
        throw Exception('Repayment cannot exceed the outstanding balance.');
      }
      final snapshot = await _snapshotRepayment(txn, repayment, loan.currency);
      final walletBalance = await _getWalletBalance(txn, snapshot.walletId);
      if (loan.loanType == 'taken' && walletBalance + 0.000001 < snapshot.walletAmount) {
        throw Exception('Insufficient wallet balance. Required: ${snapshot.walletCurrency} ${snapshot.walletAmount.toStringAsFixed(2)}.');
      }
      final newRemaining = (loan.remainingAmount - snapshot.amount).clamp(0.0, loan.amount).toDouble();
      final id = await txn.insert('loan_repayments', snapshot.toMap()..remove('id'));
      await txn.update('loans', {
        'remaining_amount': newRemaining, 'status': newRemaining <= 0 ? 'paid' : 'active',
      }, where: 'id = ?', whereArgs: [repayment.loanId]);
      await _changeWalletBalance(txn, walletId: snapshot.walletId,
        amount: loan.loanType == 'given' ? snapshot.walletAmount : -snapshot.walletAmount);
      return id;
    });
    AppRefreshController.notifyChanged();
    return repaymentId;
  }

  /// Recalculate sirf selected repayment ko reverse karke usi entry ka naya effect apply karta hai.
  static Future<void> updateRepayment(RepaymentModel repayment) async {
    if (repayment.id == null) throw Exception('Repayment ID is required.');
    final db = await _database;
    await db.transaction((txn) async {
      final oldRows = await txn.query('loan_repayments', where: 'id = ?', whereArgs: [repayment.id], limit: 1);
      if (oldRows.isEmpty) throw Exception('Repayment entry was not found.');
      final old = RepaymentModel.fromMap(oldRows.first);
      if (old.loanId != repayment.loanId) throw Exception('A repayment cannot be moved to another loan.');
      final loanRows = await txn.query('loans', where: 'id = ?', whereArgs: [old.loanId], limit: 1);
      if (loanRows.isEmpty) throw Exception('Related loan was not found.');
      final loan = LoansModel.fromMap(loanRows.first);
      _validateLoanType(loan.loanType);
      await _validateLoanRepaymentReconciliation(txn, loan);
      await _validateRepaymentWalletCurrency(txn, old);
      final oldWalletAmount = _validatedRepaymentWalletAmount(old);
      final remainingAfterOld = loan.remainingAmount + old.amount;
      if (!repayment.amount.isFinite || repayment.amount <= 0 ||
          repayment.amount > remainingAfterOld + 0.000001) {
        throw Exception('Updated repayment amount exceeds the available loan balance.');
      }
      final snapshot = await _snapshotRepayment(txn, repayment, loan.currency);
      final newRemaining = (remainingAfterOld - snapshot.amount).clamp(0.0, loan.amount).toDouble();
      await txn.update('loan_repayments', snapshot.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [repayment.id]);
      // Reverse the old repayment and apply the replacement as one net
      // movement per wallet. This avoids temporary negatives when both
      // entries affect the same wallet and prevents a negative final balance.
      final walletDeltas = <int, double>{};
      void addWalletDelta(int walletId, double delta) {
        final next = (walletDeltas[walletId] ?? 0) + delta;
        if (!next.isFinite) {
          throw Exception('Repayment wallet balance change is invalid.');
        }
        walletDeltas[walletId] = next;
      }
      addWalletDelta(
        old.walletId,
        loan.loanType == 'given' ? -oldWalletAmount : oldWalletAmount,
      );
      addWalletDelta(
        snapshot.walletId,
        loan.loanType == 'given' ? snapshot.walletAmount : -snapshot.walletAmount,
      );
      await _applyWalletDeltasSafely(txn, walletDeltas);
      await txn.update('loans', {
        'remaining_amount': newRemaining, 'status': newRemaining <= 0 ? 'paid' : 'active',
      }, where: 'id = ?', whereArgs: [old.loanId]);
    });
    AppRefreshController.notifyChanged();
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
        UPPER(TRIM(COALESCE(loans.currency, wallets.currency, 'PKR'))) AS currency,
        loans.loan_type AS loan_type,
        COALESCE(SUM(loans.remaining_amount), 0) AS total
      FROM loans
      LEFT JOIN wallets
        ON wallets.id = loans.wallet_id AND loans.wallet_id > 0
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

  /// Repayment delete karta hai aur wallet aur loan balances ko pehli halat mein lata hai.
  static Future<void> deleteRepayment(int repaymentId) async {
    final db = await _database;
    await RecycleBinService.ensureTable();

    await db.transaction((txn) async {
      final rows = await txn.query(
        'loan_repayments',
        where: 'id = ?',
        whereArgs: [repaymentId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final repaymentRecord = rows.first;
      final repayment = RepaymentModel.fromMap(repaymentRecord);
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
      _validateLoanType(loan.loanType);
      await _validateLoanRepaymentReconciliation(txn, loan);
      await _validateRepaymentWalletCurrency(txn, repayment);
      final repaymentWalletAmount = _validatedRepaymentWalletAmount(repayment);

      final restoredRemaining = (loan.remainingAmount + repayment.amount)
          .clamp(0.0, loan.amount)
          .toDouble();

      await _applyWalletDeltasSafely(
        txn,
        {
          repayment.walletId: loan.loanType == 'given'
              ? -repaymentWalletAmount
              : repaymentWalletAmount,
        },
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

      await txn.insert('recycle_bin', {
        'entity_type': 'Loan Repayment',
        'entity_title': 'Repayment • ${repaymentRecord['amount']}',
        'source_table': 'loan_repayments',
        'source_id': repaymentId.toString(),
        'payload': jsonEncode(repaymentRecord),
        'deleted_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now()
            .add(const Duration(days: RecycleBinService.retentionDays))
            .toIso8601String(),
      });

      await txn.delete(
        'loan_repayments',
        where: 'id = ?',
        whereArgs: [repaymentId],
      );
    });

    AppRefreshController.notifyChanged();
  }


  /// Existing non-asset loan ki amount aur descriptive details update karta hai.
  static Future<void> updateLoanDetails({
    required int loanId,
    required double amount,
    required String lendingDate,
    required String? dueDate,
    required String notes,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw Exception('Loan amount must be greater than zero.');
    }
    final db = await _database;
    await db.transaction((txn) async {
      final rows = await txn.query('loans', where: 'id = ?', whereArgs: [loanId], limit: 1);
      if (rows.isEmpty) throw Exception('Loan not found.');
      final loan = LoansModel.fromMap(rows.first);
      _validateLoanType(loan.loanType);
      if (loan.isAssetLinked) {
        throw Exception('Asset-linked loans must be edited from Asset Section.');
      }
      final currentWalletCurrency = await _getWalletCurrency(txn, loan.walletId);
      if (currentWalletCurrency != loan.currency.trim().toUpperCase()) {
        throw Exception(
          'The loan wallet currency has changed. Correct the wallet currency before editing this loan.',
        );
      }
      final repayments = await txn.query(
        'loan_repayments',
        columns: ['amount'],
        where: 'loan_id = ?',
        whereArgs: [loanId],
      );
      final repaid = repayments.fold<double>(
        0,
        (total, row) => total + (row['amount'] as num).toDouble(),
      );
      if (amount < repaid) {
        throw Exception('Loan amount cannot be less than the amount already repaid.');
      }
      final difference = amount - loan.amount;
      if (difference != 0) {
        final walletDelta = loan.loanType == 'given' ? -difference : difference;
        await _applyWalletDeltasSafely(
          txn,
          {loan.walletId: walletDelta},
          insufficientBalanceMessage:
              'Insufficient wallet balance to update this loan amount.',
        );
      }
      final remaining = amount - repaid;
      await txn.update(
        'loans',
        {
          'amount': amount,
          'remaining_amount': remaining,
          'lending_date': lendingDate,
          'due_date': dueDate,
          'notes': notes,
          'status': remaining <= 0 ? 'paid' : 'active',
        },
        where: 'id = ?',
        whereArgs: [loanId],
      );
    });
    AppRefreshController.notifyChanged();
  }

  /// Loan delete karta hai aur us se mutaliq wallet balance changes wapas karta hai.
  /// Loan ko wallet effects ke saath aik atomic transaction mein recycle karta hai.
  static Future<void> deleteLoan(int loanId) async {
    final db = await _database;
    await RecycleBinService.ensureTable();

    await db.transaction((txn) async {
      final loanRows = await txn.query(
        'loans',
        where: 'id = ?',
        whereArgs: [loanId],
        limit: 1,
      );
      if (loanRows.isEmpty) return;

      final loanRecord = loanRows.first;
      if (loanRecord['source_type'] != null) {
        throw Exception('This loan is linked to an asset. Delete the related asset from Asset Section instead.');
      }

      final loan = LoansModel.fromMap(loanRecord);
      _validateLoanType(loan.loanType);
      final currentWalletCurrency = await _getWalletCurrency(txn, loan.walletId);
      if (currentWalletCurrency != loan.currency.trim().toUpperCase()) {
        throw Exception(
          'The loan wallet currency has changed. Correct the wallet currency before deleting this loan.',
        );
      }
      final repayments = await txn.query(
        'loan_repayments',
        where: 'loan_id = ?',
        whereArgs: [loanId],
      );

      // Calculate the complete delete effect before changing any wallet.
      // A repayment may have been received into a different wallet and spent;
      // deleting the loan must not silently push that wallet below zero.
      final walletDeltas = <int, double>{};
      void addWalletDelta(int walletId, double delta) {
        final next = (walletDeltas[walletId] ?? 0) + delta;
        if (!next.isFinite) {
          throw Exception('Loan deletion wallet balance change is invalid.');
        }
        walletDeltas[walletId] = next;
      }

      for (final row in repayments) {
        final repayment = RepaymentModel.fromMap(row);
        await _validateRepaymentWalletCurrency(txn, repayment);
        final repaymentWalletAmount = _validatedRepaymentWalletAmount(repayment);
        addWalletDelta(
          repayment.walletId,
          loan.loanType == 'given'
              ? -repaymentWalletAmount
              : repaymentWalletAmount,
        );
      }
      addWalletDelta(
        loan.walletId,
        loan.loanType == 'given' ? loan.amount : -loan.amount,
      );
      await _applyWalletDeltasSafely(
        txn,
        walletDeltas,
        insufficientBalanceMessage:
            'Insufficient wallet balance to delete this loan and reverse its repayments.',
      );

      final partyId = (loanRecord['party_id'] as num?)?.toInt();
      final partyRows = partyId == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'loan_parties',
              columns: ['name'],
              where: 'id = ?',
              whereArgs: [partyId],
              limit: 1,
            );

      await txn.insert('recycle_bin', {
        'entity_type': 'Loan',
        'entity_title': partyRows.isEmpty
            ? 'Loan'
            : partyRows.first['name']?.toString() ?? 'Loan',
        'source_table': 'loans',
        'source_id': loanId.toString(),
        'payload': jsonEncode(loanRecord),
        'related_payload': repayments.isEmpty ? null : jsonEncode(repayments),
        'deleted_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now()
            .add(const Duration(days: RecycleBinService.retentionDays))
            .toIso8601String(),
      });

      await txn.delete(
        'loan_repayments',
        where: 'loan_id = ?',
        whereArgs: [loanId],
      );
      await txn.delete('loans', where: 'id = ?', whereArgs: [loanId]);
    });

    AppRefreshController.notifyChanged();
  }
}
