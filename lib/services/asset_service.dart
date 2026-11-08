import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/asset_model.dart';

class AssetService {
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

  static Future<double> _getBalance(
    Transaction txn,
    int accountId,
  ) async {
    final account = await _getAccount(txn, accountId);
    return (account['balance'] as num).toDouble();
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

  static void _validateAsset(AssetModel asset) {
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
        throw Exception('Sale date cannot be before purchase date.');
      }
    }
  }

  /// Adds an asset and deducts its purchase price from the account.
  static Future<int> addAsset(AssetModel asset) async {
    final db = await _database;

    _validateAsset(asset);

    return db.transaction((txn) async {
      final balance = await _getBalance(
        txn,
        asset.accountId,
      );

      final totalRequired =
          asset.purchasePrice + (asset.isSold ? 0 : 0);

      if (balance < totalRequired) {
        throw Exception('Insufficient account balance.');
      }

      if (asset.isSold) {
        throw Exception(
          'Please add the asset first, then record its sale.',
        );
      }

      final now = DateTime.now();

      final assetId = await txn.insert(
        'assets',
        asset.copyWith(
          name: asset.name.trim(),
          category: asset.category.trim().isEmpty
              ? 'Other'
              : asset.category.trim(),
          createdAt: asset.createdAt ?? now,
        ).toMap()
          ..remove('id'),
      );

      await _changeBalance(
        txn,
        accountId: asset.accountId,
        amount: -asset.purchasePrice,
      );

      return assetId;
    });
  }

  /// Returns all assets, newest first.
  static Future<List<AssetModel>> getAssets({
    bool includeSold = true,
  }) async {
    final db = await _database;

    final rows = await db.query(
      'assets',
      where: includeSold ? null : 'is_sold = 0',
      orderBy: 'purchase_date DESC, id DESC',
    );

    return rows.map(AssetModel.fromMap).toList();
  }

  /// Returns one asset by ID.
  static Future<AssetModel?> getAssetById(int assetId) async {
    final db = await _database;

    final rows = await db.query(
      'assets',
      where: 'id = ?',
      whereArgs: [assetId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return AssetModel.fromMap(rows.first);
  }

  /// Updates the current market value of an asset.
  static Future<void> updateCurrentValue(
    int assetId,
    double newValue,
  ) async {
    if (!newValue.isFinite || newValue < 0) {
      throw Exception('Current value cannot be negative.');
    }

    final db = await _database;

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

  /// Records an asset sale and credits the sale amount
  /// to the original linked account.
  static Future<void> sellAsset({
    required int assetId,
    required double salePrice,
    required DateTime saleDate,
  }) async {
    if (!salePrice.isFinite || salePrice < 0) {
      throw Exception('Please enter a valid sale price.');
    }

    final db = await _database;

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
        throw Exception('Sale date cannot be before purchase date.');
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

  /// Updates an asset and safely adjusts the linked account balance.
  static Future<void> updateAsset(AssetModel updatedAsset) async {
    if (updatedAsset.id == null) {
      throw Exception('Asset ID is required for updating.');
    }

    _validateAsset(updatedAsset);

    final db = await _database;

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
        throw Exception(
          'Sold assets cannot be edited. Delete and recreate if necessary.',
        );
      }

      final oldAccountBalance = await _getBalance(
        txn,
        oldAsset.accountId,
      );

      // Restore the original purchase amount.
      await _changeBalance(
        txn,
        accountId: oldAsset.accountId,
        amount: oldAsset.purchasePrice,
      );

      // Deduct the updated purchase amount.
      final newBalance = await _getBalance(
        txn,
        updatedAsset.accountId,
      );

      if (newBalance < updatedAsset.purchasePrice) {
        throw Exception('Insufficient account balance.');
      }

      await _changeBalance(
        txn,
        accountId: updatedAsset.accountId,
        amount: -updatedAsset.purchasePrice,
      );

      await txn.update(
        'assets',
        updatedAsset.copyWith(
          name: updatedAsset.name.trim(),
          createdAt: oldAsset.createdAt,
        ).toMap()
          ..remove('id'),
        where: 'id = ?',
        whereArgs: [updatedAsset.id],
      );
    });
  }

  /// Deletes an asset and restores its purchase amount.
  /// Sold asset proceeds are also reversed.
  static Future<void> deleteAsset(int assetId) async {
    final db = await _database;

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

      // Reverse sale proceeds if the asset was sold.
      if (asset.isSold && asset.salePrice != null) {
        await _changeBalance(
          txn,
          accountId: asset.accountId,
          amount: -asset.salePrice!,
        );
      }

      // Restore original purchase amount.
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

  /// Total current value of unsold assets.
  static Future<double> getTotalCurrentValue() async {
    final db = await _database;

    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(current_value), 0) AS total
      FROM assets
      WHERE is_sold = 0
    ''');

    return (result.first['total'] as num).toDouble();
  }

  /// Total purchase cost of unsold assets.
  static Future<double> getTotalPurchaseValue() async {
    final db = await _database;

    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(purchase_price), 0) AS total
      FROM assets
      WHERE is_sold = 0
    ''');

    return (result.first['total'] as num).toDouble();
  }

  /// Total realized profit or loss from sold assets.
  static Future<double> getTotalRealizedProfitLoss() async {
    final db = await _database;

    final result = await db.rawQuery('''
      SELECT COALESCE(
        SUM(sale_price - purchase_price), 0
      ) AS total
      FROM assets
      WHERE is_sold = 1
    ''');

    return (result.first['total'] as num).toDouble();
  }

  /// Returns assets belonging to a specific account.
  static Future<List<AssetModel>> getAssetsByAccount(
    int accountId,
  ) async {
    final db = await _database;

    final rows = await db.query(
      'assets',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'purchase_date DESC',
    );

    return rows.map(AssetModel.fromMap).toList();
  }
}
