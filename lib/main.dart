import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

import 'models/finance_category.dart';
import 'screens/transactions_screen.dart';
import 'screens/loans_screen.dart';
import 'screens/more_features_screen.dart';
import 'services/app_startup_service.dart';
import 'services/category_service.dart';
import 'services/transaction_service.dart';

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

  Future<void> close() async {
    final currentDatabase = _db;
    _db = null;

    if (currentDatabase != null && currentDatabase.isOpen) {
      await currentDatabase.close();
    }
  }

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
                              style: const TextStyle(
                                color: Colors.white70,
                              ),
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

                    final iconCode = account['icon_code'] as int? ??
                        Icons.account_balance_wallet.codePoint;

                    final accountIcon = IconData(
                      iconCode,
                      fontFamily: 'MaterialIcons',
                    );

                    final accountNumber =
                        (account['account_number'] ?? '').toString();

                    return Card(
                      child: ListTile(
                        onTap: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AccountDetailsPage(
                                accountId: (account['id'] as num).toInt(),
                              ),
                            ),
                          );
                          onRefresh();
                        },
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

class AccountDetailsPage extends StatefulWidget {
  final int accountId;

  const AccountDetailsPage({
    super.key,
    required this.accountId,
  });

  @override
  State<AccountDetailsPage> createState() => _AccountDetailsPageState();
}

class _AccountDetailsPageState extends State<AccountDetailsPage> {
  bool _loading = true;
  Map<String, dynamic>? _account;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _accounts = [];
  double _income = 0;
  double _expenses = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final accountRows = await FinanceDB.instance.accounts();
      final transactionRows = await TransactionService.getTransactions();

      final matches = accountRows.where(
        (item) => (item['id'] as num).toInt() == widget.accountId,
      );
      final selectedAccount = matches.isEmpty ? null : matches.first;

      final relatedTransactions = transactionRows.where((item) {
        final fromId = (item['account_id'] as num?)?.toInt();
        final toId = (item['to_account_id'] as num?)?.toInt();
        return fromId == widget.accountId || toId == widget.accountId;
      }).toList();

      double income = 0;
      double expenses = 0;

      for (final item in relatedTransactions) {
        final type = (item['type'] ?? '').toString().toLowerCase();
        final fromId = (item['account_id'] as num?)?.toInt();
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;

        if (fromId == widget.accountId && type == 'income') {
          income += amount;
        } else if (fromId == widget.accountId && type == 'expense') {
          expenses += amount;
        }
      }

      if (!mounted) return;

