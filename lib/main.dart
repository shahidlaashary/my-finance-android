import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'screens/categories_screen.dart';
import 'screens/transactions_screen.dart';
import 'screens/loans_screen.dart';
import 'screens/more_features_screen.dart';
import 'services/app_startup_service.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await FinanceDB.instance.init();
  await AppStartupService.initialize();
  runApp(const MyFinanceApp());
}
class FinanceDB {
  FinanceDB._();
  static final instance = FinanceDB._();
  Database? _db;
  Database get db => _db!;
  Future<void> init() async {
    if (_db != null && _db!.isOpen) return;
    final base = await getDatabasesPath();
    _db = await openDatabase(
      p.join(base, 'my_finance.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            currency TEXT NOT NULL DEFAULT 'PKR',
            balance REAL NOT NULL DEFAULT 0,
            exclude_total INTEGER NOT NULL DEFAULT 0,
            account_number TEXT NOT NULL DEFAULT '',
            icon_code INTEGER NOT NULL DEFAULT ${Icons.account_balance_wallet.codePoint}
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            account_id INTEGER NOT NULL,
            to_account_id INTEGER,
            note TEXT NOT NULL DEFAULT '',
            date TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE accounts ADD COLUMN account_number TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE accounts ADD COLUMN icon_code INTEGER NOT NULL DEFAULT ${Icons.account_balance_wallet.codePoint}',
          );
        }
      },
    );
  }
  // Close the current database connection.
  Future<void> close() async {
    final currentDatabase = _db;
    _db = null;
    if (currentDatabase != null && currentDatabase.isOpen) {
      await currentDatabase.close();
    }
  }
  // Reopen the database after backup restoration.
  Future<void> reopen() async {
    await close();
    await init();
  }
  Future<List<Map<String, dynamic>>> accounts() async {
    return db.query('accounts', orderBy: 'name ASC');
  }
  Future<List<Map<String, dynamic>>> transactions() async {
    return db.query(
      'transactions',
      orderBy: 'date DESC, id DESC',
    );
  }
  Future<void> addAccount({
    required String name,
    required String type,
    required String currency,
    required double openingBalance,
    required String accountNumber,
    required int iconCode,
    required bool excludeTotal,
  }) async {
    await db.insert('accounts', {
      'name': name,
      'type': type,
      'currency': currency,
      'balance': openingBalance,
      'account_number': accountNumber,
      'icon_code': iconCode,
      'exclude_total': excludeTotal ? 1 : 0,
    });
  }
  Future<void> updateAccount({
    required int id,
    required String name,
    required String type,
    required String accountNumber,
    required int iconCode,
    required bool excludeTotal,
  }) async {
    await db.update(
      'accounts',
      {
        'name': name,
        'type': type,
        'account_number': accountNumber,
        'icon_code': iconCode,
        'exclude_total': excludeTotal ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  Future<void> deleteAccount(int id) async {
    await db.transaction((txn) async {
      final tables = await txn.rawQuery('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
      ''');
      final accountColumns = {
        'account_id',
        'to_account_id',
        'from_account_id',
        'source_account_id',
        'destination_account_id',
      };
      final linkedTables = <String>[];
      for (final table in tables) {
        final tableName = table['name']?.toString();
        if (tableName == null || tableName == 'accounts') {
          continue;
        }
        final escapedTableName = tableName.replaceAll('"', '""');
        final columns = await txn.rawQuery(
          'PRAGMA table_info("$escapedTableName")',
        );
        final matchingColumns = columns
            .map((column) => column['name']?.toString())
            .whereType<String>()
            .where(accountColumns.contains)
            .toList();
        if (matchingColumns.isEmpty) {
          continue;
        }
        final conditions = matchingColumns
            .map((column) => '"$column" = ?')
            .join(' OR ');
        final linked = await txn.rawQuery(
          'SELECT COUNT(*) AS total FROM "$escapedTableName" '
          'WHERE $conditions',
          List.filled(matchingColumns.length, id),
        );
        final count = (linked.first['total'] as num).toInt();
        if (count > 0) {
          linkedTables.add(tableName);
        }
      }
      if (linkedTables.isNotEmpty) {
        throw Exception(
          'This account has linked records in: '
          '${linkedTables.join(', ')}. '
          'Remove or reassign those records before deleting this account.',
        );
      }
      final deleted = await txn.delete(
        'accounts',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (deleted == 0) {
        throw Exception('Account not found.');
      }
    });
  }
  Future<void> addTransaction({
    required String type,
    required double amount,
    required int accountId,
    int? toAccountId,
    required String note,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
    await db.transaction((txn) async {
      final source = await txn.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [accountId],
      );
      if (source.isEmpty) {
        throw Exception('Account not found.');
      }
      if (type == 'Transfer') {
        if (toAccountId == null || toAccountId == accountId) {
          throw Exception('Select a different destination account.');
        }
        final destination = await txn.query(
          'accounts',
          where: 'id = ?',
          whereArgs: [toAccountId],
        );
        if (destination.isEmpty) {
          throw Exception('Destination account not found.');
        }
        if (source.first['currency'] != destination.first['currency']) {
          throw Exception(
            'Transfers between different currencies are not yet supported.',
          );
        }
        final balance = (source.first['balance'] as num).toDouble();
        if (balance < amount) {
          throw Exception('Insufficient account balance.');
        }
        await txn.update(
          'accounts',
          {'balance': balance - amount},
          where: 'id = ?',
          whereArgs: [accountId],
        );
        final destinationBalance =
            (destination.first['balance'] as num).toDouble();
        await txn.update(
          'accounts',
          {'balance': destinationBalance + amount},
          where: 'id = ?',
          whereArgs: [toAccountId],
        );
      } else if (type == 'Expense') {
        final balance = (source.first['balance'] as num).toDouble();
        await txn.update(
          'accounts',
          {'balance': balance - amount},
          where: 'id = ?',
          whereArgs: [accountId],
        );
      } else if (type == 'Income') {
        final balance = (source.first['balance'] as num).toDouble();
        await txn.update(
          'accounts',
          {'balance': balance + amount},
          where: 'id = ?',
          whereArgs: [accountId],
        );
      } else {
        throw Exception('Invalid transaction type.');
      }
      await txn.insert('transactions', {
        'type': type,
        'amount': amount,
        'account_id': accountId,
        'to_account_id': toAccountId,
        'note': note,
        'date': DateTime.now().toIso8601String(),
      });
    });
  }
  Future<List<Map<String, dynamic>>> dashboardSummary() async {
    final accountResults = await db.rawQuery('''
      SELECT
        currency,
        SUM(
          CASE WHEN exclude_total = 0 THEN balance ELSE 0 END
        ) AS total_balance
      FROM accounts
      GROUP BY currency
    ''');
    final transactionResults = await db.rawQuery('''
      SELECT
        accounts.currency AS currency,
        LOWER(transactions.type) AS transaction_type,
        SUM(transactions.amount) AS total_amount
      FROM transactions
      INNER JOIN accounts
        ON accounts.id = transactions.account_id
      WHERE LOWER(transactions.type) IN ('income', 'expense')
      GROUP BY accounts.currency, LOWER(transactions.type)
    ''');
    final Map<String, Map<String, dynamic>> summaries = {};
    for (final account in accountResults) {
      final currency = (account['currency'] ?? 'PKR').toString();
      summaries[currency] = {
        'currency': currency,
        'balance': (account['total_balance'] as num?)?.toDouble() ?? 0,
        'income': 0.0,
        'expense': 0.0,
      };
    }
    for (final transaction in transactionResults) {
      final currency = (transaction['currency'] ?? 'PKR').toString();
      final type = transaction['transaction_type'].toString();
      final amount =
          (transaction['total_amount'] as num?)?.toDouble() ?? 0;
      summaries.putIfAbsent(currency, () {
        return {
          'currency': currency,
          'balance': 0.0,
          'income': 0.0,
          'expense': 0.0,
        };
      });
      if (type == 'income') {
        summaries[currency]!['income'] = amount;
      } else if (type == 'expense') {
        summaries[currency]!['expense'] = amount;
      }
    }
    final result = summaries.values.toList();
    result.sort(
      (a, b) => a['currency'].toString().compareTo(
            b['currency'].toString(),
          ),
    );
    return result;
  }
  Future<double> totalBalance() async {
    final result = await db.rawQuery('''
      SELECT SUM(balance) AS total
      FROM accounts
      WHERE exclude_total = 0
    ''');
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }
  Future<double> totalByType(String type) async {
    final result = await db.rawQuery(
      '''
      SELECT SUM(amount) AS total
      FROM transactions
      WHERE LOWER(type) = LOWER(?)
      ''',
      [type],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }
}
class MyFinanceApp extends StatelessWidget {
  const MyFinanceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Finance',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF147D59),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
      ),
      home: const MainScreen(),
    );
  }
}
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;
  void refresh() {
    setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(onRefresh: refresh),
      AccountsPage(onRefresh: refresh),
      const TransactionsScreen(),
      const CategoriesScreen(),
      const LoansScreen(),
      const MoreFeaturesScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Finance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
      ),
      body: pages[selectedIndex],
      floatingActionButton: selectedIndex == 2
          ? FloatingActionButton(
              onPressed: () async {
                await showTransactionDialog(context);
                refresh();
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) {
          setState(() => selectedIndex = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: 'Categories',
          ),
          NavigationDestination(
            icon: Icon(Icons.handshake_outlined),
            selectedIcon: Icon(Icons.handshake),
            label: 'Loans',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_customize_outlined),
            selectedIcon: Icon(Icons.dashboard_customize),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
class DashboardPage extends StatelessWidget {
  final VoidCallback onRefresh;
  const DashboardPage({
    super.key,
    required this.onRefresh,
  });
  String money(String currency, double amount) {
    return '$currency ${NumberFormat('#,##0.00').format(amount)}';
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: FinanceDB.instance.dashboardSummary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final summaries = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Financial Overview',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (summaries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF147D59),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Balance',
                        style: TextStyle(color: Colors.white70),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'No accounts yet',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Add an account to see your financial summary.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ...summaries.map((summary) {
                final currency = summary['currency'].toString();
                final balance = (summary['balance'] as num).toDouble();
                final income = (summary['income'] as num).toDouble();
                final expense = (summary['expense'] as num).toDouble();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: const Color(0xFF147D59),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$currency Total Balance',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              money(currency, balance),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'My Finance',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SummaryCard(
                              title: '$currency Income',
                              amount: money(currency, income),
                              icon: Icons.trending_up,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SummaryCard(
                              title: '$currency Expenses',
                              amount: money(currency, expense),
                              icon: Icons.trending_down,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ActionTile(
                    label: 'Income',
                    icon: Icons.add_circle_outline,
                    onTap: () => showTransactionDialog(
                      context,
                      initialType: 'Income',
                    ),
                  ),
                  ActionTile(
                    label: 'Expense',
                    icon: Icons.remove_circle_outline,
                    onTap: () => showTransactionDialog(
                      context,
                      initialType: 'Expense',
                    ),
                  ),
                  ActionTile(
                    label: 'Transfer',
                    icon: Icons.swap_horiz,
                    onTap: () => showTransactionDialog(
                      context,
                      initialType: 'Transfer',
                    ),
                  ),
                  ActionTile(
                    label: 'Add Account',
                    icon: Icons.account_balance,
                    onTap: () async {
                      await showAccountDialog(context);
                      onRefresh();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
class SummaryCard extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  final Color color;
  const SummaryCard({
    super.key,
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(title),
            const SizedBox(height: 5),
            Text(
              amount,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
class ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const ActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(icon, size: 29),
                const SizedBox(height: 8),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class AccountsPage extends StatelessWidget {
  final VoidCallback onRefresh;
  const AccountsPage({
    super.key,
    required this.onRefresh,
  });
  Future<void> _deleteAccount(
    BuildContext context,
    Map<String, dynamic> account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(
          'Are you sure you want to delete "${account['name']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await FinanceDB.instance.deleteAccount(account['id'] as int);
      onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: FinanceDB.instance.accounts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final accounts = snapshot.data ?? [];
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              await showAccountDialog(context);
              onRefresh();
            },
            child: const Icon(Icons.add),
          ),
          body: accounts.isEmpty
              ? const Center(
                  child: Text('No accounts yet. Add your first account.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: accounts.length,
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    final balance =
                        (account['balance'] as num?)?.toDouble() ?? 0;
                    final iconCode =
                        account['icon_code'] as int? ??
                        Icons.account_balance_wallet.codePoint;
                    final accountIcon = IconData(
                      iconCode,
                      fontFamily: 'MaterialIcons',
                    );
                    final accountNumber =
                        (account['account_number'] ?? '').toString();
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(accountIcon),
                        ),
                        title: Text(account['name'].toString()),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${account['type']} • ${account['currency']}',
                            ),
                            if (accountNumber.isNotEmpty)
                              Text('A/C: $accountNumber'),
                            if ((account['exclude_total'] as int? ?? 0) == 1)
                              const Text(
                                'Excluded from total balance',
                                style: TextStyle(color: Colors.orange),
                              ),
                          ],
                        ),
                        isThreeLine: accountNumber.isNotEmpty ||
                            (account['exclude_total'] as int? ?? 0) == 1,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                '${account['currency']} '
                                '${NumberFormat('#,##0.00').format(balance)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await showAccountDialog(
                                    context,
                                    account: account,
                                  );
                                  onRefresh();
                                } else if (value == 'delete') {
                                  await _deleteAccount(context, account);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit),
                                    title: Text('Edit'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline),
                                    title: Text('Delete'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: FinanceDB.instance.transactions(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(
            child: Text('No transactions recorded yet.'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final type = (item['type'] as String).toLowerCase();
            final color = type == 'income'
                ? Colors.green
                : type == 'expense'
                    ? Colors.red
                    : Colors.blue;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(
                    type == 'income'
                        ? Icons.arrow_downward
                        : type == 'expense'
                            ? Icons.arrow_upward
                            : Icons.swap_horiz,
                    color: color,
                  ),
                ),
                title: Text(type.toUpperCase()),
                subtitle: Text(
                  '${item['note']}\n'
                  '${item['date'].toString().substring(0, 10)}',
                ),
                isThreeLine: true,
                trailing: Text(
                  NumberFormat('#,##0.00').format(item['amount']),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
const List<String> _accountTypes = [
  'Cash',
  'Bank',
  'Savings',
  'Current',
  'Credit Card',
  'Debit Card',
  'Digital Wallet',
  'Investment',
  'Other',
  'Custom',
];
const List<IconData> _accountIcons = [
  Icons.account_balance_wallet,
  Icons.account_balance,
  Icons.savings,
  Icons.credit_card,
  Icons.account_box,
  Icons.wallet,
  Icons.phone_android,
  Icons.trending_up,
  Icons.attach_money,
  Icons.money,
  Icons.business,
  Icons.home,
];
Future<void> showAccountDialog(
  BuildContext context, {
  Map<String, dynamic>? account,
}) async {
  final isEditing = account != null;
  final nameController = TextEditingController(
    text: account?['name']?.toString() ?? '',
  );
  final balanceController = TextEditingController(
    text: account == null
        ? '0'
        : ((account['balance'] as num?)?.toString() ?? '0'),
  );
  final accountNumberController = TextEditingController(
    text: account?['account_number']?.toString() ?? '',
  );
  final customTypeController = TextEditingController();
  final existingType = account?['type']?.toString() ?? 'Cash';
  String type = _accountTypes.contains(existingType) &&
          existingType != 'Custom'
      ? existingType
      : (account == null ? 'Cash' : 'Custom');
  if (type == 'Custom') {
    customTypeController.text = existingType == 'Custom' ? '' : existingType;
  }
  String currency = account?['currency']?.toString() ?? 'PKR';
  int iconCode = account?['icon_code'] as int? ??
      Icons.account_balance_wallet.codePoint;
  bool excludeTotal = (account?['exclude_total'] as int? ?? 0) == 1;
  await showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(isEditing ? 'Edit Account' : 'Add Account'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                ),
              ),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Account type',
                ),
                items: _accountTypes.map((v) {
                  return DropdownMenuItem(
                    value: v,
                    child: Text(v),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() => type = v);
                  }
                },
              ),
              if (type == 'Custom')
                TextField(
                  controller: customTypeController,
                  decoration: const InputDecoration(
                    labelText: 'Custom account type',
                  ),
                ),
              DropdownButtonFormField<String>(
                value: currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                ),
                items: const [
                  'PKR',
                  'USD',
                  'GBP',
                  'EUR',
                  'AED',
                  'SAR',
                ].map((v) {
                  return DropdownMenuItem(
                    value: v,
                    child: Text(v),
                  );
                }).toList(),
                onChanged: isEditing
                    ? null
                    : (v) {
                        if (v != null) {
                          setDialogState(() => currency = v);
                        }
                      },
              ),
              if (isEditing)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Currency cannot be changed for existing accounts.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ),
              if (!isEditing)
                TextField(
                  controller: balanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Opening balance',
                  ),
                ),
              TextField(
                controller: accountNumberController,
                decoration: const InputDecoration(
                  labelText: 'Account number (optional)',
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Account Icon',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _accountIcons.map((icon) {
                  final selected = icon.codePoint == iconCode;
                  return InkWell(
                    onTap: () {
                      setDialogState(() => iconCode = icon.codePoint);
                    },
                    borderRadius: BorderRadius.circular(30),
                    child: CircleAvatar(
                      backgroundColor: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade200,
                      child: Icon(
                        icon,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: excludeTotal,
                title: const Text(
                  'Exclude from Total Balance',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'This account will not be included in dashboard balance.',
                  style: TextStyle(fontSize: 11),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) {
                  setDialogState(() => excludeTotal = value ?? false);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final accountType = type == 'Custom'
                  ? customTypeController.text.trim()
                  : type;
              final balance =
                  double.tryParse(balanceController.text.trim()) ?? 0;
              if (name.isEmpty || accountType.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter account name and account type.'),
                  ),
                );
                return;
              }
              if (!isEditing && balance < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Opening balance cannot be negative.'),
                  ),
                );
                return;
              }
              try {
                if (isEditing) {
                  await FinanceDB.instance.updateAccount(
                    id: account['id'] as int,
                    name: name,
                    type: accountType,
                    accountNumber: accountNumberController.text.trim(),
                    iconCode: iconCode,
                    excludeTotal: excludeTotal,
                  );
                } else {
                  await FinanceDB.instance.addAccount(
                    name: name,
                    type: accountType,
                    currency: currency,
                    openingBalance: balance,
                    accountNumber: accountNumberController.text.trim(),
                    iconCode: iconCode,
                    excludeTotal: excludeTotal,
                  );
                }
