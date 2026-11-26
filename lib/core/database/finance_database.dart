import 'package:sqflite/sqflite.dart';

import 'package:my_finance/core/database/database_manager.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';
import 'package:my_finance/modules/finance/services/category_service.dart';
import 'package:my_finance/modules/finance/services/currency_service.dart';

/// My Finance app ka central SQLite schema aur compatibility facade.
///
/// Fresh install par version 1 ka mukammal finance database schema banata hai.
class FinanceDB {
  FinanceDB._();

  static final FinanceDB instance = FinanceDB._();

  /// Shared finance connection initialize karta hai. Fresh-install schema
  /// FinanceDB ke paas rehta hai aur DatabaseManager aik connection manage karta hai.
  Future<void> init() async {
    await DatabaseManager.instance.initialize(onCreate: _createDatabase);
  }

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

    // Har currency ke aik unit ki selected app Base Currency mein qeemat.
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

    // Property Manager module ka schema bhi isi shared database mein rehta hai.
    await db.execute('''
      CREATE TABLE properties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'House',
        address TEXT NOT NULL DEFAULT '',
        ownership TEXT NOT NULL DEFAULT 'Owned',
        area TEXT NOT NULL DEFAULT '',
        purchase_price REAL NOT NULL DEFAULT 0,
        purchase_date TEXT NOT NULL DEFAULT '',
        current_value REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'Active',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE property_tenants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        identity_number TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE property_contracts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        property_id INTEGER NOT NULL,
        tenant_id INTEGER NOT NULL,
        contract_type TEXT NOT NULL DEFAULT 'Rental',
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL DEFAULT '',
        rent REAL NOT NULL DEFAULT 0,
        frequency TEXT NOT NULL DEFAULT 'Monthly',
        deposit REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'Draft',
        notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE property_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        property_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        mime_type TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_property_contracts_property ON property_contracts(property_id)');
    await db.execute('CREATE INDEX idx_property_contracts_tenant ON property_contracts(tenant_id)');
    await db.execute('CREATE INDEX idx_property_documents_property ON property_documents(property_id)');
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

  /// Compatibility facade: category persistence belongs to CategoryService.
  Future<List<Map<String, dynamic>>> getCategories(String type) {
    return CategoryService.getCategoryMaps(type);
  }

  Future<void> saveCategories(
    String type,
    List<Map<String, dynamic>> categories,
  ) {
    return CategoryService.saveCategoryMaps(type, categories);
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

  // Currency operations CurrencyService own karta hai. Ye forwarding methods
  // purane callers ke liye compatibility facade ke taur par mojood hain.
  Future<double?> getExchangeRate(String currency) =>
      CurrencyService.getExchangeRate(currency);

  Future<String> getBaseCurrency() => CurrencyService.getBaseCurrency();

  Future<void> setBaseCurrency(String currency) =>
      CurrencyService.setBaseCurrency(currency);

  Future<double> getTotalBalanceInBaseCurrency() =>
      CurrencyService.getTotalBalanceInBaseCurrency();

  Future<bool> refreshMissingExchangeRatesOnline({
    required List<String> currencies,
  }) =>
      CurrencyService.refreshMissingExchangeRatesOnline(
        currencies: currencies,
      );

  Future<List<Map<String, dynamic>>> getExchangeRates() =>
      CurrencyService.getExchangeRates();

  Future<void> saveExchangeRate(
    String currency,
    double rate, {
    String source = 'manual',
  }) =>
      CurrencyService.saveExchangeRate(currency, rate, source: source);

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
  }) {
    return WalletService.updateWallet(
      id: id,
      name: name,
      type: type,
      customType: customType,
      currency: currency,
      requestedCurrentBalance: requestedCurrentBalance,
      walletNumber: walletNumber,
      iconCode: iconCode,
      excludeTotal: excludeTotal,
    );
  }

  Future<void> deleteWallet(int id) => WalletService.deleteWallet(id);

  // ----------------------------------------------------------
  // Tamam wallets ka majmoi balance
  // ----------------------------------------------------------

}