      setState(() {
        _account = selectedAccount;
        _accounts = accountRows;
        _transactions = relatedTransactions;
        _income = income;
        _expenses = expenses;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load account: $error')),
      );
    }
  }

  String _accountName(int? id) {
    if (id == null) return 'Unknown account';

    for (final item in _accounts) {
      if ((item['id'] as num).toInt() == id) {
        return item['name'].toString();
      }
    }

    return 'Unknown account';
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return value?.toString() ?? '';
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _formatMoney(double amount) {
    final currency = _account?['currency']?.toString() ?? 'PKR';
    return '$currency ${NumberFormat('#,##0.00').format(amount)}';
  }

  Future<void> _editAccount() async {
    final currentAccount = _account;
    if (currentAccount == null) return;

    await showAccountDialog(context, account: currentAccount);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account Details')),
        body: const Center(child: Text('Account not found.')),
      );
    }

    final balance = (_account!['balance'] as num?)?.toDouble() ?? 0;
    final iconCode = _account!['icon_code'] as int? ??
        Icons.account_balance_wallet.codePoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Details'),
        actions: [
          IconButton(
            tooltip: 'Edit Account',
            onPressed: _editAccount,
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFF147D59),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: Colors.white24,
                      child: Icon(
                        IconData(iconCode, fontFamily: 'MaterialIcons'),
                        color: Colors.white,
                        size: 29,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _account!['name'].toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_account!['type']} • ${_account!['currency']}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Current Balance',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _formatMoney(balance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if ((_account!['account_number'] ?? '')
                        .toString()
                        .isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'A/C: ${_account!['account_number']}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                    if ((_account!['exclude_total'] as int? ?? 0) == 1) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Excluded from Total Balance',
                        style: TextStyle(color: Colors.orangeAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Financial Summary',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.trending_up, color: Colors.green),
                          const SizedBox(height: 8),
                          const Text('Total Income'),
                          const SizedBox(height: 5),
                          Text(
                            _formatMoney(_income),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.trending_down, color: Colors.red),
                          const SizedBox(height: 8),
                          const Text('Total Expenses'),
                          const SizedBox(height: 5),
                          Text(
                            _formatMoney(_expenses),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Transaction History',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (_transactions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Center(
                    child: Text('No transactions for this account yet.'),
                  ),
                ),
              )
            else
              ..._transactions.map((item) {
                final type = (item['type'] ?? '').toString().toLowerCase();
                final fromId = (item['account_id'] as num?)?.toInt();
                final toId = (item['to_account_id'] as num?)?.toInt();
                final amount = (item['amount'] as num?)?.toDouble() ?? 0;

                final outgoing =
                    type == 'transfer' && fromId == widget.accountId;
                final incoming =
                    type == 'transfer' && toId == widget.accountId;

                final color = type == 'income'
                    ? Colors.green
                    : type == 'expense'
                        ? Colors.red
                        : Colors.blue;

                final title = outgoing
                    ? 'Transfer to ${_accountName(toId)}'
                    : incoming
                        ? 'Transfer from ${_accountName(fromId)}'
                        : type.isEmpty
                            ? 'Transaction'
                            : type[0].toUpperCase() + type.substring(1);

                final icon = type == 'income'
                    ? Icons.arrow_downward
                    : type == 'expense'
                        ? Icons.arrow_upward
                        : incoming
                            ? Icons.call_received
                            : Icons.call_made;

                final negative = type == 'expense' || outgoing;

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withOpacity(0.12),
                      child: Icon(icon, color: color),
                    ),
                    title: Text(title),
                    subtitle: Text(
                      [
                        if ((item['note'] ?? '').toString().isNotEmpty)
                          item['note'].toString(),
                        _formatDate(item['date']),
                      ].join('\n'),
                    ),
                    isThreeLine:
                        (item['note'] ?? '').toString().isNotEmpty,
                    trailing: Text(
                      '${negative ? '-' : '+'}${NumberFormat('#,##0.00').format(amount)}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
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
                  backgroundColor: color.withOpacity(0.12),
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
    customTypeController.text =
        existingType == 'Custom' ? '' : existingType;
  }

  String currency = account?['currency']?.toString() ?? 'PKR';

  int iconCode = account?['icon_code'] as int? ??
      Icons.account_balance_wallet.codePoint;

  bool excludeTotal =
      (account?['exclude_total'] as int? ?? 0) == 1;

  try {
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
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                if (!isEditing)
                  TextField(
                    controller: balanceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(
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
                        setDialogState(
                          () => iconCode = icon.codePoint,
                        );
                      },
                      borderRadius: BorderRadius.circular(30),
                      child: CircleAvatar(
                        backgroundColor: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade200,
                        child: Icon(
                          icon,
                          color: selected
                              ? Colors.white
                              : Colors.black87,
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
                  controlAffinity:
                      ListTileControlAffinity.leading,
                  onChanged: (value) {
                    setDialogState(
                      () => excludeTotal = value ?? false,
                    );
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

                final balanceText = balanceController.text.trim();
                final balance = double.tryParse(balanceText);

                if (name.isEmpty || accountType.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter account name and account type.',
                      ),
                    ),
                  );
                  return;
                }

                if (!isEditing &&
                    (balance == null ||
                        !balance.isFinite ||
                        balance < 0)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter a valid non-negative opening balance.',
                      ),
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
                      accountNumber:
                          accountNumberController.text.trim(),
                      iconCode: iconCode,
                      excludeTotal: excludeTotal,
                    );
                  } else {
                    await FinanceDB.instance.addAccount(
                      name: name,
                      type: accountType,
                      currency: currency,
                      openingBalance: balance!,
                      accountNumber:
                          accountNumberController.text.trim(),
                      iconCode: iconCode,
                      excludeTotal: excludeTotal,
                    );
                  }

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('Error saving account: $e'),
                      ),
                    );
                  }
                }
              },
              child: Text(
                isEditing ? 'Update Account' : 'Save Account',
              ),
            ),
          ],
        ),
      ),
    );
  } finally {
    nameController.dispose();
    balanceController.dispose();
    accountNumberController.dispose();
    customTypeController.dispose();
  }
}

