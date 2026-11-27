import 'dart:convert';
import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/modules/finance/services/currency_service.dart';
import 'package:my_finance/modules/finance/services/assets_service.dart';
import 'package:my_finance/modules/finance/services/loans_service.dart';
import 'package:my_finance/modules/finance/services/recurring_transaction_service.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
import 'package:my_finance/modules/committee/services/committee_service.dart';
import 'package:my_finance/core/services/recycle_bin_archive_service.dart';

/// Wallet data operations manage karta hai aur application ka shared
/// DatabaseManager connection use karta hai.
class WalletService {
  WalletService._();

  static Future<List<Map<String, dynamic>>> getWallets({
    String orderBy = 'name COLLATE NOCASE ASC',
  }) async {
    const allowedOrderings = {
      'name',
      'name ASC',
      'name COLLATE NOCASE ASC',
      'id ASC',
    };
    if (!allowedOrderings.contains(orderBy)) {
      throw ArgumentError.value(orderBy, 'orderBy');
    }
    return DatabaseManager.instance.database.query(
      'wallets',
      orderBy: orderBy,
    );
  }

  static Future<Map<String, String>> getWalletDisplaySettings() async {
    final rows = await DatabaseManager.instance.database.query(
      'app_settings',
      columns: ['setting_key', 'setting_value'],
      where: 'setting_key IN (?, ?)',
      whereArgs: ['hidden_wallet_ids', 'wallet_display_order'],
    );
    return {
      for (final row in rows)
        row['setting_key'].toString(): row['setting_value']?.toString() ?? '',
    };
  }

  static Future<void> saveWalletIdSettings(
    String key,
    List<int> ids,
  ) async {
    if (key != 'hidden_wallet_ids' && key != 'wallet_display_order') {
      throw ArgumentError.value(key, 'key', 'Unsupported wallet setting');
    }
    await DatabaseManager.instance.database.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': jsonEncode(ids)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppRefreshController.notifyChanged();
  }

  static Future<Map<int, String>> getWalletCurrencyMap() async {
    final rows = await DatabaseManager.instance.database.query(
      'wallets',
      columns: ['id', 'currency'],
    );
    return {
      for (final row in rows)
        (row['id'] as num).toInt(): row['currency']?.toString() ?? '',
    };
  }

