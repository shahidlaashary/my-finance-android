import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:intl/intl.dart';

import 'package:my_finance/features/finance/services/reports_service.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/budgets_service.dart';
import 'package:my_finance/features/finance/services/goals_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
import 'package:my_finance/features/finance/models/budgets_model.dart';
import 'package:my_finance/features/finance/models/goals_model.dart';
import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final ReportsService _reports = ReportsService();
  final NumberFormat _numberFormat = NumberFormat('#,##0.00');

  bool _loading = true;
  bool _hideBalances = false;
  String? _error;
  String _period = 'This Month';
  String _currency = 'PKR';
  String _trendView = 'Both';
  bool _showAllCategories = false;
  static const List<Color> _chartColors = [
    Color(0xFF3978F6), Color(0xFF17B890), Color(0xFFFFA62B),
    Color(0xFF9B6BDF), Color(0xFFFF6685), Color(0xFF20B8C9),
    Color(0xFF6C9A45), Color(0xFFE07835),
  ];
  List<String> _currencies = [];
  List<Map<String, dynamic>> _balances = [];
  List<Map<String, dynamic>> _trend = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, double> _totals = {'income': 0, 'expense': 0, 'net': 0};
  int _transactionCount = 0;
  List<AssetsModel> _assets = [];
  List<BudgetsModel> _budgets = [];
  List<GoalsModel> _goals = [];
  List<LoansModel> _loans = [];
  List<Map<String, dynamic>> _wallets = [];

  DateTime get _startDate {
    final now = DateTime.now();
    switch (_period) {
      case 'Last Month':
        return DateTime(now.year, now.month - 1, 1);
      case 'This Year':
        return DateTime(now.year, 1, 1);
      case 'Last 6 Months':
        return DateTime(now.year, now.month - 5, 1);
      case 'All Time':
        return DateTime(2000, 1, 1);
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  DateTime get _endDate {
    final now = DateTime.now();
    if (_period == 'Last Month') {
      return DateTime(now.year, now.month, 0);
    }
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    _loadData();
  }

  void _onPreferencesChanged() async {
    final hidden = await GeneralPreferences.instance.hideBalances;
    if (mounted && hidden != _hideBalances) {
      setState(() => _hideBalances = hidden);
    }
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final hideBalances = await GeneralPreferences.instance.hideBalances;
      final currencies = await _reports.getAvailableCurrencies();
      final assets = await AssetsService().getAssets();
      final budgets = await BudgetsService.getBudgets();
      final goals = await GoalsService.getGoals();
      final loans = await LoansService.getLoans();
      final wallets = await TransactionsService.getAccounts();
      final balances = await _reports.getBalancesByCurrency();
      final allCurrencies = <String>{
        ...currencies,
        ...balances.map((row) => row['currency'].toString()),
      }.where((value) => value.trim().isNotEmpty).toList()
        ..sort();

      final selected = allCurrencies.contains(_currency)
          ? _currency
          : (allCurrencies.isNotEmpty ? allCurrencies.first : 'PKR');

      final start = _startDate;
      final end = _endDate;
      final totals = await _reports.getIncomeExpenseTotals(
        startDate: start,
        endDate: end,
        currency: selected,
      );
      final summary = await _reports.getSummary(
        startDate: start,
        endDate: end,
      );
      final selectedSummary = summary.where(
        (row) => row['currency'].toString().toUpperCase() == selected.toUpperCase(),
      );
      final count = selectedSummary.isEmpty
          ? 0
          : (selectedSummary.first['transaction_count'] as num?)?.toInt() ?? 0;

      final trendStart = DateTime(DateTime.now().year, DateTime.now().month - 5, 1);
      final trend = await _reports.getMonthlyTrend(
        startDate: trendStart,
        endDate: DateTime.now(),
        currency: selected,
      );
      final categories = await _reports.getCategoryBreakdown(
        startDate: start,
        endDate: end,
        type: 'expense',
        currency: selected,
      );

      if (!mounted) return;
      setState(() {
        _hideBalances = hideBalances;
        _currencies = allCurrencies;
        _currency = selected;
        _balances = balances;
        _totals = totals;
        _transactionCount = count;
        _trend = trend;
        _categories = categories;
        _assets = assets;
        _budgets = budgets;
        _goals = goals;
        _loans = loans;
        _wallets = wallets;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  String _money(Object? value) => _hideBalances ? '••••••' : _numberFormat.format((value as num?)?.toDouble() ?? 0);

  Widget _metricCard({
    required String title,
    required String amount,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(height: 9),
              Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (subtitle != null) Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTrend() {
    if (_trend.isEmpty) {
      return const Text('No income or expense trend available yet.', style: TextStyle(color: Colors.black54));
    }
    final maxValue = _trend.fold<double>(0, (maxValue, row) {
      final income = (row['income'] as num?)?.toDouble() ?? 0;
      final expense = (row['expense'] as num?)?.toDouble() ?? 0;
      final visible = _trendView == 'Income'
          ? income
          : _trendView == 'Expense'
              ? expense
              : math.max(income, expense).toDouble();
      return math.max(maxValue, visible).toDouble();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          children: ['Both', 'Income', 'Expense'].map((view) {
            final selected = _trendView == view;
            return ChoiceChip(
              label: Text(view),
              selected: selected,
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF52645C),
              ),
              selectedColor: const Color(0xFF246B52),
              backgroundColor: const Color(0xFFF0F4F1),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _trendView = view),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Container(
          height: 174,
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAF9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _trend.map((row) {
              final month = DateTime.tryParse('${row['month']}-01');
              final label = month == null ? row['month'].toString() : DateFormat('MMM').format(month);
              final income = (row['income'] as num?)?.toDouble() ?? 0;
              final expense = (row['expense'] as num?)?.toDouble() ?? 0;
              final incomeFactor = maxValue <= 0 ? 0.0 : (income / maxValue).clamp(0.0, 1.0).toDouble();
              final expenseFactor = maxValue <= 0 ? 0.0 : (expense / maxValue).clamp(0.0, 1.0).toDouble();
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_trendView != 'Expense')
                              Tooltip(
                                message: 'Income: $_currency ${_money(income)}',
                                child: Container(
                                  width: _trendView == 'Both' ? 11 : 19,
                                  height: math.max(3.0, 112 * incomeFactor),
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                    gradient: const LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [Color(0xFF16865B), Color(0xFF55D6A2)],
                                    ),
                                  ),
                                ),
                              ),
                            if (_trendView == 'Both') const SizedBox(width: 4),
                            if (_trendView != 'Income')
                              Tooltip(
                                message: 'Expense: $_currency ${_money(expense)}',
                                child: Container(
                                  width: _trendView == 'Both' ? 11 : 19,
                                  height: math.max(3.0, 112 * expenseFactor),
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                    gradient: const LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [Color(0xFFE45D67), Color(0xFFFFA17A)],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF68766F), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 11),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            if (_trendView != 'Expense') _chartLegend(const Color(0xFF20B987), 'Income'),
            if (_trendView != 'Income') _chartLegend(const Color(0xFFEF7371), 'Expense'),
          ],
        ),
      ],
    );
  }

  Widget _chartLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildCategories() {
    if (_categories.isEmpty) {
      return const Text('No expense categories recorded for this period.', style: TextStyle(color: Colors.black54));
    }
    final visibleCategories = _showAllCategories ? _categories : _categories.take(5).toList();
    final total = visibleCategories.fold<double>(
      0,
      (sum, row) => sum + ((row['total'] as num?)?.toDouble() ?? 0),
    );
    final values = visibleCategories.map((row) => (row['total'] as num?)?.toDouble() ?? 0).toList();
    final colors = List<Color>.generate(values.length, (index) => _chartColors[index % _chartColors.length]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _showAllCategories ? 'All categories' : 'Top 5 categories',
              style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
            ),
            TextButton(
              onPressed: () => setState(() => _showAllCategories = !_showAllCategories),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(_showAllCategories ? 'Show top 5' : 'View all'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              width: 142,
              height: 142,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(142, 142),
                    painter: _DonutChartPainter(values: values, colors: colors),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 10, color: Colors.black54)),
                      const SizedBox(height: 3),
                      Text(
                        _money(total),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      Text(_currency, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: List.generate(visibleCategories.length, (index) {
                  final row = visibleCategories[index];
                  final amount = values[index];
                  final percent = total <= 0 ? 0 : amount / total * 100;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: colors[index], shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            row['category_name'].toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text('${percent.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(visibleCategories.length, (index) {
          final row = visibleCategories[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(row['category_name'].toString(), style: const TextStyle(fontSize: 11, color: Colors.black54))),
                Text('$_currency ${_money(values[index])}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBalances() {
    if (_balances.isEmpty) {
      return const Text('Create a wallet to see account balances here.', style: TextStyle(color: Colors.black54));
    }
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: _balances.map((row) {
        return Container(
          width: 145,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F8F5),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row['currency'].toString(), style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(_money(row['total_balance']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text('${row['account_count']} account(s)', style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        );
      }).toList(),
    );
  }

  Widget _buildOverviewSection(String title, IconData icon, List<Widget> details) {
    return Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, color: const Color(0xFF147D59), size: 21), const SizedBox(width: 9), Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))]),
      const SizedBox(height: 12),
      ...details,
    ])));
  }

  Widget _overviewLine(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13))),
      const SizedBox(width: 8),
      Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    ]));
  }

  List<Widget> _buildAdditionalStats() {
    final assetRows = _assets.where((asset) => !asset.isSold).toList();
    final assetValue = assetRows.fold<double>(0, (sum, asset) {
      final matches = _wallets.where((w) => (w['id'] as num).toInt() == asset.walletId);
      final currency = matches.isEmpty ? 'PKR' : (matches.first['currency']?.toString() ?? 'PKR');
      return sum + (currency.toUpperCase() == _currency.toUpperCase() ? asset.currentValue : 0);
    });
    final assetPurchase = assetRows.fold<double>(0, (sum, asset) {
      final matches = _wallets.where((w) => (w['id'] as num).toInt() == asset.walletId);
      final currency = matches.isEmpty ? 'PKR' : (matches.first['currency']?.toString() ?? 'PKR');
      return sum + (currency.toUpperCase() == _currency.toUpperCase() ? asset.purchasePrice : 0);
    });
    final currencyBudgets = _budgets.where((b) => b.currency.toUpperCase() == _currency.toUpperCase()).toList();
    final budgetLimit = currencyBudgets.fold<double>(0, (sum, b) => sum + b.limitAmount);
    final budgetSpent = currencyBudgets.fold<double>(0, (sum, b) => sum + b.spentAmount);
    final currencyGoals = _goals.where((goal) {
      if (goal.walletId == null) return _currency.toUpperCase() == 'PKR';
      final matches = _wallets.where((w) => (w['id'] as num).toInt() == goal.walletId);
      final currency = matches.isEmpty ? 'PKR' : (matches.first['currency']?.toString() ?? 'PKR');
      return currency.toUpperCase() == _currency.toUpperCase();
    }).toList();
    final goalTarget = currencyGoals.fold<double>(0, (sum, g) => sum + g.targetAmount);
    final goalSaved = currencyGoals.fold<double>(0, (sum, g) => sum + g.savedAmount);
    final currencyLoans = _loans.where((loan) {
      final matches = _wallets.where((w) => (w['id'] as num).toInt() == loan.walletId);
      final currency = matches.isEmpty ? 'PKR' : (matches.first['currency']?.toString() ?? 'PKR');
      return currency.toUpperCase() == _currency.toUpperCase();
    }).toList();
    final loanOutstanding = currencyLoans.fold<double>(0, (sum, l) => sum + l.remainingAmount);
    final loanRepaid = currencyLoans.fold<double>(0, (sum, l) => sum + l.repaidAmount);
    return [
      _buildOverviewSection('Assets', Icons.real_estate_agent_outlined, [
        _overviewLine('Active assets', assetRows.length.toString()),
        _overviewLine('Current asset value', '$_currency ${_money(assetValue)}'),
        _overviewLine('Purchase value', '$_currency ${_money(assetPurchase)}'),
      ]),
      const SizedBox(height: 12),
      _buildOverviewSection('Budgets', Icons.pie_chart_outline_rounded, [
        _overviewLine('Total budgets', currencyBudgets.length.toString()),
        _overviewLine('Budget limits', '$_currency ${_money(budgetLimit)}'),
        _overviewLine('Spent', '$_currency ${_money(budgetSpent)}'),
        _overviewLine('Remaining', '$_currency ${_money((budgetLimit - budgetSpent).clamp(0, double.infinity))}'),
      ]),
      const SizedBox(height: 12),
      _buildOverviewSection('Goals', Icons.flag_outlined, [
        _overviewLine('Total goals', currencyGoals.length.toString()),
        _overviewLine('Target amount', '$_currency ${_money(goalTarget)}'),
        _overviewLine('Saved amount', '$_currency ${_money(goalSaved)}'),
        _overviewLine('Remaining target', '$_currency ${_money((goalTarget - goalSaved).clamp(0, double.infinity))}'),
      ]),
      const SizedBox(height: 12),
      _buildOverviewSection('Loans', Icons.handshake_outlined, [
        _overviewLine('Total loans', currencyLoans.length.toString()),
        _overviewLine('Outstanding', '$_currency ${_money(loanOutstanding)}'),
        _overviewLine('Repaid', '$_currency ${_money(loanRepaid)}'),
        _overviewLine('Overdue loans', currencyLoans.where((l) => l.isOverdue).length.toString()),
      ]),
      const SizedBox(height: 12),
      _buildOverviewSection('Transactions', Icons.receipt_long_outlined, [
        _overviewLine('Transactions in period', _transactionCount.toString()),
        _overviewLine('Income', '$_currency ${_money(_totals['income'])}'),
        _overviewLine('Expenses', '$_currency ${_money(_totals['expense'])}'),
        _overviewLine('Net savings', '$_currency ${_money(_totals['net'])}'),
      ]),
      const SizedBox(height: 12),
    ];
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF202A26),
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: const Text('Reports and Analytics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF202A26))),
        actions: buildSharedAppBarActions(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
                    const SizedBox(height: 10),
                    Text('Could not load stats: $_error', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh), label: const Text('Try Again')),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Row(children: [
                        Expanded(child: DropdownButtonFormField<String>(
                          value: _period,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Period', prefixIcon: Icon(Icons.date_range), isDense: true),
                          items: const ['This Month', 'Last Month', 'Last 6 Months', 'This Year', 'All Time']
                              .map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                          onChanged: (value) { if (value != null) setState(() => _period = value); _loadData(); },
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: DropdownButtonFormField<String>(
                          value: _currency,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Currency', prefixIcon: Icon(Icons.payments_outlined), isDense: true),
                          items: (_currencies.isEmpty ? <String>['PKR'] : _currencies)
                              .map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                          onChanged: (value) { if (value != null) setState(() => _currency = value); _loadData(); },
                        )),
                      ]),
                      const SizedBox(height: 14),
                      Text('$_currency overview', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 9),
                      Row(children: [
                        _metricCard(title: 'Income', amount: _money(_totals['income']), icon: Icons.trending_up_rounded, color: const Color(0xFF16865B)),
                        const SizedBox(width: 9),
                        _metricCard(title: 'Expenses', amount: _money(_totals['expense']), icon: Icons.trending_down_rounded, color: const Color(0xFFD9534F)),
                      ]),
                      const SizedBox(height: 9),
                      Row(children: [
                        _metricCard(title: 'Net Savings', amount: _money(_totals['net']), icon: Icons.account_balance_wallet_outlined, color: const Color(0xFF147D59)),
                        const SizedBox(width: 9),
                        _metricCard(title: 'Transactions', amount: _transactionCount.toString(), icon: Icons.receipt_long_outlined, color: const Color(0xFF536B60)),
                      ]),
                      const SizedBox(height: 18),
                      Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _sectionTitle('Monthly Trend', subtitle: 'Last 6 months'),
                        _buildTrend(),
                      ]))),
                      const SizedBox(height: 14),
                      Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _sectionTitle('Expense by Category', subtitle: _period),
                        _buildCategories(),
                      ]))),
                      const SizedBox(height: 14),
                      Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _sectionTitle('Wallet Balances'),
                        _buildBalances(),
                      ]))),
                      const SizedBox(height: 12),
                      ..._buildAdditionalStats(),
                    ],
                  ),
                ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;

  const _DonutChartPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0 || values.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.19;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    var startAngle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      if (sweep <= 0) continue;
      paint.color = colors[i % colors.length];
      canvas.drawArc(rect, startAngle + 0.025, math.max(0.0, sweep - 0.05), false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}
