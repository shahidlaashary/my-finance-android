import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

import '../models/new_asset_record.dart';

/// Persistence boundary for New Assets System v2.
///
/// All tables are namespaced with `new_asset_v2_`; legacy assets tables,
/// services, models and transaction filters are deliberately untouched.
class NewAssetsService {
  NewAssetsService._();
  static final NewAssetsService instance = NewAssetsService._();

  Database get _db => FinanceDB.instance.db;

  Future<void> ensureTables() async {
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS new_asset_v2_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        currency TEXT NOT NULL,
        purchase_amount REAL NOT NULL CHECK (purchase_amount > 0),
        current_value REAL NOT NULL CHECK (current_value >= 0),
        purchase_date TEXT NOT NULL,
        payment_type TEXT NOT NULL CHECK (payment_type IN ('Wallet', 'Loan')),
        wallet_id INTEGER,
        party_id INTEGER,
        linked_loan_id INTEGER,
        include_in_consolidated_balance INTEGER NOT NULL DEFAULT 0,
        is_sold INTEGER NOT NULL DEFAULT 0,
        sale_amount REAL,
        sale_date TEXT,
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (
          (payment_type = 'Wallet' AND wallet_id IS NOT NULL AND party_id IS NULL)
          OR
          (payment_type = 'Loan' AND wallet_id IS NULL AND party_id IS NOT NULL)
        )
      )
    ''');
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS new_asset_v2_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        wallet_id INTEGER,
        loan_id INTEGER,
        transaction_id INTEGER,
        repayment_id INTEGER,
        event_date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY(asset_id) REFERENCES new_asset_v2_records(id) ON DELETE CASCADE
      )
    ''');
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS new_asset_v2_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        mime_type TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(asset_id) REFERENCES new_asset_v2_records(id) ON DELETE CASCADE
      )
    ''');
    await _db.execute('CREATE INDEX IF NOT EXISTS idx_new_asset_v2_records_status ON new_asset_v2_records(is_sold, currency)');
    await _db.execute('CREATE INDEX IF NOT EXISTS idx_new_asset_v2_events_asset_date ON new_asset_v2_events(asset_id, event_date)');
  }

  /// Creates the v2 asset record. Loan purchases intentionally do not require
  /// or reserve a wallet; the repayment wallet is chosen at repayment time.
  ///
  /// Wallet cash movement is added atomically in the next integration phase,
  /// together with the v2-linked transaction metadata. This method only
  /// persists the isolated asset record and its opening event for now.
  Future<int> createAsset(NewAssetRecord asset) async {
    await ensureTables();
    if (asset.name.trim().isEmpty) throw ArgumentError('Asset name is required.');
    if (!asset.purchaseAmount.isFinite || asset.purchaseAmount <= 0) {
      throw ArgumentError('Purchase amount must be greater than zero.');
    }
    if (!asset.currentValue.isFinite || asset.currentValue < 0) {
      throw ArgumentError('Current value cannot be negative.');
    }
    if (asset.paymentType == 'Wallet' && asset.walletId == null) {
      throw ArgumentError('Select a wallet for wallet-funded assets.');
    }
    if (asset.paymentType == 'Loan' && asset.partyId == null) {
      throw ArgumentError('Select a party for loan-funded assets.');
    }
    if (asset.paymentType != 'Wallet' && asset.paymentType != 'Loan') {
      throw ArgumentError('Unsupported payment type.');
    }

    final id = await _db.transaction((txn) async {
      if (asset.paymentType == 'Loan') {
        final parties = await txn.query(
          'loan_parties',
          columns: ['id', 'currency'],
          where: 'id = ?',
          whereArgs: [asset.partyId],
          limit: 1,
        );
        if (parties.isEmpty) throw StateError('Selected party was not found.');
        final partyCurrency = (parties.first['currency'] as String? ?? 'PKR').toUpperCase();
        if (partyCurrency != asset.currency.toUpperCase()) {
          throw StateError('Asset currency must match the selected party currency.');
        }
      }

      if (asset.paymentType == 'Wallet') {
        final wallets = await txn.query(
          'wallets',
          columns: ['id', 'currency', 'balance'],
          where: 'id = ?',
          whereArgs: [asset.walletId],
          limit: 1,
        );
        if (wallets.isEmpty) throw StateError('Selected wallet was not found.');
        final wallet = wallets.first;
        final walletCurrency = (wallet['currency'] as String).toUpperCase();
        if (walletCurrency != asset.currency.toUpperCase()) {
          throw StateError('Asset currency must match the selected wallet.');
        }
        final balance = (wallet['balance'] as num).toDouble();
        if (balance + 0.000001 < asset.purchaseAmount) {
          throw StateError('Insufficient wallet balance.');
        }
      }

      final now = DateTime.now().toIso8601String();
      final assetId = await txn.insert(
        'new_asset_v2_records',
        asset.toInsertMap(),
      );

      if (asset.paymentType == 'Wallet') {
        final currentWalletRows = await txn.query(
          'wallets',
          columns: ['balance'],
          where: 'id = ?',
          whereArgs: [asset.walletId],
          limit: 1,
        );
        final currentWalletBalance =
            (currentWalletRows.single['balance'] as num).toDouble();
        await txn.update(
          'wallets',
          {'balance': currentWalletBalance - asset.purchaseAmount},
          where: 'id = ?',
          whereArgs: [asset.walletId],
        );
        final transactionId = await txn.insert('transactions', {
          'type': 'Expense',
          'amount': asset.purchaseAmount,
          'wallet_id': asset.walletId,
          'to_wallet_id': null,
          'to_amount': null,
          'exchange_rate': null,
          'balance_delta': null,
          'category': 'Asset Purchase',
          'note': 'New Asset v2: ${asset.name.trim()}',
          'date': asset.purchaseDate.toIso8601String(),
          'created_at': now,
        });
        await txn.insert('new_asset_v2_events', {
          'asset_id': assetId,
          'event_type': 'purchase',
          'amount': asset.purchaseAmount,
          'currency': asset.currency.toUpperCase(),
          'wallet_id': asset.walletId,
          'transaction_id': transactionId,
          'event_date': asset.purchaseDate.toIso8601String(),
          'note': 'Wallet-funded asset purchase',
          'created_at': now,
        });
      } else {
        final loanId = await txn.insert('loans', {
          'party_id': asset.partyId,
          'loan_type': 'taken',
          'amount': asset.purchaseAmount,
          'remaining_amount': asset.purchaseAmount,
          // No wallet is reserved at purchase time. The first repayment
          // records the actual wallet used.
          'wallet_id': -1,
          'currency': asset.currency.toUpperCase(),
          'source_type': 'new_asset_v2_purchase',
          'source_id': assetId,
          'lending_date': asset.purchaseDate.toIso8601String(),
          'due_date': null,
          'notes': 'New Asset v2: ${asset.name.trim()}',
          'status': 'active',
          'created_at': now,
        });
        await txn.update(
          'new_asset_v2_records',
          {'linked_loan_id': loanId},
          where: 'id = ?',
          whereArgs: [assetId],
        );
        await txn.insert('new_asset_v2_events', {
          'asset_id': assetId,
          'event_type': 'purchase',
          'amount': asset.purchaseAmount,
          'currency': asset.currency.toUpperCase(),
          'wallet_id': null,
          'loan_id': loanId,
          'event_date': asset.purchaseDate.toIso8601String(),
          'note': 'Loan-funded asset purchase',
          'created_at': now,
        });
      }
      return assetId;
    });
    AppRefreshController.notifyChanged();
    return id;
  }

  Future<List<NewAssetRecord>> getAssets({bool includeSold = false}) async {
    await ensureTables();
    final rows = await _db.query(
      'new_asset_v2_records',
      where: includeSold ? null : 'is_sold = 0',
      orderBy: 'purchase_date DESC, id DESC',
    );
    return rows.map(NewAssetRecord.fromMap).toList(growable: false);
  }

  Future<NewAssetRecord?> getAsset(int id) async {
    await ensureTables();
    final rows = await _db.query(
      'new_asset_v2_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : NewAssetRecord.fromMap(rows.first);
  }

  /// Assets enabled for Consolidated Balance, excluding sold assets.
  Future<Map<String, double>> getConsolidatedAssetValueByCurrency() async {
    await ensureTables();
    final rows = await _db.rawQuery('''
      SELECT currency, SUM(current_value) AS total
      FROM new_asset_v2_records
      WHERE is_sold = 0 AND include_in_consolidated_balance = 1
      GROUP BY currency
    ''');
    return {
      for (final row in rows)
        (row['currency'] as String).toUpperCase(): (row['total'] as num).toDouble(),
    };
  }

  Future<int> addAttachment({
    required int assetId,
    required String filePath,
    required String fileName,
    String? mimeType,
  }) async {
    await ensureTables();
    final asset = await getAsset(assetId);
    if (asset == null) throw StateError('Asset not found.');
    final id = await _db.insert('new_asset_v2_attachments', {
      'asset_id': assetId,
      'file_path': filePath,
      'file_name': fileName,
      'mime_type': mimeType,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<List<Map<String, Object?>>> getAttachments(int assetId) async {
    await ensureTables();
    return _db.query(
      'new_asset_v2_attachments',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      orderBy: 'id DESC',
    );
  }

  Future<void> updateCurrentValue(int assetId, double value) async {
    await ensureTables();
    if (!value.isFinite || value < 0) {
      throw ArgumentError('Current value cannot be negative.');
    }
    final changed = await _db.update(
      'new_asset_v2_records',
      {'current_value': value, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND is_sold = 0',
      whereArgs: [assetId],
    );
    if (changed == 0) throw StateError('Active asset not found.');
    AppRefreshController.notifyChanged();
  }

  Future<Map<String, Object?>?> getLinkedLoan(int assetId) async {
    await ensureTables();
    final assets = await _db.query(
      'new_asset_v2_records',
      columns: ['linked_loan_id'],
      where: 'id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    if (assets.isEmpty || assets.first['linked_loan_id'] == null) return null;
    final loans = await _db.query(
      'loans',
      where: 'id = ? AND source_type = ? AND source_id = ?',
      whereArgs: [assets.first['linked_loan_id'], 'new_asset_v2_purchase', assetId],
      limit: 1,
    );
    return loans.isEmpty ? null : loans.first;
  }

  /// Repayment, wallet balance, wallet transaction, loan balance and asset
  /// event are committed together. The wallet is chosen at repayment time.
  Future<int> addLoanRepayment({
    required int assetId,
    required int walletId,
    required double amount,
    required DateTime repaymentDate,
    String notes = '',
  }) async {
    await ensureTables();
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Repayment amount must be greater than zero.');
    }
    final repaymentId = await _db.transaction((txn) async {
      final assetRows = await txn.query(
        'new_asset_v2_records',
        where: 'id = ? AND payment_type = ? AND is_sold = 0',
        whereArgs: [assetId, 'Loan'],
        limit: 1,
      );
      if (assetRows.isEmpty) throw StateError('Active loan-funded asset not found.');
      final asset = NewAssetRecord.fromMap(assetRows.first);
      final loanId = (assetRows.first['linked_loan_id'] as num?)?.toInt();
      if (loanId == null) throw StateError('Linked loan was not found.');
      final loanRows = await txn.query(
        'loans',
        where: 'id = ? AND source_type = ? AND source_id = ?',
        whereArgs: [loanId, 'new_asset_v2_purchase', assetId],
        limit: 1,
      );
      if (loanRows.isEmpty) throw StateError('Linked loan was not found.');
      final loan = loanRows.first;
      final outstanding = (loan['remaining_amount'] as num).toDouble();
      if (amount > outstanding + 0.000001) {
        throw StateError('Repayment cannot exceed the outstanding loan.');
      }
      final wallets = await txn.query(
        'wallets',
        columns: ['id', 'currency', 'balance'],
        where: 'id = ?',
        whereArgs: [walletId],
        limit: 1,
      );
      if (wallets.isEmpty) throw StateError('Selected wallet was not found.');
      final wallet = wallets.single;
      final walletCurrency = (wallet['currency'] as String? ?? 'PKR').toUpperCase();
      if (walletCurrency != asset.currency.toUpperCase()) {
        throw StateError('Wallet currency must match the loan currency (${asset.currency}).');
      }
      final balance = (wallet['balance'] as num).toDouble();
      if (balance + 0.000001 < amount) {
        throw StateError('Insufficient wallet balance.');
      }
      final now = DateTime.now().toIso8601String();
      final newRemaining = (outstanding - amount).clamp(0.0, outstanding).toDouble();
      final repaymentId = await txn.insert('loan_repayments', {
        'loan_id': loanId,
        'amount': amount,
        'wallet_id': walletId,
        'repayment_date': repaymentDate.toIso8601String(),
        'payment_method': 'cash',
        'notes': notes.trim(),
        'created_at': now,
      });
      await txn.update(
        'loans',
        {
          'remaining_amount': newRemaining,
          'status': newRemaining <= 0 ? 'paid' : 'active',
          'wallet_id': walletId,
        },
        where: 'id = ?',
        whereArgs: [loanId],
      );
      await txn.update(
        'wallets',
        {'balance': balance - amount},
        where: 'id = ?',
        whereArgs: [walletId],
      );
      final transactionId = await txn.insert('transactions', {
        'type': 'Expense',
        'amount': amount,
        'wallet_id': walletId,
        'to_wallet_id': null,
        'to_amount': null,
        'exchange_rate': null,
        'balance_delta': null,
        'category': 'Loan Repayment',
        'note': 'New Asset v2: ${asset.name} repayment',
        'date': repaymentDate.toIso8601String(),
        'created_at': now,
      });
      await txn.insert('new_asset_v2_events', {
        'asset_id': assetId,
        'event_type': 'loan_repayment',
        'amount': amount,
        'currency': asset.currency,
        'wallet_id': walletId,
        'loan_id': loanId,
        'transaction_id': transactionId,
        'repayment_id': repaymentId,
        'event_date': repaymentDate.toIso8601String(),
        'note': notes.trim().isEmpty ? 'Loan repayment' : notes.trim(),
        'created_at': now,
      });
      return repaymentId;
    });
    AppRefreshController.notifyChanged();
    return repaymentId;
  }

  Future<List<Map<String, Object?>>> getEvents(int assetId) async {
    await ensureTables();
    return _db.query(
      'new_asset_v2_events',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      orderBy: 'event_date DESC, id DESC',
    );
  }
}
