import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';

class AssetDepreciationService {
  Future<Database> get _db => TransactionsService.database;

  Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asset_depreciation (
        asset_id INTEGER PRIMARY KEY,
        method TEXT NOT NULL DEFAULT 'straight_line',
        useful_life_years REAL NOT NULL DEFAULT 5,
        salvage_value REAL NOT NULL DEFAULT 0,
        declining_rate REAL NOT NULL DEFAULT 20,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<Map<String, dynamic>?> getSettings(int assetId) async {
    final db = await _db;
    await _ensureTable(db);
    final rows = await db.query('asset_depreciation',
        where: 'asset_id = ?', whereArgs: [assetId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveSettings({
    required int assetId,
    required String method,
    required double usefulLifeYears,
    required double salvageValue,
    required double decliningRate,
  }) async {
    if (!['straight_line', 'declining_balance'].contains(method)) {
      throw ArgumentError('Unsupported depreciation method.');
    }
    if (!usefulLifeYears.isFinite || usefulLifeYears <= 0 ||
        usefulLifeYears > 100) {
      throw ArgumentError('Useful life must be between 0 and 100 years.');
    }
    if (!salvageValue.isFinite || salvageValue < 0) {
      throw ArgumentError('Salvage value cannot be negative.');
    }
    if (!decliningRate.isFinite || decliningRate <= 0 ||
        decliningRate > 100) {
      throw ArgumentError('Declining rate must be between 0 and 100%.');
    }
    final db = await _db;
    await _ensureTable(db);
    await db.insert('asset_depreciation', {
      'asset_id': assetId,
      'method': method,
      'useful_life_years': usefulLifeYears,
      'salvage_value': salvageValue,
      'declining_rate': decliningRate,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, double> calculate({
    required double purchasePrice,
    required DateTime purchaseDate,
    required Map<String, dynamic>? settings,
    DateTime? asOf,
  }) {
    final config = settings ?? const <String, dynamic>{};
    final method = config['method']?.toString() ?? 'straight_line';
    final life = (config['useful_life_years'] as num?)?.toDouble() ?? 5;
    final salvage = (config['salvage_value'] as num?)?.toDouble() ?? 0;
    final rate = ((config['declining_rate'] as num?)?.toDouble() ?? 20) / 100;
    final days = ((asOf ?? DateTime.now()).difference(purchaseDate).inDays)
        .clamp(0, 365250);
    final years = days / 365.25;
    final depreciable = (purchasePrice - salvage).clamp(0, double.infinity);
    double bookValue;
    if (method == 'declining_balance') {
      bookValue = purchasePrice * math.pow(1 - rate, years).toDouble();
      bookValue = bookValue.clamp(salvage, purchasePrice);
    } else {
      final annual = depreciable / life;
      bookValue = (purchasePrice - annual * years).clamp(salvage, purchasePrice);
    }
    final accumulated = (purchasePrice - bookValue).clamp(0, purchasePrice);
    return {
      'book_value': bookValue,
      'accumulated_depreciation': accumulated,
      'annual_depreciation': method == 'declining_balance'
          ? bookValue * rate
          : depreciable / life,
      'monthly_depreciation': (method == 'declining_balance'
          ? bookValue * rate
          : depreciable / life) / 12,
      'elapsed_years': years,
    };
  }

  double _pow(double base, double exponent) {
    if (base <= 0) return 0;
    return _integerPower(base, exponent.floor()) *
        _fractionalPower(base, exponent - exponent.floor());
  }

  double _integerPower(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  double _fractionalPower(double base, double exponent) {
    if (exponent == 0) return 1;
    // Smooth fractional-year approximation for a declining-balance schedule.
    return 1 - (1 - base) * exponent;
  }
}
