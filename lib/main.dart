import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

import 'screens/assets_screen.dart';
import 'screens/loans_screen.dart';
import 'screens/transactions_screen.dart';
import 'screens/more_features_screen.dart';

import 'services/app_startup_service.dart';
import 'services/appearance_settings_service.dart';
import 'services/category_service.dart';
import 'services/transaction_service.dart';

// ============================================================
// APPLICATION START
// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await FinanceDB.instance.init();

  await AppearanceSettingsService.configure(
    getSetting: FinanceDB.instance.getSetting,
    setSetting: FinanceDB.instance.setSetting,
  );

  await AppearanceSettingsService.load();

  await AppStartupService.initialize();

  runApp(const MyFinanceApp());
}

// ============================================================
// DATABASE
// ============================================================

class FinanceDB {
  FinanceDB._();

  static final FinanceDB instance = FinanceDB._();

  Database? _database;

  Database get db {
    if (_database == null || !_database!.isOpen) {
      throw Exception('My Finance database is not initialized.');
    }
    return _database!;
  }

  Future<void> init() async {
    if (_database != null && _database!.isOpen) return;

    final databaseDirectory = await getDatabasesPath();
    final databasePath = p.join(
      databaseDirectory,
      'my_finance.db',
    );

    _database = await openDatabase(
      databasePath,
      version: 4,
      onCreate: (database, version) async {
        await _createTables(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        await _upgradeDatabase(
          database,
          oldVersion,
          newVersion,
        );
      },
    );
  }

  // ----------------------------------------------------------
  // CREATE TABLES
  // ----------------------------------------------------------

  Future<void> _createTables(Database database) async {
    await database.execute('''
      CREATE TABLE wallets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'PKR',
        balance REAL NOT NULL DEFAULT 0,
        exclude_total INTEGER NOT NULL DEFAULT 0,
        wallet_number TEXT,
        icon_code INTEGER
      )
    ''');

    await database.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        wallet_id INTEGER NOT NULL,
        to_wallet_id INTEGER,
        note TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT
      )
    ''');
  }

  // ----------------------------------------------------------
  // DATABASE HELPERS
  // ----------------------------------------------------------

  Future<bool> _tableExists(
    Database database,
    String tableName,
  ) async {
    final result = await database.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = ?
      ''',
      [tableName],
    );

