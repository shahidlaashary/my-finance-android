import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

import 'screens/categories_screen.dart';
import 'screens/transactions_screen.dart';
import 'screens/loans_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await FinanceDB.instance.init();

  runApp(const MyFinanceApp());
}

class FinanceDB {
  FinanceDB._();

  static final instance = FinanceDB._();

  Database? _db;

  Database get db => _db!;

  Future<void> init() async {
    final base = await getDatabasesPath();

    _db = await openDatabase(
      p.join(base, 'my_finance.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            currency TEXT NOT NULL DEFAULT 'PKR',
            balance REAL NOT NULL DEFAULT 0,
            exclude_total INTEGER NOT NULL DEFAULT 0
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
    );
  }

  Future<List<Map<String, dynamic>>> accounts() async {
    return db.query(
      'accounts',
      orderBy: 'name ASC',
    );
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
  }) async {
    await db.insert('accounts', {
      'name': name,
      'type': type,
      'currency': currency,
      'balance': openingBalance,
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
          throw Exception(
            'Select a different destination account.',
          );
        }

        final destination = await txn.query(
          'accounts',
          where: 'id = ?',
          whereArgs: [toAccountId],
        );

        if (destination.isEmpty) {
          throw Exception('Destination account not found.');
        }

        if (source.first['currency'] !=
            destination.first['currency']) {
          throw Exception(
            'Transfers between different currencies are not yet supported.',
          );
        }

        final balance =
            (source.first['balance'] as num).toDouble();

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
        final balance =
            (source.first['balance'] as num).toDouble();

        await txn.update(
          'accounts',
          {'balance': balance - amount},
          where: 'id = ?',
          whereArgs: [accountId],
        );
      } else if (type == 'Income') {
        final balance =
            (source.first['balance'] as num).toDouble();

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

  Future<double> totalBalance() async {
    final result = await db.rawQuery(
      '''
      SELECT SUM(balance) AS total
      FROM accounts
      WHERE exclude_total = 0
      ''',
    );

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
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Finance',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
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
          setState(() {
            selectedIndex = value;
          });
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

  String money(double amount) {
    return 'PKR ${NumberFormat('#,##0.00').format(amount)}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<double>>(
      future: Future.wait([
        FinanceDB.instance.totalBalance(),
        FinanceDB.instance.totalByType('Income'),
        FinanceDB.instance.totalByType('Expense'),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final values = snapshot.data!;

        return RefreshIndicator(
          onRefresh: () async {
            onRefresh();
          },
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF147D59),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Balance',
                      style: TextStyle(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      money(values[0]),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'My Finance',
                      style: TextStyle(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      title: 'Income',
                      amount: money(values[1]),
                      icon: Icons.trending_up,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SummaryCard(
                      title: 'Expenses',
                      amount: money(values[2]),
                      icon: Icons.trending_down,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
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
                    onTap: () => showAccountDialog(context),
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
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: FinanceDB.instance.accounts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final accounts = snapshot.data!;

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
                  child: Text(
                    'No accounts yet. Add your first account.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: accounts.length,
                  itemBuilder: (context, index) {
                    final account = accounts[index];

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(
                            Icons.account_balance_wallet,
                          ),
                        ),
                        title: Text(account['name']),
                        subtitle: Text(
                          '${account['type']} • '
                          '${account['currency']}',
                        ),
                        trailing: Text(
                          '${account['currency']} '
                          '${NumberFormat('#,##0.00').format(account['balance'])}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
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
          return const Center(
            child: CircularProgressIndicator(),
          );
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

Future<void> showAccountDialog(BuildContext context) async {
  final nameController = TextEditingController();
  final balanceController = TextEditingController(text: '0');

  String type = 'Cash';
  String currency = 'PKR';

  await showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add Account'),
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
                items: [
                  'Cash',
                  'Bank',
                  'Savings',
                  'Current',
                  'Credit Card',
                  'Debit Card',
                  'Digital Wallet',
                  'Investment',
                  'Other',
                ].map((v) {
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
              DropdownButtonFormField<String>(
                value: currency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                ),
                items: [
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
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() => currency = v);
                  }
                },
              ),
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
              final balance =
                  double.tryParse(balanceController.text) ?? 0;

              if (name.isEmpty || balance < 0) return;

              await FinanceDB.instance.addAccount(
                name: name,
                type: type,
                currency: currency,
                openingBalance: balance,
              );

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  nameController.dispose();
  balanceController.dispose();
}

Future<void> showTransactionDialog(
  BuildContext context, {
  String initialType = 'Expense',
}) async {
  final amountController = TextEditingController();
  final noteController = TextEditingController();

  final accounts = await FinanceDB.instance.accounts();

  if (!context.mounted) return;

  if (accounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please create an account first.'),
      ),
    );

    return;
  }

  String type = initialType;
  int accountId = accounts.first['id'] as int;
  int? destinationId;

  await showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add Transaction'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                ),
                items: [
                  'Income',
                  'Expense',
                  'Transfer',
                ].map((v) {
                  return DropdownMenuItem(
                    value: v,
                    child: Text(v),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() {
                      type = v;
                      destinationId = null;
                    });
                  }
                },
              ),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                ),
              ),
              DropdownButtonFormField<int>(
                value: accountId,
                decoration: const InputDecoration(
                  labelText: 'From account',
                ),
                items: accounts.map((a) {
                  return DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text(a['name']),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() {
                      accountId = v;

                      if (destinationId == accountId) {
                        destinationId = null;
                      }
                    });
                  }
                },
              ),
              if (type == 'Transfer')
                DropdownButtonFormField<int>(
                  value: destinationId,
                  decoration: const InputDecoration(
                    labelText: 'To account',
                  ),
                  items: accounts
                      .where((a) => a['id'] != accountId)
                      .map((a) {
                    return DropdownMenuItem<int>(
                      value: a['id'] as int,
                      child: Text(a['name']),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setDialogState(() {
                      destinationId = v;
                    });
                  },
                ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(
                amountController.text.trim(),
              );

              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid amount.'),
                  ),
                );
                return;
              }

              if (type == 'Transfer' &&
                  destinationId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Select a destination account.',
                    ),
                  ),
                );
                return;
              }

              try {
                await FinanceDB.instance.addTransaction(
                  type: type,
                  amount: amount,
                  accountId: accountId,
                  toAccountId: destinationId,
                  note: noteController.text.trim(),
                );

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  amountController.dispose();
  noteController.dispose();
}
