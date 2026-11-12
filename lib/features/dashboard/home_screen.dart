import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';

import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/models/budgets_model.dart';
import 'package:my_finance/features/finance/services/budgets_service.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/features/finance/screens/assets_screen.dart';
import 'package:my_finance/features/finance/screens/budgets_screen.dart';

/// Dashboard home screen and its existing data-loading/presentation logic.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.featurePageBuilder});

  final Widget Function(String title) featurePageBuilder;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double totalBalance = 0;
  double monthlyIncome = 0;
  double monthlyExpense = 0;
  double currentAssetsPKR = 0;
  double loansReceivablePKR = 0;
  List<BudgetsModel> budgetAlerts = [];
  bool loading = true;
  bool hideBalances = false;
  String numberFormat = '1,234.56';

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    if (mounted) setState(() => loading = true);
    try {
      final hide = await GeneralPreferences.instance.hideBalances;
      final format = await GeneralPreferences.instance.numberFormat;
      final db = FinanceDB.instance.db;
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      final totals = await db.rawQuery('''
        SELECT UPPER(t.type) AS type,
          COALESCE(SUM(
            t.amount * COALESCE(
              er.rate,
              CASE WHEN UPPER(w.currency) = 'PKR' THEN 1.0 ELSE 0.0 END
            )
          ), 0) AS total
        FROM transactions t
        INNER JOIN wallets w ON w.id = t.wallet_id
        LEFT JOIN exchange_rates er
          ON UPPER(er.currency) = UPPER(w.currency)
        WHERE UPPER(t.type) IN ('INCOME', 'EXPENSE')
          AND date(t.date) >= date(?)
          AND date(t.date) < date(?)
        GROUP BY UPPER(t.type)
      ''', [monthStart.toIso8601String(), nextMonth.toIso8601String()]);

      double income = 0;
      double expense = 0;
      for (final row in totals) {
        final value = (row['total'] as num?)?.toDouble() ?? 0;
        if (row['type'] == 'INCOME') income = value;
        if (row['type'] == 'EXPENSE') expense = value;
      }

      final balance = await FinanceDB.instance.getTotalBalancePKR();
      final assetsByCurrency =
          await AssetsService().getTotalCurrentValueByCurrency();
      final loansByCurrency =
          await LoansService.getTotalOutstandingByCurrency();
      final assetsValue = await _convertValuesToPKR(assetsByCurrency);
      final loansValue = await _convertValuesToPKR(loansByCurrency);
      final budgets = await BudgetsService.getBudgets(activeOnly: true);
      final newBudgetNotifications = await _checkBudgetThresholds(budgets);
      final alerts = budgets
          .where((budget) =>
              budget.isCurrentlyActive &&
              budget.limitAmount > 0 &&
              budget.spentAmount / budget.limitAmount >= 0.5)
          .toList()
        ..sort((a, b) =>
            (b.spentAmount / b.limitAmount)
                .compareTo(a.spentAmount / a.limitAmount));

      if (!mounted) return;
      setState(() {
        hideBalances = hide;
        numberFormat = format;
        totalBalance = balance;
        monthlyIncome = income;
        monthlyExpense = expense;
        currentAssetsPKR = assetsValue;
        loansReceivablePKR = loansValue;
        budgetAlerts = alerts;
        loading = false;
      });
      if (newBudgetNotifications.isNotEmpty && mounted) {
        final first = newBudgetNotifications.first;
        final extraCount = newBudgetNotifications.length - 1;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(extraCount > 0
                ? '$first (+$extraCount more budget alert(s))'
                : first),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dashboard update failed: $error')),
      );
    }
  }

  Future<List<String>> _checkBudgetThresholds(
    List<BudgetsModel> budgets,
  ) async {
    final db = FinanceDB.instance.db;
    final notifications = <String>[];

    for (final budget in budgets) {
      if (!budget.isCurrentlyActive ||
          budget.id == null ||
          budget.limitAmount <= 0) {
        continue;
      }

      final percent = budget.spentAmount / budget.limitAmount * 100;
      final currentLevel = percent >= 100
          ? 100
          : percent >= 90
              ? 90
              : percent >= 75
                  ? 75
                  : percent >= 50
                      ? 50
                      : 0;
      final key = 'budget_alert_level_${budget.id}';
      final savedRows = await db.query(
        'app_settings',
        columns: ['setting_value'],
        where: 'setting_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      final previousLevel = savedRows.isEmpty
          ? 0
          : int.tryParse(
                  savedRows.first['setting_value']?.toString() ?? '0') ??
              0;

      if (currentLevel > previousLevel) {
        final status = currentLevel >= 100
            ? 'has reached its limit'
            : 'has used $currentLevel% of its budget';
        notifications.add('${budget.name} $status.');
      }

      if (currentLevel != previousLevel) {
        await db.insert(
          'app_settings',
          {
            'setting_key': key,
            'setting_value': currentLevel.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    return notifications;
  }

  Future<double> _convertValuesToPKR(
    Map<String, double> values,
  ) async {
    double total = 0;
    for (final entry in values.entries) {
      final rate = await FinanceDB.instance.getExchangeRate(
        entry.key.toUpperCase(),
      );
      if (rate != null) total += entry.value * rate;
    }
    return total;
  }

  double get estimatedNetWorth =>
      totalBalance + currentAssetsPKR + loansReceivablePKR;

  String money(double amount) {
    if (hideBalances) return 'PKR ••••••';
    final locale = numberFormat == '1.234,56' ? 'de_DE' : 'en_US';
    return 'PKR ${NumberFormat('#,##0.00', locale).format(amount)}';
  }

  double get monthlySavings => monthlyIncome - monthlyExpense;

  double get savingsRate => monthlyIncome <= 0
      ? 0
      : ((monthlySavings / monthlyIncome) * 100);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'My Finance',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        actions: buildSharedAppBarActions(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE7EEEA)),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // Primary wallet balance.
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF147D59), Color(0xFF0B6245)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(23),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Wallet Balance',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  loading
                      ? const SizedBox(
                          height: 30,
                          width: 30,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          money(totalBalance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                  const SizedBox(height: 7),
                  const Text('Consolidated in PKR',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text('Financial Snapshot',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                    color: AppColors.text)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    title: 'Assets',
                    value: currentAssetsPKR,
                    icon: Icons.real_estate_agent_outlined,
                    color: const Color(0xFF3978C5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    title: 'Loans Receivable',
                    value: loansReceivablePKR,
                    icon: Icons.handshake_outlined,
                    color: const Color(0xFF9A65C7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: const Color(0xFFEDF1EE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: AppColors.primary, size: 25),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Estimated Net Worth',
                        style: TextStyle(fontWeight: FontWeight.w700,
                            color: AppColors.text, fontSize: 13)),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        loading ? '...' : money(estimatedNetWorth),
                        style: const TextStyle(fontWeight: FontWeight.w800,
                            color: AppColors.primary, fontSize: 17),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text('This Month',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                    color: AppColors.text)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    title: 'Income',
                    value: monthlyIncome,
                    icon: Icons.south_west_rounded,
                    color: AppColors.income,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    title: 'Expenses',
                    value: monthlyExpense,
                    icon: Icons.north_east_rounded,
                    color: AppColors.expense,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: const Color(0xFFEDF1EE)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF147D59).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.savings_outlined,
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Net Monthly Savings',
                            style: TextStyle(fontSize: 12,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(money(monthlySavings),
                            style: TextStyle(fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: monthlySavings >= 0
                                    ? AppColors.income
                                    : AppColors.expense)),
                      ],
                    ),
                  ),
                  Text(
                    '${savingsRate.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text('Budget Alerts',
                      style: TextStyle(fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text)),
                ),
                if (budgetAlerts.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const BudgetsScreen())),
                    child: const Text('View Budgets'),
                  ),
              ],
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (budgetAlerts.isEmpty)
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEDF1EE)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: AppColors.income),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('No budget alerts. Your active budgets are below 50%.',
                          style: TextStyle(fontSize: 12,
                              color: AppColors.muted)),
                    ),
                  ],
                ),
              )
            else
              ...budgetAlerts.take(4).map(_budgetAlertCard),
            const SizedBox(height: 22),
            const Text('Overview',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                    color: AppColors.text)),
            const SizedBox(height: 12),
            _overviewCard(
              icon: Icons.real_estate_agent_outlined,
              title: 'Assets Overview',
              subtitle: 'View and manage your assets',
              color: const Color(0xFF3978C5),
              destinationTitle: 'Assets',
            ),
            _overviewCard(
              icon: Icons.handshake_outlined,
              title: 'Loans Overview',
              subtitle: 'Manage borrowed and lent money',
              color: const Color(0xFF9A65C7),
              destinationTitle: 'Loans',
            ),
            _overviewCard(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Budgets Overview',
              subtitle: 'Track your budgets',
              color: const Color(0xFFDB9840),
              destinationTitle: 'Budgets',
            ),
            _overviewCard(
              icon: Icons.flag_outlined,
              title: 'Goals Overview',
              subtitle: 'Track your saving goals',
              color: const Color(0xFF279C83),
              destinationTitle: 'Goals',
            ),
            _overviewCard(
              icon: Icons.repeat_rounded,
              title: 'Recurring Txns',
              subtitle: 'Manage scheduled transactions',
              color: const Color(0xFF6C78C7),
              destinationTitle: 'Recurring Transactions',
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFEDF1EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 7),
            Text(title, style: const TextStyle(fontSize: 12,
                color: AppColors.muted, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 9),
          loading
              ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(money(value),
                      style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w800, color: color)),
                ),
        ],
      ),
    );
  }

  Widget _budgetAlertCard(BudgetsModel budget) {
    final ratio = budget.spentAmount / budget.limitAmount;
    final percent = ratio * 100;
    final exceeded = ratio >= 1;
    final color = exceeded
        ? AppColors.expense
        : ratio >= 0.9
            ? const Color(0xFFE18A35)
            : ratio >= 0.75
                ? const Color(0xFFCC9A35)
                : AppColors.primary;
    final status = exceeded
        ? 'Budget limit reached'
        : ratio >= 0.9
            ? 'Almost exceeded'
            : ratio >= 0.75
                ? '75% used'
                : '50% used';
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(budget.name,
                  style: const TextStyle(fontWeight: FontWeight.w800,
                      fontSize: 13, color: AppColors.text)),
            ),
            Text('${percent.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 5),
          Text(status, style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 7,
              backgroundColor: const Color(0xFFEDF1EE),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 7),
          Text('${budget.currency} ${NumberFormat('#,##0.00').format(budget.spentAmount)} spent of ${NumberFormat('#,##0.00').format(budget.limitAmount)}',
              style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _overviewCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String destinationTitle,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => destinationTitle == 'Assets'
                ? const AssetsScreen()
                : widget.featurePageBuilder(destinationTitle),
          ),
        );
      },
      borderRadius: BorderRadius.circular(17),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFEDF1EE)),
        ),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 23),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(
                      color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
