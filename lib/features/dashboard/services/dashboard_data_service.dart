import 'package:sqflite/sqflite.dart';
import 'package:my_finance/core/database/database_manager.dart';

/// Dashboard-specific read models and alert state persisted in my_finance.db.
class DashboardDataService {
  DashboardDataService._();

  static Database get _db => DatabaseManager.instance.database;

  static Future<List<Map<String, Object?>>> getMonthlyIncomeExpense({
    required double baseRate,
    required DateTime monthStart,
    required DateTime nextMonth,
  }) {
    return _db.rawQuery('''
      SELECT UPPER(t.type) AS type,
        COALESCE(SUM(
          t.amount * COALESCE(
            er.rate,
            CASE WHEN UPPER(w.currency) = 'PKR' THEN 1.0 ELSE 0.0 END
          ) / ?
        ), 0) AS total
      FROM transactions t
      INNER JOIN wallets w ON w.id = t.wallet_id
      LEFT JOIN exchange_rates er
        ON UPPER(er.currency) = UPPER(w.currency)
      WHERE UPPER(t.type) IN ('INCOME', 'EXPENSE')
        AND date(t.date) >= date(?)
        AND date(t.date) < date(?)
      GROUP BY UPPER(t.type)
    ''', [
      baseRate,
      monthStart.toIso8601String(),
      nextMonth.toIso8601String(),
    ]);
  }

  static Future<Map<String, double>> getWalletTotalsByCurrency() async {
    final rows = await _db.rawQuery('''
      SELECT UPPER(currency) AS currency, COALESCE(SUM(balance), 0) AS total
      FROM wallets
      WHERE COALESCE(exclude_total, 0) = 0
      GROUP BY UPPER(currency)
      ORDER BY UPPER(currency)
    ''');
    return {
      for (final row in rows)
        (row['currency'] as String? ?? '').toUpperCase():
            (row['total'] as num?)?.toDouble() ?? 0,
    };
  }

  static Future<int> getBudgetAlertLevel(int budgetId) async {
    final rows = await _db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['budget_alert_level_$budgetId'],
      limit: 1,
    );
    return rows.isEmpty
        ? 0
        : int.tryParse(rows.first['setting_value']?.toString() ?? '0') ?? 0;
  }

  static Future<void> saveBudgetAlertLevel(
    int budgetId,
    int level,
  ) async {
    await _db.insert(
      'app_settings',
      {
        'setting_key': 'budget_alert_level_$budgetId',
        'setting_value': level.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
