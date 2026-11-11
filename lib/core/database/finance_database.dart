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

// ============================================================
// Wallet ke options
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
  Icons.business_center_outlined,
  Icons.shopping_bag_outlined,
  Icons.currency_exchange_outlined,
  Icons.home_work_outlined,
  Icons.storefront_outlined,
  Icons.local_atm_outlined,
];

// ============================================================
// Wallets ka safha
// ============================================================

class _WalletWavePainter extends CustomPainter {
  final Color color;
  const _WalletWavePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    Path wave(double offset) => Path()
      ..moveTo(0, size.height * 0.30 + offset)
      ..quadraticBezierTo(size.width * 0.28, -size.height * 0.08 - offset, size.width * 0.52, size.height * 0.38)
      ..quadraticBezierTo(size.width * 0.78, size.height * 0.88 + offset, size.width, size.height * 0.20)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wave(2), Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawPath(wave(0), Paint()..color = color.withValues(alpha: 0.55));
    canvas.drawPath(wave(-2), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WalletWavePainter oldDelegate) => oldDelegate.color != color;
}

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
    // Wallet ka form aik behtar bottom sheet mein kholta hai.
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
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
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: const Text(
          'My Wallets',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        actions: _sharedAppBarActions(context),
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
                        color: AppColors.primary,
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
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.92,
                    ),
                    itemCount: wallets.length,
                    itemBuilder: (context, index) {
                      final wallet = wallets[index];
                      final balance = (wallet['balance'] as num).toDouble();
                      final currency = wallet['currency'] as String;
                      final iconCode = wallet['icon_code'] as int;
                      final walletType = (wallet['type'] as String?) ?? 'Wallet';
                      final excluded = (wallet['exclude_total'] as int) == 1;

                      return Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE5ECE8)),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0, right: 0, bottom: 0, height: 52,
                              child: CustomPaint(
                                painter: _WalletWavePainter(AppColors.primary),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 6, 4, 7),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 29, height: 29,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(9),
                                        ),
                                        child: Icon(IconData(iconCode, fontFamily: 'MaterialIcons'),
                                            color: AppColors.primary, size: 17),
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(wallet['name'] as String,
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 10.5,
                                                fontWeight: FontWeight.w800, color: AppColors.text)),
                                            const SizedBox(height: 2),
                                            Text(walletType, maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 9,
                                                fontWeight: FontWeight.w700, color: AppColors.primary)),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 22,
                                        child: PopupMenuButton<String>(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 145),
                                          icon: const Icon(Icons.more_vert_rounded),
                                          iconSize: 17,
                                        onSelected: (value) {
                                          if (value == 'edit') openWalletForm(wallet);
                                          else if (value == 'delete') deleteWallet(wallet);
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'edit', child: Row(children: [
                                            Icon(Icons.edit_outlined, size: 18), SizedBox(width: 9), Text('Edit Wallet')])),
                                          PopupMenuItem(value: 'delete', child: Row(children: [
                                            Icon(Icons.delete_outline, size: 18, color: AppColors.expense),
                                            SizedBox(width: 9), Text('Delete Wallet')])),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 47,
                                        child: Text('BALANCE', textAlign: TextAlign.left,
                                          style: TextStyle(fontSize: 8,
                                            fontWeight: FontWeight.w800, color: Colors.white)),
                                      ),
                                      Expanded(
                                        child: Text(formatMoney(balance, currency),
                                          maxLines: 1, textAlign: TextAlign.end,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12,
                                            fontWeight: FontWeight.w900, color: Colors.white,
                                            letterSpacing: -0.3)),
                                      ),
                                      if (excluded) ...[
                                        const SizedBox(width: 3),
                                        const Icon(Icons.visibility_off_outlined,
                                          size: 11, color: Colors.white),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ============================================================
// Wallet add ya edit karne ka form
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

    selectedIcon =
        wallet?['icon_code'] as int? ?? walletIcons.first.codePoint;
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

  InputDecoration _fieldDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 19),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E9E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E9E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
      isDense: true,
    );
  }

  Widget _buildIconPicker() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 16 icons ko 8 columns mein rakh kar 2 rows banata hai.
        const spacing = 6.0;
        final itemWidth = (constraints.maxWidth - spacing * 7) / 8;

        return Wrap(
          spacing: spacing,
          runSpacing: 6,
          children: walletIcons.map((icon) {
            final selected = selectedIcon == icon.codePoint;

            return InkWell(
              onTap: () => setState(() => selectedIcon = icon.codePoint),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: itemWidth,
                height: 37,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : const Color(0xFFF4F7F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : const Color(0xFFE8EEEA),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.muted,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardIsOpen = keyboardHeight > 0;
    final maxSheetHeight = keyboardIsOpen
        ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * 0.95
        : screenHeight * 0.72;

    // Keyboard khulne par bottom sheet uski jagah ke mutabiq narmi se upar jati hai.
    // Keyboard band hone par sheet apni pehli jagah par wapas aa jati hai.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Form(
                key: formKey,
                // Sheet ko scroll karne ke bajaye keyboard khulne par upar le jana.
                child: SingleChildScrollView(
                  primary: false,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sheet ko kheenchne ke liye chhota handle.
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9E0DC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isEditing ? 'Edit Wallet' : 'Add Wallet',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close_rounded),
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Pehli row mein wallet ka naam aur qisam.
                      Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: TextFormField(
                              controller: nameController,
                              decoration: _fieldDecoration(
                                'Wallet Name',
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Name required';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: selectedType,
                              isExpanded: true,
                              decoration: _fieldDecoration('Wallet Type'),
                              items: walletTypes.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(
                                    type,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => selectedType = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      if (selectedType == 'Custom') ...[
                        const SizedBox(height: 9),
                        TextFormField(
                          controller: customTypeController,
                          decoration: _fieldDecoration('Custom Wallet Type'),
                          validator: (value) {
                            if (selectedType == 'Custom' &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Custom type required';
                            }
                            return null;
                          },
                        ),
                      ],

                      const SizedBox(height: 8),
                      const Text(
                        'Wallet Icon',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _buildIconPicker(),

                      const SizedBox(height: 8),

                      // Currency aur amount aik hi row mein.
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                              value: selectedCurrency,
                              isExpanded: true,
                              decoration: _fieldDecoration('Currency'),
                              items: walletCurrencies.map((currency) {
                                return DropdownMenuItem(
                                  value: currency,
                                  child: Text(
                                    currency,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => selectedCurrency = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 5,
                            child: TextFormField(
                              controller: isEditing
                                  ? currentController
                                  : openingController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: _fieldDecoration(
                                isEditing
                                    ? 'Current Balance'
                                    : 'Opening Balance',
                              ),
                              validator: (value) {
                                if (value == null ||
                                    double.tryParse(value.trim()) == null) {
                                  return 'Enter valid amount';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 7),
                      TextFormField(
                        controller: numberController,
                        decoration: _fieldDecoration(
                          'Wallet Number (Optional)',
                          icon: Icons.numbers_outlined,
                        ),
                      ),

                      const SizedBox(height: 3),
                      // Label aur standard toggle aik hi seedhi line mein.
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Exclude from Total Balance',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: excludeTotal,
                            activeTrackColor: AppColors.primary,
                            onChanged: (value) {
                              setState(() => excludeTotal = value);
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: AppColors.text,
                                side: const BorderSide(
                                  color: Color(0xFFDDE5E0),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: saving ? null : saveWallet,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Save Wallet',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// My Finance app
// ============================================================
