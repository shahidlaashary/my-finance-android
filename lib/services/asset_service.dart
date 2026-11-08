
import 'package:sqflite/sqflite.dart';

import '../models/asset_model.dart';
import 'transaction_service.dart';

class AssetService {
  Future<Database> get _database async {
    return TransactionService.database;
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
        account_id INTEGER NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        is_sold INTEGER NOT NULL DEFAULT 0,
        sale_date TEXT,
        sale_price REAL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_assets_account
      ON assets(account_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_assets_sold
      ON assets(is_sold)
    ''');
  }

  Future<void> _ensureTables(Database db) async {
    await _createTables(db);
  }

  Future<Map<String, dynamic>> _getAccount(
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

  Future<double> _getBalance(
    Transaction txn,
    int accountId,
  ) async {
    final account = await _getAccount(txn, accountId);
    return (account['balance'] as num).toDouble();
  }

  Future<void> _changeBalance(
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

  void _validateAsset(AssetModel asset) {
    if (asset.name.trim().isEmpty) {
      throw Exception('Asset name is required.');
    }

    if (asset.accountId <= 0) {
      throw Exception('Please select a valid account.');
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

  Future<int> addAsset(AssetModel asset) async {
    _validateAsset(asset);

    if (asset.isSold) {
      throw Exception(
        'Please add the asset first, then record its sale.',
      );
    }

    final db = await _database;
    await _ensureTables(db);

    return db.transaction((txn) async {
      final account = await _getAccount(
        txn,
        asset.accountId,
      );

      final balance = (account['balance'] as num).toDouble();

      if (balance < asset.purchasePrice) {
        throw Exception('Insufficient account balance.');
      }

      final now = DateTime.now();

      final map = asset.copyWith(
        name: asset.name.trim(),
        category: asset.category.trim().isEmpty
            ? 'Other'
            : asset.category.trim(),
        createdAt: asset.createdAt ?? now,
      ).toMap()
        ..remove('id');

      final assetId = await txn.insert('assets', map);

      await _changeBalance(
        txn,
        accountId: asset.accountId,
        amount: -asset.purchasePrice,
      );

      return assetId;
    });
  }

  Future<List<AssetModel>> getAssets({
    bool includeSold = true,
  }) async {
    final db = await _database;
    await _ensureTables(db);

    final rows = await db.query(
      'assets',
      where: includeSold ? null : 'is_sold = 0',
      orderBy: 'purchase_date DESC, id DESC',
    );

    return rows.map(AssetModel.fromMap).toList();
  }

  Future<AssetModel?> getAssetById(int assetId) async {
    final db = await _database;
    await _ensureTables(db);

    final rows = await db.query(
      'assets',
      where: 'id = ?',
      whereArgs: [assetId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return AssetModel.fromMap(rows.first);
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
  }

  Future<void> sellAsset({
    required int assetId,
    required double salePrice,
    required DateTime saleDate,
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

      if (rows.isEmpty) {
        throw Exception('Asset was not found.');
      }

      final asset = AssetModel.fromMap(rows.first);

      if (asset.isSold) {
        throw Exception('This asset has already been sold.');
      }

      if (saleDate.isBefore(asset.purchaseDate)) {
        throw Exception(
          'Sale date cannot be before purchase date.',
        );
      }

      await _getAccount(txn, asset.accountId);

      await txn.update(
        'assets',
        {
          'is_sold': 1,
          'sale_date': saleDate.toIso8601String(),
          'sale_price': salePrice,
        },
        where: 'id = ?',
        whereArgs: [assetId],
      );

      await _changeBalance(
        txn,
        accountId: asset.accountId,
        amount: salePrice,
      );
    });
  }

  Future<void> updateAsset(AssetModel updatedAsset) async {
    if (updatedAsset.id == null) {
      throw Exception('Asset ID is required for updating.');
    }

    _validateAsset(updatedAsset);

    if (updatedAsset.isSold) {
      throw Exception(
        'Use the Sell Asset option to record a sale.',
      );
    }

    final db = await _database;
    await _ensureTables(db);

    await db.transaction((txn) async {
      final rows = await txn.query(
        'assets',
        where: 'id = ?',
        whereArgs: [updatedAsset.id],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw Exception('Asset was not found.');
      }

      final oldAsset = AssetModel.fromMap(rows.first);

      if (oldAsset.isSold) {
        throw Exception('Sold assets cannot be edited.');
      }

      await _getAccount(txn, oldAsset.accountId);
      await _getAccount(txn, updatedAsset.accountId);

      // Restore the old purchase amount.
      await _changeBalance(
        txn,
        accountId: oldAsset.accountId,
        amount: oldAsset.purchasePrice,
      );

      // Check the available balance after restoring the old amount.
      final newBalance = await _getBalance(
        txn,
        updatedAsset.accountId,
      );

      if (newBalance < updatedAsset.purchasePrice) {
        throw Exception('Insufficient account balance.');
      }

      // Deduct the updated purchase amount.
      await _changeBalance(
        txn,
        accountId: updatedAsset.accountId,
        amount: -updatedAsset.purchasePrice,
      );

      final map = updatedAsset.copyWith(
        name: updatedAsset.name.trim(),
        category: updatedAsset.category.trim().isEmpty
            ? 'Other'
            : updatedAsset.category.trim(),
        createdAt: oldAsset.createdAt,
      ).toMap()
        ..remove('id');

      await txn.update(
        'assets',
        map,
        where: 'id = ?',
        whereArgs: [updatedAsset.id],
      );
    });
  }

  Future<void> deleteAsset(int assetId) async {
    final db = await _database;
    await _ensureTables(db);

    await db.transaction((txn) async {
      final rows = await txn.query(
        'assets',
        where: 'id = ?',
        whereArgs: [assetId],
        limit: 1,
      );

      if (rows.isEmpty) return;

      final asset = AssetModel.fromMap(rows.first);

      await _getAccount(txn, asset.accountId);

      // Reverse sale proceeds if already sold.
      if (asset.isSold && asset.salePrice != null) {
        await _changeBalance(
          txn,
          accountId: asset.accountId,
          amount: -asset.salePrice!,
        );
      }

      // Restore the original purchase amount.
      await _changeBalance(
        txn,
        accountId: asset.accountId,
        amount: asset.purchasePrice,
      );

      await txn.delete(
        'assets',
        where: 'id = ?',
        whereArgs: [assetId],
      );
    });
  }

  Future<Map<String, double>> getTotalCurrentValueByCurrency() async {
    final db = await _database;
    await _ensureTables(db);

    final rows = await db.rawQuery('''
      SELECT a.currency AS currency,
             COALESCE(SUM(s.current_value), 0) AS total
      FROM assets s
      INNER JOIN accounts a ON a.id = s.account_id
      WHERE s.is_sold = 0
      GROUP BY a.currency
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
      SELECT a.currency AS currency,
             COALESCE(SUM(s.purchase_price), 0) AS total
      FROM assets s
      INNER JOIN accounts a ON a.id = s.account_id
      WHERE s.is_sold = 0
      GROUP BY a.currency
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
      SELECT a.currency AS currency,
             COALESCE(
               SUM(s.sale_price - s.purchase_price), 0
             ) AS total
      FROM assets s
      INNER JOIN accounts a ON a.id = s.account_id
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
    return values.values.fold(0.0, (a, b) => a + b);
  }

  Future<double> getTotalPurchaseValue() async {
    final values = await getTotalPurchaseValueByCurrency();
    return values.values.fold(0.0, (a, b) => a + b);
  }

  Future<double> getTotalRealizedProfitLoss() async {
    final values =
        await getTotalRealizedProfitLossByCurrency();
    return values.values.fold(0.0, (a, b) => a + b);
  }

  Future<List<AssetModel>> getAssetsByAccount(
    int accountId,
  ) async {
    final db = await _database;
    await _ensureTables(db);

    final rows = await db.query(
      'assets',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'purchase_date DESC',
    );

    return rows.map(AssetModel.fromMap).toList();
  }
}
