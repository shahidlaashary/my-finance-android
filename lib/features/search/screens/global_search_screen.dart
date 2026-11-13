import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/features/dashboard/home_screen.dart';
import 'package:my_finance/features/finance/screens/assets_screen.dart';
import 'package:my_finance/features/finance/screens/budgets_screen.dart';
import 'package:my_finance/features/finance/screens/goals_screen.dart';
import 'package:my_finance/features/finance/screens/loans_screen.dart';
import 'package:my_finance/features/finance/screens/stats_screen.dart';
import 'package:my_finance/features/finance/screens/transactions_screen.dart';
import 'package:my_finance/features/finance/screens/wallets_screen.dart';
import 'package:my_finance/features/documents/screens/my_documents_screen.dart';
import 'package:my_finance/features/installments/screens/installments_screen.dart';
import 'package:my_finance/features/vehicles/screens/vehicles_screen.dart';
import 'package:my_finance/features/stock/screens/stock_manager_screen.dart';
import 'package:my_finance/features/staff/screens/staff_screen.dart';
import 'package:my_finance/features/finance/screens/recurring_transactions_screen.dart';
import 'package:my_finance/features/finance/screens/exchange_rates_screen.dart';
import 'package:my_finance/features/finance/screens/debt_payoff_screen.dart';
import 'package:my_finance/features/backup_restore/screens/backup_restore_screen.dart';
import 'package:my_finance/features/recycle_bin/screens/recycle_bin_screen.dart';
import 'package:my_finance/features/notifications/screens/reminders_screen.dart';
import 'package:my_finance/features/security/app_lock_screen.dart';
import 'package:my_finance/features/settings/general_app_preferences_screen.dart';
import 'package:my_finance/features/settings/base_currency_screen.dart';
import 'package:my_finance/features/settings/language_settings_screen.dart';
import 'package:my_finance/features/finance/screens/asset_depreciation_screen.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/documents/services/my_documents_service.dart';
import 'package:my_finance/features/stock/services/stock_service.dart';
import 'package:my_finance/features/staff/services/staff_service.dart';
import 'package:my_finance/features/installments/services/installment_service.dart';
import 'package:my_finance/features/vehicles/services/vehicle_service.dart';
import 'package:my_finance/app/screens/more_features_screen.dart' show AppSettingsScreen;
import 'package:my_finance/app/screens/about_hub_screen.dart';

class _SearchEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> keywords;
  final Widget Function() page;

  const _SearchEntry(this.title, this.subtitle, this.icon, this.keywords, this.page);
}