    return result.isNotEmpty;
  }

  Future<List<String>> _getColumns(
    Database database,
    String tableName,
  ) async {
    final result = await database.rawQuery(
      'PRAGMA table_info($tableName)',
    );

    return result
        .map((row) => row['name'].toString())
        .toList();
  }

  // ----------------------------------------------------------
  // MIGRATION
  // Old Accounts data will be transferred to Wallets.
  // ----------------------------------------------------------

  Future<void> _upgradeDatabase(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    await _migrateAccountsToWallets(database);
  }

  Future<void> _migrateAccountsToWallets(
    Database database,
  ) async {
    if (!await _tableExists(database, 'wallets')) {
      await database.execute('''
        CREATE TABLE wallets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          currency TEXT NOT NULL DEFAULT 'PKR',
          balance REAL NOT NULL DEFAULT 0,
          exclude_total INTEGER NOT NULL DEFAULT 0,
          wallet_number TEXT,
          icon_code INTEGER
        )
      ''');
    }

    if (await _tableExists(database, 'accounts')) {
      final columns = await _getColumns(
        database,
        'accounts',
      );

      final accountNumber = columns.contains('account_number')
          ? 'account_number'
          : 'NULL';

      final iconCode = columns.contains('icon_code')
          ? 'icon_code'
          : 'NULL';

      final excludeTotal = columns.contains('exclude_total')
          ? 'exclude_total'
          : '0';

      await database.execute('''
        INSERT OR IGNORE INTO wallets (
          id,
          name,
          type,
          currency,
          balance,
          exclude_total,
          wallet_number,
          icon_code
        )
        SELECT
          id,
          name,
          type,
          currency,
          balance,
          $excludeTotal,
          $accountNumber,
          $iconCode
        FROM accounts
      ''');
    }

    if (await _tableExists(database, 'transactions')) {
      final columns = await _getColumns(
        database,
        'transactions',
      );

      if (!columns.contains('wallet_id')) {
        await database.execute(
          'ALTER TABLE transactions ADD COLUMN wallet_id INTEGER',
        );
      }

      if (!columns.contains('to_wallet_id')) {
        await database.execute(
          'ALTER TABLE transactions ADD COLUMN to_wallet_id INTEGER',
        );
      }

      if (columns.contains('account_id')) {
        await database.execute('''
          UPDATE transactions
          SET wallet_id = account_id
          WHERE wallet_id IS NULL
        ''');
      }

      if (columns.contains('to_account_id')) {
        await database.execute('''
          UPDATE transactions
          SET to_wallet_id = to_account_id
          WHERE to_wallet_id IS NULL
        ''');
      }
    }

    if (!await _tableExists(database, 'app_settings')) {
      await database.execute('''
        CREATE TABLE app_settings (
          setting_key TEXT PRIMARY KEY,
          setting_value TEXT
        )
      ''');
    }
  }

  // ==========================================================
  // APP SETTINGS
  // ==========================================================

  Future<String?> getSetting(String key) async {
    final result = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (result.isEmpty) return null;

    return result.first['setting_value'] as String?;
  }

  Future<void> setSetting(
    String key,
    String value,
  ) async {
    await db.insert(
      'app_settings',
      {
        'setting_key': key,
        'setting_value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==========================================================
  // WALLET FUNCTIONS
  // ==========================================================

  Future<List<Map<String, dynamic>>> getWallets() async {
    return db.query(
      'wallets',
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<Map<String, dynamic>?> getWallet(int walletId) async {
    final result = await db.query(
      'wallets',
      where: 'id = ?',
      whereArgs: [walletId],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  Future<int> addWallet({
    required String name,
    required String type,
    required String currency,
    required double openingBalance,
    String? walletNumber,
    required int iconCode,
    required bool excludeTotal,
  }) async {
    if (name.trim().isEmpty) {
      throw Exception('Wallet name is required.');
    }

    return db.insert(
      'wallets',
      {
        'name': name.trim(),
        'type': type,
        'currency': currency,
        'balance': openingBalance,
        'wallet_number': walletNumber,
        'icon_code': iconCode,
        'exclude_total': excludeTotal ? 1 : 0,
      },
    );
  }

  Future<int> updateWallet({
    required int id,
    required String name,
    required String type,
    String? walletNumber,
    required int iconCode,
    required bool excludeTotal,
  }) async {
    return db.update(
      'wallets',
      {
        'name': name.trim(),
        'type': type,
        'wallet_number': walletNumber,
        'icon_code': iconCode,
        'exclude_total': excludeTotal ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteWallet(int walletId) async {
    final transactions = await db.query(
      'transactions',
      where: 'wallet_id = ? OR to_wallet_id = ?',
      whereArgs: [walletId, walletId],
      limit: 1,
    );

    if (transactions.isNotEmpty) {
      throw Exception(
        'This wallet has transaction history. '
        'You cannot delete it.',
      );
    }

    await db.delete(
      'wallets',
      where: 'id = ?',
      whereArgs: [walletId],
    );
  }

  // ==========================================================
  // TRANSACTION FUNCTIONS
  // ==========================================================

  Future<List<Map<String, dynamic>>> getTransactions() async {
    return db.query(
      'transactions',
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<int> addTransaction({
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    required String note,
    DateTime? date,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }

    final sourceWallet = await getWallet(walletId);

    if (sourceWallet == null) {
      throw Exception('Selected wallet was not found.');
    }

    final transactionDate =
        (date ?? DateTime.now()).toIso8601String();

    return db.transaction((txn) async {
      final sourceBalance =
          (sourceWallet['balance'] as num).toDouble();

      if (type == 'Expense') {
        if (sourceBalance < amount) {
          throw Exception('Insufficient wallet balance.');
        }

        await txn.update(
          'wallets',
          {'balance': sourceBalance - amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      } else if (type == 'Income') {
        await txn.update(
          'wallets',
          {'balance': sourceBalance + amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      } else if (type == 'Transfer') {
        if (toWalletId == null || toWalletId == walletId) {
          throw Exception('Please select a different destination wallet.');
        }

        final destinationResult = await txn.query(
          'wallets',
          where: 'id = ?',
          whereArgs: [toWalletId],
          limit: 1,
        );

        if (destinationResult.isEmpty) {
          throw Exception('Destination wallet was not found.');
        }

        final destinationWallet = destinationResult.first;

        if (sourceWallet['currency'] !=
            destinationWallet['currency']) {
          throw Exception(
            'Different-currency transfers require an exchange rate.',
          );
        }

        if (sourceBalance < amount) {
          throw Exception('Insufficient wallet balance.');
        }

        final destinationBalance =
            (destinationWallet['balance'] as num).toDouble();

        await txn.update(
          'wallets',
          {'balance': sourceBalance - amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );

        await txn.update(
          'wallets',
          {'balance': destinationBalance + amount},
          where: 'id = ?',
          whereArgs: [toWalletId],
        );
      } else {
        throw Exception('Invalid transaction type.');
      }

      return txn.insert(
        'transactions',
        {
          'type': type,
          'amount': amount,
          'wallet_id': walletId,
          'to_wallet_id': toWalletId,
          'note': note,
          'date': transactionDate,
        },
      );
    });
  }

  // ==========================================================
  // DASHBOARD SUMMARY
  // ==========================================================

  Future<List<Map<String, dynamic>>> dashboardSummary() async {
    final walletTotals = await db.rawQuery('''
      SELECT
        currency,
        SUM(balance) AS total_balance
      FROM wallets
      WHERE exclude_total = 0
      GROUP BY currency
      ORDER BY currency
    ''');

    final incomeTotals = await db.rawQuery('''
      SELECT
        w.currency,
        SUM(t.amount) AS total_income
      FROM transactions t
      INNER JOIN wallets w ON w.id = t.wallet_id
      WHERE t.type = 'Income'
      GROUP BY w.currency
    ''');

    final expenseTotals = await db.rawQuery('''
      SELECT
        w.currency,
        SUM(t.amount) AS total_expense
      FROM transactions t
      INNER JOIN wallets w ON w.id = t.wallet_id
      WHERE t.type = 'Expense'
      GROUP BY w.currency
    ''');

    final currencies = <String>{};

    for (final row in walletTotals) {
      currencies.add(row['currency'].toString());
    }

    for (final row in incomeTotals) {
      currencies.add(row['currency'].toString());
    }

    for (final row in expenseTotals) {
      currencies.add(row['currency'].toString());
    }

    return currencies.map((currency) {
      final wallet = walletTotals.firstWhere(
        (row) => row['currency'] == currency,
        orElse: () => {'total_balance': 0},
      );

      final income = incomeTotals.firstWhere(
        (row) => row['currency'] == currency,
        orElse: () => {'total_income': 0},
      );

      final expense = expenseTotals.firstWhere(
        (row) => row['currency'] == currency,
        orElse: () => {'total_expense': 0},
      );

      return {
        'currency': currency,
        'balance': wallet['total_balance'] ?? 0,
        'income': income['total_income'] ?? 0,
        'expense': expense['total_expense'] ?? 0,
      };
    }).toList();
  }

  Future<double> totalBalance() async {
    final result = await db.rawQuery('''
      SELECT SUM(balance) AS total
      FROM wallets
      WHERE exclude_total = 0 AND currency = 'PKR'
    ''');

    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> totalByType(String type) async {
    final result = await db.rawQuery(
      '''
      SELECT SUM(amount) AS total
      FROM transactions
      WHERE type = ?
      ''',
      [type],
    );

    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  // ==========================================================
  // DATABASE CLOSE / REOPEN
  // ==========================================================

  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
    }

    _database = null;
  }

  Future<void> reopen() async {
    await close();
    await init();
  }
}
// ============================================================
// MY FINANCE APPLICATION
// ============================================================

class MyFinanceApp extends StatelessWidget {
  const MyFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppearanceSettingsService.themeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'My Finance',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF147D59),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor:
                const Color(0xFFF5F7F6),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF5F7F6),
              elevation: 0,
              centerTitle: false,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF147D59),
              brightness: Brightness.dark,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          home: const MainScreen(),
        );
      },
    );
  }
}

// ============================================================
// MAIN SCREEN AND NAVIGATION
// ============================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;

  void refreshScreen() {
    if (mounted) {
      setState(() {});
    }
  }

  final List<String> pageTitles = const [
    'Home',
    'Assets',
    'Loans',
    'Transactions',
    'Wallets',
  ];

  Future<void> showPlusMenu() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Create New',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _plusOption(
                        icon: Icons.trending_up_rounded,
                        title: 'Income',
                        color: Colors.green,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showTransactionDialog(
                            context,
                            initialType: 'Income',
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _plusOption(
                        icon: Icons.trending_down_rounded,
                        title: 'Expense',
                        color: Colors.red,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showTransactionDialog(
                            context,
                            initialType: 'Expense',
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _plusOption(
                        icon: Icons.swap_horiz_rounded,
                        title: 'Transfer',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showTransactionDialog(
                            context,
                            initialType: 'Transfer',
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _plusOption(
                        icon: Icons.account_balance_wallet_rounded,
                        title: 'Wallet',
                        color: Colors.deepPurple,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          showWalletDialog(context);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    refreshScreen();
  }

  Widget _plusOption({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: color.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> get pages => [
        DashboardPage(
          onRefresh: refreshScreen,
        ),
        const AssetsScreen(),
        const LoansScreen(),
        const TransactionsScreen(),
        WalletsPage(
          onRefresh: refreshScreen,
        ),
      ];

  Future<void> openMoreFeatures() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MoreFeaturesScreen(),
      ),
    );

    refreshScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          pageTitles[selectedIndex],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            onPressed: openMoreFeatures,
            tooltip: 'More Features and Settings',
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: selectedIndex,
        children: pages,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showPlusMenu,
        backgroundColor:
            Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.diamond_outlined),
            selectedIcon: Icon(Icons.diamond_rounded),
            label: 'Assets',
          ),
          NavigationDestination(
            icon: Icon(Icons.handshake_outlined),
            selectedIcon: Icon(Icons.handshake_rounded),
            label: 'Loans',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon:
                Icon(Icons.account_balance_wallet_rounded),
            label: 'Wallets',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// HOME DASHBOARD
// ============================================================

class DashboardPage extends StatefulWidget {
  final VoidCallback onRefresh;

  const DashboardPage({
    super.key,
    required this.onRefresh,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, dynamic>> summaries = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    try {
      final data =
          await FinanceDB.instance.dashboardSummary();

      if (!mounted) return;

      setState(() {
        summaries = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  String money(dynamic value, String currency) {
    final amount = value is num ? value.toDouble() : 0.0;

    return '$currency ${NumberFormat('#,##0.00').format(amount)}';
  }

  Widget overviewCard({
    required String title,
    required String amount,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget balanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF147D59),
            Color(0xFF07543C),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white70,
              ),
              SizedBox(width: 9),
              Text(
                'My Wallet Overview',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Your balances by currency',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          if (summaries.isEmpty)
            const Text(
              'No wallet balance available',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            )
          else
            ...summaries.map((summary) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    Text(
                      summary['currency'].toString(),
                      style: const TextStyle(
                        color: Colors.white70,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      money(
                        summary['balance'],
                        summary['currency'].toString(),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const Divider(color: Colors.white24, height: 24),
          const Text(
            'Excluded wallets are not included in this overview.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget currencyOverview(Map<String, dynamic> summary) {
    final currency = summary['currency'].toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currency,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              overviewCard(
                title: 'Income',
                amount: money(summary['income'], currency),
                icon: Icons.trending_up_rounded,
                color: Colors.green,
              ),
              const SizedBox(width: 10),
              overviewCard(
                title: 'Expenses',
                amount: money(summary['expense'], currency),
                icon: Icons.trending_down_rounded,
                color: Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: loadDashboard,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Welcome Back!',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Here is your financial overview.',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            balanceCard(),
            const SizedBox(height: 25),
            const Text(
              'Income & Expense Overview',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 13),
            if (summaries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'Add a wallet to start managing your finances.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ...summaries.map(currencyOverview),
          ],
          const SizedBox(height: 25),
        ],
      ),
    );
  }
}

// ============================================================
// WALLETS SCREEN
// ============================================================

class WalletsPage extends StatefulWidget {
  final VoidCallback onRefresh;

  const WalletsPage({
    super.key,
    required this.onRefresh,
  });

  @override
  State<WalletsPage> createState() => _WalletsPageState();
}

class _WalletsPageState extends State<WalletsPage> {
  List<Map<String, dynamic>> wallets = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadWallets();
  }

  Future<void> loadWallets() async {
    try {
      final result = await FinanceDB.instance.getWallets();

      if (!mounted) return;

      setState(() {
        wallets = result;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  String formatBalance(dynamic value, String currency) {
    final amount = value is num ? value.toDouble() : 0.0;

    return '$currency ${NumberFormat('#,##0.00').format(amount)}';
  }

  IconData walletIcon(dynamic code) {
    if (code is int) {
      return IconData(
        code,
        fontFamily: 'MaterialIcons',
      );
    }

    return Icons.account_balance_wallet_rounded;
  }

  Future<void> addWallet() async {
    await showWalletDialog(context);
    await loadWallets();
    widget.onRefresh();
  }

  Future<void> deleteWallet(Map<String, dynamic> wallet) async {
    final id = wallet['id'] as int;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Wallet?'),
          content: Text(
            'Are you sure you want to delete "${wallet['name']}"?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await FinanceDB.instance.deleteWallet(id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wallet deleted successfully.'),
        ),
      );

      await loadWallets();
      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Widget walletCard(Map<String, dynamic> wallet) {
    final currency = wallet['currency'].toString();
    final balance = wallet['balance'];
    final excluded = wallet['exclude_total'] == 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 13),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                walletIcon(wallet['icon_code']),
                color: Theme.of(context)
                    .colorScheme
                    .primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wallet['name'].toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    wallet['type'].toString(),
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    formatBalance(balance, currency),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (excluded)
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Text(
                        'Excluded from Total Balance',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  deleteWallet(wallet);
                } else if (value == 'edit') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Wallet editing will be connected in Part 3.',
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit Wallet'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete Wallet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: loadWallets,
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : wallets.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 100),
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 65,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 18),
                      Center(
                        child: Text(
                          'No Wallets Yet',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Create your first wallet to get started.',
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: wallets.length,
                    itemBuilder: (context, index) {
                      return walletCard(wallets[index]);
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addWallet,
        icon: const Icon(Icons.add),
        label: const Text('Add Wallet'),
      ),
    );
  }
}
// ============================================================
// PLUS FORM
// INCOME / EXPENSE / TRANSFER / WALLET
// ============================================================

Future<void> showTransactionDialog(
  BuildContext context, {
  String initialType = 'Income',
}) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlusFormScreen(
        initialType: initialType,
      ),
    ),
  );
}

// ============================================================
// WALLET DIALOG
// ============================================================

Future<void> showWalletDialog(
  BuildContext context, {
  Map<String, dynamic>? wallet,
}) async {
  await showDialog(
    context: context,
    builder: (_) => WalletFormDialog(
      wallet: wallet,
    ),
  );
}

// ============================================================
// PLUS FORM SCREEN
// ============================================================

class PlusFormScreen extends StatefulWidget {
  final String initialType;

  const PlusFormScreen({
    super.key,
    required this.initialType,
  });

  @override
  State<PlusFormScreen> createState() => _PlusFormScreenState();
}

class _PlusFormScreenState extends State<PlusFormScreen>
    with SingleTickerProviderStateMixin {
  late TabController tabController;

  final List<String> tabs = [
    'Income',
    'Expense',
    'Transfer',
    'Wallet',
  ];

  @override
  void initState() {
    super.initState();

    final initialIndex = tabs.indexOf(widget.initialType);

    tabController = TabController(
      length: tabs.length,
      vsync: this,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    );
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create New',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: tabController,
          isScrollable: true,
          tabs: const [
            Tab(
              icon: Icon(Icons.trending_up_rounded),
              text: 'Income',
            ),
            Tab(
              icon: Icon(Icons.trending_down_rounded),
              text: 'Expense',
            ),
            Tab(
              icon: Icon(Icons.swap_horiz_rounded),
              text: 'Transfer',
            ),
            Tab(
              icon: Icon(Icons.account_balance_wallet_rounded),
              text: 'Wallet',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: const [
          TransactionEntryForm(type: 'Income'),
          TransactionEntryForm(type: 'Expense'),
          TransactionEntryForm(type: 'Transfer'),
          WalletEntryForm(),
        ],
      ),
    );
  }
}

// ============================================================
// TRANSACTION ENTRY FORM
// ============================================================

class TransactionEntryForm extends StatefulWidget {
  final String type;

  const TransactionEntryForm({
    super.key,
    required this.type,
  });

  @override
  State<TransactionEntryForm> createState() =>
      _TransactionEntryFormState();
}

class _TransactionEntryFormState
    extends State<TransactionEntryForm> {
  final amountController = TextEditingController();
  final noteController = TextEditingController();

  List<Map<String, dynamic>> wallets = [];

  int? selectedWalletId;
  int? destinationWalletId;

  DateTime selectedDate = DateTime.now();

  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    loadWallets();
  }

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> loadWallets() async {
    try {
      final result = await FinanceDB.instance.getWallets();

      if (!mounted) return;

      setState(() {
        wallets = result;

        if (wallets.isNotEmpty) {
          selectedWalletId ??= wallets.first['id'] as int;
        }
      });
    } catch (_) {}
  }

  double get amount {
    return double.tryParse(
          amountController.text.trim().replaceAll(',', ''),
        ) ??
        0;
  }

  String get selectedCurrency {
    final wallet = wallets.where(
      (item) => item['id'] == selectedWalletId,
    );

    if (wallet.isEmpty) return 'PKR';

    return wallet.first['currency'].toString();
  }

  Future<void> selectDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (result != null) {
      setState(() {
        selectedDate = result;
      });
    }
  }

  Future<void> saveTransaction() async {
    if (isSaving) return;

    if (wallets.isEmpty) {
      showMessage('Please create a wallet first.');
      return;
    }

    if (selectedWalletId == null) {
      showMessage('Please select a wallet.');
      return;
    }

    if (amount <= 0) {
      showMessage('Please enter a valid amount.');
      return;
    }

    if (widget.type == 'Transfer') {
      if (destinationWalletId == null) {
        showMessage('Please select destination wallet.');
        return;
      }

      if (destinationWalletId == selectedWalletId) {
        showMessage('Source and destination wallets must be different.');
        return;
      }
    }

    setState(() {
      isSaving = true;
    });

    try {
      await FinanceDB.instance.addTransaction(
        type: widget.type,
        amount: amount,
        walletId: selectedWalletId!,
        toWalletId: widget.type == 'Transfer'
            ? destinationWalletId
            : null,
        note: noteController.text.trim(),
        date: selectedDate,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.type} saved successfully.'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  InputDecoration inputDecoration(
    String label,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
      ),
    );
  }

  Widget walletDropdown({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
    int? excludedWalletId,
  }) {
    final availableWallets = wallets.where(
      (wallet) => wallet['id'] != excludedWalletId,
    ).toList();

    return DropdownButtonFormField<int>(
      value: availableWallets.any(
        (wallet) => wallet['id'] == value,
      )
          ? value
          : null,
      decoration: inputDecoration(
        label,
        Icons.account_balance_wallet_outlined,
      ),
      items: availableWallets.map((wallet) {
        return DropdownMenuItem<int>(
          value: wallet['id'] as int,
          child: Text(
            '${wallet['name']} (${wallet['currency']})',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTransfer = widget.type == 'Transfer';

    final color = widget.type == 'Income'
        ? Colors.green
        : widget.type == 'Expense'
            ? Colors.red
            : Colors.blue;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                  isTransfer
                      ? Icons.swap_horiz_rounded
                      : widget.type == 'Income'
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                  color: color,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Text(
                  'Add ${widget.type}',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: inputDecoration(
              'Amount ($selectedCurrency)',
              Icons.payments_outlined,
            ),
          ),

          const SizedBox(height: 18),

          walletDropdown(
            label: isTransfer ? 'From Wallet' : 'Wallet',
            value: selectedWalletId,
            onChanged: (value) {
              setState(() {
                selectedWalletId = value;
              });
            },
          ),

          if (isTransfer) ...[
            const SizedBox(height: 18),
            walletDropdown(
              label: 'To Wallet',
              value: destinationWalletId,
              excludedWalletId: selectedWalletId,
              onChanged: (value) {
                setState(() {
                  destinationWalletId = value;
                });
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Transfers between different currencies require an exchange rate. This basic form currently supports same-currency transfers only.',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 18),

          TextField(
            controller: noteController,
            maxLines: 3,
            decoration: inputDecoration(
              'Note (Optional)',
              Icons.notes_rounded,
            ),
          ),

          const SizedBox(height: 18),

          InkWell(
            onTap: selectDate,
            borderRadius: BorderRadius.circular(15),
            child: InputDecorator(
              decoration: inputDecoration(
                'Transaction Date',
                Icons.calendar_month_rounded,
              ),
              child: Text(
                DateFormat('dd MMM yyyy').format(selectedDate),
              ),
            ),
          ),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: isSaving ? null : saveTransaction,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                isSaving ? 'Saving...' : 'Save ${widget.type}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WALLET ENTRY FORM
// ============================================================

class WalletEntryForm extends StatelessWidget {
  const WalletEntryForm({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: WalletFormFields(),
    );
  }
}

// ============================================================
// WALLET FORM DIALOG
// ============================================================

class WalletFormDialog extends StatelessWidget {
  final Map<String, dynamic>? wallet;

  const WalletFormDialog({
    super.key,
    this.wallet,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            wallet == null ? 'Add Wallet' : 'Edit Wallet',
          ),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: WalletFormFields(wallet: wallet),
        ),
      ),
    );
  }
}

// ============================================================
// WALLET FORM FIELDS
// ============================================================

class WalletFormFields extends StatefulWidget {
  final Map<String, dynamic>? wallet;

  const WalletFormFields({
    super.key,
    this.wallet,
  });

  @override
  State<WalletFormFields> createState() =>
      _WalletFormFieldsState();
}

class _WalletFormFieldsState extends State<WalletFormFields> {
  final nameController = TextEditingController();
  final customTypeController = TextEditingController();
  final numberController = TextEditingController();
  final balanceController = TextEditingController();

  final List<String> walletTypes = [
    'Cash',
    'Bank',
    'Savings',
    'Current',
    'Credit Card',
    'Debit Card',
    'Digital Wallet',
    'Investment',
    'Other',
  ];

  final List<String> currencies = [
    'PKR',
    'USD',
    'GBP',
    'EUR',
    'AED',
    'SAR',
  ];

  final List<IconData> availableIcons = [
    Icons.account_balance_wallet_rounded,
    Icons.account_balance_rounded,
    Icons.savings_rounded,
    Icons.credit_card_rounded,
    Icons.payments_rounded,
    Icons.phone_android_rounded,
    Icons.trending_up_rounded,
    Icons.money_rounded,
    Icons.home_work_rounded,
    Icons.business_rounded,
    Icons.currency_exchange_rounded,
    Icons.wallet_rounded,
  ];

  String selectedType = 'Cash';
  String selectedCurrency = 'PKR';

  int selectedIconCode =
      Icons.account_balance_wallet_rounded.codePoint;

  bool excludeTotal = false;
  bool isSaving = false;

  bool get isEditing => widget.wallet != null;

  @override
  void initState() {
    super.initState();

    final wallet = widget.wallet;

    if (wallet != null) {
      nameController.text = wallet['name']?.toString() ?? '';

      selectedType = wallet['type']?.toString() ?? 'Cash';

      if (!walletTypes.contains(selectedType)) {
        selectedType = 'Other';
        customTypeController.text =
            wallet['type']?.toString() ?? '';
      }

      selectedCurrency =
          wallet['currency']?.toString() ?? 'PKR';

      if (!currencies.contains(selectedCurrency)) {
        selectedCurrency = 'PKR';
      }

      numberController.text =
          wallet['wallet_number']?.toString() ?? '';

      balanceController.text =
          wallet['balance']?.toString() ?? '0';

      selectedIconCode =
          wallet['icon_code'] as int? ??
          Icons.account_balance_wallet_rounded.codePoint;

      excludeTotal = wallet['exclude_total'] == 1;
    } else {
      balanceController.text = '0';
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    customTypeController.dispose();
    numberController.dispose();
    balanceController.dispose();
    super.dispose();
  }

  Future<void> saveWallet() async {
    if (isSaving) return;

    final name = nameController.text.trim();

    final type = selectedType == 'Other'
        ? customTypeController.text.trim()
        : selectedType;

    final openingBalance =
        double.tryParse(balanceController.text.trim()) ?? 0;

    if (name.isEmpty) {
      showMessage('Please enter wallet name.');
      return;
    }

    if (type.isEmpty) {
      showMessage('Please enter wallet type.');
      return;
    }

    if (!isEditing && openingBalance < 0) {
      showMessage('Opening balance cannot be negative.');
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      if (isEditing) {
        await FinanceDB.instance.updateWallet(
          id: widget.wallet!['id'] as int,
          name: name,
          type: type,
          walletNumber: numberController.text.trim(),
          iconCode: selectedIconCode,
          excludeTotal: excludeTotal,
        );
      } else {
        await FinanceDB.instance.addWallet(
          name: name,
          type: type,
          currency: selectedCurrency,
          openingBalance: openingBalance,
          walletNumber: numberController.text.trim(),
          iconCode: selectedIconCode,
          excludeTotal: excludeTotal,
        );
      }

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Wallet updated successfully.'
                : 'Wallet created successfully.',
          ),
        ),
      );
    } catch (e) {
      showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  InputDecoration decoration(
    String label,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
      ),
    );
  }

  Future<void> chooseIcon() async {
    final result = await showModalBottomSheet<IconData>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 15,
            crossAxisSpacing: 15,
          ),
          itemCount: availableIcons.length,
          itemBuilder: (context, index) {
            final icon = availableIcons[index];

            return InkWell(
              onTap: () => Navigator.pop(sheetContext, icon),
              borderRadius: BorderRadius.circular(15),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: Theme.of(context)
                      .colorScheme
                      .primary,
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        selectedIconCode = result.codePoint;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: InkWell(
            onTap: chooseIcon,
            borderRadius: BorderRadius.circular(25),
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(
                IconData(
                  selectedIconCode,
                  fontFamily: 'MaterialIcons',
                ),
                size: 42,
                color: Theme.of(context)
                    .colorScheme
                    .primary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        const Center(
          child: Text(
            'Tap to choose wallet icon',
            style: TextStyle(fontSize: 12),
          ),
        ),

        const SizedBox(height: 25),

        TextField(
          controller: nameController,
          decoration: decoration(
            'Wallet Name',
            Icons.account_balance_wallet_outlined,
          ),
        ),

        const SizedBox(height: 18),

        DropdownButtonFormField<String>(
          value: selectedType,
          decoration: decoration(
            'Wallet Type',
            Icons.category_outlined,
          ),
          items: walletTypes.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(type),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                selectedType = value;
              });
            }
          },
        ),

        if (selectedType == 'Other') ...[
          const SizedBox(height: 18),
          TextField(
            controller: customTypeController,
            decoration: decoration(
              'Custom Wallet Type',
              Icons.edit_outlined,
            ),
          ),
        ],

        const SizedBox(height: 18),

        DropdownButtonFormField<String>(
          value: selectedCurrency,
          decoration: decoration(
            'Currency',
            Icons.currency_exchange_rounded,
          ),
          items: currencies.map((currency) {
            return DropdownMenuItem(
              value: currency,
              child: Text(currency),
            );
          }).toList(),
          onChanged: isEditing
              ? null
              : (value) {
                  if (value != null) {
                    setState(() {
                      selectedCurrency = value;
                    });
                  }
                },
        ),

        const SizedBox(height: 18),

        TextField(
          controller: numberController,
          decoration: decoration(
            'Wallet Number (Optional)',
            Icons.numbers_rounded,
          ),
        ),

        const SizedBox(height: 18),

        if (!isEditing)
          TextField(
            controller: balanceController,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: decoration(
              'Opening Balance',
              Icons.payments_outlined,
            ),
          ),

        if (!isEditing) const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: Theme.of(context).cardColor,
            border: Border.all(
              color: Theme.of(context).dividerColor,
            ),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Exclude from Total Balance',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Keep this wallet visible but exclude it from the combined total.',
              style: TextStyle(fontSize: 11),
            ),
            value: excludeTotal,
            onChanged: (value) {
              setState(() {
                excludeTotal = value;
              });
            },
          ),
        ),

        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: isSaving ? null : saveWallet,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(
              isSaving
                  ? 'Saving...'
                  : isEditing
                      ? 'Update Wallet'
                      : 'Create Wallet',
            ),
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }
}
