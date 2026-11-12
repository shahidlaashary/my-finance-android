import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:my_finance/app/my_finance_app.dart';
import 'package:my_finance/app/screens/more_features_page.dart' show MoreFeaturesPage;
import 'package:my_finance/app/screens/main_screen.dart' show MainScreen;
import 'package:my_finance/app/screens/simple_feature_page.dart' show SimpleFeaturePage;
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/startup/app_bootstrap_service.dart';
import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/features/dashboard/screens/home_screen.dart' show HomePage;
import 'package:my_finance/features/finance/screens/assets_screen.dart';
import 'package:my_finance/features/finance/screens/budgets_screen.dart';
import 'package:my_finance/features/finance/screens/categories_management_screen.dart' show CategoriesPage;
import 'package:my_finance/features/finance/screens/goals_screen.dart';
import 'package:my_finance/features/finance/screens/loans_screen.dart';
import 'package:my_finance/features/finance/screens/stats_screen.dart';
import 'package:my_finance/features/finance/screens/transaction_entry_form.dart' show TransactionEntryForm;
import 'package:my_finance/features/finance/screens/transactions_screen.dart';
import 'package:my_finance/features/finance/screens/wallets_screen.dart' show WalletsPage;

// ============================================================
// Naya database aur wallet ka intizam
// ============================================================

Future<void> main() async {
  await AppBootstrapService.initialize();

  runApp(MyFinanceApp(
    home: const MainScreen(),
    routes: {'/settings': (_) => const MoreFeaturesPage()},
  ));
}

// ============================================================
// Database ka nizam
// ============================================================

// App composition is maintained in lib/app/my_finance_app.dart.


// ============================================================
// Main screen aur 9 jagah wali bottom navigation
// ============================================================

class AssetsPage extends StatelessWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AssetsScreen();
  }
}

// ============================================================
// Loans ka safha
// ============================================================

class LoansPage extends StatelessWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SimpleFeaturePage(title: 'Loans');
  }
}

// ============================================================
// Mazeed sahuliyat
// ============================================================

// ============================================================
// Categories ka intizam
// ============================================================

// Feature ka sada safha
// ============================================================

// Transactions database ke operations
// ============================================================

// Transactions ki history
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

    try {
      final result =
          await FinanceDB.instance.getTransactions();

      if (!mounted) return;

      setState(() {
        transactions = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> deleteTransaction(
    Map<String, dynamic> transaction,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text(
          'Kya aap is transaction ko delete karna chahte hain? '
          'Wallet balance bhi reverse ho jayega.',
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: const Text(
          'Transactions',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        actions: buildMainSectionAppBarActions(context),
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
                        color: AppColors.primary,
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
                      final item = transactions[index];

                      final type = item['type'] as String;
                      final amount =
                          (item['amount'] as num).toDouble();

                      final currency =
                          item['wallet_currency'] as String? ?? 'PKR';

                      final date = DateTime.tryParse(
                            item['date'] as String? ?? '',
                          ) ??
                          DateTime.now();

                      final isIncome = type == 'Income';
                      final isExpense = type == 'Expense';
                      final isTransfer = type == 'Transfer';

                      final color = isIncome
                          ? AppColors.income
                          : isExpense
                              ? AppColors.expense
                              : AppColors.primary;

                      final icon = isIncome
                          ? Icons.south_west_rounded
                          : isExpense
                              ? Icons.north_east_rounded
                              : Icons.swap_horiz_rounded;

                      final destinationName =
                          item['to_wallet_name'] as String?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.10),
                            child: Icon(icon, color: AppColors.primary),
                          ),
                          title: Text(
                            isTransfer
                                ? '${
                                    item['wallet_name'] ?? 'Wallet'
                                  } → ${destinationName ?? 'Wallet'}'
                                : (item['wallet_name'] ?? 'Wallet')
                                    .toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                '$type • ${DateFormat('dd MMM yyyy').format(date)}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              if ((item['category'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text(
                                  item['category'] as String,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                              if (isTransfer &&
                                  (item['transfer_fee'] as num? ?? 0).toDouble() > 0)
                                Text(
                                  'Transfer Fee: $currency ${NumberFormat('#,##0.##').format((item['transfer_fee'] as num).toDouble())}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                              if ((item['note'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text(
                                  item['note'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isTransfer
                                    ? '$currency ${NumberFormat('#,##0.##').format(amount + ((item['transfer_fee'] as num?)?.toDouble() ?? 0))}'
                                    : '${isIncome ? '+' : isExpense ? '-' : ''}$currency ${NumberFormat('#,##0.##').format(amount)}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    deleteTransaction(item);
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
                      );
                    },
                  ),
                ),
    );
  }
}

// ============================================================
// My Finance app
// ============================================================