class _RecordSearchResult {
  final String title, subtitle;
  final IconData icon;
  final Widget Function() page;
  const _RecordSearchResult(this.title, this.subtitle, this.icon, this.page);
}

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  Timer? _searchDebounce;
  List<_RecordSearchResult> _recordResults = [];
  bool _searchingRecords = false;
  int _searchRequest = 0;

  bool _matches(Map<String, dynamic> row, String query) =>
      row.values.any((value) => value != null && value.toString().toLowerCase().contains(query));

  // Har keypress par database ki tamam queries chalane ke bajaye thora waqfa dete hain.
  void _scheduleRecordSearch(String query) {
    _searchRequest++;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchRecords(query);
    });
  }

  Future<void> _searchRecords(String rawQuery) async {
    final query = rawQuery.trim().toLowerCase();
    final request = ++_searchRequest;
    if (query.length < 2) {
      if (mounted) setState(() { _recordResults = []; _searchingRecords = false; });
      return;
    }
    setState(() => _searchingRecords = true);
    final found = <_RecordSearchResult>[];
    Future<void> collect(Future<void> Function() task) async {
      try { await task(); } catch (_) {}
    }
    await collect(() async {
      final rows = await TransactionsService.getTransactions();
      for (final row in rows.where((r) => _matches(r, query)).take(12)) {
        final type = row['type']?.toString() ?? 'Transaction';
        final category = row['category_name']?.toString() ?? row['category']?.toString() ?? '';
        final note = row['note']?.toString() ?? '';
        found.add(_RecordSearchResult('$type • ${row['amount'] ?? ''}',
          [category, note, row['date']?.toString() ?? ''].where((v) => v.trim().isNotEmpty).join(' · '),
          Icons.receipt_long_outlined, () => const TransactionsScreen()));
      }
    });
    await collect(() async {
      final rows = await AssetsService().getAssets();
      for (final item in rows.where((a) => [a.name, a.category, a.notes].any((v) => v.toLowerCase().contains(query))).take(8)) {
        found.add(_RecordSearchResult(item.name, 'Asset · ${item.category}${item.isSold ? ' · Sold' : ''}',
          Icons.real_estate_agent_outlined, () => const AssetsScreen()));
      }
    });
    await collect(() async {
      final rows = await MyDocumentsService.instance.getDocuments();
      for (final item in rows.where((d) => [d.title, d.category, d.documentNumber, d.notes].any((v) => v.toLowerCase().contains(query))).take(8)) {
        found.add(_RecordSearchResult(item.title, 'Document · ${item.category}${item.documentNumber.isEmpty ? '' : ' · ${item.documentNumber}'}',
          Icons.folder_copy_outlined, () => const MyDocumentsScreen()));
      }
    });
    await collect(() async {
      final rows = await StockService.getItems();
      for (final item in rows.where((i) => [i.name, i.sku, i.category, i.notes].any((v) => v.toLowerCase().contains(query))).take(8)) {
        found.add(_RecordSearchResult(item.name, 'Stock · ${item.category} · Qty ${item.quantity}',
          Icons.inventory_2_outlined, () => const StockManagerScreen()));
      }
    });
    await collect(() async {
      final rows = await StaffService.getStaff();
      for (final row in rows.where((r) => _matches(r, query)).take(8)) {
        found.add(_RecordSearchResult(row['name']?.toString() ?? 'Staff',
          'Staff · ${row['role'] ?? ''} · ${row['phone'] ?? ''}',
          Icons.badge_outlined, () => const StaffScreen()));
      }
    });
    await collect(() async {
      final rows = await InstallmentService.getContracts();
      for (final row in rows.where((r) => _matches(r, query)).take(8)) {
        found.add(_RecordSearchResult(row['item_name']?.toString() ?? 'Installment',
          'Installment · ${row['party_name'] ?? ''} · ${row['direction'] ?? ''}',
          Icons.payments_outlined, () => const InstallmentsScreen()));
      }
    });
    await collect(() async {
      final rows = await VehicleService.getVehicles();
      for (final row in rows.where((r) => _matches(r, query)).take(8)) {
        found.add(_RecordSearchResult(row['name']?.toString() ?? row['model']?.toString() ?? 'Vehicle',
          'Vehicle · ${row['registration'] ?? row['registration_number'] ?? row['make'] ?? ''}',
          Icons.directions_car_outlined, () => const VehiclesScreen()));
      }
    });
    if (!mounted || request != _searchRequest) return;
    setState(() { _recordResults = found; _searchingRecords = false; });
  }
  late final List<_SearchEntry> _entries = [
    _SearchEntry('Home', 'Dashboard and financial snapshot', Icons.home_outlined, ['dashboard','overview','balance','home'], () => const HomePage(featurePageBuilder: _unusedFeatureBuilder)),
    _SearchEntry('Assets', 'Manage owned assets and depreciation', Icons.real_estate_agent_outlined, ['property','vehicle','gold','livestock','business','asset depreciation'], () => const AssetsScreen()),
    _SearchEntry('Budgets', 'Limits, spending and budget alerts', Icons.account_balance_wallet_outlined, ['budget','limit','spending','alerts'], () => const BudgetsScreen()),
    _SearchEntry('Goals', 'Savings targets and progress', Icons.flag_outlined, ['saving','target','goal'], () => const GoalsScreen()),
    _SearchEntry('Loans', 'Track money lent and borrowed', Icons.handshake_outlined, ['debt','borrow','lend','receivable','payable'], () => const LoansScreen()),
    _SearchEntry('Reports & Analytics', 'Charts, insights and financial reports', Icons.bar_chart_outlined, ['reports','analytics','graphs','charts','statistics','income expense'], () => const StatsScreen()),
    _SearchEntry('Transactions', 'Search and manage income, expenses and transfers', Icons.receipt_long_outlined, ['income','expense','transfer','entries','payments'], () => const TransactionsScreen()),
    _SearchEntry('Wallets', 'Accounts, balances and currencies', Icons.account_balance_outlined, ['accounts','cash','bank','currency','wallet'], () => const WalletsPage()),
    _SearchEntry('My Documents', 'Store and find important documents', Icons.folder_copy_outlined, ['files','papers','pdf','attachments','identity','expiry'], () => const MyDocumentsScreen()),
    _SearchEntry('Installment Manager', 'Buy or sell items on installments', Icons.payments_outlined, ['qist','qistain','installment','monthly payment','buy','sell'], () => const InstallmentsScreen()),
    _SearchEntry('Vehicle Manager', 'Vehicle details and records', Icons.directions_car_outlined, ['car','bike','motorcycle','vehicle'], () => const VehiclesScreen()),
    _SearchEntry('Stock Manager', 'Inventory and stock records', Icons.inventory_2_outlined, ['inventory','products','items','stock'], () => const StockManagerScreen()),
    _SearchEntry('Staff Management', 'Manage staff and employee records', Icons.badge_outlined, ['employees','salary','team','staff'], () => const StaffScreen()),
    _SearchEntry('Recurring Transactions', 'Scheduled income and expenses', Icons.repeat_rounded, ['recurring','repeat','schedule','automatic','monthly'], () => const RecurringTransactionsScreen()),
    _SearchEntry('Exchange Rates', 'Currency conversion and exchange rates', Icons.currency_exchange_rounded, ['forex','convert','rate','exchange'], () => const ExchangeRatesScreen()),
    _SearchEntry('Debt Payoff Planner', 'Plan debt repayments', Icons.trending_down_rounded, ['debt','repayment','payoff','loan plan'], () => const DebtPayoffScreen()),
    _SearchEntry('Backup & Restore', 'Back up or restore app data', Icons.backup_outlined, ['backup','restore','export','import','data safety'], () => const BackupRestoreScreen()),
    _SearchEntry('Recycle Bin', 'Restore or permanently delete removed records', Icons.delete_outline_rounded, ['deleted','trash','restore','bin'], () => const RecycleBinScreen()),
    _SearchEntry('Notifications & Reminders', 'Manage reminders and alerts', Icons.notifications_active_outlined, ['notification','reminder','alarm','due date'], () => const RemindersScreen()),
    _SearchEntry('App Lock & Security', 'PIN and biometric protection', Icons.security_outlined, ['security','pin','password','fingerprint','face unlock','lock'], () => const AppLockScreen()),
    _SearchEntry('App Settings', 'Preferences and app configuration', Icons.tune_rounded, ['settings','preferences','customize'], () => const AppSettingsScreen()),
    _SearchEntry('Appearance', 'Themes, colors and display mode', Icons.palette_outlined, ['theme','dark mode','light mode','color'], () => const GeneralAppPreferencesScreen()),
    _SearchEntry('Base Currency', 'Choose your main currency', Icons.currency_exchange_outlined, ['pkr','default currency','main currency'], () => const BaseCurrencyScreen()),
    _SearchEntry('Languages', 'Change the app language', Icons.language_rounded, ['translation','urdu','english','pashto','balochi'], () => const LanguageSettingsScreen()),
    _SearchEntry('Asset Depreciation', 'Calculate asset value reduction', Icons.trending_down_rounded, ['depreciation','straight line','declining balance'], () => const AssetDepreciationScreen()),
    _SearchEntry('About', 'App information and credits', Icons.info_outline_rounded, ['about app','version','created by'], () => const AboutHubScreen()),
  ];

  static Widget _unusedFeatureBuilder(String title) => const SizedBox.shrink();

  List<_SearchEntry> get _results {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries.where((entry) {
      final haystack = ([entry.title, entry.subtitle, ...entry.keywords].join(' ')).toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _open(_SearchEntry entry) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => entry.page()));
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Global Search', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (value) { setState(() {}); _scheduleRecordSearch(value); },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search any feature or module...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty ? null : IconButton(
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _controller.clear();
                    _searchRecords('');
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 9),
            child: Row(
              children: [
                Text(_controller.text.isEmpty ? 'ALL FEATURES' : 'FEATURES & RECORDS',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: AppColors.muted)),
                const Spacer(),
                Text('${results.length + _recordResults.length} found', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
          Expanded(
            child: results.isEmpty && _recordResults.isEmpty && !_searchingRecords
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.search_off_rounded, size: 48, color: AppColors.muted.withValues(alpha: .6)),
                  const SizedBox(height: 10),
                  const Text('No matching result found', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('Try another keyword, name, number or detail.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: results.length + _recordResults.length + (_searchingRecords ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (context, index) {
                    if (index >= results.length) {
                      if (_searchingRecords && index == results.length) {
                        return const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()));
                      }
                      final record = _recordResults[index - results.length - (_searchingRecords ? 1 : 0)];
                      return Material(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
                          leading: Container(width: 40, height: 40,
                            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .09), borderRadius: BorderRadius.circular(12)),
                            child: Icon(record.icon, color: AppColors.primary, size: 21)),
                          title: Text(record.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          subtitle: Text(record.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.muted),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => record.page())),
                        ),
                      );
                    }
                    final entry = results[index];
                    return Material(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
                        leading: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .09), borderRadius: BorderRadius.circular(12)),
                          child: Icon(entry.icon, color: AppColors.primary, size: 21),
                        ),
                        title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        subtitle: Text(entry.subtitle, style: const TextStyle(fontSize: 11)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.muted),
                        onTap: () => _open(entry),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
