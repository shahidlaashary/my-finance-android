import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/settings/app_settings_service.dart';

/// Dashboard ke read models aur alert state my_finance.db mein save/manage karta hai.
class DashboardDataService {
  DashboardDataService._();

  static Database get _db => DatabaseManager.instance.database;

  static Future<List<Map<String, Object?>>> getMonthlyIncomeExpense({
    required double baseRate,
    required String baseCurrency,
    required bool useManualRates,
    required DateTime monthStart,
    required DateTime nextMonth,
  }) {
    return _db.rawQuery('''
      SELECT UPPER(t.type) AS type,
        COALESCE(SUM(
          t.amount * CASE
            WHEN ? = 1 THEN COALESCE(
              mcp.rate,
              CASE WHEN mpr.rate > 0 THEN 1.0 / mpr.rate END,
              CASE WHEN UPPER(w.currency) = UPPER(?) THEN 1.0 END,
              0.0
            )
            ELSE COALESCE(er.rate, CASE WHEN UPPER(w.currency) = UPPER(?) THEN ? ELSE 0.0 END) / ?
          END
        ), 0) AS total
      FROM transactions t
      INNER JOIN wallets w ON w.id = t.wallet_id
      LEFT JOIN exchange_rates er
        ON UPPER(er.currency) = UPPER(w.currency)
      LEFT JOIN manual_currency_pairs mcp
        ON UPPER(mcp.from_currency) = UPPER(w.currency)
        AND UPPER(mcp.to_currency) = UPPER(?)
      LEFT JOIN manual_currency_pairs mpr
        ON UPPER(mpr.from_currency) = UPPER(?)
        AND UPPER(mpr.to_currency) = UPPER(w.currency)
      WHERE UPPER(t.type) IN ('INCOME', 'EXPENSE')
        AND date(t.date) >= date(?)
        AND date(t.date) < date(?)
      GROUP BY UPPER(t.type)
    ''', [
      useManualRates ? 1 : 0,
      baseCurrency,
      baseCurrency,
      baseRate,
      baseRate,
      baseCurrency,
      baseCurrency,
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
    final saved = await AppSettingsService.get('budget_alert_level_$budgetId');
    return int.tryParse(saved ?? '0') ?? 0;
  }

  static Future<void> saveBudgetAlertLevel(
    int budgetId,
    int level,
  ) async {
    await AppSettingsService.set(
      'budget_alert_level_$budgetId',
      level.toString(),
    );
  }
}
