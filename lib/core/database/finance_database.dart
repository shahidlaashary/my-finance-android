import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

/// Central SQLite database for the My Finance application.
///
/// Version 1 creates the complete fresh finance database schema.
class FinanceDB {
  FinanceDB._();

  static final FinanceDB instance = FinanceDB._();

  /// Initializes the shared finance database connection. FinanceDB keeps
  /// ownership of the fresh-install schema while DatabaseManager owns the
  /// single connection lifecycle used by all finance modules.
  Future<void> init() async {
    await DatabaseManager.instance.initialize(onCreate: _createDatabase);
  }

  /// Internal repository handle. Other modules must use DatabaseManager.
  Database get _db => DatabaseManager.instance.database;

  // Database band karke restore ke baad dobara kholne ke liye.
  Future<void> close() => DatabaseManager.instance.close();

  // Restore ke baad naya database connection shuru karta hai.
  Future<void> reopen() => init();

  Future<void> _createDatabase(Database db, int version) async {
    // Wallets ka table.
    await db.execute('''
      CREATE TABLE wallets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        custom_type TEXT,
        currency TEXT NOT NULL DEFAULT 'PKR',
        balance REAL NOT NULL DEFAULT 0,
        opening_balance REAL NOT NULL DEFAULT 0,
        wallet_number TEXT,
        icon_code INTEGER NOT NULL,
        exclude_total INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Transactions ka table.
    // to_amount aur exchange_rate cross-currency transfers ke liye hain.
    // balance_delta manual balance adjustment ke liye hai.
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        wallet_id INTEGER NOT NULL,
        to_wallet_id INTEGER,
        to_amount REAL,
        exchange_rate REAL,
        balance_delta REAL,
        category TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Har currency ke aik unit ki PKR mein qeemat.
    await db.execute('''
      CREATE TABLE exchange_rates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        currency TEXT NOT NULL UNIQUE,
        rate REAL NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT
      )
    ''');

    // PKR app ki bunyadi currency hai.
    await db.insert('exchange_rates', {
      'currency': 'PKR',
      'rate': 1.0,
      'updated_at': DateTime.now().toIso8601String(),
    });

    // App ki bunyadi currency ki setting.
    await db.insert('app_settings', {
      'setting_key': 'main_currency',
      'setting_value': 'PKR',
    });
  }

  // ----------------------------------------------------------
  // Wallet database ke functions
  // ----------------------------------------------------------

  Future<List<Map<String, dynamic>>> getWallets() {
    return WalletService.getWallets();
  }

  // ----------------------------------------------------------
  // Categories ke functions
  // ----------------------------------------------------------

  List<Map<String, dynamic>> _defaultCategories(String type) {
    final income = [
      {'name': 'Salary', 'icon': Icons.account_balance_wallet_outlined.codePoint},
      {'name': 'Business', 'icon': Icons.business_center_outlined.codePoint},
      {'name': 'Investment', 'icon': Icons.trending_up_outlined.codePoint},
      {'name': 'Gift', 'icon': Icons.card_giftcard_outlined.codePoint},
      {'name': 'Rental Income', 'icon': Icons.home_work_outlined.codePoint},
      {'name': 'Freelance', 'icon': Icons.laptop_mac_outlined.codePoint},
      {'name': 'Interest / Profit', 'icon': Icons.savings_outlined.codePoint},
      {'name': 'Other Income', 'icon': Icons.more_horiz_rounded.codePoint},
    ];
    final expense = [
      {'name': 'Food & Dining', 'icon': Icons.restaurant_outlined.codePoint},
      {'name': 'Transport', 'icon': Icons.directions_car_outlined.codePoint},
      {'name': 'Shopping', 'icon': Icons.shopping_bag_outlined.codePoint},
      {'name': 'Rent / Home', 'icon': Icons.home_outlined.codePoint},
      {'name': 'Bills & Utilities', 'icon': Icons.receipt_long_outlined.codePoint},
      {'name': 'Health', 'icon': Icons.health_and_safety_outlined.codePoint},
      {'name': 'Education', 'icon': Icons.school_outlined.codePoint},
      {'name': 'Clothing', 'icon': Icons.checkroom_outlined.codePoint},
      {'name': 'Mobile & Internet', 'icon': Icons.phone_android_outlined.codePoint},
      {'name': 'Family', 'icon': Icons.people_outline.codePoint},
      {'name': 'Travel', 'icon': Icons.flight_outlined.codePoint},
      {'name': 'Entertainment', 'icon': Icons.movie_outlined.codePoint},
      {'name': 'Charity', 'icon': Icons.volunteer_activism_outlined.codePoint},
      {'name': 'Other Expense', 'icon': Icons.more_horiz_rounded.codePoint},
    ];
    return (type == 'Income' ? income : expense)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getCategories(String type) async {
    final key = type == 'Income' ? 'income_categories' : 'expense_categories';
    final rows = await _db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty || (rows.first['setting_value'] as String? ?? '').isEmpty) {
      final defaults = _defaultCategories(type);
      await saveCategories(type, defaults);
      return defaults;
    }

    try {
      final decoded = jsonDecode(rows.first['setting_value'] as String);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    } catch (_) {
      // Invalid stored data ko safe defaults se replace karna.
    }

    final defaults = _defaultCategories(type);
    await saveCategories(type, defaults);
    return defaults;
  }

  Future<void> saveCategories(
    String type,
    List<Map<String, dynamic>> categories,
  ) async {
    final key = type == 'Income' ? 'income_categories' : 'expense_categories';
    await _db.insert(
      'app_settings',
      {
        'setting_key': key,
        'setting_value': jsonEncode(categories),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppRefreshController.notifyChanged();
  }

  Future<Map<String, dynamic>?> getWallet(int id) {
    return WalletService.getWallet(id);
  }

  Future<int> addWallet({
    required String name,
    required String type,
    String? customType,
    required String currency,
    required double openingBalance,
    String? walletNumber,
    required int iconCode,
    required bool excludeTotal,
  }) {
    return WalletService.addWallet(
      name: name,
      type: type,
      customType: customType,
      currency: currency,
      openingBalance: openingBalance,
      walletNumber: walletNumber,
      iconCode: iconCode,
      excludeTotal: excludeTotal,
    );
  }

  // ----------------------------------------------------------
  // Currency rate ke functions
  // ----------------------------------------------------------

  Future<double?> getExchangeRate(String currency) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == 'PKR') return 1.0;
    final rows = await _db.query(
      'exchange_rates',
      columns: ['rate'],
      where: 'UPPER(currency) = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final rate = (rows.first['rate'] as num).toDouble();
    return rate.isFinite && rate > 0 ? rate : null;
  }

  Future<String> getBaseCurrency() async {
    final rows = await _db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['main_currency'],
      limit: 1,
    );
    return (rows.isEmpty ? 'PKR' : rows.first['setting_value']?.toString() ?? 'PKR')
        .toUpperCase();
  }

  Future<void> setBaseCurrency(String currency) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized.isEmpty) throw Exception('Base currency select karein.');
    if (normalized != 'PKR' && await getExchangeRate(normalized) == null) {
      throw Exception('Is currency ka exchange rate pehle set karein.');
    }
    await _db.insert(
      'app_settings',
      {'setting_key': 'main_currency', 'setting_value': normalized},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppRefreshController.notifyChanged();
  }

  Future<double> getTotalBalanceInBaseCurrency() async {
    final baseCurrency = await getBaseCurrency();
    final baseRate = await getExchangeRate(baseCurrency);
    if (baseRate == null || baseRate <= 0) {
      throw Exception('Base currency ka exchange rate available nahi.');
    }
    final wallets = await _db.query('wallets', where: 'exclude_total = 0');
    double total = 0;
    for (final wallet in wallets) {
      final currency = (wallet['currency'] as String).toUpperCase();
      final balance = (wallet['balance'] as num).toDouble();
      final rate = await getExchangeRate(currency);
      if (rate == null) {
        throw Exception(
          'Exchange rate for $currency is missing. Set or refresh this rate '
          'before viewing the consolidated wallet balance.',
        );
      }
      total += balance * rate / baseRate;
    }
    return total;
  }

  /// Refreshes missing currency rates from the same online provider used by
  /// the Exchange Rates screen. Existing saved rates are left untouched.
  Future<bool> refreshMissingExchangeRatesOnline({
    required List<String> currencies,
  }) async {
    final required = currencies
        .map((code) => code.trim().toUpperCase())
        .where((code) => code.isNotEmpty && code != 'PKR')
        .toSet();
    if (required.isEmpty) return true;

    final missing = <String>[];
    for (final currency in required) {
      if (await getExchangeRate(currency) == null) missing.add(currency);
    }
    if (missing.isEmpty) return true;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client
          .getUrl(Uri.parse('https://open.er-api.com/v6/latest/PKR'))
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) return false;
      final body = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 20));
      final payload = jsonDecode(body) as Map<String, dynamic>;
      if (payload['result'] != 'success') return false;
      final rates = payload['rates'] as Map<String, dynamic>?;
      if (rates == null) return false;

      var savedAny = false;
      for (final currency in missing) {
        final providerRate = rates[currency];
        if (providerRate is! num || providerRate <= 0) continue;
        // Provider returns foreign units per PKR; app stores PKR per unit.
        final pkrPerUnit = 1 / providerRate.toDouble();
        if (!pkrPerUnit.isFinite || pkrPerUnit <= 0) continue;
        await saveExchangeRate(currency, pkrPerUnit, source: 'automatic');
        savedAny = true;
      }
      for (final currency in missing) {
        if (await getExchangeRate(currency) == null) return false;
      }
      return savedAny || missing.isEmpty;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, dynamic>>> getExchangeRates() {
    return _db.query('exchange_rates', orderBy: 'currency COLLATE NOCASE ASC');
  }

  Future<void> saveExchangeRate(
    String currency,
    double rate, {
    String source = 'manual',
  }) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == 'PKR' || normalized.isEmpty ||
        !rate.isFinite || rate <= 0) {
      throw Exception('Exchange rate durust nahi hai.');
    }
    final now = DateTime.now().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert(
        'exchange_rates',
        {
          'currency': normalized,
          'rate': rate,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    AppRefreshController.notifyChanged();
  }

  // ----------------------------------------------------------
  // Wallet update karna
  // ----------------------------------------------------------

  Future<void> updateWallet({
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
    // Refresh missing currency rates before starting the conversion transaction.
    // This prevents wallet currency changes from requiring a manual visit to
    // the Exchange Rates screen. Only missing rates are fetched; saved rates
    // remain unchanged.
    final currentWalletRows = await _db.query(
      'wallets',
      columns: ['currency'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (currentWalletRows.isNotEmpty) {
      final currentCurrency = currentWalletRows.first['currency']
          ?.toString()
          .trim()
          .toUpperCase() ?? '';
      if (currentCurrency != currency) {
        await refreshMissingExchangeRatesOnline(
          currencies: [currentCurrency, currency],
        );
      }
    }

    await _db.transaction((txn) async {
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
        final loanTable = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'loans'",
        );
        if (loanTable.isNotEmpty) {
          final linkedLoans = await txn.query(
            'loans', columns: ['id'], where: 'wallet_id = ?', whereArgs: [id], limit: 1,
          );
          final linkedRepayments = await txn.query(
            'loan_repayments', columns: ['id'], where: 'wallet_id = ?', whereArgs: [id], limit: 1,
          );
          if (linkedLoans.isNotEmpty || linkedRepayments.isNotEmpty) {
            throw Exception('Wallet currency cannot be changed while loans or repayments are linked to it.');
          }
        }
        final assetTable = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'assets'",
        );
        if (assetTable.isNotEmpty) {
          final linkedAssets = await txn.query(
            'assets',
            columns: ['id'],
            where: 'wallet_id = ? OR sale_wallet_id = ?',
            whereArgs: [id, id],
            limit: 1,
          );
          if (linkedAssets.isNotEmpty) {
            throw Exception('Wallet currency cannot be changed while assets are linked to it.');
          }
        }
        final oldRate = await _getRateInTransaction(txn, oldCurrency);
        final newRate = await _getRateInTransaction(txn, currency);

        if (oldRate == null || newRate == null) {
          throw Exception(
            'Currency change karne se pehle dono currencies ke '
            'exchange rates set karein.',
          );
        }

        final factor = oldRate / newRate;

        newOpening = oldOpening * factor;
        convertedOldBalance = oldBalance * factor;

        // Income aur Expense amounts convert.
        await txn.rawUpdate('''
          UPDATE transactions
          SET amount = amount * ?
          WHERE wallet_id = ?
          AND type IN ('Income', 'Expense')
        ''', [factor, id]);

        // Transfer source amounts convert.
        await txn.rawUpdate('''
          UPDATE transactions
          SET amount = amount * ?
          WHERE wallet_id = ?
          AND type = 'Transfer'
        ''', [factor, id]);

        // Source wallet ki currency change hone par linked transfer fees bhi convert.
        final feeTransactions = await txn.query(
          'transactions',
          columns: ['id'],
          where: "wallet_id = ? AND type = 'Transfer'",
          whereArgs: [id],
        );
        for (final transaction in feeTransactions) {
          final transactionId = transaction['id'] as int;
          final feeRows = await txn.query(
            'app_settings',
            columns: ['setting_value'],
            where: 'setting_key = ?',
            whereArgs: ['transaction_transfer_fee_$transactionId'],
            limit: 1,
          );
          if (feeRows.isNotEmpty) {
            final oldFee = double.tryParse(
                  feeRows.first['setting_value']?.toString() ?? '',
                ) ??
                0;
            await txn.update(
              'app_settings',
              {'setting_value': (oldFee * factor).toString()},
              where: 'setting_key = ?',
              whereArgs: ['transaction_transfer_fee_$transactionId'],
            );
          }
        }

        // Transfer destination amounts convert.
        await txn.rawUpdate('''
          UPDATE transactions
          SET to_amount = COALESCE(to_amount, amount) * ?
          WHERE to_wallet_id = ?
          AND type = 'Transfer'
        ''', [factor, id]);

        // Transfer exchange rates dobara calculate.
        await txn.rawUpdate('''
          UPDATE transactions
          SET exchange_rate =
            CASE
              WHEN to_amount IS NULL OR amount = 0 THEN NULL
              ELSE to_amount / amount
            END
          WHERE type = 'Transfer'
          AND (wallet_id = ? OR to_wallet_id = ?)
        ''', [id, id]);

        // Committee transfer ka amount pehle hi source Transfer query mein convert ho chuka hai.
        // Is ka balance_delta bhi convert hona zaroori hai warna committee delete par
        // purana delta wallet balance ko ghalat rollback karega.
        await txn.rawUpdate('''
          UPDATE transactions
          SET balance_delta = balance_delta * ?
          WHERE wallet_id = ?
            AND type = 'Transfer'
            AND category = 'Committee Transfer'
            AND balance_delta IS NOT NULL
        ''', [factor, id]);

        final committeeEntriesTable = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'committee_entries'",
        );
        if (committeeEntriesTable.isNotEmpty) {
          await txn.rawUpdate('''
            UPDATE committee_entries
            SET wallet_amount = wallet_amount * ?,
                wallet_currency = ?
            WHERE wallet_id = ?
          ''', [factor, currency, id]);
        }

        // Recurring transfer schedules ko currency change ke baad same-currency
        // rule todne se bachane ke liye block karein. Income/Expense schedules
        // source wallet ki nayi currency mein convert ho jate hain.
        final recurringTable = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'recurring_transactions'",
        );
        if (recurringTable.isNotEmpty) {
          final linkedRecurringTransfers = await txn.rawQuery('''
            SELECT id FROM recurring_transactions
            WHERE LOWER(type) = 'transfer'
              AND (wallet_id = ? OR to_wallet_id = ?)
            LIMIT 1
          ''', [id, id]);
          if (linkedRecurringTransfers.isNotEmpty) {
            throw Exception(
              'Wallet currency cannot be changed while a recurring transfer is linked. '
              'Update or remove that schedule first.',
            );
          }
          await txn.rawUpdate('''
            UPDATE recurring_transactions
            SET amount = amount * ?,
                transfer_fee = transfer_fee * ?
            WHERE wallet_id = ?
              AND LOWER(type) IN ('income', 'expense')
          ''', [factor, factor, id]);
        }

        // Adjustment amounts convert.
        await txn.rawUpdate('''
          UPDATE transactions
          SET amount = amount * ?,
              balance_delta = balance_delta * ?
          WHERE wallet_id = ?
          AND type = 'Adjustment'
        ''', [factor, factor, id]);
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
        final now = DateTime.now().toIso8601String();

        await txn.insert('transactions', {
          'type': 'Adjustment',
          'amount': difference.abs(),
          'wallet_id': id,
          'to_wallet_id': null,
          'to_amount': null,
          'exchange_rate': null,
          'balance_delta': difference,
          'category': 'Balance Adjustment',
          'note': 'Manual wallet balance adjustment',
          'date': now,
          'created_at': now,
        });
      }
    });
    AppRefreshController.notifyChanged();
  }

  Future<double?> _getRateInTransaction(
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

  Future<void> deleteWallet(int id) async {
    final recurringTable = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'recurring_transactions'",
    );
    if (recurringTable.isNotEmpty) {
      final linkedRecurring = await _db.query(
        'recurring_transactions',
        columns: ['id'],
        where: 'wallet_id = ? OR to_wallet_id = ?',
        whereArgs: [id, id],
        limit: 1,
      );
      if (linkedRecurring.isNotEmpty) {
        throw Exception(
          'This wallet is linked to a recurring transaction. '
          'Update or delete that schedule before deleting the wallet.',
        );
      }
    }

    final linked = await _db.query(
      'transactions',
      columns: ['id'],
      where: 'wallet_id = ? OR to_wallet_id = ?',
      whereArgs: [id, id],
      limit: 1,
    );

    if (linked.isNotEmpty) {
      throw Exception(
        'Is wallet ke saath transactions linked hain. '
        'Pehle un transactions ko manage karein.',
      );
    }

    final loanTable = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'loans'",
    );
    if (loanTable.isNotEmpty) {
      final linkedLoans = await _db.query(
        'loans', columns: ['id'], where: 'wallet_id = ?', whereArgs: [id], limit: 1,
      );
      final linkedRepayments = await _db.query(
        'loan_repayments', columns: ['id'], where: 'wallet_id = ?', whereArgs: [id], limit: 1,
      );
      if (linkedLoans.isNotEmpty || linkedRepayments.isNotEmpty) {
        throw Exception('This wallet is linked to loan records or repayments. Remove or settle those records before deleting the wallet.');
      }
    }

    final assetTable = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'assets'",
    );
    if (assetTable.isNotEmpty) {
      final linkedAssets = await _db.query(
        'assets',
        columns: ['id'],
        where: 'wallet_id = ? OR sale_wallet_id = ?',
        whereArgs: [id, id],
        limit: 1,
      );
      if (linkedAssets.isNotEmpty) {
        throw Exception('This wallet is linked to an asset purchase or sale. Delete or update the asset before deleting the wallet.');
      }
    }

    final walletRows = await _db.query('wallets', where: 'id = ?', whereArgs: [id], limit: 1);
    if (walletRows.isEmpty) return;
    await RecycleBinService.archive(type: 'Wallet', title: walletRows.first['name']?.toString() ?? 'Wallet', table: 'wallets', id: id, record: walletRows.first);
    await _db.delete('wallets', where: 'id = ?', whereArgs: [id]);
    AppRefreshController.notifyChanged();
  }

  // ----------------------------------------------------------
  // Tamam wallets ka majmoi balance
  // ----------------------------------------------------------

}