  static Future<void> ensureDefaultWallets({
    required String currency,
    required List<Map<String, dynamic>> defaults,
  }) async {
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty) {
      throw ArgumentError.value(currency, 'currency');
    }
    await DatabaseManager.instance.database.transaction((txn) async {
      for (final wallet in defaults) {
        final name = wallet['name']?.toString().trim() ?? '';
        final type = wallet['type']?.toString() ?? '';
        final iconCode = wallet['icon_code'];
        if (name.isEmpty || type.isEmpty || iconCode is! int) {
          throw ArgumentError('Default wallet data is incomplete.');
        }
        final existing = await txn.query(
          'wallets',
          columns: ['id'],
          where: 'LOWER(name) = ? AND type = ?',
          whereArgs: [name.toLowerCase(), type],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        await txn.insert('wallets', {
          'name': name,
          'type': type,
          'custom_type': null,
          'currency': normalizedCurrency,
          'balance': 0.0,
          'opening_balance': 0.0,
          'wallet_number': null,
          'icon_code': iconCode,
          'exclude_total': 0,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    });
    AppRefreshController.notifyChanged();
  }

  static Future<Map<String, dynamic>?> getWallet(int id) async {
    final rows = await DatabaseManager.instance.database.query(
      'wallets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<int> addWallet({
    required String name,
    required String type,
    String? customType,
    required String currency,
    required double openingBalance,
    String? walletNumber,
    required int iconCode,
    required bool excludeTotal,
  }) async {
    final normalizedName = name.trim();
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedName.isEmpty ||
        normalizedCurrency.isEmpty ||
        !openingBalance.isFinite) {
      throw Exception(
        'Wallet name, currency aur opening balance durust enter karein.',
      );
    }

    final id = await DatabaseManager.instance.database.insert('wallets', {
      'name': normalizedName,
      'type': type,
      'custom_type': customType,
      'currency': normalizedCurrency,
      'balance': openingBalance,
      'opening_balance': openingBalance,
      'wallet_number': walletNumber,
      'icon_code': iconCode,
      'exclude_total': excludeTotal ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    AppRefreshController.notifyChanged();
    return id;
  }

  static Future<void> updateWallet({
    required int id,
    required String name,
    required String type,
    String? customType,
    required String currency,
    required double requestedCurrentBalance,
    String? walletNumber,
    required int iconCode,
    required bool excludeTotal,
  }) async {
    final normalizedName = name.trim();
    currency = currency.trim().toUpperCase();
    if (normalizedName.isEmpty || currency.isEmpty ||
        !requestedCurrentBalance.isFinite) {
      throw Exception('Wallet name, currency aur current balance durust enter karein.');
    }
    // Conversion transaction se pehle missing currency rates refresh karein.
    // Is se wallet currency change karne ke liye Exchange Rates screen kholna zaroori nahi.
    // Sirf missing rates fetch hoti hain; saved rates change nahi hoti.
    final currentWalletRows = await DatabaseManager.instance.database.query(
      'wallets',
      columns: ['currency'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    var useAutomaticRates = await CurrencyService.isOnline();
    if (currentWalletRows.isNotEmpty) {
      final currentCurrency = currentWalletRows.first['currency']
          ?.toString()
          .trim()
          .toUpperCase() ?? '';
      if (currentCurrency != currency) {
        if (useAutomaticRates) {
          await CurrencyService.refreshMissingExchangeRatesOnline(
            currencies: [currentCurrency, currency],
          );
        }
        // Internet check ke baad source ko aik martaba dobara confirm karein.
        useAutomaticRates = await CurrencyService.isOnline();
      }
    }

    await DatabaseManager.instance.database.transaction((txn) async {
      final rows = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw Exception('Wallet nahi mila.');
      }

      final oldWallet = rows.first;
      final oldCurrency = (oldWallet['currency'] as String).trim().toUpperCase();
      final oldBalance = (oldWallet['balance'] as num).toDouble();
      final oldOpening =
          (oldWallet['opening_balance'] as num).toDouble();

      double newOpening = oldOpening;
      double convertedOldBalance = oldBalance;

      // Loan aur asset records ki currency fixed hoti hai. Un ke
      // reference wallet ki currency badalne se purane records ghalat ho sakte hain.
      if (oldCurrency != currency) {
        if (await LoansService.hasWalletReferences(txn, id)) {
          throw Exception('Wallet currency cannot be changed while loans or repayments are linked to it.');
        }
        if (await AssetsService.hasWalletReferences(txn, id)) {
          throw Exception('Wallet currency cannot be changed while assets are linked to it.');
        }
        double? factor;
        if (useAutomaticRates) {
          final oldRate = await _getRateInTransaction(txn, oldCurrency);
          final newRate = await _getRateInTransaction(txn, currency);
          if (oldRate != null && newRate != null && newRate > 0) {
            factor = oldRate / newRate;
          }
        } else {
          factor = await _getManualPairRateInTransaction(
            txn, oldCurrency, currency,
          );
        }

        if (factor == null || !factor.isFinite || factor <= 0) {
          throw Exception(useAutomaticRates
            ? 'Automatic exchange rates $oldCurrency → $currency available nahi.'
            : 'Offline currency change ke liye Manual pair $oldCurrency → $currency add karein.');
        }

        newOpening = oldOpening * factor;
        convertedOldBalance = oldBalance * factor;

        // Historical transaction amounts and currency snapshots are immutable.
        // Only the wallet's current balance/opening balance are converted here.

        await CommitteeService.convertWalletAmounts(
          txn, id, factor, currency,
        );

        // Recurring schedules own their currency-conversion rules.
        await RecurringTransactionService.convertWalletAmounts(
          txn, id, factor,
        );


      }

      // Current balance ki manual change calculate karna.
      final difference = requestedCurrentBalance - convertedOldBalance;

      await txn.update(
        'wallets',
        {
          'name': normalizedName,
          'type': type,
          'custom_type': customType,
          'currency': currency,
          'balance': requestedCurrentBalance,
          'opening_balance': newOpening,
          'wallet_number': walletNumber,
          'icon_code': iconCode,
          'exclude_total': excludeTotal ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      // Manual balance change ka record history mein save karna.
      if (difference.abs() > 0.000001) {
        await TransactionsService.addWalletBalanceAdjustment(
          txn,
          walletId: id,
          difference: difference,
          date: DateTime.now(),
        );
      }
    });
    AppRefreshController.notifyChanged();
  }

  static Future<double?> _getManualPairRateInTransaction(
    Transaction txn,
    String fromCurrency,
    String toCurrency,
  ) async {
    final from = fromCurrency.trim().toUpperCase();
    final to = toCurrency.trim().toUpperCase();
    if (from == to) return 1.0;
    final rows = await txn.query('manual_currency_pairs');
    final direct = rows.where((row) =>
      row['from_currency'].toString().toUpperCase() == from &&
      row['to_currency'].toString().toUpperCase() == to);
    if (direct.isNotEmpty) {
      final value = (direct.first['rate'] as num).toDouble();
      return value.isFinite && value > 0 ? value : null;
    }
    final graph = <String, List<MapEntry<String, double>>>{};
    for (final row in rows) {
      final a = row['from_currency'].toString().toUpperCase();
      final b = row['to_currency'].toString().toUpperCase();
      final rate = (row['rate'] as num).toDouble();
      if (!rate.isFinite || rate <= 0) continue;
      graph.putIfAbsent(a, () => []).add(MapEntry(b, rate));
      graph.putIfAbsent(b, () => []).add(MapEntry(a, 1 / rate));
    }
    final queue = <(String, double)>[(from, 1.0)];
    final visited = <String>{from};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final edge in graph[current.$1] ?? const <MapEntry<String, double>>[]) {
        if (!visited.add(edge.key)) continue;
        final combined = current.$2 * edge.value;
        if (!combined.isFinite || combined <= 0) continue;
        if (edge.key == to) return combined;
        queue.add((edge.key, combined));
      }
    }
    return null;
  }

  static Future<double?> _getRateInTransaction(
    Transaction txn,
    String currency,
  ) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == 'PKR') return 1.0;

    final rows = await txn.query(
      'exchange_rates',
      columns: ['rate'],
      where: 'currency = ?',
      whereArgs: [normalized],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final rate = (rows.first['rate'] as num).toDouble();
    return rate.isFinite && rate > 0 ? rate : null;
  }

  // ----------------------------------------------------------
  // Wallet delete karna
  // ----------------------------------------------------------

  static Future<void> deleteWallet(int id) async {
    final hasRecurringReferences = await DatabaseManager.instance.database
        .transaction((txn) => RecurringTransactionService.hasWalletReferences(txn, id));
    if (hasRecurringReferences) {
      throw Exception(
        'This wallet is linked to a recurring transaction. '
        'Update or delete that schedule before deleting the wallet.',
      );
    }

    final linkedTransactions = await TransactionsService.hasWalletReferences(
      DatabaseManager.instance.database,
      id,
    );

    if (linkedTransactions) {
      throw Exception(
        'Is wallet ke saath transactions linked hain. '
        'Pehle un transactions ko manage karein.',
      );
    }

    final db = DatabaseManager.instance.database;
    final hasLoanReferences = await db.transaction(
      (txn) => LoansService.hasWalletReferences(txn, id),
    );
    if (hasLoanReferences) {
      throw Exception('This wallet is linked to loan records or repayments. Remove or settle those records before deleting the wallet.');
    }
    final hasAssetReferences = await db.transaction(
      (txn) => AssetsService.hasWalletReferences(txn, id),
    );
    if (hasAssetReferences) {
      throw Exception('This wallet is linked to an asset purchase or sale. Delete or update the asset before deleting the wallet.');
    }

    final walletRows = await DatabaseManager.instance.database.query('wallets', where: 'id = ?', whereArgs: [id], limit: 1);
    if (walletRows.isEmpty) return;
    await RecycleBinArchiveService.archive(type: 'Wallet', title: walletRows.first['name']?.toString() ?? 'Wallet', table: 'wallets', id: id, record: walletRows.first);
    await DatabaseManager.instance.database.delete('wallets', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }
  static Future<void> restoreArchivedWallet(
    Transaction txn, Map<String, dynamic> record,
  ) async {
    final duplicate = await txn.query('wallets', columns: ['id'],
      where: 'id = ?', whereArgs: [record['id']], limit: 1);
    if (duplicate.isNotEmpty) throw Exception('This wallet already exists.');
    await txn.insert('wallets', record);
  }

}