Future<void> showTransactionDialog(
  BuildContext context, {
  String initialType = 'income',
}) async {
  final accounts = await TransactionService.getAccounts();

  if (!context.mounted) return;

  if (accounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please add an account first.')),
    );
    return;
  }

  String type = initialType.toLowerCase();
  if (!['income', 'expense', 'transfer'].contains(type)) {
    type = 'income';
  }

  int? accountId = accounts.first['id'] as int;
  int? toAccountId;
  int? categoryId;
  DateTime selectedDate = DateTime.now();

  List<FinanceCategory> categories = type == 'transfer'
      ? []
      : await CategoryService.getCategories(type);

  if (!context.mounted) return;

  final amountController = TextEditingController();
  final noteController = TextEditingController();
  bool saving = false;

  try {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, updateDialog) {
            final destinations = accounts
                .where((account) => account['id'] != accountId)
                .toList();

            return AlertDialog(
              title: const Text('Add Transaction'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(
                        labelText: 'Transaction Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'income',
                          child: Text('Income'),
                        ),
                        DropdownMenuItem(
                          value: 'expense',
                          child: Text('Expense'),
                        ),
                        DropdownMenuItem(
                          value: 'transfer',
                          child: Text('Transfer'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) async {
                              if (value == null) return;

                              final newCategories = value == 'transfer'
                                  ? <FinanceCategory>[]
                                  : await CategoryService.getCategories(value);

                              if (!dialogContext.mounted) return;

                              updateDialog(() {
                                type = value;
                                categories = newCategories;
                                categoryId = null;
                                toAccountId = null;
                              });
                            },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      value: accountId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        border: OutlineInputBorder(),
                      ),
                      items: accounts.map((account) {
                        return DropdownMenuItem<int>(
                          value: account['id'] as int,
                          child: Text(
                            '${account['name']} (${account['currency']})',
                          ),
                        );
                      }).toList(),
                      onChanged: saving
                          ? null
                          : (value) {
                              updateDialog(() {
                                accountId = value;
                                if (toAccountId == accountId) {
                                  toAccountId = null;
                                }
                              });
                            },
                    ),
                    if (type == 'transfer') ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        value: toAccountId,
                        isExpanded: true,
                        hint: const Text('Select destination'),
                        decoration: const InputDecoration(
                          labelText: 'Destination Account',
                          border: OutlineInputBorder(),
                        ),
                        items: destinations.map((account) {
                          return DropdownMenuItem<int>(
                            value: account['id'] as int,
                            child: Text(
                              '${account['name']} (${account['currency']})',
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                updateDialog(() {
                                  toAccountId = value;
                                });
                              },
                      ),
                    ],
                    if (type != 'transfer') ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int?>(
                        value: categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('No category'),
                          ),
                          ...categories.map((category) {
                            return DropdownMenuItem<int?>(
                              value: category.id,
                              child: Text(
                                '${category.icon} ${category.name}',
                              ),
                            );
                          }),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                updateDialog(() {
                                  categoryId = value;
                                });
                              },
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Transaction Date'),
                      subtitle: Text(
                        DateFormat('yyyy-MM-dd').format(selectedDate),
                      ),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: saving
                          ? null
                          : () async {
                              final date = await showDatePicker(
                                context: dialogContext,
                                initialDate: selectedDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );

                              if (date != null && dialogContext.mounted) {
                                updateDialog(() {
                                  selectedDate = date;
                                });
                              }
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final amount = double.tryParse(
                            amountController.text.trim(),
                          );

                          if (amount == null ||
                              !amount.isFinite ||
                              amount <= 0) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid amount.'),
                              ),
                            );
                            return;
                          }

                          if (accountId == null) return;

                          if (type == 'transfer' && toAccountId == null) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Select a destination account.',
                                ),
                              ),
                            );
                            return;
                          }

                          updateDialog(() {
                            saving = true;
                          });

                          try {
                            await TransactionService.addTransaction(
                              type: type,
                              amount: amount,
                              accountId: accountId!,
                              toAccountId:
                                  type == 'transfer' ? toAccountId : null,
                              categoryId:
                                  type == 'transfer' ? null : categoryId,
                              note: noteController.text.trim(),
                              date: selectedDate.toIso8601String(),
                            );

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              updateDialog(() {
                                saving = false;
                              });

                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Transaction'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction added successfully.'),
        ),
      );
    }
  } finally {
    amountController.dispose();
    noteController.dispose();
  }
}
