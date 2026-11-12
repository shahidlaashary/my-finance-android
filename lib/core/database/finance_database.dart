import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'package:my_finance/core/services/app_refresh_service.dart';

/// Central SQLite database for the My Finance application.
///
/// Keep the existing schema and database version unchanged unless a
/// separately reviewed feature requires a deliberate schema update.
class FinanceDB {
  FinanceDB._();

  static final FinanceDB instance = FinanceDB._();

  Database? _database;

  Future<void> init() async {
    if (_database != null) return;

    final databasePath = await getDatabasesPath();
    final fullPath = p.join(databasePath, 'my_finance.db');

    // Fresh database: koi migration ya old-data conversion nahi.
    _database = await openDatabase(
      fullPath,
      version: 2,
      onCreate: _createDatabase,
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createExchangeRateHistoryTable(database);
          await database.execute('''
            INSERT INTO exchange_rate_history (currency, rate, recorded_at, source)
            SELECT currency, rate, updated_at, 'migration'
            FROM exchange_rates
          ''');
        }
      },
    );
  }

  Database get db {
    if (_database == null) {
      throw StateError('Database initialize nahi hua.');
    }
    return _database!;
  }

  // Database band karke restore ke baad dobara kholne ke liye.
  Future<void> close() async {
    final currentDatabase = _database;
    _database = null;
    if (currentDatabase != null && currentDatabase.isOpen) {
      await currentDatabase.close();
    }
  }

  // Restore ke baad naya database connection shuru karta hai.
  Future<void> reopen() async {
    await init();
  }

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

    await _createExchangeRateHistoryTable(db);

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

  Future<void> _createExchangeRateHistoryTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS exchange_rate_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        currency TEXT NOT NULL,
        rate REAL NOT NULL,
        recorded_at TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual'
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS idx_exchange_rate_history_currency_date
      ON exchange_rate_history(currency, recorded_at DESC)
    ''');
  }

  // ----------------------------------------------------------
  // Wallet database ke functions
  // ----------------------------------------------------------

  Future<List<Map<String, dynamic>>> getWallets() {
    return db.query(
      'wallets',
      orderBy: 'name COLLATE NOCASE ASC',
    );
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
    final rows = await db.query(
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
    await db.insert(
      'app_settings',
      {
        'setting_key': key,
        'setting_value': jsonEncode(categories),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppRefreshController.notifyChanged();
  }

  Future<Map<String, dynamic>?> getWallet(int id) async {
    final rows = await db.query(
      'wallets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
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
  }) async {
    final id = await db.insert('wallets', {
      'name': name.trim(),
      'type': type,
      'custom_type': customType,
      'currency': currency,
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

  // ----------------------------------------------------------
  // Currency rate ke functions
  // ----------------------------------------------------------

  Future<double?> getExchangeRate(String currency) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == 'PKR') return 1.0;
    final rows = await db.query(
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

  Future<List<Map<String, dynamic>>> getExchangeRates() {
    return db.query('exchange_rates', orderBy: 'currency COLLATE NOCASE ASC');
  }

  Future<List<Map<String, dynamic>>> getExchangeRateHistory({
    String? currency,
    int limit = 100,
  }) {
    return db.query(
      'exchange_rate_history',
      where: currency == null ? null : 'UPPER(currency) = ?',
      whereArgs: currency == null ? null : [currency.toUpperCase()],
      orderBy: 'recorded_at DESC, id DESC',
      limit: limit,
    );
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
    await db.transaction((txn) async {
      await txn.insert(
        'exchange_rates',
        {
          'currency': normalized,
          'rate': rate,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('exchange_rate_history', {
        'currency': normalized,
        'rate': rate,
        'recorded_at': now,
        'source': source,
      });
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
    await db.transaction((txn) async {
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
      final oldCurrency = oldWallet['currency'] as String;
      final oldBalance = (oldWallet['balance'] as num).toDouble();
      final oldOpening =
          (oldWallet['opening_balance'] as num).toDouble();

      double newOpening = oldOpening;
      double convertedOldBalance = oldBalance;

      // Currency badalne par linked history convert karna.
      if (oldCurrency != currency) {
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
          'name': name.trim(),
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
    if (currency == 'PKR') return 1.0;

    final rows = await txn.query(
      'exchange_rates',
      columns: ['rate'],
      where: 'currency = ?',
      whereArgs: [currency],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final rate = (rows.first['rate'] as num).toDouble();
    return rate > 0 ? rate : null;
  }

  // ----------------------------------------------------------
  // Wallet delete karna
  // ----------------------------------------------------------

  Future<void> deleteWallet(int id) async {
    final linked = await db.query(
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

    await db.delete(
      'wallets',
      where: 'id = ?',
      whereArgs: [id],
    );
    AppRefreshController.notifyChanged();
  }

  // ----------------------------------------------------------
  // Tamam wallets ka majmoi balance
  // ----------------------------------------------------------

  Future<double> getTotalBalancePKR() async {
    final wallets = await db.query(
      'wallets',
      where: 'exclude_total = 0',
    );

    double total = 0;

    for (final wallet in wallets) {
      final currency = wallet['currency'] as String;
      final balance = (wallet['balance'] as num).toDouble();
      final rate = await getExchangeRate(currency);

      // Unknown exchange rate ko 1 assume nahi karna.
      if (rate != null) {
        total += balance * rate;
      }
    }

    return total;
  }

  // Income aur Expense ka total.
  // Adjustment aur Transfer ko is total mein shamil nahi karna.
  Future<double> totalByType(String type) async {
    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM transactions
      WHERE type = ?
      ''',
      [type],
    );

    return (result.first['total'] as num).toDouble();
  }
}
