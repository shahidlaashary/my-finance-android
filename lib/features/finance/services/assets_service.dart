import 'package:sqflite/sqflite.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';
class AssetsService {
  Future<Database> get _database async {
    return TransactionsService.database;
  }
  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'Other',
        purchase_price REAL NOT NULL,
        current_value REAL NOT NULL,
        purchase_date TEXT NOT NULL,
        wallet_id INTEGER NOT NULL,
        payment_type TEXT NOT NULL DEFAULT 'Wallet',
        party_id INTEGER,
        currency TEXT NOT NULL DEFAULT 'PKR',
        linked_loan_id INTEGER,
        notes TEXT NOT NULL DEFAULT '',
        is_sold INTEGER NOT NULL DEFAULT 0,
        sale_date TEXT,
        sale_price REAL,
        sale_wallet_id INTEGER,
        sale_payment_type TEXT NOT NULL DEFAULT 'Wallet',
        sale_party_id INTEGER,
        sale_linked_loan_id INTEGER,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_assets_account
      ON assets(wallet_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_assets_sold
      ON assets(is_sold)
    ''');
  }
  Future<void> _ensureTables(Database db) async {
    await _createTables(db);
    final columns = await db.rawQuery('PRAGMA table_info(assets)');
    final existing = columns.map((row) => row['name']).toSet();
    final migrations = <String, String>{
      'payment_type': "ALTER TABLE assets ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'Wallet'",
      'party_id': 'ALTER TABLE assets ADD COLUMN party_id INTEGER',
      'currency': "ALTER TABLE assets ADD COLUMN currency TEXT NOT NULL DEFAULT 'PKR'",
      'linked_loan_id': 'ALTER TABLE assets ADD COLUMN linked_loan_id INTEGER',
      'sale_payment_type': "ALTER TABLE assets ADD COLUMN sale_payment_type TEXT NOT NULL DEFAULT 'Wallet'",
      'sale_party_id': 'ALTER TABLE assets ADD COLUMN sale_party_id INTEGER',
      'sale_linked_loan_id': 'ALTER TABLE assets ADD COLUMN sale_linked_loan_id INTEGER',
    };
    for (final entry in migrations.entries) {
      if (!existing.contains(entry.key)) {
        await db.execute(entry.value);
        if (entry.key == 'currency') {
          await db.execute("UPDATE assets SET currency = COALESCE((SELECT currency FROM wallets WHERE wallets.id = assets.wallet_id), 'PKR')");
        }
      }
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_assets_linked_loan ON assets(linked_loan_id, sale_linked_loan_id)');
  }
  Future<Map<String, dynamic>> _getWallet(
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
      throw Exception('Selected wallet was not found.');
    }
    return rows.first;
  }
  Future<double> _getBalance(
    Transaction txn,
    int walletId,
  ) async {
    final wallet = await _getWallet(txn, walletId);
    return (wallet['balance'] as num).toDouble();
  }
  Future<void> _changeBalance(
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
  void _validateAsset(AssetsModel asset) {
    if (asset.name.trim().isEmpty) {
      throw Exception('Asset name is required.');
    }
    if (asset.paymentType.toLowerCase() != 'loan' && asset.walletId <= 0) {
      throw Exception('Please select a valid wallet.');
    }
    if (!asset.purchasePrice.isFinite ||
        asset.purchasePrice <= 0) {
      throw Exception('Purchase price must be greater than zero.');
    }
    if (!asset.currentValue.isFinite ||
        asset.currentValue < 0) {
      throw Exception('Current value cannot be negative.');
    }
    if (asset.isSold) {
      if (asset.salePrice == null ||
          !asset.salePrice!.isFinite ||
          asset.salePrice! < 0) {
        throw Exception('Please enter a valid sale price.');
      }
      if (asset.saleDate == null) {
        throw Exception('Sale date is required.');
      }
      if (asset.saleDate!.isBefore(asset.purchaseDate)) {
        throw Exception(
          'Sale date cannot be before purchase date.',
        );
      }
    }
  }
  Future<int> addAsset(AssetsModel asset) async {
    _validateAsset(asset);
    if (asset.isSold) throw Exception('Please add the asset first, then record its sale.');
    final db = await _database;
    await _ensureTables(db);
    final isLoan = asset.paymentType.toLowerCase() == 'loan';
    var anchorWalletId = asset.walletId;
    var currency = asset.currency.toUpperCase();
    if (isLoan) {
      if (asset.partyId == null) throw Exception('Please select a party for this loan purchase.');
      final party = await LoansService.getPartyById(asset.partyId!);
      if (party == null) throw Exception('Selected party was not found.');
      currency = (party['currency']?.toString() ?? 'PKR').toUpperCase();
      final matching = await db.query('wallets', columns: ['id'], where: "UPPER(TRIM(COALESCE(currency, 'PKR'))) = ?", whereArgs: [currency], limit: 1);
      if (matching.isEmpty) throw Exception('Create a ' + currency + ' wallet first. It is required for future loan repayments.');
      anchorWalletId = (matching.first['id'] as num).toInt();
    }
    final assetId = await db.transaction((txn) async {
      final wallet = await _getWallet(txn, anchorWalletId);
      final walletCurrency = (wallet['currency'] ?? 'PKR').toString().toUpperCase();
      if (isLoan && walletCurrency != currency) throw Exception('Asset currency does not match its party currency.');
      if (!isLoan) currency = walletCurrency;
      if (!isLoan && (wallet['balance'] as num).toDouble() < asset.purchasePrice) throw Exception('Insufficient wallet balance.');
      final map = asset.copyWith(
        walletId: anchorWalletId, currency: currency,
        name: asset.name.trim(),
        category: asset.category.trim().isEmpty ? 'Other' : asset.category.trim(),
        createdAt: asset.createdAt ?? DateTime.now(),
      ).toMap()..remove('id');
      final id = await txn.insert('assets', map);
      if (!isLoan) await _changeBalance(txn, walletId: anchorWalletId, amount: -asset.purchasePrice);
      return id;
    });
    if (isLoan) {
      try {
        final loanId = await LoansService.createAssetLinkedLoan(
          partyId: asset.partyId!, loanType: 'taken', amount: asset.purchasePrice,
          lendingDate: asset.purchaseDate.toIso8601String().split('T').first,
          sourceType: 'asset_purchase', sourceId: assetId,
          notes: 'Asset purchase: ' + asset.name,
        );
        await db.update('assets', {'linked_loan_id': loanId}, where: 'id = ?', whereArgs: [assetId]);
      } catch (_) {
        await db.delete('assets', where: 'id = ?', whereArgs: [assetId]);
        rethrow;
      }
    }
    AppRefreshController.notifyChanged();
    return assetId;
  }

  Future<List<AssetsModel>> getAssets({
    bool includeSold = true,
  }) async {
    final db = await _database;
    await _ensureTables(db);
    final rows = await db.query(
      'assets',
      where: includeSold ? null : 'is_sold = 0',
      orderBy: 'purchase_date DESC, id DESC',
    );
    return rows.map(AssetsModel.fromMap).toList();
  }
  Future<AssetsModel?> getAssetById(int assetId) async {
    final db = await _database;
    await _ensureTables(db);
    final rows = await db.query(
      'assets',
      where: 'id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AssetsModel.fromMap(rows.first);
  }
  Future<void> updateCurrentValue(
    int assetId,
    double newValue,
  ) async {
    if (!newValue.isFinite || newValue < 0) {
      throw Exception('Current value cannot be negative.');
    }
    final db = await _database;
    await _ensureTables(db);
    final result = await db.update(
      'assets',
      {'current_value': newValue},
      where: 'id = ? AND is_sold = 0',
      whereArgs: [assetId],
    );
    if (result == 0) {
      throw Exception('Asset not found or already sold.');
    }
    AppRefreshController.notifyChanged();
  }
  Future<void> sellAsset({
    required int assetId,
    required double salePrice,
    required DateTime saleDate,
    required int saleWalletId,
    String paymentType = 'Wallet',
    int? partyId,
  }) async {
    if (!salePrice.isFinite || salePrice < 0) throw Exception('Please enter a valid sale price.');
    final db = await _database;
    await _ensureTables(db);
    final rows = await db.query('assets', where: 'id = ?', whereArgs: [assetId], limit: 1);
    if (rows.isEmpty) throw Exception('Asset was not found.');
    final asset = AssetsModel.fromMap(rows.first);
    if (asset.isSold) throw Exception('This asset has already been sold.');
    if (saleDate.isBefore(asset.purchaseDate)) throw Exception('Sale date cannot be before purchase date.');
    final isLoan = paymentType.toLowerCase() == 'loan';
    var anchorWalletId = saleWalletId;
    if (isLoan) {
      if (partyId == null) throw Exception('Please select the buyer party.');
      final party = await LoansService.getPartyById(partyId);
      if (party == null) throw Exception('Selected buyer party was not found.');
      final buyerCurrency = (party['currency']?.toString() ?? 'PKR').toUpperCase();
      if (buyerCurrency != asset.currency.toUpperCase()) throw Exception('Buyer party currency must match the asset currency (' + asset.currency + ').');
      final matching = await db.query('wallets', columns: ['id'], where: "UPPER(TRIM(COALESCE(currency, 'PKR'))) = ?", whereArgs: [buyerCurrency], limit: 1);
      if (matching.isEmpty) throw Exception('Create a ' + buyerCurrency + ' wallet first for future loan repayments.');
      anchorWalletId = (matching.first['id'] as num).toInt();
    }
    await db.transaction((txn) async {
      final purchaseWallet = await _getWallet(txn, asset.walletId);
      final saleWallet = await _getWallet(txn, anchorWalletId);
      final purchaseCurrency = (purchaseWallet['currency'] ?? asset.currency).toString().toUpperCase();
      final saleCurrency = (saleWallet['currency'] ?? 'PKR').toString().toUpperCase();
      if (purchaseCurrency != saleCurrency) throw Exception('Asset sale must use the same currency as its purchase.');
      if (!isLoan) await _changeBalance(txn, walletId: anchorWalletId, amount: salePrice);
      await txn.update('assets', {
        'is_sold': 1, 'sale_date': saleDate.toIso8601String(),
        'sale_price': salePrice, 'sale_wallet_id': anchorWalletId,
        'sale_payment_type': paymentType, 'sale_party_id': isLoan ? partyId : null,
      }, where: 'id = ?', whereArgs: [assetId]);
    });
    if (isLoan) {
      try {
        final loanId = await LoansService.createAssetLinkedLoan(
          partyId: partyId!, loanType: 'given', amount: salePrice,
          lendingDate: saleDate.toIso8601String().split('T').first,
          sourceType: 'asset_sale', sourceId: assetId,
          notes: 'Asset sale: ' + asset.name,
        );
        await db.update('assets', {'sale_linked_loan_id': loanId}, where: 'id = ?', whereArgs: [assetId]);
      } catch (_) {
        await db.update('assets', {
          'is_sold': 0, 'sale_date': null, 'sale_price': null,
          'sale_wallet_id': null, 'sale_payment_type': 'Wallet', 'sale_party_id': null,
        }, where: 'id = ?', whereArgs: [assetId]);
        rethrow;
      }
    }
    AppRefreshController.notifyChanged();
  }

  Future<void> updateAsset(AssetsModel updatedAsset) async {
    if (updatedAsset.id == null) throw Exception('Asset ID is required for updating.');
    _validateAsset(updatedAsset);
    if (updatedAsset.isSold) throw Exception('Use the Sell Asset option to record a sale.');
    final db = await _database;
    await _ensureTables(db);
    final rows = await db.query('assets', where: 'id = ?', whereArgs: [updatedAsset.id], limit: 1);
    if (rows.isEmpty) throw Exception('Asset was not found.');
    final oldAsset = AssetsModel.fromMap(rows.first);
    if (oldAsset.isSold) throw Exception('Sold assets cannot be edited.');
    final oldIsLoan = oldAsset.paymentType.toLowerCase() == 'loan';
    final newIsLoan = updatedAsset.paymentType.toLowerCase() == 'loan';
    if (oldIsLoan != newIsLoan) throw Exception('Payment Type cannot be changed after saving. Delete and recreate the asset to change it.');
    if (oldIsLoan) {
      if (updatedAsset.partyId == null || oldAsset.linkedLoanId == null) throw Exception('Linked loan or party is missing.');
      final party = await LoansService.getPartyById(updatedAsset.partyId!);
      if (party == null) throw Exception('Selected party was not found.');
      final currency = (party['currency']?.toString() ?? 'PKR').toUpperCase();
      final loanTermsChanged =
          updatedAsset.purchasePrice != oldAsset.purchasePrice ||
          updatedAsset.partyId != oldAsset.partyId ||
          !updatedAsset.purchaseDate.isAtSameMomentAs(oldAsset.purchaseDate);
      if (loanTermsChanged && currency != oldAsset.currency.toUpperCase()) {
        throw Exception('Party currency must remain ' + oldAsset.currency + ' for this asset.');
      }
      if (loanTermsChanged) {
        await LoansService.updateAssetLinkedLoan(
          loanId: oldAsset.linkedLoanId!, partyId: updatedAsset.partyId!,
          loanType: 'taken', amount: updatedAsset.purchasePrice,
          lendingDate: updatedAsset.purchaseDate.toIso8601String().split('T').first,
          notes: 'Asset purchase: ' + updatedAsset.name,
        );
      }
      await db.update('assets', updatedAsset.copyWith(
        walletId: oldAsset.walletId, currency: oldAsset.currency,
        linkedLoanId: oldAsset.linkedLoanId, createdAt: oldAsset.createdAt,
      ).toMap()..remove('id'), where: 'id = ?', whereArgs: [updatedAsset.id]);
    } else {
      await db.transaction((txn) async {
        final oldWallet = await _getWallet(txn, oldAsset.walletId);
        final updatedWallet = await _getWallet(txn, updatedAsset.walletId);
        final oldCurrency = (oldWallet['currency'] ?? 'PKR').toString().toUpperCase();
        final updatedCurrency = (updatedWallet['currency'] ?? 'PKR').toString().toUpperCase();
        if (oldCurrency != updatedCurrency) throw Exception('Asset must remain linked to a wallet with the same currency.');
        await _changeBalance(txn, walletId: oldAsset.walletId, amount: oldAsset.purchasePrice);
        if (await _getBalance(txn, updatedAsset.walletId) < updatedAsset.purchasePrice) throw Exception('Insufficient wallet balance.');
        await _changeBalance(txn, walletId: updatedAsset.walletId, amount: -updatedAsset.purchasePrice);
        final map = updatedAsset.copyWith(currency: updatedCurrency, createdAt: oldAsset.createdAt).toMap()..remove('id');
        await txn.update('assets', map, where: 'id = ?', whereArgs: [updatedAsset.id]);
      });
    }
    AppRefreshController.notifyChanged();
  }

  Future<void> _deleteAssetLinkedLoan(int loanId) async {
    final repayments = await LoansService.getRepayments(loanId);
    await LoansService.deleteLoan(loanId, fromAssetDelete: true);
    await AttachmentService.deleteOwnerAttachments(
      ownerType: AttachmentOwnerTypes.loan,
      ownerId: loanId,
    );
    for (final repayment in repayments) {
      if (repayment.id != null) {
        await AttachmentService.deleteOwnerAttachments(
          ownerType: AttachmentOwnerTypes.repayment,
          ownerId: repayment.id!,
        );
      }
    }
  }

  Future<void> deleteAsset(int assetId) async {
    final db = await _database;
    await _ensureTables(db);
    final existing = await db.query('assets', where: 'id = ?', whereArgs: [assetId], limit: 1);
    if (existing.isEmpty) return;
    final asset = AssetsModel.fromMap(existing.first);
    if (asset.linkedLoanId != null) await _deleteAssetLinkedLoan(asset.linkedLoanId!);
    if (asset.saleLinkedLoanId != null) await _deleteAssetLinkedLoan(asset.saleLinkedLoanId!);
    await RecycleBinService.archive(type: 'Asset', title: asset.name, table: 'assets', id: assetId, record: existing.first);
    await db.transaction((txn) async {
      final rows = await txn.query('assets', where: 'id = ?', whereArgs: [assetId], limit: 1);
      if (rows.isEmpty) return;
      final current = AssetsModel.fromMap(rows.first);
      if (current.isSold && current.salePrice != null && current.salePaymentType.toLowerCase() != 'loan') {
        await _getWallet(txn, current.saleWalletId ?? current.walletId);
        await _changeBalance(txn, walletId: current.saleWalletId ?? current.walletId, amount: -current.salePrice!);
      }
      if (current.paymentType.toLowerCase() != 'loan') {
        await _getWallet(txn, current.walletId);
        await _changeBalance(txn, walletId: current.walletId, amount: current.purchasePrice);
      }
      await txn.delete('assets', where: 'id = ?', whereArgs: [assetId]);
    });
    AppRefreshController.notifyChanged();
  }

  Future<Map<String, double>> getTotalCurrentValueByCurrency() async {
    final db = await _database;
    await _ensureTables(db);
    final rows = await db.rawQuery('''
      SELECT s.currency AS currency,
             COALESCE(SUM(s.current_value), 0) AS total
      FROM assets s
      INNER JOIN wallets a ON a.id = s.wallet_id
      WHERE s.is_sold = 0
      GROUP BY s.currency
    ''');
    return {
      for (final row in rows)
        (row['currency'] ?? 'PKR').toString():
            (row['total'] as num).toDouble(),
    };
  }
  Future<Map<String, double>> getTotalPurchaseValueByCurrency() async {
    final db = await _database;
    await _ensureTables(db);
    final rows = await db.rawQuery('''
      SELECT s.currency AS currency,
             COALESCE(SUM(s.purchase_price), 0) AS total
      FROM assets s
      INNER JOIN wallets a ON a.id = s.wallet_id
      WHERE s.is_sold = 0
      GROUP BY s.currency
    ''');
    return {
      for (final row in rows)
        (row['currency'] ?? 'PKR').toString():
            (row['total'] as num).toDouble(),
    };
  }
  Future<Map<String, double>> getTotalRealizedProfitLossByCurrency() async {
    final db = await _database;
    await _ensureTables(db);
    final rows = await db.rawQuery('''
      SELECT s.currency AS currency,
             COALESCE(
               SUM(s.sale_price - s.purchase_price), 0
             ) AS total
      FROM assets s
      INNER JOIN wallets a ON a.id = s.wallet_id
      WHERE s.is_sold = 1
      GROUP BY a.currency
    ''');
    return {
      for (final row in rows)
        (row['currency'] ?? 'PKR').toString():
            (row['total'] as num).toDouble(),
    };
  }
  Future<double> getTotalCurrentValue() async {
    final values = await getTotalCurrentValueByCurrency();
    return values.values.fold<double>(
      0.0,
      (double total, double value) => total + value,
    );
  }
  Future<double> getTotalPurchaseValue() async {
    final values = await getTotalPurchaseValueByCurrency();
    return values.values.fold<double>(
      0.0,
      (double total, double value) => total + value,
    );
  }
  Future<double> getTotalRealizedProfitLoss() async {
    final values =
        await getTotalRealizedProfitLossByCurrency();
    return values.values.fold<double>(
      0.0,
      (double total, double value) => total + value,
    );
  }
  Future<List<AssetsModel>> getAssetsByWallet(
    int walletId,
  ) async {
    final db = await _database;
    await _ensureTables(db);
    final rows = await db.query(
      'assets',
      where: 'wallet_id = ?',
      whereArgs: [walletId],
      orderBy: 'purchase_date DESC',
    );
    return rows.map(AssetsModel.fromMap).toList();
  }
}
