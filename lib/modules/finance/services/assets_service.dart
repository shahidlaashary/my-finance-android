import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/modules/finance/models/assets_model.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
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
        include_in_consolidated_balance INTEGER NOT NULL DEFAULT 0,
        sale_date TEXT,
        sale_price REAL,
        sale_wallet_id INTEGER,
        sale_wallet_amount REAL,
        sale_wallet_currency TEXT NOT NULL DEFAULT 'PKR',
        sale_exchange_rate REAL NOT NULL DEFAULT 1,
        sale_is_manual_rate INTEGER NOT NULL DEFAULT 0,
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
  /// Asset, linked loan aur tamam attachments ko all-or-nothing save karta hai.
  /// Files pehle temporary location mein prepare hoti hain; phir finance rows aur
  /// attachment metadata ek hi SQLite transaction mein commit hotay hain.
  Future<int> addAssetWithAttachments(
    AssetsModel asset,
    List<Map<String, String>> attachmentSources,
  ) async {
    _validateAsset(asset);
    if (asset.isSold) throw Exception('Please add the asset first, then record its sale.');

    final prepared = await AttachmentService.prepareAssetAttachments(attachmentSources);
    final createdPaths = <String>[];
    try {
      final db = await _database;
      await _ensureTables(db);
      final isLoan = asset.paymentType.toLowerCase() == 'loan';
      var assetWalletId = asset.walletId;
      var currency = asset.currency.toUpperCase();

      if (isLoan) {
        if (asset.partyId == null) throw Exception('Please select a party for this loan purchase.');
        assetWalletId = 0;
      }

      final assetId = await db.transaction((txn) async {
        if (isLoan) {
          final parties = await txn.query(
            'loan_parties',
            columns: ['id', 'currency'],
            where: 'id = ?',
            whereArgs: [asset.partyId],
            limit: 1,
          );
          if (parties.isEmpty) throw Exception('Selected party was not found.');
          currency = (parties.first['currency']?.toString() ?? 'PKR').toUpperCase();
        } else {
          final wallet = await _getWallet(txn, assetWalletId);
          currency = (wallet['currency'] ?? 'PKR').toString().toUpperCase();
          if ((wallet['balance'] as num).toDouble() < asset.purchasePrice) {
            throw Exception('Insufficient wallet balance.');
          }
        }

        final assetMap = asset.copyWith(
          walletId: assetWalletId,
          currency: currency,
          name: asset.name.trim(),
          category: asset.category.trim().isEmpty ? 'Other' : asset.category.trim(),
          createdAt: asset.createdAt ?? DateTime.now(),
        ).toMap()..remove('id');
        final id = await txn.insert('assets', assetMap);
        if (!isLoan) {
          await _changeBalance(
            txn,
            walletId: assetWalletId,
            amount: -asset.purchasePrice,
          );
        } else {
          final loanId = await txn.insert('loans', {
            'party_id': asset.partyId,
            'loan_type': 'taken',
            'amount': asset.purchasePrice,
            'remaining_amount': asset.purchasePrice,
            'wallet_id': 0,
            'currency': currency,
            'source_type': 'asset_purchase',
            'source_id': id,
            'lending_date': asset.purchaseDate.toIso8601String().split('T').first,
            'notes': 'Asset purchase: ${asset.name}',
            'status': 'active',
            'created_at': DateTime.now().toIso8601String(),
          });
          await txn.update('assets', {'linked_loan_id': loanId}, where: 'id = ?', whereArgs: [id]);
        }

        await AttachmentService.insertPreparedAssetAttachments(
          txn: txn,
          assetId: id,
          prepared: prepared,
          createdPaths: createdPaths,
        );
        return id;
      });

      AppRefreshController.notifyChanged();
      return assetId;
    } catch (_) {
      await AttachmentService.cleanupCreatedAssetAttachmentFiles(createdPaths);
      rethrow;
    } finally {
      await AttachmentService.cleanupPreparedAssetAttachments(prepared);
    }
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
    if (result != 1) {
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
    double? walletAmount,
    String? walletCurrency,
    double exchangeRate = 1.0,
    bool isManualRate = false,
  }) async {
    if (!salePrice.isFinite || salePrice < 0) {
      throw Exception('Please enter a valid sale price.');
    }

    final db = await _database;
    await _ensureTables(db);

    await db.transaction((txn) async {
      final rows = await txn.query(
        'assets',
        where: 'id = ?',
        whereArgs: [assetId],
        limit: 1,
      );
      if (rows.isEmpty) throw Exception('Asset was not found.');

      final asset = AssetsModel.fromMap(rows.first);
      if (asset.isSold) throw Exception('This asset has already been sold.');
      if (saleDate.isBefore(asset.purchaseDate)) {
        throw Exception('Sale date cannot be before purchase date.');
      }

      final isLoan = paymentType.toLowerCase() == 'loan';
      if (isLoan && salePrice <= 0) {
        throw Exception('Loan sale price must be greater than zero.');
      }

      var actualWalletAmount = walletAmount ?? salePrice;
      var actualWalletCurrency = (walletCurrency ?? asset.currency).toUpperCase();
      var appliedExchangeRate = exchangeRate;
      int? linkedLoanId;
      var anchorWalletId = saleWalletId;

      if (isLoan) {
        if (partyId == null) throw Exception('Please select the buyer party.');
        final parties = await txn.query(
          'loan_parties',
          where: 'id = ?',
          whereArgs: [partyId],
          limit: 1,
        );
        if (parties.isEmpty) throw Exception('Selected buyer party was not found.');
        final buyerCurrency =
            (parties.first['currency']?.toString() ?? 'PKR').toUpperCase();
        if (buyerCurrency != asset.currency.toUpperCase()) {
          throw Exception(
            'Buyer party currency must match the asset currency (${asset.currency}).',
          );
        }

        anchorWalletId = 0;
        actualWalletAmount = 0;
        actualWalletCurrency = asset.currency.toUpperCase();
        appliedExchangeRate = 1.0;
        linkedLoanId = await txn.insert('loans', {
          'party_id': partyId,
          'loan_type': 'given',
          'amount': salePrice,
          'remaining_amount': salePrice,
          'wallet_id': 0,
          'currency': buyerCurrency,
          'source_type': 'asset_sale',
          'source_id': assetId,
          'lending_date': saleDate.toIso8601String().split('T').first,
          'notes': 'Asset sale: ${asset.name}',
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        final saleWallet = await _getWallet(txn, anchorWalletId);
        final saleCurrency =
            (saleWallet['currency'] ?? 'PKR').toString().toUpperCase();
        if (saleCurrency != actualWalletCurrency) {
          throw Exception(
            'Receiving wallet currency changed. Please reopen the sale form.',
          );
        }
        if (!actualWalletAmount.isFinite || actualWalletAmount < 0) {
          throw Exception('Please enter a valid wallet amount received.');
        }
        if (!appliedExchangeRate.isFinite || appliedExchangeRate <= 0) {
          throw Exception('Invalid asset sale exchange rate.');
        }
        if (salePrice > 0 &&
            (actualWalletAmount / salePrice - appliedExchangeRate).abs() >
                0.000001) {
          throw Exception(
            'Sale conversion details are inconsistent. Please retry.',
          );
        }
        await _changeBalance(
          txn,
          walletId: anchorWalletId,
          amount: actualWalletAmount,
        );
      }

      final updated = await txn.update(
        'assets',
        {
          'is_sold': 1,
          'sale_date': saleDate.toIso8601String(),
          'sale_price': salePrice,
          'sale_wallet_id': anchorWalletId,
          'sale_wallet_amount': isLoan ? null : actualWalletAmount,
          'sale_wallet_currency': actualWalletCurrency,
          'sale_exchange_rate': appliedExchangeRate,
          'sale_is_manual_rate': isManualRate ? 1 : 0,
          'sale_payment_type': paymentType,
          'sale_party_id': isLoan ? partyId : null,
          'sale_linked_loan_id': linkedLoanId,
        },
        where: 'id = ? AND is_sold = 0',
        whereArgs: [assetId],
      );
      if (updated != 1) {
        throw Exception('This asset has already been sold or could not be updated.');
      }
    });

    AppRefreshController.notifyChanged();
  }

  Future<void> updateAsset(AssetsModel updatedAsset) async {
    if (updatedAsset.id == null) {
      throw Exception('Asset ID is required for updating.');
    }
    _validateAsset(updatedAsset);
    if (updatedAsset.isSold) {
      throw Exception('Use the Sell Asset option to record a sale.');
    }

    final db = await _database;
    await _ensureTables(db);

    await db.transaction((txn) async {
      // Read the current record inside the transaction so an intervening
      // sale or deletion cannot leave this update working from stale data.
      final rows = await txn.query(
        'assets',
        where: 'id = ?',
        whereArgs: [updatedAsset.id],
        limit: 1,
      );
      if (rows.isEmpty) throw Exception('Asset was not found.');

      final oldAsset = AssetsModel.fromMap(rows.first);
      if (oldAsset.isSold) throw Exception('Sold assets cannot be edited.');

      final oldIsLoan = oldAsset.paymentType.toLowerCase() == 'loan';
      final newIsLoan = updatedAsset.paymentType.toLowerCase() == 'loan';
      if (oldIsLoan != newIsLoan) {
        throw Exception(
          'Payment Type cannot be changed after saving. Delete and recreate the asset to change it.',
        );
      }

      if (oldIsLoan) {
        if (updatedAsset.partyId == null || oldAsset.linkedLoanId == null) {
          throw Exception('Linked loan or party is missing.');
        }

        final loanTermsChanged =
            updatedAsset.purchasePrice != oldAsset.purchasePrice ||
            updatedAsset.partyId != oldAsset.partyId ||
            !updatedAsset.purchaseDate.isAtSameMomentAs(oldAsset.purchaseDate) ||
            updatedAsset.name != oldAsset.name;

        final parties = await txn.query(
          'loan_parties',
          columns: ['id', 'currency'],
          where: 'id = ?',
          whereArgs: [updatedAsset.partyId],
          limit: 1,
        );
        if (parties.isEmpty) throw Exception('Selected party was not found.');
        final currency =
            (parties.first['currency']?.toString() ?? 'PKR').toUpperCase();
        if (currency != oldAsset.currency.toUpperCase()) {
          throw Exception(
            'Party currency must remain ${oldAsset.currency} for this asset.',
          );
        }

        final loanRows = await txn.query(
          'loans',
          columns: [
            'id', 'source_type', 'source_id', 'loan_type', 'party_id',
            'amount', 'remaining_amount', 'wallet_id', 'currency',
          ],
          where: 'id = ?',
          whereArgs: [oldAsset.linkedLoanId],
          limit: 1,
        );
        if (loanRows.isEmpty) {
          throw Exception('Linked asset loan was not found.');
        }
        final linkedLoan = loanRows.first;
        final linkedAmount = (linkedLoan['amount'] as num?)?.toDouble();
        final linkedRemaining =
            (linkedLoan['remaining_amount'] as num?)?.toDouble();
        if (linkedLoan['source_type'] != 'asset_purchase' ||
            (linkedLoan['source_id'] as num?)?.toInt() != updatedAsset.id ||
            linkedLoan['loan_type']?.toString().toLowerCase() != 'taken' ||
            (linkedLoan['party_id'] as num?)?.toInt() != oldAsset.partyId ||
            (linkedLoan['wallet_id'] as num?)?.toInt() != 0 ||
            linkedAmount == null ||
            !linkedAmount.isFinite ||
            (linkedAmount - oldAsset.purchasePrice).abs() > 0.000001 ||
            linkedRemaining == null ||
            !linkedRemaining.isFinite ||
            linkedRemaining < 0 ||
            linkedRemaining > linkedAmount + 0.000001 ||
            (linkedLoan['currency']?.toString() ?? 'PKR').toUpperCase() !=
                oldAsset.currency.toUpperCase()) {
          throw Exception('Linked asset loan does not match the saved Asset details.');
        }

        final linkedRepayments = await txn.query(
          'loan_repayments',
          columns: ['amount'],
          where: 'loan_id = ?',
          whereArgs: [oldAsset.linkedLoanId],
        );
        var repaidTotal = 0.0;
        for (final repayment in linkedRepayments) {
          final repaymentAmount =
              (repayment['amount'] as num?)?.toDouble();
          if (repaymentAmount == null ||
              !repaymentAmount.isFinite ||
              repaymentAmount <= 0) {
            throw Exception(
              'Linked asset loan repayment history contains invalid amounts.',
            );
          }
          repaidTotal += repaymentAmount;
        }
        if (!repaidTotal.isFinite ||
            (repaidTotal - (linkedAmount - linkedRemaining)).abs() >
                0.000001) {
          throw Exception(
            'Linked asset loan balance does not reconcile with its repayment history.',
          );
        }

        if (loanTermsChanged) {
          final repayments = await txn.query(
            'loan_repayments',
            columns: ['id'],
            where: 'loan_id = ?',
            whereArgs: [oldAsset.linkedLoanId],
            limit: 1,
          );
          if (repayments.isNotEmpty) {
            throw Exception(
              'This asset already has loan repayments. Its linked loan details cannot be changed.',
            );
          }

          final loanUpdated = await txn.update(
            'loans',
            {
              'party_id': updatedAsset.partyId,
              'loan_type': 'taken',
              'amount': updatedAsset.purchasePrice,
              'remaining_amount': updatedAsset.purchasePrice,
              'wallet_id': 0,
              'currency': currency,
              'lending_date':
                  updatedAsset.purchaseDate.toIso8601String().split('T').first,
              'notes': 'Asset purchase: ${updatedAsset.name}',
              'status': 'active',
            },
            where: 'id = ? AND source_type = ? AND source_id = ?',
            whereArgs: [oldAsset.linkedLoanId, 'asset_purchase', updatedAsset.id],
          );
          if (loanUpdated != 1) {
            throw Exception('Linked asset loan could not be updated.');
          }
        }

        final assetUpdated = await txn.update(
          'assets',
          updatedAsset.copyWith(
            walletId: oldAsset.walletId,
            currency: oldAsset.currency,
            linkedLoanId: oldAsset.linkedLoanId,
            createdAt: oldAsset.createdAt,
          ).toMap()..remove('id'),
          where: 'id = ? AND is_sold = 0',
          whereArgs: [updatedAsset.id],
        );
        if (assetUpdated != 1) {
          throw Exception('Asset not found or already sold.');
        }
        return;
      }

      final oldWallet = await _getWallet(txn, oldAsset.walletId);
      final updatedWallet = await _getWallet(txn, updatedAsset.walletId);
      final oldCurrency =
          (oldWallet['currency'] ?? 'PKR').toString().toUpperCase();
      final updatedCurrency =
          (updatedWallet['currency'] ?? 'PKR').toString().toUpperCase();
      if (oldCurrency != updatedCurrency) {
        throw Exception(
          'Asset must remain linked to a wallet with the same currency.',
        );
      }

      // Reverse the old purchase first, then debit the selected wallet.
      await _changeBalance(
        txn,
        walletId: oldAsset.walletId,
        amount: oldAsset.purchasePrice,
      );
      if (await _getBalance(txn, updatedAsset.walletId) <
          updatedAsset.purchasePrice) {
        throw Exception('Insufficient wallet balance.');
      }
      await _changeBalance(
        txn,
        walletId: updatedAsset.walletId,
        amount: -updatedAsset.purchasePrice,
      );

      final assetUpdated = await txn.update(
        'assets',
        updatedAsset.copyWith(
          currency: updatedCurrency,
          createdAt: oldAsset.createdAt,
        ).toMap()..remove('id'),
        where: 'id = ? AND is_sold = 0',
        whereArgs: [updatedAsset.id],
      );
      if (assetUpdated != 1) {
        throw Exception('Asset not found or already sold.');
      }
    });

    AppRefreshController.notifyChanged();
  }

  Future<void> deleteAsset(int assetId) async {
    final db = await _database;
    await _ensureTables(db);
    await RecycleBinService.ensureTable();

    await db.transaction((txn) async {
      final assetRows = await txn.query(
        'assets',
        where: 'id = ?',
        whereArgs: [assetId],
        limit: 1,
      );
      if (assetRows.isEmpty) return;
      final assetRecord = assetRows.first;
      final asset = AssetsModel.fromMap(assetRecord);

      if ((asset.paymentType.toLowerCase() == 'loan') !=
          (asset.linkedLoanId != null)) {
        throw Exception('Asset purchase loan link is missing or inconsistent.');
      }
      if (asset.isSold &&
          (asset.salePaymentType.toLowerCase() == 'loan') !=
              (asset.saleLinkedLoanId != null)) {
        throw Exception('Asset sale loan link is missing or inconsistent.');
      }
      if (!asset.isSold && asset.saleLinkedLoanId != null) {
        throw Exception('An unsold Asset cannot have a linked sale loan.');
      }
      if (asset.linkedLoanId != null &&
          asset.linkedLoanId == asset.saleLinkedLoanId) {
        throw Exception('Purchase and sale cannot reference the same linked loan.');
      }

      // Net all wallet effects first. This avoids temporary balance changes
      // depending on whether the purchase or sale loan is processed first.
      final walletDeltas = <int, double>{};
      Future<void> validateWalletCurrency(int walletId, String expectedCurrency) async {
        final walletRows = await txn.query(
          'wallets',
          columns: ['currency'],
          where: 'id = ?',
          whereArgs: [walletId],
          limit: 1,
        );
        if (walletRows.isEmpty) {
          throw Exception('A linked Asset wallet no longer exists. Restore the wallet first.');
        }
        final currentCurrency =
            (walletRows.first['currency']?.toString() ?? 'PKR').trim().toUpperCase();
        if (currentCurrency != expectedCurrency.trim().toUpperCase()) {
          throw Exception(
            'An Asset wallet currency has changed. Correct the wallet currency before deleting this Asset.',
          );
        }
      }
      void addWalletDelta(int walletId, double delta) {
        if (walletId <= 0 || !delta.isFinite) {
          throw Exception('The Asset contains invalid wallet accounting details.');
        }
        final next = (walletDeltas[walletId] ?? 0) + delta;
        if (!next.isFinite) {
          throw Exception('The Asset wallet balance change is invalid.');
        }
        walletDeltas[walletId] = next;
      }

      final linkedLoanIds = <int>[
        if (asset.saleLinkedLoanId != null) asset.saleLinkedLoanId!,
        if (asset.linkedLoanId != null) asset.linkedLoanId!,
      ];
      final linkedLoanSnapshots = <Map<String, dynamic>>[];

      for (final loanId in linkedLoanIds) {
        final isPurchaseLoan = loanId == asset.linkedLoanId;
        final expectedSource = isPurchaseLoan ? 'asset_purchase' : 'asset_sale';
        final expectedLoanType = isPurchaseLoan ? 'taken' : 'given';
        final expectedAmount = isPurchaseLoan ? asset.purchasePrice : asset.salePrice;
        final expectedPartyId = isPurchaseLoan ? asset.partyId : asset.salePartyId;

        final loanRows = await txn.query(
          'loans',
          where: 'id = ?',
          whereArgs: [loanId],
          limit: 1,
        );
        if (loanRows.isEmpty) {
          throw Exception('A linked asset loan is missing. Asset deletion was cancelled.');
        }
        final loanRecord = loanRows.first;
        final loanAmount = (loanRecord['amount'] as num?)?.toDouble();
        if (loanRecord['source_type'] != expectedSource ||
            (loanRecord['source_id'] as num?)?.toInt() != assetId ||
            loanRecord['loan_type']?.toString().toLowerCase() != expectedLoanType ||
            (loanRecord['wallet_id'] as num?)?.toInt() != 0 ||
            expectedPartyId == null ||
            expectedPartyId <= 0 ||
            (loanRecord['party_id'] as num?)?.toInt() != expectedPartyId ||
            loanAmount == null ||
            !loanAmount.isFinite ||
            expectedAmount == null ||
            (loanAmount - expectedAmount).abs() > 0.000001 ||
            (loanRecord['currency']?.toString() ?? 'PKR').toUpperCase() !=
                asset.currency.toUpperCase()) {
          throw Exception('The linked asset loan does not match this asset. Asset deletion was cancelled.');
        }

        final repaymentRows = await txn.query(
          'loan_repayments',
          where: 'loan_id = ?',
          whereArgs: [loanId],
        );
        final loanRemaining =
            (loanRecord['remaining_amount'] as num?)?.toDouble();
        final repaidTotal = repaymentRows.fold<double>(
          0,
          (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? double.nan),
        );
        if (loanRemaining == null ||
            !loanRemaining.isFinite ||
            loanRemaining < 0 ||
            loanRemaining > loanAmount + 0.000001 ||
            !repaidTotal.isFinite ||
            (repaidTotal - (loanAmount - loanRemaining)).abs() > 0.000001) {
          throw Exception(
            'The linked asset loan balance does not reconcile with its repayment history. Asset deletion was cancelled.',
          );
        }
        linkedLoanSnapshots.add({
          'loan': loanRecord,
          'repayments': repaymentRows,
        });

        for (final repayment in repaymentRows) {
          final repaymentAmount = (repayment['amount'] as num).toDouble();
          final repaymentWalletId = (repayment['wallet_id'] as num).toInt();
          final repaymentWalletAmount =
              (repayment['wallet_amount'] as num?)?.toDouble() ??
                  repaymentAmount;
          if ((repayment['loan_id'] as num?)?.toInt() != loanId ||
              !repaymentAmount.isFinite ||
              repaymentAmount <= 0 ||
              !repaymentWalletAmount.isFinite ||
              repaymentWalletAmount <= 0 ||
              repaymentWalletId <= 0) {
            throw Exception('A linked loan repayment contains invalid data. Asset deletion was cancelled.');
          }
          final repaymentWalletRows = await txn.query(
            'wallets',
            columns: ['currency'],
            where: 'id = ?',
            whereArgs: [repaymentWalletId],
            limit: 1,
          );
          if (repaymentWalletRows.isEmpty) {
            throw Exception('A repayment wallet no longer exists. Restore the wallet first.');
          }
          final savedWalletCurrency =
              repayment['wallet_currency']?.toString().trim().toUpperCase() ?? '';
          final currentWalletCurrency =
              (repaymentWalletRows.first['currency']?.toString() ?? 'PKR')
                  .trim()
                  .toUpperCase();
          if (savedWalletCurrency.isNotEmpty &&
              savedWalletCurrency != currentWalletCurrency) {
            throw Exception(
              'A linked loan repayment wallet currency has changed. Correct the wallet currency before deleting this Asset.',
            );
          }
          addWalletDelta(
            repaymentWalletId,
            expectedLoanType == 'given'
                ? -repaymentWalletAmount
                : repaymentWalletAmount,
          );
        }
      }

      if (asset.isSold && asset.salePaymentType.toLowerCase() != 'loan') {
        if (asset.salePrice == null ||
            !asset.salePrice!.isFinite ||
            asset.salePrice! < 0) {
          throw Exception('The Asset sale details are invalid. Asset deletion was cancelled.');
        }
        final receivingWalletId = asset.saleWalletId ?? asset.walletId;
        final receivedAmount = asset.saleWalletAmount ?? asset.salePrice!;
        if (!receivedAmount.isFinite || receivedAmount < 0) {
          throw Exception('The Asset sale wallet amount is invalid. Asset deletion was cancelled.');
        }
        await validateWalletCurrency(receivingWalletId, asset.saleWalletCurrency);
        addWalletDelta(receivingWalletId, -receivedAmount);
      }

      if (asset.paymentType.toLowerCase() != 'loan') {
        if (!asset.purchasePrice.isFinite || asset.purchasePrice <= 0) {
          throw Exception('The Asset purchase amount is invalid. Asset deletion was cancelled.');
        }
        await validateWalletCurrency(asset.walletId, asset.currency);
        addWalletDelta(asset.walletId, asset.purchasePrice);
      }

      final now = DateTime.now();
      await txn.insert('recycle_bin', {
        'entity_type': 'Asset',
        'entity_title': asset.name,
        'source_table': 'assets',
        'source_id': assetId.toString(),
        'payload': jsonEncode(assetRecord),
        'related_payload': linkedLoanSnapshots.isEmpty
            ? null
            : jsonEncode(linkedLoanSnapshots),
        'deleted_at': now.toIso8601String(),
        'expires_at': now
            .add(const Duration(days: RecycleBinService.retentionDays))
            .toIso8601String(),
      });

      // Reversing a sale or repayment must never push a wallet below
      // zero when its proceeds have already been spent. Validate every net
      // wallet effect before applying any of them.
      for (final entry in walletDeltas.entries) {
        final walletRows = await txn.query(
          'wallets',
          columns: ['balance'],
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (walletRows.isEmpty) {
          throw Exception('The linked wallet no longer exists. Restore the wallet first.');
        }
        final balance = (walletRows.first['balance'] as num).toDouble();
        if (!balance.isFinite || balance + entry.value < -0.000001) {
          throw Exception(
            'Insufficient wallet balance to delete this Asset and reverse its sale or loan repayments.',
          );
        }
      }
      for (final entry in walletDeltas.entries) {
        if (entry.value == 0) continue;
        await _changeBalance(
          txn,
          walletId: entry.key,
          amount: entry.value,
        );
      }

      for (final loanId in linkedLoanIds) {
        await txn.delete(
          'loan_repayments',
          where: 'loan_id = ?',
          whereArgs: [loanId],
        );
        await txn.delete('loans', where: 'id = ?', whereArgs: [loanId]);
      }

      final deleted = await txn.delete(
        'assets',
        where: 'id = ?',
        whereArgs: [assetId],
      );
      if (deleted != 1) {
        throw Exception('Asset could not be deleted. The transaction was cancelled.');
      }
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
      WHERE s.is_sold = 0
      GROUP BY s.currency
    ''');
    return {
      for (final row in rows)
        (row['currency'] ?? 'PKR').toString():
            (row['total'] as num).toDouble(),
    };
  }
  Future<Map<String, double>> getConsolidatedIncludedCurrentValueByCurrency() async {
    final db = await _database;
    await _ensureTables(db);
    final rows = await db.rawQuery('''
      SELECT currency AS currency,
             COALESCE(SUM(current_value), 0) AS total
      FROM assets
      WHERE is_sold = 0 AND include_in_consolidated_balance = 1
      GROUP BY currency
    ''');
    return {
      for (final row in rows)
        (row['currency'] ?? 'PKR').toString().toUpperCase():
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
      WHERE s.is_sold = 0
      GROUP BY s.currency
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
}
