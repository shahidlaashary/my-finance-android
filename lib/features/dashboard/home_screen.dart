import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/models/budgets_model.dart';
import 'package:my_finance/features/finance/services/budgets_service.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';
import 'package:my_finance/features/finance/services/goals_service.dart';
import 'package:my_finance/features/finance/services/recurring_transaction_service.dart';
import 'package:my_finance/features/finance/screens/assets_screen.dart';
import 'package:my_finance/features/finance/screens/budgets_screen.dart';
import 'package:my_finance/features/finance/screens/goals_screen.dart';
import 'package:my_finance/features/finance/screens/loans_screen.dart';
import 'package:my_finance/features/finance/screens/recurring_transactions_screen.dart';

/// Dashboard home screen and its existing data-loading/presentation logic.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.featurePageBuilder});

  final Widget Function(String title) featurePageBuilder;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double totalBalance = 0;
  double baseCurrencyWalletTotal = 0;
  Map<String, double> otherCurrencyTotals = {};
  double monthlyIncome = 0;
  double monthlyExpense = 0;
  double currentAssetsPKR = 0;
  double loansReceivablePKR = 0;
  double loansPayablePKR = 0;
  double consolidatedIncludedAssetsPKR = 0;
  String baseCurrency = 'PKR';
  List<BudgetsModel> budgetAlerts = [];
  int overviewAssetCount = 0;
  int overviewLoanCount = 0;
  int overviewOverdueLoanCount = 0;
  int overviewBudgetCount = 0;
  int overviewGoalCount = 0;
  int overviewCompletedGoalCount = 0;
  int overviewRecurringCount = 0;
  int overviewActiveRecurringCount = 0;
  bool loading = false;
  bool hideBalances = false;
  String numberFormat = '1,234.56';

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    AppRefreshController.revision.addListener(_onAppDataChanged);
    loadDashboard();
  }

  void _onAppDataChanged() {
    if (mounted) loadDashboard();
  }

  void _onPreferencesChanged() {
    if (mounted) loadDashboard();
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    super.dispose();
  }

  Future<void> loadDashboard() async {
    if (mounted) setState(() => loading = true);
    try {
      final hide = await GeneralPreferences.instance.hideBalances;
      final format = await GeneralPreferences.instance.numberFormat;
      final db = FinanceDB.instance.db;
      final selectedBaseCurrency = await FinanceDB.instance.getBaseCurrency();
      final baseRate = await FinanceDB.instance.getExchangeRate(selectedBaseCurrency) ?? 1.0;
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      final totals = await db.rawQuery('''
        SELECT UPPER(t.type) AS type,
          COALESCE(SUM(
            t.amount * COALESCE(
              er.rate,
              CASE WHEN UPPER(w.currency) = 'PKR' THEN 1.0 ELSE 0.0 END
            ) / ?
          ), 0) AS total
        FROM transactions t
        INNER JOIN wallets w ON w.id = t.wallet_id
        LEFT JOIN exchange_rates er
          ON UPPER(er.currency) = UPPER(w.currency)
        WHERE UPPER(t.type) IN ('INCOME', 'EXPENSE')
          AND date(t.date) >= date(?)
          AND date(t.date) < date(?)
        GROUP BY UPPER(t.type)
      ''', [baseRate, monthStart.toIso8601String(), nextMonth.toIso8601String()]);

      double income = 0;
      double expense = 0;
      for (final row in totals) {
        final value = (row['total'] as num?)?.toDouble() ?? 0;
        if (row['type'] == 'INCOME') income = value;
        if (row['type'] == 'EXPENSE') expense = value;
      }

      final balance = await FinanceDB.instance.getTotalBalanceInBaseCurrency();
      final includedAssetValues = await AssetsService().getConsolidatedIncludedCurrentValueByCurrency();
      final includedAssetsInBaseCurrency = await _convertValuesToPKR(includedAssetValues, baseRate);
      final walletCurrencyRows = await db.rawQuery('''
        SELECT UPPER(currency) AS currency, COALESCE(SUM(balance), 0) AS total
        FROM wallets
        WHERE COALESCE(exclude_total, 0) = 0
        GROUP BY UPPER(currency)
        ORDER BY UPPER(currency)
      ''');
      double baseCurrencyBalance = 0;
      final foreignBalances = <String, double>{};
      for (final row in walletCurrencyRows) {
        final currency = (row['currency'] as String? ?? '').toUpperCase();
        final amount = (row['total'] as num?)?.toDouble() ?? 0;
        if (currency == selectedBaseCurrency.trim().toUpperCase()) {
          baseCurrencyBalance = amount;
        } else if (currency.isNotEmpty) {
          foreignBalances[currency] = amount;
        }
      }
      final assetsByCurrency =
          await AssetsService().getTotalCurrentValueByCurrency();
      final outstandingLoans =
          await LoansService.getTotalOutstandingByCurrency();
      final receivableByCurrency = <String, double>{};
      final payableByCurrency = <String, double>{};
      for (final entry in outstandingLoans.entries) {
        final parts = entry.key.split(' • ');
        if (parts.length != 2) continue;
        final currency = parts.first.trim().toUpperCase();
        final loanType = parts.last.trim().toLowerCase();
        if (loanType == 'receivable') {
          receivableByCurrency[currency] =
              (receivableByCurrency[currency] ?? 0) + entry.value;
        } else if (loanType == 'payable') {
          payableByCurrency[currency] =
              (payableByCurrency[currency] ?? 0) + entry.value;
        }
      }
      final assetsValue = await _convertValuesToPKR(assetsByCurrency, baseRate);
      final receivableValue =
          await _convertValuesToPKR(receivableByCurrency, baseRate);
      final payableValue =
          await _convertValuesToPKR(payableByCurrency, baseRate);
      final budgets = await BudgetsService.getBudgets(activeOnly: true);
      final assets = await AssetsService().getAssets(includeSold: false);
      final loans = await LoansService.getLoans();
      final goals = await GoalsService.getGoals();
      final recurring = await RecurringTransactionService().getRecurringTransactions();
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
        baseCurrency = selectedBaseCurrency;
        totalBalance = balance + includedAssetsInBaseCurrency;
        baseCurrencyWalletTotal = baseCurrencyBalance;
        otherCurrencyTotals = foreignBalances;
        monthlyIncome = income;
        monthlyExpense = expense;
        currentAssetsPKR = assetsValue;
        loansReceivablePKR = receivableValue;
        loansPayablePKR = payableValue;
        consolidatedIncludedAssetsPKR = includedAssetsInBaseCurrency;
        budgetAlerts = alerts;
        overviewAssetCount = assets.length;
        overviewLoanCount = loans.where((loan) => !loan.isPaid).length;
        overviewBudgetCount = budgets.length;
        overviewOverdueLoanCount = loans.where((loan) => loan.isOverdue).length;
        overviewGoalCount = goals.where((goal) => !goal.isCompleted).length;
        overviewCompletedGoalCount = goals.where((goal) => goal.isCompleted).length;
        overviewRecurringCount = recurring.length;
        overviewActiveRecurringCount = recurring.where((item) => item.isActive).length;
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
        SnackBar(content: Text('${appText(context, 'Dashboard update failed:', 'ڈیش بورڈ اپ ڈیٹ نہیں ہو سکا:')} $error')),
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
    double baseRate,
  ) async {
    double total = 0;
    for (final entry in values.entries) {
      final rate = await FinanceDB.instance.getExchangeRate(
        entry.key.toUpperCase(),
      );
      if (rate != null) total += entry.value * rate / baseRate;
    }
    return total;
  }

  double get estimatedNetWorth =>
      totalBalance +
      currentAssetsPKR -
      consolidatedIncludedAssetsPKR +
      loansReceivablePKR -
      loansPayablePKR;

  String money(double amount) {
    if (hideBalances) return '$baseCurrency ******';
    final locale = numberFormat == '1.234,56' ? 'de_DE' : 'en_US';
    return '$baseCurrency ${NumberFormat('#,##0.00', locale).format(amount)}';
  }

  String _currencyAmount(String currency, double amount) {
    if (hideBalances) return '$currency ******';
    final locale = numberFormat == '1.234,56' ? 'de_DE' : 'en_US';
    return '$currency ${NumberFormat('#,##0.00', locale).format(amount)}';
  }

  MapEntry<String, double>? get firstOtherCurrency {
    if (otherCurrencyTotals.isEmpty) return null;
    final entries = otherCurrencyTotals.entries
        .where((entry) =>
            entry.key.trim().toUpperCase() != baseCurrency.trim().toUpperCase())
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.first;
  }

  String _currencyFlag(String currency) {
    const flags = {
      'PKR': '🇵🇰', 'USD': '🇺🇸', 'GBP': '🇬🇧', 'EUR': '🇪🇺',
      'AED': '🇦🇪', 'SAR': '🇸🇦', 'INR': '🇮🇳', 'CAD': '🇨🇦',
      'AUD': '🇦🇺', 'JPY': '🇯🇵', 'CNY': '🇨🇳', 'CHF': '🇨🇭',
      'SGD': '🇸🇬', 'NZD': '🇳🇿', 'KWD': '🇰🇼', 'QAR': '🇶🇦',
      'BHD': '🇧🇭', 'OMR': '🇴🇲', 'MYR': '🇲🇾', 'TRY': '🇹🇷',
      'ZAR': '🇿🇦', 'HKD': '🇭🇰', 'IDR': '🇮🇩', 'KRW': '🇰🇷',
      'THB': '🇹🇭', 'BDT': '🇧🇩', 'LKR': '🇱🇰', 'NPR': '🇳🇵',
      'AFN': '🇦🇫', 'IRR': '🇮🇷', 'RUB': '🇷🇺',
    };
    return flags[currency.toUpperCase()] ?? '🌐';
  }

  String _currencyCountry(String currency) {
    const countries = {
      'PKR': 'Pakistan', 'USD': 'United States', 'GBP': 'United Kingdom',
      'EUR': 'European Union', 'AED': 'United Arab Emirates',
      'SAR': 'Saudi Arabia', 'INR': 'India', 'CAD': 'Canada',
      'AUD': 'Australia', 'JPY': 'Japan', 'CNY': 'China',
      'CHF': 'Switzerland', 'SGD': 'Singapore', 'NZD': 'New Zealand',
      'KWD': 'Kuwait', 'QAR': 'Qatar', 'BHD': 'Bahrain',
      'OMR': 'Oman', 'MYR': 'Malaysia', 'TRY': 'Türkiye',
      'ZAR': 'South Africa', 'HKD': 'Hong Kong', 'IDR': 'Indonesia',
      'KRW': 'South Korea', 'THB': 'Thailand', 'BDT': 'Bangladesh',
      'LKR': 'Sri Lanka', 'NPR': 'Nepal', 'AFN': 'Afghanistan',
      'IRR': 'Iran', 'RUB': 'Russia',
    };
    return countries[currency.toUpperCase()] ?? 'Other region';
  }

  Future<void> _showAllCurrencies() async {
    final entries = otherCurrencyTotals.entries
        .where((entry) =>
            entry.key.trim().toUpperCase() != baseCurrency.trim().toUpperCase())
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // The Exchange Rates screen refreshes missing rates when it opens.
    // The dashboard summary can be opened without visiting that screen, so
    // fetch any rates required by this summary before reading the saved table.
    final requiredCurrencies = <String>{
      ...entries.map((entry) => entry.key.trim().toUpperCase()),
      baseCurrency.trim().toUpperCase(),
    }..remove('PKR');

    final savedRates = await FinanceDB.instance.getExchangeRates();
    final availableCurrencies = savedRates
        .map((row) => row['currency']?.toString().trim().toUpperCase() ?? '')
        .where((code) => code.isNotEmpty)
        .toSet();
    final missingBeforeRefresh =
        requiredCurrencies.difference(availableCurrencies);

    if (missingBeforeRefresh.isNotEmpty) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final request = await client
            .getUrl(Uri.parse('https://open.er-api.com/v6/latest/PKR'))
            .timeout(const Duration(seconds: 20));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response =
            await request.close().timeout(const Duration(seconds: 20));
        if (response.statusCode == HttpStatus.ok) {
          final body = await response
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 20));
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final providerRates = payload['rates'] as Map<String, dynamic>?;
          if (payload['result'] == 'success' && providerRates != null) {
            for (final currency in missingBeforeRefresh) {
              final rawRate = providerRates[currency];
              if (rawRate is! num || rawRate <= 0) continue;
              // Provider gives foreign units per PKR; store PKR per unit.
              final pkrPerUnit = 1 / rawRate.toDouble();
              if (!pkrPerUnit.isFinite || pkrPerUnit <= 0) continue;
              await FinanceDB.instance.saveExchangeRate(
                currency,
                pkrPerUnit,
                source: 'automatic',
              );
            }
          }
        }
      } catch (_) {
        // Keep the summary usable offline; missing rates are shown below.
      } finally {
        client.close(force: true);
      }
    }

    final savedRateRows = await FinanceDB.instance.getExchangeRates();
    final ratesByCurrency = <String, double>{};
    for (final row in savedRateRows) {
      final code = row['currency']?.toString().trim().toUpperCase() ?? '';
      final rawRate = row['rate'];
      if (code.isEmpty || rawRate is! num) continue;
      final rate = rawRate.toDouble();
      if (rate.isFinite && rate > 0) {
        ratesByCurrency[code] = rate;
      }
    }
    ratesByCurrency['PKR'] = 1.0;

    final selectedBaseRate = ratesByCurrency[baseCurrency.trim().toUpperCase()];
    final convertedByCurrency = <String, double>{};
    final missingRates = <String>[];
    double foreignTotalPKR = 0;
    for (final entry in entries) {
      final currency = entry.key.trim().toUpperCase();
      final rate = ratesByCurrency[currency];
      if (rate == null) {
        missingRates.add(currency);
        continue;
      }
      // Exchange rates are stored as PKR value per one unit of currency.
      foreignTotalPKR += entry.value * rate;
      if (selectedBaseRate != null && selectedBaseRate > 0) {
        convertedByCurrency[currency] =
            entry.value * rate / selectedBaseRate;
      }
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.72,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onPrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.currency_exchange_rounded,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        appText(context, 'Foreign Currencies Summary',
                            'غیر ملکی کرنسیوں کا خلاصہ'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: appText(context, 'Close', 'بند کریں'),
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          appText(context, 'No other currency wallets.',
                              'دیگر کرنسی کے والٹس موجود نہیں۔'),
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1, color: Theme.of(context).dividerColor),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final converted = convertedByCurrency[
                              entry.key.trim().toUpperCase()];
                          final amountText = _currencyAmount(
                            entry.key,
                            entry.value,
                          );
                          final convertedText = hideBalances
                              ? '$baseCurrency ******'
                              : converted == null
                                  ? 'Rate missing'
                                  : _currencyAmount(baseCurrency, converted);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: Text(
                                    _currencyFlag(entry.key),
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    _currencyCountry(entry.key),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 0),
                                Expanded(
                                  flex: 8,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              amountText,
                                            maxLines: 1,
                                            softWrap: false,
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Theme.of(context).colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Expanded(
                                        flex: 7,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            '= $convertedText',
                                            maxLines: 1,
                                            softWrap: false,
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: converted == null
                                                  ? Theme.of(context).colorScheme.error
                                                  : Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                        ),
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
              if (entries.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total of foreign currencies in $baseCurrency',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hideBalances
                            ? '$baseCurrency ******'
                            : missingRates.isNotEmpty
                                ? 'Rate needed: ${missingRates.join(', ')}'
                                : selectedBaseRate == null ||
                                        selectedBaseRate <= 0
                                    ? '$baseCurrency —'
                                    : _currencyAmount(
                                        baseCurrency,
                                        foreignTotalPKR / selectedBaseRate,
                                      ),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double get monthlySavings => monthlyIncome - monthlyExpense;

  double get savingsRate => monthlyIncome <= 0
      ? 0
      : ((monthlySavings / monthlyIncome) * 100);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: GeneralPreferences.instance.personalizedHeaderTitle(context, Text(appText(context, "My Finance", "My Finance"),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
        )),
        actions: buildSharedAppBarActions(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Theme.of(context).dividerColor),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // Primary wallet balance.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$baseCurrency Wallets Total',
                          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .82), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5)),
                        const SizedBox(height: 5),
                        loading ? const SizedBox(height: 25, width: 25,
                          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 2))
                          : FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                            child: Text(_currencyAmount(baseCurrency, baseCurrencyWalletTotal),
                              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 25, fontWeight: FontWeight.w800))),
                      ])),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(appText(context, 'Other Currencies', 'دیگر کرنسیاں'),
                          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .78), fontSize: 11, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        if (loading)
                          const SizedBox(height: 25, width: 25,
                            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 2))
                        else if (firstOtherCurrency == null)
                          Text(appText(context, 'No other currencies', 'کوئی دوسری کرنسی نہیں'),
                            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12))
                        else ...[
                          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                            child: Text(_currencyAmount(firstOtherCurrency!.key, firstOtherCurrency!.value),
                              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 19, fontWeight: FontWeight.w800))),
                          if (otherCurrencyTotals.length > 1)
                            Padding(padding: const EdgeInsets.only(top: 3),
                              child: Text('+${otherCurrencyTotals.length - 1} ${appText(context, 'more currencies', 'مزید کرنسیاں')}',
                                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .78), fontSize: 11))),
                          TextButton(onPressed: _showAllCurrencies,
                            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 4), minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: Text(appText(context, 'View All Currencies', 'تمام کرنسیاں دیکھیں'),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                        ],
                      ])),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(child: Text('${appText(context, 'Consolidated in', 'میں مجموعی حساب')} $baseCurrency',
                        style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .78), fontSize: 11, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      loading ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(color: Theme.of(context).colorScheme.onPrimary, strokeWidth: 2))
                        : Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight,
                            child: Text(money(totalBalance),
                              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 20, fontWeight: FontWeight.w900)))),
                    ]),
                  ),
                ],
              ),
            ),
            SizedBox(height: 18),
            Text(appText(context, 'Financial Snapshot', 'مالیاتی جائزہ'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface)),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    title: appText(context, 'Assets', 'اثاثے'),
                    value: currentAssetsPKR,
                    icon: Icons.real_estate_agent_outlined,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    title: appText(context, 'Loans Receivable', 'وصول طلب قرضے'),
                    value: loansReceivablePKR,
                    icon: Icons.handshake_outlined,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onPrimary,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      color: Theme.of(context).colorScheme.primary, size: 25),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(appText(context, 'Estimated Net Worth', 'تخمینی خالص مالیت'),
                        style: TextStyle(fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        loading ? '...' : money(estimatedNetWorth),
                        style: const TextStyle(fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary, fontSize: 17),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 18),
            Text(appText(context, 'This Month', 'اس ماہ'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface)),
            SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    title: appText(context, 'Income', 'آمدنی'),
                    value: monthlyIncome,
                    icon: Icons.south_west_rounded,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    title: appText(context, 'Expenses', 'اخراجات'),
                    value: monthlyExpense,
                    icon: Icons.north_east_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onPrimary,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.savings_outlined,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(appText(context, 'Net Monthly Savings', 'ماہانہ خالص بچت'),
                            style: TextStyle(fontSize: 12,
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.w600)),
                        SizedBox(height: 3),
                        Text(money(monthlySavings),
                            style: TextStyle(fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: monthlySavings >= 0
                                    ? Theme.of(context).colorScheme.secondary
                                    : Theme.of(context).colorScheme.error)),
                      ],
                    ),
                  ),
                  Text(
                    '${savingsRate.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
            SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(appText(context, 'Budget Alerts', 'بجٹ الرٹس'),
                      style: TextStyle(fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface)),
                ),
                if (budgetAlerts.isNotEmpty)
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const BudgetsScreen())),
                    child: Text(appText(context, 'View Budgets', 'بجٹ دیکھیں')),
                  ),
              ],
            ),
            SizedBox(height: 10),
            if (loading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (budgetAlerts.isEmpty)
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onPrimary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: Theme.of(context).colorScheme.secondary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(appText(context, 'No budget alerts. Your active budgets are below 50%.', 'کوئی بجٹ الرٹ نہیں۔ آپ کے فعال بجٹ 50 فیصد سے کم ہیں۔'),
                          style: TextStyle(fontSize: 12,
                              color: Theme.of(context).hintColor)),
                    ),
                  ],
                ),
              )
            else
              ...budgetAlerts.take(4).map(_budgetAlertCard),
            SizedBox(height: 22),
            Text(appText(context, 'Overview', 'جائزہ'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface)),
            SizedBox(height: 10),
            _overviewCard(
              icon: Icons.real_estate_agent_outlined,
              title: appText(context, 'Assets Overview', 'اثاثوں کا جائزہ'),
              summary: loading ? 'Loading asset summary...' : '$overviewAssetCount active asset(s)',
              detail: 'Currently owned assets',
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _overviewCard(
              icon: Icons.handshake_outlined,
              title: appText(context, 'Loans Overview', 'قرضوں کا جائزہ'),
              summary: loading ? 'Loading loan summary...' : '$overviewLoanCount outstanding loan(s)',
              detail: '$overviewOverdueLoanCount overdue',
              color: Theme.of(context).colorScheme.secondary,
            ),
            _overviewCard(
              icon: Icons.account_balance_wallet_outlined,
              title: appText(context, 'Budgets Overview', 'بجٹ کا جائزہ'),
              summary: loading ? 'Loading budget summary...' : '$overviewBudgetCount active budget(s)',
              detail: budgetAlerts.isEmpty ? 'No budget alerts' : '${budgetAlerts.length} budget(s) need attention',
              color: Theme.of(context).colorScheme.tertiary,
            ),
            _overviewCard(
              icon: Icons.flag_outlined,
              title: appText(context, 'Goals Overview', 'اہداف کا جائزہ'),
              summary: loading ? 'Loading goals summary...' : '$overviewGoalCount active goal(s)',
              detail: '$overviewCompletedGoalCount completed',
              color: Theme.of(context).colorScheme.secondary,
            ),
            _overviewCard(
              icon: Icons.repeat_rounded,
              title: appText(context, 'Recurring Txns', 'مقررہ لین دین'),
              summary: loading ? 'Loading schedules...' : '$overviewActiveRecurringCount active schedule(s)',
              detail: '$overviewRecurringCount total schedule(s)',
              color: Theme.of(context).colorScheme.primary,
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
        color: Theme.of(context).colorScheme.onPrimary,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            SizedBox(width: 7),
            Text(title, style: const TextStyle(fontSize: 12,
                color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
          ]),
          SizedBox(height: 9),
          loading
              ? SizedBox(height: 18, width: 18,
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
        ? Theme.of(context).colorScheme.error
        : ratio >= 0.9
            ? Theme.of(context).colorScheme.tertiary
            : ratio >= 0.75
                ? Theme.of(context).colorScheme.tertiary
                : Theme.of(context).colorScheme.primary;
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
        color: Theme.of(context).colorScheme.onPrimary,
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
                      fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
            ),
            Text('${percent.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800, color: color)),
          ]),
          SizedBox(height: 5),
          Text(status, style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w600, color: color)),
          SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 7,
              backgroundColor: Theme.of(context).dividerColor,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          SizedBox(height: 7),
          Text('${budget.currency} ${NumberFormat('#,##0.00').format(budget.spentAmount)} spent of ${NumberFormat('#,##0.00').format(budget.limitAmount)}',
              style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }

  Widget _overviewCard({
    required IconData icon,
    required String title,
    required String summary,
    required String detail,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onPrimary,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Theme.of(context).dividerColor),
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
                const SizedBox(height: 4),
                Text(summary, style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(
                    color: Theme.of(context).hintColor, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
