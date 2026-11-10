
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await FinanceDB.instance.init();

  runApp(const MyFinanceApp());
}

// ------------------------------------------------------------
// APP COLORS
// ------------------------------------------------------------

class AppColors {
  static const primary = Color(0xFF147D59);
  static const background = Color(0xFFF5F7F6);
  static const dark = Color(0xFF17231F);
  static const muted = Color(0xFF7B8983);
  static const income = Color(0xFF16865D);
  static const expense = Color(0xFFE05252);
}

// ------------------------------------------------------------
// DATABASE
// ------------------------------------------------------------

class FinanceDB {
  FinanceDB._();

  static final FinanceDB instance = FinanceDB._();

  Database? _db;

  Database get db {
    if (_db == null) {
      throw Exception('Database is not initialized');
    }
    return _db!;
  }

  Future<void> init() async {
    if (_db != null) return;

    final directory = await getDatabasesPath();
    final path = p.join(directory, 'my_finance.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE wallets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            custom_type TEXT,
            currency TEXT NOT NULL DEFAULT 'PKR',
            balance REAL NOT NULL DEFAULT 0,
            wallet_number TEXT,
            icon_code INTEGER NOT NULL DEFAULT 57680,
            exclude_total INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            wallet_id INTEGER NOT NULL,
            to_wallet_id INTEGER,
            category TEXT,
            note TEXT,
            date TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(wallet_id) REFERENCES wallets(id),
            FOREIGN KEY(to_wallet_id) REFERENCES wallets(id)
          )
        ''');

        await database.execute('''
          CREATE TABLE exchange_rates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            currency TEXT NOT NULL UNIQUE,
            rate REAL NOT NULL
          )
        ''');

        await database.execute('''
          CREATE TABLE app_settings (
            setting_key TEXT PRIMARY KEY,
            setting_value TEXT
          )
        ''');

        await database.insert('app_settings', {
          'setting_key': 'main_currency',
          'setting_value': 'PKR',
        });
      },
    );
  }

  // WALLET OPERATIONS

  Future<List<Map<String, dynamic>>> getWallets() {
    return db.query('wallets', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<Map<String, dynamic>?> getWallet(int id) async {
    final result = await db.query(
      'wallets',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isEmpty ? null : result.first;
  }

  Future<int> addWallet(Map<String, dynamic> wallet) {
    return db.insert('wallets', {
      ...wallet,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateWallet(
    int id,
    Map<String, dynamic> wallet,
  ) {
    return db.update(
      'wallets',
      wallet,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteWallet(int id) async {
    final used = await db.query(
      'transactions',
      where: 'wallet_id = ? OR to_wallet_id = ?',
      whereArgs: [id, id],
      limit: 1,
    );

    if (used.isNotEmpty) {
      throw Exception(
        'Is Wallet ki transactions mojood hain. Pehle transactions delete karein.',
      );
    }

    return db.delete(
      'wallets',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // TRANSACTION OPERATIONS

  Future<List<Map<String, dynamic>>> getTransactions() async {
    return db.rawQuery('''
      SELECT
        t.*,
        w.name AS wallet_name,
        w.currency AS wallet_currency,
        tw.name AS to_wallet_name
      FROM transactions t
      LEFT JOIN wallets w ON w.id = t.wallet_id
      LEFT JOIN wallets tw ON tw.id = t.to_wallet_id
      ORDER BY t.date DESC, t.id DESC
    ''');
  }

  Future<void> addTransaction({
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    String? category,
    String? note,
    required DateTime date,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount zero se zyada hona chahiye.');
    }

    await db.transaction((txn) async {
      final source = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
        limit: 1,
      );

      if (source.isEmpty) {
        throw Exception('Wallet nahi mila.');
      }

      if (type == 'Transfer') {
        if (toWalletId == null || toWalletId == walletId) {
          throw Exception('Destination Wallet select karein.');
        }

        final destination = await txn.query(
          'wallets',
          where: 'id = ?',
          whereArgs: [toWalletId],
          limit: 1,
        );

        if (destination.isEmpty) {
          throw Exception('Destination Wallet nahi mila.');
        }

        if (source.first['currency'] != destination.first['currency']) {
          throw Exception(
            'Filhal transfer dono Wallets ki same currency mein hona chahiye.',
          );
        }

        final sourceBalance =
            (source.first['balance'] as num).toDouble();

        if (sourceBalance < amount) {
          throw Exception('Wallet mein kafi balance nahi hai.');
        }

        await txn.update(
          'wallets',
          {'balance': sourceBalance - amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );

        final destinationBalance =
            (destination.first['balance'] as num).toDouble();

        await txn.update(
          'wallets',
          {'balance': destinationBalance + amount},
          where: 'id = ?',
          whereArgs: [toWalletId],
        );
      } else {
        final currentBalance =
            (source.first['balance'] as num).toDouble();

        final newBalance = type == 'Income'
            ? currentBalance + amount
            : currentBalance - amount;

        await txn.update(
          'wallets',
          {'balance': newBalance},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      }

      await txn.insert('transactions', {
        'type': type,
        'amount': amount,
        'wallet_id': walletId,
        'to_wallet_id': toWalletId,
        'category': category,
        'note': note,
        'date': date.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> deleteTransaction(int id) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rows.isEmpty) return;

      final item = rows.first;
      final amount = (item['amount'] as num).toDouble();
      final walletId = item['wallet_id'] as int;
      final toWalletId = item['to_wallet_id'] as int?;

      final sourceRows = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
      );

      if (sourceRows.isNotEmpty) {
        final balance =
            (sourceRows.first['balance'] as num).toDouble();

        double restored = balance;

        if (item['type'] == 'Income') {
          restored -= amount;
        } else {
          restored += amount;
        }

        await txn.update(
          'wallets',
          {'balance': restored},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      }

      if (item['type'] == 'Transfer' && toWalletId != null) {
        final destinationRows = await txn.query(
          'wallets',
          where: 'id = ?',
          whereArgs: [toWalletId],
        );

        if (destinationRows.isNotEmpty) {
          final balance =
              (destinationRows.first['balance'] as num).toDouble();

          await txn.update(
            'wallets',
            {'balance': balance - amount},
            where: 'id = ?',
            whereArgs: [toWalletId],
          );
        }
      }

      await txn.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // DASHBOARD TOTALS

  Future<double> totalByType(String type) async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total '
      'FROM transactions WHERE type = ?',
      [type],
    );

    return (result.first['total'] as num).toDouble();
  }

  Future<double> totalBalance() async {
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(balance), 0) AS total '
      'FROM wallets WHERE exclude_total = 0 AND currency = ?',
      ['PKR'],
    );

    return (result.first['total'] as num).toDouble();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

// ------------------------------------------------------------
// APP
// ------------------------------------------------------------

class MyFinanceApp extends StatelessWidget {
  const MyFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Finance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ------------------------------------------------------------
// MAIN NAVIGATION
// ------------------------------------------------------------

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;
  int refreshKey = 0;

  void refreshPages() {
    setState(() => refreshKey++);
  }

  void openPlus() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlusFormScreen(onSaved: refreshPages),
      ),
    );
  }

  void openMore() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MoreFeaturesPage(),
      ),
    );
  }

  void openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NotificationsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(key: ValueKey('home_$refreshKey'),
          onRefresh: refreshPages),
      const SimpleFeaturePage(
        title: 'Assets',
        icon: Icons.diamond_outlined,
        description: 'Manage your assets',
      ),
      const SimpleFeaturePage(
        title: 'Loans',
        icon: Icons.handshake_outlined,
        description: 'Manage loans and repayments',
      ),
      TransactionsPage(key: ValueKey('transactions_$refreshKey'),
          onRefresh: refreshPages),
      WalletsPage(key: ValueKey('wallets_$refreshKey'),
          onRefresh: refreshPages),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (selectedIndex == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'My Finance',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: openNotifications,
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                    IconButton(
                      onPressed: openMore,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
            Expanded(child: pages[selectedIndex]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index == 5) {
            openPlus();
            return;
          }
          setState(() => selectedIndex = index);
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
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Wallets',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'Plus',
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// HOME DASHBOARD
// ------------------------------------------------------------

class HomePage extends StatefulWidget {
  final VoidCallback onRefresh;

  const HomePage({
    super.key,
    required this.onRefresh,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> wallets = [];
  double income = 0;
  double expense = 0;
  double total = 0;
  bool loading = true;

  final Map<String, double> exchangeRates = {
    'PKR': 1,
    'USD': 280,
    'AED': 76,
    'SAR': 74,
    'GBP': 360,
    'EUR': 325,
    'INR': 3.35,
  };

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    setState(() => loading = true);

    final data = await FinanceDB.instance.getWallets();

    double convertedTotal = 0;

    for (final wallet in data) {
      if ((wallet['exclude_total'] as int) == 1) {
        continue;
      }

      final currency = wallet['currency'] as String;
      final balance = (wallet['balance'] as num).toDouble();

      final rate = exchangeRates[currency] ?? 1;
      convertedTotal += balance * rate;
    }

    final inc = await FinanceDB.instance.totalByType('Income');
    final exp = await FinanceDB.instance.totalByType('Expense');

    if (!mounted) return;

    setState(() {
      wallets = data;
      income = inc;
      expense = exp;
      total = convertedTotal;
      loading = false;
    });
  }

  String money(double amount) {
    return NumberFormat.currency(
      locale: 'en_PK',
      symbol: 'Rs. ',
      decimalDigits: 2,
    ).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: loadDashboard,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text(
            'Your Financial Overview',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),

          // TOTAL BALANCE CARD
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF147D59),
                  Color(0xFF0B5940),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.20),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total Balance',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white70,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  loading ? 'Loading...' : money(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Consolidated balance in PKR',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  title: 'Income',
                  amount: income,
                  icon: Icons.arrow_downward_rounded,
                  color: AppColors.income,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _summaryCard(
                  title: 'Expense',
                  amount: expense,
                  icon: Icons.arrow_upward_rounded,
                  color: AppColors.expense,
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'My Wallets',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  widget.onRefresh();
                },
                child: const Text('Refresh'),
              ),
            ],
          ),

          const SizedBox(height: 8),

          if (loading)
            const Center(
              child: CircularProgressIndicator(),
            )
          else if (wallets.isEmpty)
            _emptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No Wallets Yet',
              subtitle: 'Create your first Wallet using the Plus button.',
            )
          else
            ...wallets.map((wallet) {
              return _dashboardWalletCard(wallet);
            }),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            NumberFormat('#,##0.00').format(amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardWalletCard(Map<String, dynamic> wallet) {
    final balance = (wallet['balance'] as num).toDouble();
    final currency = wallet['currency'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.10),
            child: Icon(
              IconData(
                wallet['icon_code'] as int,
                fontFamily: 'MaterialIcons',
              ),
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet['name'] as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${wallet['type']} • $currency',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$currency ${NumberFormat('#,##0.00').format(balance)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// WALLET MANAGEMENT PAGE
// ------------------------------------------------------------

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
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadWallets();
  }

  Future<void> loadWallets() async {
    setState(() => loading = true);

    final data = await FinanceDB.instance.getWallets();

    if (!mounted) return;

    setState(() {
      wallets = data;
      loading = false;
    });
  }

  Future<void> openWalletForm({
    Map<String, dynamic>? wallet,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => WalletFormDialog(wallet: wallet),
    );

    await loadWallets();
    widget.onRefresh();
  }

  Future<void> removeWallet(int id) async {
    try {
      await FinanceDB.instance.deleteWallet(id);
      await loadWallets();
      widget.onRefresh();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallet deleted successfully')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openWalletForm(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Wallet'),
      ),
      body: RefreshIndicator(
        onRefresh: loadWallets,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
          children: [
            const Text(
              'My Wallets',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Manage all your money sources in one place.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 22),

            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (wallets.isEmpty)
              _emptyState(
                icon: Icons.wallet_outlined,
                title: 'No Wallets Created',
                subtitle: 'Tap Add Wallet to create your first Wallet.',
              )
            else
              ...wallets.map((wallet) {
                final id = wallet['id'] as int;
                final balance =
                    (wallet['balance'] as num).toDouble();

                return Card(
                  margin: const EdgeInsets.only(bottom: 13),
                  child: Padding(
                    padding: const EdgeInsets.all(17),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.10),
                          child: Icon(
                            IconData(
                              wallet['icon_code'] as int,
                              fontFamily: 'MaterialIcons',
                            ),
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                wallet['name'] as String,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${wallet['type']} • ${wallet['currency']}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${wallet['currency']} ${NumberFormat('#,##0.00').format(balance)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              if ((wallet['exclude_total'] as int) == 1)
                                const Text(
                                  'Excluded from Total Balance',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.expense,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              openWalletForm(wallet: wallet);
                            } else if (value == 'delete') {
                              removeWallet(id);
                            }
                          },
                          itemBuilder: (_) => const [
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
              }),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// WALLET CREATE / EDIT DIALOG
// ------------------------------------------------------------

class WalletFormDialog extends StatefulWidget {
  final Map<String, dynamic>? wallet;

  const WalletFormDialog({
    super.key,
    this.wallet,
  });

  @override
  State<WalletFormDialog> createState() => _WalletFormDialogState();
}

class _WalletFormDialogState extends State<WalletFormDialog> {
  final formKey = GlobalKey<FormState>();

  late TextEditingController nameController;
  late TextEditingController numberController;
  late TextEditingController balanceController;
  late TextEditingController customTypeController;

  final walletTypes = [
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

  final currencies = [
    'PKR',
    'USD',
    'GBP',
    'EUR',
    'AED',
    'SAR',
    'INR',
  ];

  final icons = <IconData>[
    Icons.account_balance_wallet_rounded,
    Icons.account_balance_rounded,
    Icons.savings_rounded,
    Icons.credit_card_rounded,
    Icons.money_rounded,
    Icons.phone_android_rounded,
    Icons.trending_up_rounded,
    Icons.payments_rounded,
    Icons.business_rounded,
    Icons.wallet_rounded,
  ];

  late String selectedType;
  late String selectedCurrency;
  late int selectedIcon;
  late bool excludeTotal;

  bool saving = false;

  bool get isEditing => widget.wallet != null;

  @override
  void initState() {
    super.initState();

    final wallet = widget.wallet;

    nameController = TextEditingController(
      text: wallet?['name']?.toString() ?? '',
    );

    numberController = TextEditingController(
      text: wallet?['wallet_number']?.toString() ?? '',
    );

    balanceController = TextEditingController(
      text: wallet?['balance']?.toString() ?? '0',
    );

    customTypeController = TextEditingController(
      text: wallet?['custom_type']?.toString() ?? '',
    );

    selectedType = wallet?['type']?.toString() ?? 'Cash';
    selectedCurrency = wallet?['currency']?.toString() ?? 'PKR';
    selectedIcon = wallet?['icon_code'] as int? ??
        Icons.account_balance_wallet_rounded.codePoint;

    excludeTotal = (wallet?['exclude_total'] as int? ?? 0) == 1;
  }

  @override
  void dispose() {
    nameController.dispose();
    numberController.dispose();
    balanceController.dispose();
    customTypeController.dispose();
    super.dispose();
  }

  Future<void> saveWallet() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      final data = <String, dynamic>{
        'name': nameController.text.trim(),
        'type': selectedType,
        'custom_type': selectedType == 'Other'
            ? customTypeController.text.trim()
            : null,
        'wallet_number': numberController.text.trim().isEmpty
            ? null
            : numberController.text.trim(),
        'icon_code': selectedIcon,
        'exclude_total': excludeTotal ? 1 : 0,
      };

      if (!isEditing) {
        data['currency'] = selectedCurrency;
        data['balance'] =
            double.tryParse(balanceController.text.trim()) ?? 0;

        await FinanceDB.instance.addWallet(data);
      } else {
        await FinanceDB.instance.updateWallet(
          widget.wallet!['id'] as int,
          data,
        );
      }

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Wallet updated successfully'
                : 'Wallet created successfully',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(25),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Edit Wallet' : 'Create Wallet',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),

                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Wallet Name',
                    prefixIcon: Icon(Icons.wallet_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty
                          ? 'Wallet name required'
                          : null,
                ),

                const SizedBox(height: 15),

                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Wallet Type',
                    border: OutlineInputBorder(),
                  ),
                  items: walletTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedType = value);
                    }
                  },
                ),

                if (selectedType == 'Other') ...[
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: customTypeController,
                    decoration: const InputDecoration(
                      labelText: 'Custom Wallet Type',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        selectedType == 'Other' &&
                                (value == null || value.trim().isEmpty)
                            ? 'Enter custom type'
                            : null,
                  ),
                ],

                const SizedBox(height: 15),

                if (!isEditing)
                  DropdownButtonFormField<String>(
                    value: selectedCurrency,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                    ),
                    items: currencies.map((currency) {
                      return DropdownMenuItem(
                        value: currency,
                        child: Text(currency),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedCurrency = value);
                      }
                    },
                  ),

                if (!isEditing) ...[
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: balanceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Opening Balance',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          double.tryParse(value.trim()) == null) {
                        return 'Enter a valid balance';
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 15),

                TextFormField(
                  controller: numberController,
                  decoration: const InputDecoration(
                    labelText: 'Wallet Number (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'Choose Wallet Icon',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 10),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: icons.map((icon) {
                    final selected = selectedIcon == icon.codePoint;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          selectedIcon = icon.codePoint;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppColors.primary
                                : Colors.transparent,
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: selected
                              ? AppColors.primary
                              : AppColors.muted,
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 15),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Exclude from Total Balance',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: excludeTotal,
                  activeThumbColor: AppColors.primary,
                  onChanged: (value) {
                    setState(() => excludeTotal = value);
                  },
                ),

                const SizedBox(height: 15),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: saving ? null : saveWallet,
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(isEditing ? 'Update' : 'Create'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// EMPTY STATE
// ------------------------------------------------------------

Widget _emptyState({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 45),
    child: Column(
      children: [
        Icon(
          icon,
          size: 55,
          color: AppColors.muted.withValues(alpha: 0.55),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.muted,
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------
// PLUS FORM SCREEN
// ------------------------------------------------------------

class PlusFormScreen extends StatelessWidget {
  final VoidCallback onSaved;

  const PlusFormScreen({
    super.key,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Add New',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            tabs: [
              Tab(text: 'Income'),
              Tab(text: 'Expense'),
              Tab(text: 'Transfer'),
              Tab(text: 'Wallet'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            TransactionEntryForm(
              type: 'Income',
              onSaved: onSaved,
            ),
            TransactionEntryForm(
              type: 'Expense',
              onSaved: onSaved,
            ),
            TransactionEntryForm(
              type: 'Transfer',
              onSaved: onSaved,
            ),
            WalletEntryTab(onSaved: onSaved),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// WALLET TAB
// ------------------------------------------------------------

class WalletEntryTab extends StatelessWidget {
  final VoidCallback onSaved;

  const WalletEntryTab({
    super.key,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                size: 55,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Create a New Wallet',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add a bank account, cash wallet, savings wallet or any other money source.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (_) => const WalletFormDialog(),
                  );
                  onSaved();
                },
                icon: const Icon(Icons.add),
                label: const Text('Create Wallet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// TRANSACTION ENTRY FORM
// ------------------------------------------------------------

class TransactionEntryForm extends StatefulWidget {
  final String type;
  final VoidCallback onSaved;

  const TransactionEntryForm({
    super.key,
    required this.type,
    required this.onSaved,
  });

  @override
  State<TransactionEntryForm> createState() =>
      _TransactionEntryFormState();
}

class _TransactionEntryFormState
    extends State<TransactionEntryForm> {
  final formKey = GlobalKey<FormState>();

  final amountController = TextEditingController();
  final categoryController = TextEditingController();
  final noteController = TextEditingController();

  List<Map<String, dynamic>> wallets = [];

  int? selectedWalletId;
  int? destinationWalletId;

  DateTime selectedDate = DateTime.now();

  bool saving = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadWallets();
  }

  @override
  void dispose() {
    amountController.dispose();
    categoryController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> loadWallets() async {
    final data = await FinanceDB.instance.getWallets();

    if (!mounted) return;

    setState(() {
      wallets = data;
      loading = false;

      if (wallets.isNotEmpty) {
        selectedWalletId ??= wallets.first['id'] as int;
      }

      if (wallets.length > 1) {
        destinationWalletId ??= wallets[1]['id'] as int;
      }
    });
  }

  Future<void> selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (date != null) {
      setState(() => selectedDate = date);
    }
  }

  Future<void> saveTransaction() async {
    if (!formKey.currentState!.validate()) return;

    if (selectedWalletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create a Wallet first.')),
      );
      return;
    }

    if (widget.type == 'Transfer') {
      if (destinationWalletId == null ||
          destinationWalletId == selectedWalletId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a different destination Wallet.'),
          ),
        );
        return;
      }
    }

    setState(() => saving = true);

    try {
      await FinanceDB.instance.addTransaction(
        type: widget.type,
        amount: double.parse(amountController.text.trim()),
        walletId: selectedWalletId!,
        toWalletId: widget.type == 'Transfer'
            ? destinationWalletId
            : null,
        category: categoryController.text.trim(),
        note: noteController.text.trim(),
        date: selectedDate,
      );

      if (!mounted) return;

      amountController.clear();
      categoryController.clear();
      noteController.clear();

      setState(() {
        saving = false;
        selectedDate = DateTime.now();
      });

      widget.onSaved();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.type} saved successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (wallets.isEmpty) {
      return _emptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No Wallet Available',
        subtitle: 'Please create a Wallet before adding a transaction.',
      );
    }

    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Add ${widget.type}',
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),

          TextFormField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixIcon: const Icon(Icons.payments_outlined),
              prefixText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            validator: (value) {
              final amount = double.tryParse(value ?? '');
              if (amount == null || amount <= 0) {
                return 'Enter a valid amount';
              }
              return null;
            },
          ),

          const SizedBox(height: 16),

          DropdownButtonFormField<int>(
            value: selectedWalletId,
            decoration: InputDecoration(
              labelText: widget.type == 'Transfer'
                  ? 'From Wallet'
                  : 'Wallet',
              prefixIcon: const Icon(
                Icons.account_balance_wallet_outlined,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            items: wallets.map((wallet) {
              return DropdownMenuItem<int>(
                value: wallet['id'] as int,
                child: Text(wallet['name'] as String),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => selectedWalletId = value);
            },
          ),

          if (widget.type == 'Transfer') ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: destinationWalletId,
              decoration: InputDecoration(
                labelText: 'To Wallet',
                prefixIcon: const Icon(Icons.swap_horiz_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              items: wallets
                  .where((wallet) =>
                      wallet['id'] != selectedWalletId)
                  .map((wallet) {
                return DropdownMenuItem<int>(
                  value: wallet['id'] as int,
                  child: Text(wallet['name'] as String),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => destinationWalletId = value);
              },
            ),
          ],

          if (widget.type != 'Transfer') ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: categoryController,
              decoration: InputDecoration(
                labelText: 'Category (Optional)',
                prefixIcon: const Icon(Icons.category_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          InkWell(
            onTap: selectDate,
            borderRadius: BorderRadius.circular(15),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Transaction Date',
                prefixIcon: const Icon(Icons.calendar_month_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Text(
                DateFormat('dd MMM yyyy').format(selectedDate),
              ),
            ),
          ),

          const SizedBox(height: 16),

          TextFormField(
            controller: noteController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Notes (Optional)',
              prefixIcon: const Icon(Icons.notes_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),

          const SizedBox(height: 25),

          SizedBox(
            height: 53,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.type == 'Expense'
                    ? AppColors.expense
                    : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: saving ? null : saveTransaction,
              child: saving
                  ? const CircularProgressIndicator(
                      color: Colors.white,
                    )
                  : Text(
                      'Save ${widget.type}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// TRANSACTIONS PAGE
// ------------------------------------------------------------

class TransactionsPage extends StatefulWidget {
  final VoidCallback onRefresh;

  const TransactionsPage({
    super.key,
    required this.onRefresh,
  });

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  List<Map<String, dynamic>> transactions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadTransactions();
  }

  Future<void> loadTransactions() async {
    setState(() => loading = true);

    final data = await FinanceDB.instance.getTransactions();

    if (!mounted) return;

    setState(() {
      transactions = data;
      loading = false;
    });
  }

  Future<void> removeTransaction(int id) async {
    await FinanceDB.instance.deleteTransaction(id);
    await loadTransactions();
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: loadTransactions,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 25),
        children: [
          const Text(
            'Transactions',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your income, expenses and transfers.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 20),

          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (transactions.isEmpty)
            _emptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No Transactions Yet',
              subtitle: 'Your transactions will appear here.',
            )
          else
            ...transactions.map((item) {
              final type = item['type'] as String;
              final amount = (item['amount'] as num).toDouble();

              final color = type == 'Income'
                  ? AppColors.income
                  : type == 'Expense'
                      ? AppColors.expense
                      : AppColors.primary;

              final icon = type == 'Income'
                  ? Icons.arrow_downward_rounded
                  : type == 'Expense'
                      ? Icons.arrow_upward_rounded
                      : Icons.swap_horiz_rounded;

              final date = DateTime.tryParse(
                    item['date']?.toString() ?? '',
                  ) ??
                  DateTime.now();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 7,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(icon, color: color),
                  ),
                  title: Text(
                    type,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    '${item['wallet_name'] ?? 'Wallet'}'
                    '${item['to_wallet_name'] == null ? '' : ' → ${item['to_wallet_name']}'}'
                    '\n${DateFormat('dd MMM yyyy').format(date)}'
                    '${item['note'] == null || item['note'].toString().isEmpty ? '' : '\n${item['note']}'}',
                  ),
                  isThreeLine: true,
                  trailing: SizedBox(
                    width: 115,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item['wallet_currency'] ?? 'PKR'} ${NumberFormat('#,##0.00').format(amount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'delete') {
                              removeTransaction(item['id'] as int);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete Transaction'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// NOTIFICATIONS PAGE
// ------------------------------------------------------------

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _emptyState(
        icon: Icons.notifications_none_rounded,
        title: 'No Notifications',
        subtitle: 'Your important updates and reminders will appear here.',
      ),
    );
  }
}

// ------------------------------------------------------------
// MORE FEATURES PAGE
// ------------------------------------------------------------

class MoreFeaturesPage extends StatelessWidget {
  const MoreFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final features = [
      {
        'title': 'Budgets',
        'subtitle': 'Manage your spending limits',
        'icon': Icons.pie_chart_outline_rounded,
      },
      {
        'title': 'Categories',
        'subtitle': 'Manage income and expense categories',
        'icon': Icons.category_outlined,
      },
      {
        'title': 'Recurring Transactions',
        'subtitle': 'Manage scheduled transactions',
        'icon': Icons.repeat_rounded,
      },
      {
        'title': 'Reports & Analytics',
        'subtitle': 'Review your financial performance',
        'icon': Icons.analytics_outlined,
      },
      {
        'title': 'Savings Goals',
        'subtitle': 'Track your savings progress',
        'icon': Icons.savings_outlined,
      },
      {
        'title': 'Settings',
        'subtitle': 'Manage app preferences',
        'icon': Icons.settings_outlined,
      },
      {
        'title': 'Backup & Restore',
        'subtitle': 'Protect your finance data',
        'icon': Icons.backup_outlined,
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'More Features',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          ...features.map((feature) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.10),
                  child: Icon(
                    feature['icon'] as IconData,
                    color: AppColors.primary,
                  ),
                ),
                title: Text(
                  feature['title'] as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  feature['subtitle'] as String,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SimpleFeaturePage(
                        title: feature['title'] as String,
                        icon: feature['icon'] as IconData,
                        description:
                            feature['subtitle'] as String,
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// SIMPLE FEATURE PLACEHOLDER
// ------------------------------------------------------------

class SimpleFeaturePage extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;

  const SimpleFeaturePage({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 65,
                color: AppColors.primary,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                'This feature will be implemented in its dedicated screen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
