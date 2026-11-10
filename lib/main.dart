
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';

import 'services/attachment_service.dart';
import 'models/attachment_model.dart';

// ============================================================
// MY FINANCE - PART 1
// Fresh Database + Wallet Management
// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop platforms ke liye SQLite initialize karna.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await FinanceDB.instance.init();

  runApp(const MyFinanceApp());
}

// ============================================================
// APP COLORS
// ============================================================

class AppColors {
  static const Color primary = Color(0xFF147D59);
  static const Color background = Color(0xFFF5F7F6);
  static const Color income = Color(0xFF16865B);
  static const Color expense = Color(0xFFD9534F);
  static const Color text = Color(0xFF202A26);
  static const Color muted = Color(0xFF7B8781);
}

// ============================================================
// DATABASE
// ============================================================

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
      version: 1,
      onCreate: _createDatabase,
    );
  }

  Database get db {
    if (_database == null) {
      throw StateError('Database initialize nahi hua.');
    }
    return _database!;
  }

  Future<void> _createDatabase(Database db, int version) async {
    // Wallets table.
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

    // Transactions table.
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

    // Exchange rates: 1 unit currency ki PKR value.
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

    // PKR app ki main currency hai.
    await db.insert('exchange_rates', {
      'currency': 'PKR',
      'rate': 1.0,
      'updated_at': DateTime.now().toIso8601String(),
    });

    // App ki main currency setting.
    await db.insert('app_settings', {
      'setting_key': 'main_currency',
      'setting_value': 'PKR',
    });
  }

  // ----------------------------------------------------------
  // WALLET DATABASE FUNCTIONS
  // ----------------------------------------------------------

  Future<List<Map<String, dynamic>>> getWallets() {
    return db.query(
      'wallets',
      orderBy: 'name COLLATE NOCASE ASC',
    );
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
  }) {
    return db.insert('wallets', {
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
  }

  // ----------------------------------------------------------
  // EXCHANGE RATE FUNCTIONS
  // ----------------------------------------------------------

  Future<double?> getExchangeRate(String currency) async {
    if (currency == 'PKR') return 1.0;

    final rows = await db.query(
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

  Future<void> saveExchangeRate(
    String currency,
    double rate,
  ) async {
    if (currency == 'PKR' || rate <= 0) {
      throw Exception('Exchange rate durust nahi hai.');
    }

    await db.insert(
      'exchange_rates',
      {
        'currency': currency,
        'rate': rate,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ----------------------------------------------------------
  // WALLET UPDATE
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
  // WALLET DELETE
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
  }

  // ----------------------------------------------------------
  // CONSOLIDATED TOTAL BALANCE
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

// ============================================================
// WALLET OPTIONS
// ============================================================

const List<String> walletTypes = [
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

const List<String> walletCurrencies = [
  'PKR',
  'USD',
  'GBP',
  'EUR',
  'AED',
  'SAR',
  'INR',
];

const List<IconData> walletIcons = [
  Icons.account_balance_wallet_outlined,
  Icons.account_balance_outlined,
  Icons.savings_outlined,
  Icons.credit_card_outlined,
  Icons.money_outlined,
  Icons.phone_android_outlined,
  Icons.trending_up_outlined,
  Icons.attach_money,
  Icons.payments_outlined,
  Icons.wallet_outlined,
];

// ============================================================
// WALLETS PAGE
// ============================================================

class WalletsPage extends StatefulWidget {
  const WalletsPage({super.key});

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

    final result = await FinanceDB.instance.getWallets();

    if (!mounted) return;

    setState(() {
      wallets = result;
      loading = false;
    });
  }

  String formatMoney(double amount, String currency) {
    return '$currency ${NumberFormat('#,##0.00').format(amount)}';
  }

  Future<void> openWalletForm([
    Map<String, dynamic>? wallet,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => WalletFormDialog(wallet: wallet),
    );

    if (saved == true) {
      await loadWallets();
    }
  }

  Future<void> deleteWallet(Map<String, dynamic> wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Wallet?'),
        content: Text(
          'Kya aap "${wallet['name']}" wallet delete karna chahte hain?',
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

    if (confirmed != true) return;

    try {
      await FinanceDB.instance.deleteWallet(wallet['id'] as int);
      await loadWallets();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'My Wallets',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openWalletForm(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Wallet'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : wallets.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 58,
                        color: AppColors.muted,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No wallets added yet',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadWallets,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: wallets.length,
                    itemBuilder: (context, index) {
                      final wallet = wallets[index];

                      final balance =
                          (wallet['balance'] as num).toDouble();
                      final currency = wallet['currency'] as String;
                      final iconCode = wallet['icon_code'] as int;
                      final excluded =
                          (wallet['exclude_total'] as int) == 1;

                      return Card(
                        color: Colors.white,
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.10),
                            child: Icon(
                              IconData(
                                iconCode,
                                fontFamily: 'MaterialIcons',
                              ),
                              color: AppColors.primary,
                            ),
                          ),
                          title: Text(
                            wallet['name'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                wallet['type'] == 'Custom'
                                    ? (wallet['custom_type'] ?? 'Custom')
                                    : wallet['type'] as String,
                              ),
                              if (excluded)
                                const Text(
                                  'Excluded from Total Balance',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formatMoney(balance, currency),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text(
                                    'Current Balance',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    openWalletForm(wallet);
                                  } else if (value == 'delete') {
                                    deleteWallet(wallet);
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
                    },
                  ),
                ),
    );
  }
}

// ============================================================
// ADD / EDIT WALLET FORM
// ============================================================

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

  late final TextEditingController nameController;
  late final TextEditingController customTypeController;
  late final TextEditingController openingController;
  late final TextEditingController currentController;
  late final TextEditingController numberController;

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
      text: wallet?['name'] as String? ?? '',
    );

    customTypeController = TextEditingController(
      text: wallet?['custom_type'] as String? ?? '',
    );

    openingController = TextEditingController(
      text: (wallet?['opening_balance'] ?? 0).toString(),
    );

    currentController = TextEditingController(
      text: (wallet?['balance'] ?? 0).toString(),
    );

    numberController = TextEditingController(
      text: wallet?['wallet_number'] as String? ?? '',
    );

    selectedType = wallet?['type'] as String? ?? 'Cash';
    selectedCurrency = wallet?['currency'] as String? ?? 'PKR';

    if (!walletTypes.contains(selectedType)) selectedType = 'Other';
    if (!walletCurrencies.contains(selectedCurrency)) {
      selectedCurrency = 'PKR';
    }

    selectedIcon = wallet?['icon_code'] as int? ??
        walletIcons.first.codePoint;

    excludeTotal = (wallet?['exclude_total'] as int? ?? 0) == 1;
  }

  @override
  void dispose() {
    nameController.dispose();
    customTypeController.dispose();
    openingController.dispose();
    currentController.dispose();
    numberController.dispose();
    super.dispose();
  }

  double readAmount(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  Future<void> saveWallet() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      if (isEditing) {
        await FinanceDB.instance.updateWallet(
          id: widget.wallet!['id'] as int,
          name: nameController.text,
          type: selectedType,
          customType: selectedType == 'Custom'
              ? customTypeController.text.trim()
              : null,
          currency: selectedCurrency,
          requestedCurrentBalance: readAmount(currentController),
          walletNumber: numberController.text.trim().isEmpty
              ? null
              : numberController.text.trim(),
          iconCode: selectedIcon,
          excludeTotal: excludeTotal,
        );
      } else {
        await FinanceDB.instance.addWallet(
          name: nameController.text,
          type: selectedType,
          customType: selectedType == 'Custom'
              ? customTypeController.text.trim()
              : null,
          currency: selectedCurrency,
          openingBalance: readAmount(openingController),
          walletNumber: numberController.text.trim().isEmpty
              ? null
              : numberController.text.trim(),
          iconCode: selectedIcon,
          excludeTotal: excludeTotal,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );

      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEditing ? 'Edit Wallet' : 'Add Wallet'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Wallet Name',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Wallet name zaroori hai.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

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

                if (selectedType == 'Custom') ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: customTypeController,
                    decoration: const InputDecoration(
                      labelText: 'Custom Wallet Type',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (selectedType == 'Custom' &&
                          (value == null || value.trim().isEmpty)) {
                        return 'Custom type likhein.';
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  value: selectedCurrency,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    border: OutlineInputBorder(),
                  ),
                  items: walletCurrencies.map((currency) {
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

                const SizedBox(height: 14),

                if (!isEditing)
                  TextFormField(
                    controller: openingController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Opening Balance',
                      helperText: 'Wallet shuru karte waqt ki amount.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          double.tryParse(value.trim()) == null) {
                        return 'Valid amount enter karein.';
                      }
                      return null;
                    },
                  ),

                if (isEditing)
                  TextFormField(
                    controller: currentController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Current Balance',
                      helperText:
                          'Change karne par adjustment history mein save hoga.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          double.tryParse(value.trim()) == null) {
                        return 'Valid amount enter karein.';
                      }
                      return null;
                    },
                  ),

                const SizedBox(height: 14),

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
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: walletIcons.map((icon) {
                    final selected = selectedIcon == icon.codePoint;

                    return InkWell(
                      onTap: () {
                        setState(() => selectedIcon = icon.codePoint);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 1.5,
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

                const SizedBox(height: 14),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Exclude from Total Balance'),
                  subtitle: const Text(
                    'Wallet apni jagah rahega, lekin dashboard total mein '
                    'shamil nahi hoga.',
                  ),
                  value: excludeTotal,
                  activeTrackColor: AppColors.primary,
                  onChanged: (value) {
                    setState(() => excludeTotal = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : saveWallet,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
          ),
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isEditing ? 'Save Changes' : 'Create Wallet'),
        ),
      ],
    );
  }
}

// ============================================================
// PART 2: APP THEME, NAVIGATION AUR HOME DASHBOARD
// ============================================================

// ------------------------------------------------------------
// MAIN APP
// ------------------------------------------------------------

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
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.text,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ------------------------------------------------------------
// MAIN SCREEN AND BOTTOM NAVIGATION
// ------------------------------------------------------------

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;

  final List<Widget> pages = const [
    HomePage(),
    AssetsPage(),
    LoansPage(),
    TransactionsPage(),
    WalletsPage(),
  ];

  // Plus button ek modal bottom sheet open karta hai.
  Future<void> openPlusSheet() async {
    final selectedType = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return const PlusActionSheet();
      },
    );

    if (!mounted || selectedType == null) return;

    // Sheet band hone ke baad transaction form open hota hai.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEntryForm(
          transactionType: selectedType,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void selectNavigation(int index) {
    if (index == 5) {
      openPlusSheet();
      return;
    }

    setState(() => selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
  top: false,
  child: Container(
    height: 72,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(
        top: BorderSide(color: Color(0xFFE9EEEB)),
      ),
    ),
    child: Row(
      children: [
        _navItem(0, Icons.home_outlined, 'Home'),
        _navItem(1, Icons.real_estate_agent_outlined, 'Assets'),
        _navItem(2, Icons.handshake_outlined, 'Loans'),
        _navItem(3, Icons.receipt_long_outlined, 'Txns'),
        _navItem(4, Icons.account_balance_wallet_outlined, 'Wallets'),
        _navItem(5, Icons.add_circle_outline, 'Plus'),
      ],
    ),
  ),
),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
  final selected = selectedIndex == index;
  final isPlus = index == 5;

  return Expanded(
    child: InkWell(
      onTap: () => selectNavigation(index),
      child: SizedBox(
        height: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: isPlus ? 27 : 24,
                color: selected || isPlus
                    ? AppColors.primary
                    : AppColors.muted,
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: selected || isPlus
                          ? AppColors.primary
                          : AppColors.muted,
                    ),
                  ),
                ),
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
// PLUS BOTTOM SHEET
// ------------------------------------------------------------

class PlusActionSheet extends StatelessWidget {
  const PlusActionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Add Transaction',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _actionTile(
            context,
            'Income',
            'Record money received',
            Icons.arrow_downward_rounded,
            AppColors.income,
          ),
          _actionTile(
            context,
            'Expense',
            'Record money spent',
            Icons.arrow_upward_rounded,
            AppColors.expense,
          ),
          _actionTile(
            context,
            'Transfer',
            'Move money between wallets',
            Icons.swap_horiz_rounded,
            AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _actionTile(
    BuildContext context,
    String type,
    String description,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(context, type),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.13),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// HOME DASHBOARD
// ------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String selectedPeriod = 'Monthly';

  double totalBalance = 0;
  double income = 0;
  double expenses = 0;
  bool loading = true;

  List<Map<String, dynamic>> expenseCategories = [];

  final List<String> periods = [
    'Daily',
    'Weekly',
    'Monthly',
    'Yearly',
    'All Time',
  ];

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  // Selected period ke mutabiq transactions ka date filter.
  DateTime? getPeriodStart() {
    final now = DateTime.now();

    switch (selectedPeriod) {
      case 'Daily':
        return DateTime(now.year, now.month, now.day);
      case 'Weekly':
        return DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
      case 'Monthly':
        return DateTime(now.year, now.month, 1);
      case 'Yearly':
        return DateTime(now.year, 1, 1);
      case 'All Time':
        return null;
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  Future<void> loadDashboard() async {
    setState(() => loading = true);

    final db = FinanceDB.instance.db;

    // Total Balance selected period se independent hota hai.
    final balance = await FinanceDB.instance.getTotalBalancePKR();

    final start = getPeriodStart();

    String dateCondition = '';
    List<dynamic> dateArgs = [];

    if (start != null) {
      dateCondition = 'AND date >= ?';
      dateArgs = [start.toIso8601String()];
    }

    final incomeRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM transactions
      WHERE type = 'Income' $dateCondition
      ''',
      dateArgs,
    );

    final expenseRows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM transactions
      WHERE type = 'Expense' $dateCondition
      ''',
      dateArgs,
    );

    final categoryRows = await db.rawQuery(
      '''
      SELECT category, SUM(amount) AS total
      FROM transactions
      WHERE type = 'Expense' $dateCondition
      GROUP BY category
      ORDER BY total DESC
      ''',
      dateArgs,
    );

    if (!mounted) return;

    setState(() {
      totalBalance = balance;
      income = (incomeRows.first['total'] as num).toDouble();
      expenses = (expenseRows.first['total'] as num).toDouble();
      expenseCategories = categoryRows;
      loading = false;
    });
  }

  String formatPKR(double amount) {
    return 'PKR ${NumberFormat('#,##0.00').format(amount)}';
  }

  Future<void> openMoreFeatures() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MoreFeaturesPage(),
      ),
    );

    if (mounted) loadDashboard();
  }

  Future<void> openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NotificationsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final netChange = income - expenses;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'My Finance',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: openNotifications,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'More Features',
            onPressed: openMoreFeatures,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadDashboard,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  // Consolidated Total Balance.
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF147D59),
                          Color(0xFF0C5B42),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Balance',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 9),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatPKR(totalBalance),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 29,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Consolidated wallet balance',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Period selector.
                  const Text(
                    'Financial Overview',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),

                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: periods.map((period) {
                        final selected = selectedPeriod == period;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(period),
                            selected: selected,
                            onSelected: (_) {
                              setState(() => selectedPeriod = period);
                              loadDashboard();
                            },
                            selectedColor: AppColors.primary,
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? Colors.white
                                  : AppColors.text,
                              fontWeight: FontWeight.w600,
                            ),
                            backgroundColor: Colors.white,
                            side: BorderSide.none,
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Income and Expense summary.
                  Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          'Income',
                          income,
                          AppColors.income,
                          Icons.south_west_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _summaryCard(
                          'Expenses',
                          expenses,
                          AppColors.expense,
                          Icons.north_east_rounded,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Financial overview chart.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Income vs Expenses',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 150,
                            width: double.infinity,
                            child: FinanceOverviewChart(
                              income: income,
                              expenses: expenses,
                            ),
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Net Change',
                                style: TextStyle(
                                  color: AppColors.muted,
                                ),
                              ),
                              Text(
                                formatPKR(netChange),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: netChange >= 0
                                      ? AppColors.income
                                      : AppColors.expense,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Expense structure.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Expenses Structure',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (expenseCategories.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 15),
                              child: Center(
                                child: Text(
                                  'No expenses in this period.',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...expenseCategories.take(5).map((item) {
                              final category =
                                  item['category'] as String? ?? 'Other';
                              final amount =
                                  (item['total'] as num).toDouble();
                              final ratio = expenses <= 0
                                  ? 0.0
                                  : (amount / expenses).clamp(0.0, 1.0);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            category,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          formatPKR(amount),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 7),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: ratio,
                                        minHeight: 7,
                                        backgroundColor:
                                            AppColors.background,
                                        color: AppColors.expense,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // More details button.
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SimpleFeaturePage(
                            title: 'Financial Details',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('Show More Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(
    String title,
    double amount,
    Color color,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatPKR(amount),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// FINANCIAL OVERVIEW CHART
// ------------------------------------------------------------

class FinanceOverviewChart extends StatelessWidget {
  final double income;
  final double expenses;

  const FinanceOverviewChart({
    super.key,
    required this.income,
    required this.expenses,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue = [
      income,
      expenses,
      1.0,
    ].reduce((a, b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _bar(
          'Income',
          income,
          maxValue,
          AppColors.income,
        ),
        const SizedBox(width: 45),
        _bar(
          'Expenses',
          expenses,
          maxValue,
          AppColors.expense,
        ),
      ],
    );
  }

  Widget _bar(
    String label,
    double amount,
    double maxValue,
    Color color,
  ) {
    final barHeight = (amount / maxValue * 95).clamp(4.0, 95.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          NumberFormat.compact().format(amount),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: 48,
          height: barHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(9),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------
// BASIC FEATURE SCREENS
// Part 3 mein TransactionsPage complete implement hogi.
// ------------------------------------------------------------

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleFeaturePage(title: 'Assets');
  }
}

class LoansPage extends StatelessWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleFeaturePage(title: 'Loans');
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleFeaturePage(title: 'Notifications');
  }
}

class MoreFeaturesPage extends StatelessWidget {
  const MoreFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final features = [
      'Budgets',
      'Categories',
      'Recurring Transactions',
      'Reports & Analytics',
      'Savings Goals',
      'Exchange Rates',
      'Settings',
      'Backup & Restore',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More Features')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: features.map((feature) {
          return Card(
            child: ListTile(
              title: Text(feature),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SimpleFeaturePage(title: feature),
                  ),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SimpleFeaturePage extends StatelessWidget {
  final String title;

  const SimpleFeaturePage({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.construction_outlined,
                size: 55,
                color: AppColors.primary,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This feature will be implemented in a later development step.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PART 3: TRANSACTION DATABASE FUNCTIONS
// ============================================================

extension FinanceTransactionFunctions on FinanceDB {
  // Transaction save karke us ka ID return karna.
  // Isi ID ke saath photos aur documents link honge.
  Future<int> addTransaction({
    required String type,
    required double amount,
    required int walletId,
    int? toWalletId,
    double? toAmount,
    required String category,
    required String note,
    required DateTime date,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount zero se zyada honi chahiye.');
    }

    return db.transaction((txn) async {
      final sourceRows = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
        limit: 1,
      );

      if (sourceRows.isEmpty) {
        throw Exception('Selected wallet nahi mila.');
      }

      final sourceWallet = sourceRows.first;
      final sourceBalance =
          (sourceWallet['balance'] as num).toDouble();

      int? destinationId;
      double? finalDestinationAmount;
      double? exchangeRate;

      if (type == 'Income') {
        await txn.update(
          'wallets',
          {'balance': sourceBalance + amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      } else if (type == 'Expense') {
        await txn.update(
          'wallets',
          {'balance': sourceBalance - amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );
      } else if (type == 'Transfer') {
        if (toWalletId == null || toWalletId == walletId) {
          throw Exception('Doosra wallet select karein.');
        }

        final destinationRows = await txn.query(
          'wallets',
          where: 'id = ?',
          whereArgs: [toWalletId],
          limit: 1,
        );

        if (destinationRows.isEmpty) {
          throw Exception('Destination wallet nahi mila.');
        }

        final destinationWallet = destinationRows.first;
        final destinationBalance =
            (destinationWallet['balance'] as num).toDouble();

        finalDestinationAmount = toAmount ?? amount;

        if (finalDestinationAmount <= 0) {
          throw Exception('Transfer amount durust nahi.');
        }

        destinationId = toWalletId;
        exchangeRate = finalDestinationAmount / amount;

        await txn.update(
          'wallets',
          {'balance': sourceBalance - amount},
          where: 'id = ?',
          whereArgs: [walletId],
        );

        await txn.update(
          'wallets',
          {'balance': destinationBalance + finalDestinationAmount},
          where: 'id = ?',
          whereArgs: [toWalletId],
        );
      } else {
        throw Exception('Transaction type durust nahi.');
      }

      final now = DateTime.now().toIso8601String();

      return txn.insert('transactions', {
        'type': type,
        'amount': amount,
        'wallet_id': walletId,
        'to_wallet_id': destinationId,
        'to_amount': finalDestinationAmount,
        'exchange_rate': exchangeRate,
        'balance_delta': null,
        'category': category,
        'note': note,
        'date': date.toIso8601String(),
        'created_at': now,
      });
    });
  }

  // Transaction delete karte waqt wallet balances reverse karna.
  Future<void> deleteTransaction(int id) async {
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return;

    final transaction = rows.first;

    await db.transaction((txn) async {
      final type = transaction['type'] as String;
      final amount = (transaction['amount'] as num).toDouble();
      final walletId = transaction['wallet_id'] as int;

      final sourceRows = await txn.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
        limit: 1,
      );

      if (sourceRows.isNotEmpty) {
        final balance =
            (sourceRows.first['balance'] as num).toDouble();

        if (type == 'Income') {
          await txn.update(
            'wallets',
            {'balance': balance - amount},
            where: 'id = ?',
            whereArgs: [walletId],
          );
        } else if (type == 'Expense') {
          await txn.update(
            'wallets',
            {'balance': balance + amount},
            where: 'id = ?',
            whereArgs: [walletId],
          );
        } else if (type == 'Adjustment') {
          final delta =
              (transaction['balance_delta'] as num?)?.toDouble() ?? 0;

          await txn.update(
            'wallets',
            {'balance': balance - delta},
            where: 'id = ?',
            whereArgs: [walletId],
          );
        } else if (type == 'Transfer') {
          await txn.update(
            'wallets',
            {'balance': balance + amount},
            where: 'id = ?',
            whereArgs: [walletId],
          );
        }
      }

      if (type == 'Transfer') {
        final destinationId = transaction['to_wallet_id'] as int?;
        final destinationAmount =
            (transaction['to_amount'] as num?)?.toDouble() ?? amount;

        if (destinationId != null) {
          final destinationRows = await txn.query(
            'wallets',
            where: 'id = ?',
            whereArgs: [destinationId],
            limit: 1,
          );

          if (destinationRows.isNotEmpty) {
            final balance =
                (destinationRows.first['balance'] as num).toDouble();

            await txn.update(
              'wallets',
              {'balance': balance - destinationAmount},
              where: 'id = ?',
              whereArgs: [destinationId],
            );
          }
        }
      }

      await txn.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    // Database record delete hone ke baad uski attachments delete karna.
    await AttachmentService.deleteOwnerAttachments(
  ownerType: AttachmentOwnerTypes.transaction,
  ownerId: id,
);
  }

  Future<List<Map<String, dynamic>>> getTransactions() {
    return db.query(
      'transactions',
      orderBy: 'date DESC, id DESC',
    );
  }
}

// ============================================================
// TEMPORARY ATTACHMENT MODEL
// ============================================================

class PendingAttachment {
  final String path;
  final String name;
  final bool isImage;

  const PendingAttachment({
    required this.path,
    required this.name,
    required this.isImage,
  });
}

// ============================================================
// ADD TRANSACTION FORM
// ============================================================

class TransactionEntryForm extends StatefulWidget {
  final String transactionType;

  const TransactionEntryForm({
    super.key,
    required this.transactionType,
  });

  @override
  State<TransactionEntryForm> createState() =>
      _TransactionEntryFormState();
}

class _TransactionEntryFormState extends State<TransactionEntryForm> {
  final formKey = GlobalKey<FormState>();

  final amountController = TextEditingController();
  final categoryController = TextEditingController();
  final noteController = TextEditingController();

  final ImagePicker imagePicker = ImagePicker();

  List<Map<String, dynamic>> wallets = [];
  List<PendingAttachment> selectedAttachments = [];

  int? selectedWalletId;
  int? selectedDestinationId;

  DateTime selectedDate = DateTime.now();

  bool loading = true;
  bool saving = false;

  double? destinationAmount;
  String? currencyWarning;

  bool get isTransfer => widget.transactionType == 'Transfer';

  @override
  void initState() {
    super.initState();
    loadWallets();

    amountController.addListener(updateTransferPreview);
  }

  @override
  void dispose() {
    amountController.removeListener(updateTransferPreview);
    amountController.dispose();
    categoryController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> loadWallets() async {
    final result = await FinanceDB.instance.getWallets();

    if (!mounted) return;

    setState(() {
      wallets = result;
      loading = false;

      if (wallets.isNotEmpty) {
        selectedWalletId = wallets.first['id'] as int;

        if (wallets.length > 1) {
          selectedDestinationId = wallets[1]['id'] as int;
        }
      }
    });

    await updateTransferPreview();
  }

  Map<String, dynamic>? get sourceWallet {
    for (final wallet in wallets) {
      if (wallet['id'] == selectedWalletId) return wallet;
    }
    return null;
  }

  Map<String, dynamic>? get destinationWallet {
    for (final wallet in wallets) {
      if (wallet['id'] == selectedDestinationId) return wallet;
    }
    return null;
  }

  // Cross-currency transfer ka destination amount calculate karna.
  Future<void> updateTransferPreview() async {
    if (!isTransfer || !mounted) return;

    final amount = double.tryParse(amountController.text) ?? 0;
    final source = sourceWallet;
    final destination = destinationWallet;

    if (source == null || destination == null || amount <= 0) {
      setState(() {
        destinationAmount = null;
        currencyWarning = null;
      });
      return;
    }

    final sourceCurrency = source['currency'] as String;
    final destinationCurrency = destination['currency'] as String;

    if (sourceCurrency == destinationCurrency) {
      setState(() {
        destinationAmount = amount;
        currencyWarning = null;
      });
      return;
    }

    final sourceRate =
        await FinanceDB.instance.getExchangeRate(sourceCurrency);
    final destinationRate =
        await FinanceDB.instance.getExchangeRate(destinationCurrency);

    if (!mounted) return;

    if (sourceRate == null || destinationRate == null) {
      setState(() {
        destinationAmount = null;
        currencyWarning =
            'Transfer ke liye dono currencies ke exchange rates set karein.';
      });
      return;
    }

    setState(() {
      destinationAmount = amount * sourceRate / destinationRate;
      currencyWarning = null;
    });
  }

  // Camera se photo lena.
  Future<void> takePhoto() async {
    try {
      final image = await imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image == null || !mounted) return;

      setState(() {
        selectedAttachments.add(
          PendingAttachment(
            path: image.path,
            name: image.name,
            isImage: true,
          ),
        );
      });
    } catch (e) {
      showMessage('Camera open nahi ho saka: $e');
    }
  }

  // Gallery se multiple photos select karna.
  Future<void> pickGalleryPhotos() async {
    try {
      final images = await imagePicker.pickMultiImage(
        imageQuality: 85,
      );

      if (!mounted || images.isEmpty) return;

      setState(() {
        selectedAttachments.addAll(
          images.map(
            (image) => PendingAttachment(
              path: image.path,
              name: image.name,
              isImage: true,
            ),
          ),
        );
      });
    } catch (e) {
      showMessage('Gallery se photos select nahi ho sake: $e');
    }
  }

  // File manager se PDF aur documents select karna.
  Future<void> pickDocuments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'txt',
          'csv',
        ],
      );

      if (result == null || !mounted) return;

      final newFiles = <PendingAttachment>[];

      for (final file in result.files) {
        final path = file.path;

        if (path == null) continue;

        newFiles.add(
          PendingAttachment(
            path: path,
            name: file.name,
            isImage: false,
          ),
        );
      }

      setState(() {
        selectedAttachments.addAll(newFiles);
      });
    } catch (e) {
      showMessage('Documents select nahi ho sake: $e');
    }
  }

  void showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take Photo'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    takePhoto();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    pickGalleryPhotos();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: const Text('Choose PDF or Document'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    pickDocuments();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String formatAmount(double amount, String currency) {
    return '$currency ${NumberFormat('#,##0.00').format(amount)}';
  }

  // Transaction save karna aur us ke baad attachments link karna.
  Future<void> saveTransaction() async {
    if (!formKey.currentState!.validate()) return;

    if (selectedWalletId == null) {
      showMessage('Pehle wallet select karein.');
      return;
    }

    if (isTransfer) {
      if (selectedDestinationId == null ||
          selectedDestinationId == selectedWalletId) {
        showMessage('Doosra destination wallet select karein.');
        return;
      }

      if (destinationAmount == null) {
        showMessage(
          currencyWarning ?? 'Transfer amount calculate nahi ho saka.',
        );
        return;
      }
    }

    final amount = double.parse(amountController.text.trim());

    setState(() => saving = true);

    try {
      final transactionId =
          await FinanceDB.instance.addTransaction(
        type: widget.transactionType,
        amount: amount,
        walletId: selectedWalletId!,
        toWalletId: isTransfer ? selectedDestinationId : null,
        toAmount: isTransfer ? destinationAmount : null,
        category: categoryController.text.trim().isEmpty
            ? (isTransfer ? 'Transfer' : 'Other')
            : categoryController.text.trim(),
        note: noteController.text.trim(),
        date: selectedDate,
      );

      int savedAttachments = 0;
      int failedAttachments = 0;

      // Pehle transaction save hota hai, phir attachments us ID se link.
      for (final attachment in selectedAttachments) {
        try {
          await AttachmentService.addAttachment(
            ownerType: AttachmentOwnerTypes.transaction,
            ownerId: transactionId,
            sourcePath: attachment.path,
            originalFileName: attachment.name,
          );
          savedAttachments++;
        } catch (_) {
          failedAttachments++;
        }
      }

      if (!mounted) return;

      String message = 'Transaction saved successfully.';

      if (failedAttachments > 0) {
        message +=
            ' $savedAttachments attachments saved; '
            '$failedAttachments attachments failed.';
      } else if (savedAttachments > 0) {
        message += ' $savedAttachments attachments saved.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      Navigator.pop(context, true);
    } catch (e) {
      showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );

      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.transactionType;

    final typeColor = type == 'Income'
        ? AppColors.income
        : type == 'Expense'
            ? AppColors.expense
            : AppColors.primary;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Add $type'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : wallets.isEmpty
              ? const Center(
                  child: Text('Pehle Wallets tab mein wallet banayein.'),
                )
              : Form(
                  key: formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              Icon(
                                type == 'Income'
                                    ? Icons.arrow_downward_rounded
                                    : type == 'Expense'
                                        ? Icons.arrow_upward_rounded
                                        : Icons.swap_horiz_rounded,
                                size: 32,
                                color: typeColor,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Amount',
                                style: TextStyle(
                                  color: typeColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextFormField(
                                controller: amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '0.00',
                                  border: InputBorder.none,
                                ),
                                validator: (value) {
                                  final amount =
                                      double.tryParse(value ?? '');

                                  if (amount == null || amount <= 0) {
                                    return 'Valid amount enter karein.';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      DropdownButtonFormField<int>(
                        value: selectedWalletId,
                        decoration: const InputDecoration(
                          labelText: 'From Wallet',
                          border: OutlineInputBorder(),
                          prefixIcon:
                              Icon(Icons.account_balance_wallet_outlined),
                        ),
                        items: wallets.map((wallet) {
                          return DropdownMenuItem<int>(
                            value: wallet['id'] as int,
                            child: Text(
                              '${wallet['name']} (${wallet['currency']})',
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => selectedWalletId = value);
                          updateTransferPreview();
                        },
                      ),

                      if (isTransfer) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          value: selectedDestinationId,
                          decoration: const InputDecoration(
                            labelText: 'To Wallet',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.account_balance_outlined),
                          ),
                          items: wallets
                              .where(
                                (wallet) =>
                                    wallet['id'] != selectedWalletId,
                              )
                              .map((wallet) {
                            return DropdownMenuItem<int>(
                              value: wallet['id'] as int,
                              child: Text(
                                '${wallet['name']} (${wallet['currency']})',
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(
                              () => selectedDestinationId = value,
                            );
                            updateTransferPreview();
                          },
                        ),

                        if (destinationAmount != null &&
                            destinationWallet != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Card(
                              color: AppColors.primary.withValues(
                                alpha: 0.07,
                              ),
                              child: ListTile(
                                title: const Text(
                                  'Destination Amount',
                                  style: TextStyle(fontSize: 12),
                                ),
                                subtitle: Text(
                                  formatAmount(
                                    destinationAmount!,
                                    destinationWallet!['currency'] as String,
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (currencyWarning != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              currencyWarning!,
                              style: const TextStyle(
                                color: AppColors.expense,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],

                      const SizedBox(height: 14),

                      if (!isTransfer)
                        TextFormField(
                          controller: categoryController,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                        ),

                      const SizedBox(height: 14),

                      TextFormField(
                        controller: noteController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Note (Optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.calendar_month_outlined,
                            color: AppColors.primary,
                          ),
                          title: const Text('Transaction Date'),
                          subtitle: Text(
                            DateFormat('dd MMM yyyy').format(selectedDate),
                          ),
                          trailing: const Icon(Icons.edit_calendar_outlined),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );

                            if (picked != null) {
                              setState(() => selectedDate = picked);
                            }
                          },
                        ),
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Attachments',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: showAttachmentOptions,
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                          ),
                        ],
                      ),

                      if (selectedAttachments.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFE5EAE7),
                            ),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.attach_file,
                                color: AppColors.muted,
                                size: 30,
                              ),
                              SizedBox(height: 7),
                              Text(
                                'Photos or documents attach karein',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...List.generate(
                          selectedAttachments.length,
                          (index) {
                            final attachment =
                                selectedAttachments[index];

                            return Card(
                              child: ListTile(
                                leading: attachment.isImage
                                    ? ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        child: Image.file(
                                          File(attachment.path),
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.picture_as_pdf_outlined,
                                        color: AppColors.expense,
                                        size: 32,
                                      ),
                                title: Text(
                                  attachment.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  attachment.isImage ? 'Image' : 'Document',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Remove attachment',
                                  icon: const Icon(
                                    Icons.close,
                                    color: AppColors.expense,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      selectedAttachments.removeAt(index);
                                    });
                                  },
                                ),
                              ),
                            );
                          },
                        ),

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: saving ? null : saveTransaction,
                          style: FilledButton.styleFrom(
                            backgroundColor: typeColor,
                          ),
                          child: saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'Save $type',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ============================================================
// TRANSACTIONS HISTORY PAGE
// ============================================================

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

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

    final result = await FinanceDB.instance.getTransactions();

    if (!mounted) return;

    setState(() {
      transactions = result;
      loading = false;
    });
  }

  String money(double amount, String currency) {
    return '$currency ${NumberFormat('#,##0.00').format(amount)}';
  }

  Future<void> deleteTransaction(
    Map<String, dynamic> transaction,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text(
          'Is transaction ko delete karne par wallet balance bhi reverse '
          'ho jayega aur linked attachments bhi delete hongi.',
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

    if (confirmed != true) return;

    try {
      await FinanceDB.instance.deleteTransaction(
        transaction['id'] as int,
      );

      await loadTransactions();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction deleted.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Transactions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : transactions.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 55,
                        color: AppColors.muted,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No transactions yet',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadTransactions,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final transaction = transactions[index];

                      final type = transaction['type'] as String;
                      final amount =
                          (transaction['amount'] as num).toDouble();
                      final date = DateTime.tryParse(
                            transaction['date'] as String,
                          ) ??
                          DateTime.now();

                      final walletId =
                          transaction['wallet_id'] as int;

                      final color = type == 'Income'
                          ? AppColors.income
                          : type == 'Expense'
                              ? AppColors.expense
                              : AppColors.primary;

                      final icon = type == 'Income'
                          ? Icons.arrow_downward_rounded
                          : type == 'Expense'
                              ? Icons.arrow_upward_rounded
                              : type == 'Transfer'
                                  ? Icons.swap_horiz_rounded
                                  : Icons.tune_rounded;

                      return FutureBuilder<Map<String, dynamic>?>(
                        future: FinanceDB.instance.getWallet(walletId),
                        builder: (context, walletSnapshot) {
                          final wallet = walletSnapshot.data;
                          final currency =
                              wallet?['currency'] as String? ?? 'PKR';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        color.withValues(alpha: 0.12),
                                    child: Icon(icon, color: color),
                                  ),
                                  title: Text(
                                    transaction['category'] as String? ??
                                        type,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$type • ${DateFormat('dd MMM yyyy').format(date)}',
                                      ),
                                      if ((transaction['note'] as String?)
                                              ?.isNotEmpty ==
                                          true)
                                        Text(
                                          transaction['note'] as String,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        money(amount, currency),
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'delete') {
                                            deleteTransaction(transaction);
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Transaction ke linked attachments.
                                FutureBuilder<List<AttachmentModel>>(
                                  future: AttachmentService
                                      .getTransactionAttachments(
                                    transaction['id'] as int,
                                  ),
                                  builder: (context, snapshot) {
                                    final attachments =
                                        snapshot.data ?? [];

                                    if (attachments.isEmpty) {
                                      return const SizedBox.shrink();
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        12,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: attachments.map((item) {
                                            final isImage =
                                                item.fileType
                                                    .toLowerCase()
                                                    .contains('image');

                                            return ActionChip(
                                              avatar: Icon(
                                                isImage
                                                    ? Icons.image_outlined
                                                    : Icons
                                                        .description_outlined,
                                                size: 17,
                                              ),
                                              label: SizedBox(
                                                width: 130,
                                                child: Text(
                                                  item.fileName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              onPressed: () async {
                                                await OpenFilex.open(
                                                  item.filePath,
                                                );
                                              },
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
