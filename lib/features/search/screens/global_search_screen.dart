import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/modules/finance/screens/categories_management_screen.dart';
import 'package:my_finance/modules/finance/screens/transactions_screen.dart';
import 'package:my_finance/modules/finance/services/assets_service.dart';
import 'package:my_finance/modules/finance/services/budgets_service.dart';
import 'package:my_finance/modules/finance/services/goals_service.dart';
import 'package:my_finance/modules/finance/services/loans_service.dart';
import 'package:my_finance/modules/parties/services/party_service.dart';
import 'package:my_finance/modules/finance/services/transactions_service.dart';
import 'package:my_finance/modules/committee/services/committee_service.dart';
import 'package:my_finance/modules/space/services/space_documents_service.dart';
import 'package:my_finance/modules/installments/services/installment_service.dart';
import 'package:my_finance/modules/stock/services/stock_service.dart';
import 'package:my_finance/modules/staff/services/staff_service.dart';
import 'package:my_finance/modules/vehicles/services/vehicle_service.dart';

class _SearchRecord {
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Map<String, dynamic> data;

  const _SearchRecord({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.data,
  });
}

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const List<String> _filters = [
    'All',
    'Transactions',
    'Wallets',
    'Categories',
    'Loans',
    'Budgets',
    'Goals',
    'Assets',
    'Documents',
    'Stock',
    'Staff',
    'Installments',
    'Vehicles',
    'Committee',
  ];

  final TextEditingController _controller = TextEditingController();
  Timer? _searchDebounce;
  List<_SearchRecord> _records = [];
  bool _searching = false;
  int _searchRequest = 0;
  String _activeFilter = 'All';

  bool _matches(Map<String, dynamic> data, String query) {
    return data.values.any(
      (value) => value != null && value.toString().toLowerCase().contains(query),
    );
  }

  void initState() {
    super.initState();
    AppRefreshController.revision.addListener(_onAppDataChanged);
  }

  void _onAppDataChanged() {
    final query = _controller.text.trim();
    if (mounted && query.length >= 2) _scheduleSearch(query);
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    final request = ++_searchRequest;
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _records = [];
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _searchRecords(query, request);
    });
  }

  void _addRecord(
    List<_SearchRecord> target, {
    required String query,
    required String type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Map<String, dynamic> data,
  }) {
    if (target.length >= 120 || !_matches(data, query)) return;
    target.add(_SearchRecord(
      type: type,
      title: title.trim().isEmpty ? type : title.trim(),
      subtitle: subtitle,
      icon: icon,
      data: Map<String, dynamic>.from(data),
    ));
  }

  Future<void> _collect(
    Future<void> Function() task,
  ) async {
    try {
      await task();
    } catch (_) {
      // Aik module ka unavailable hona baqi records ki search ko nahi rokta.
    }
  }

  Future<void> _searchRecords(String rawQuery, int request) async {
    final query = rawQuery.trim().toLowerCase();
    if (!mounted || query.length < 2 || request != _searchRequest) return;
    setState(() => _searching = true);

    final found = <_SearchRecord>[];

    await Future.wait([
      _collect(() async {
        final rows = await TransactionsService.getTransactions();
        for (final row in rows) {
          final data = Map<String, dynamic>.from(row);
          final type = data['type']?.toString() ?? 'Transaction';
          final amount = data['amount']?.toString() ?? '';
          final category = data['category_name']?.toString() ?? data['category']?.toString() ?? '';
          final note = data['note']?.toString() ?? '';
          _addRecord(
            found,
            query: query,
            type: 'Transactions',
            title: '$type  •  $amount',
            subtitle: [category, note, data['date']?.toString() ?? '']
                .where((value) => value.trim().isNotEmpty)
                .join('  ·  '),
            icon: Icons.receipt_long_outlined,
            data: data,
          );
          if (found.length >= 120) break;
        }
      }),
      _collect(() async {
        final rows = await FinanceDB.instance.getWallets();
        for (final row in rows) {
          final data = Map<String, dynamic>.from(row);
          final name = data['name']?.toString() ?? 'Wallet';
          final currency = data['currency']?.toString() ?? '';
          final balance = data['balance']?.toString() ?? '';
          _addRecord(
            found,
            query: query,
            type: 'Wallets',
            title: name,
            subtitle: [data['type']?.toString() ?? 'Wallet', currency, balance]
                .where((value) => value.trim().isNotEmpty)
                .join('  ·  '),
            icon: Icons.account_balance_wallet_outlined,
            data: data,
          );
        }
      }),
      _collect(() async {
        for (final categoryType in ['Income', 'Expense']) {
          final rows = await FinanceDB.instance.getCategories(categoryType);
          for (final row in rows) {
            final data = Map<String, dynamic>.from(row)..['type'] = categoryType;
            final name = data['name']?.toString() ?? 'Category';
            _addRecord(
              found,
              query: query,
              type: 'Categories',
              title: name,
              subtitle: '$categoryType category',
              icon: Icons.category_outlined,
              data: data,
            );
          }
        }
      }),
      _collect(() async {
        final rows = await LoansService.getLoans();
        final parties = await PartyService.getParties();
        final partyNames = {
          for (final party in parties)
            (party['id'] as num).toInt(): party['name']?.toString() ?? '',
        };
        for (final loan in rows) {
          final data = loan.toMap();
          final partyName = loan.partyId == null ? '' : (partyNames[loan.partyId!] ?? '');
          data['party_name'] = partyName;
          final title = partyName.isEmpty ? 'Loan #${loan.id?.toString() ?? ''}' : partyName;
          _addRecord(
            found,
            query: query,
            type: 'Loans',
            title: title,
            subtitle: '${loan.loanType == 'given' ? 'Loan Given' : 'Loan Taken'}  ·  Remaining ${loan.remainingAmount}',
            icon: Icons.handshake_outlined,
            data: data,
          );
        }
        for (final party in parties) {
          final data = Map<String, dynamic>.from(party)..['record_kind'] = 'Party';
          _addRecord(
            found,
            query: query,
            type: 'Loans',
            title: party['name']?.toString() ?? 'Party',
            subtitle: 'Loan party  ·  ${party['phone'] ?? ''}',
            icon: Icons.people_outline,
            data: data,
          );
        }
      }),
      _collect(() async {
        final rows = await BudgetsService.getBudgets();
        for (final item in rows) {
          final data = item.toMap();
          _addRecord(
            found,
            query: query,
            type: 'Budgets',
            title: item.name,
            subtitle: '${item.period} budget  ·  ${item.currency} ${item.limitAmount}',
            icon: Icons.account_balance_outlined,
            data: data,
          );
        }
      }),
      _collect(() async {
        final rows = await GoalsService.getGoals();
        for (final item in rows) {
          final data = item.toMap();
          _addRecord(
            found,
            query: query,
            type: 'Goals',
            title: item.name,
            subtitle: 'Savings goal  ·  Target ${item.targetAmount}',
            icon: Icons.flag_outlined,
            data: data,
          );
        }
      }),
      _collect(() async {
        final rows = await AssetsService().getAssets();
        for (final item in rows) {
          final data = item.toMap();
          _addRecord(
            found,
            query: query,
            type: 'Assets',
            title: item.name,
            subtitle: 'Asset  ·  ${item.category}${item.isSold ? '  ·  Sold' : ''}',
            icon: Icons.real_estate_agent_outlined,
            data: data,
          );
        }
      }),
      _collect(() async {
        final rows = await SpaceDocumentsService.instance.getDocuments();
        for (final item in rows) {
          final data = item.toMap();
          _addRecord(
            found,
            query: query,
            type: 'Documents',
            title: item.title,
            subtitle: 'Document  ·  ${item.category}${item.documentNumber.isEmpty ? '' : '  ·  ${item.documentNumber}'}',
            icon: Icons.folder_copy_outlined,
            data: data,
          );
        }
      }),
      _collect(() async {
        final rows = await StockService.getItems();
        for (final item in rows) {
          final data = <String, dynamic>{
            'id': item.id,
            'name': item.name,
            'sku': item.sku,
            'category': item.category,
            'unit': item.unit,
            'quantity': item.quantity,
            'low_stock_at': item.lowStockAt,
            'purchase_price': item.purchasePrice,
            'sale_price': item.salePrice,
            'notes': item.notes,
          };
          _addRecord(
            found,
            query: query,
            type: 'Stock',
            title: item.name,
            subtitle: 'Stock  ·  ${item.category}  ·  Qty ${item.quantity} ${item.unit}',
            icon: Icons.inventory_2_outlined,
            data: data,
          );
        }
      }),
      _collect(() async {
        final rows = await StaffService.getStaff();
        for (final row in rows) {
          final data = Map<String, dynamic>.from(row);
          _addRecord(
            found,
            query: query,
            type: 'Staff',
            title: data['name']?.toString() ?? 'Staff',
            subtitle: 'Staff  ·  ${data['role'] ?? ''}  ·  ${data['phone'] ?? ''}',
            icon: Icons.badge_outlined,
            data: data,
          );
        }
      }),
      _collect(() async {
        final rows = await InstallmentService.getContracts();
        for (final row in rows) {
          final data = Map<String, dynamic>.from(row);
          _addRecord(
            found,
            query: query,
            type: 'Installments',
            title: data['item_name']?.toString() ?? 'Installment',
            subtitle: 'Installment  ·  ${data['party_name'] ?? ''}  ·  ${data['direction'] ?? ''}',
            icon: Icons.payments_outlined,
            data: data,
          );
        }
      }),
      _collect(() async {
        final committees = await CommitteeService.getCommittees();
        for (final committee in committees) {
          final committeeId = (committee['id'] as num).toInt();
          final committeeName = committee['name']?.toString() ?? 'Committee';
          final committeeData = Map<String, dynamic>.from(committee)
            ..['record_kind'] = 'Committee';
          _addRecord(
            found,
            query: query,
            type: 'Committee',
            title: committeeName,
            subtitle: 'Committee  ·  ${committee['frequency'] ?? ''}  ·  ${committee['status'] ?? ''}',
            icon: Icons.groups_2_outlined,
            data: committeeData,
          );

          final members = await CommitteeService.getMembers(committeeId);
          for (final member in members) {
            final data = Map<String, dynamic>.from(member)
              ..['committee_name'] = committeeName
              ..['record_kind'] = 'Member';
            _addRecord(
              found,
              query: query,
              type: 'Committee',
              title: member['name']?.toString() ?? 'Committee member',
              subtitle: 'Member  ·  $committeeName  ·  ${member['phone'] ?? ''}',
              icon: Icons.person_outline_rounded,
              data: data,
            );
          }

          final entries = await CommitteeService.getEntries(committeeId);
          for (final entry in entries) {
            final data = Map<String, dynamic>.from(entry)
              ..['committee_name'] = committeeName
              ..['record_kind'] = 'Committee entry';
            _addRecord(
              found,
              query: query,
              type: 'Committee',
              title: entry['member_name']?.toString() ?? 'Committee entry',
              subtitle: '${entry['entry_type'] ?? 'Entry'}  ·  $committeeName  ·  ${entry['amount'] ?? ''}  ·  ${entry['entry_date'] ?? ''}',
              icon: Icons.payments_outlined,
              data: data,
            );
          }
        }
      }),
      _collect(() async {
        final rows = await VehicleService.getVehicles();
        for (final row in rows) {
          final data = Map<String, dynamic>.from(row);
          _addRecord(
            found,
            query: query,
            type: 'Vehicles',
            title: data['name']?.toString() ?? data['model']?.toString() ?? 'Vehicle',
            subtitle: 'Vehicle  ·  ${data['registration'] ?? data['registration_number'] ?? data['make'] ?? ''}',
            icon: Icons.directions_car_outlined,
            data: data,
          );
        }
      }),
    ]);

    if (!mounted || request != _searchRequest) return;
    setState(() {
      _records = found;
      _searching = false;
    });
  }

  List<_SearchRecord> get _visibleRecords {
    if (_activeFilter == 'All') return _records;
    return _records.where((record) => record.type == _activeFilter).toList();
  }

  void _openRecord(_SearchRecord record) {
    if (record.type == 'Transactions') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(transaction: record.data),
        ),
      );
      return;
    }

    VoidCallback? relatedAction;
    String? relatedLabel;
    if (record.type == 'Wallets') {
      final walletId = (record.data['id'] as num?)?.toInt();
      if (walletId != null) {
        relatedLabel = 'View wallet transactions';
        relatedAction = () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TransactionsScreen(
                walletId: walletId,
                walletName: record.title,
              ),
            ),
          );
        };
      }
    } else if (record.type == 'Categories') {
      relatedLabel = 'Open category manager';
      relatedAction = () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoriesPage(
              initialType: record.data['type']?.toString() ?? 'Income',
            ),
          ),
        );
      };
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SearchRecordDetailScreen(
          record: record,
          relatedLabel: relatedLabel,
          onRelatedTap: relatedAction,
        ),
      ),
    );
  }

  @override
  void dispose() {
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    _searchDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final visibleRecords = _visibleRecords;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Global Search',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _scheduleSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search transactions, wallets, categories...',
                prefixIcon: Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchRequest++;
                          _controller.clear();
                          setState(() {
                            _records = [];
                            _searching = false;
                          });
                        },
                        icon: Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final selected = _activeFilter == filter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: selected,
                  onSelected: (_) => setState(() => _activeFilter = filter),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                  ),
                  selectedColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: Theme.of(context).cardColor,
                  side: BorderSide(
                    color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  showCheckmark: false,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 9, 18, 8),
            child: Row(
              children: [
                Text(
                  query.length < 2 ? 'SEARCH SAVED RECORDS' : 'SEARCH RESULTS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.05,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                const Spacer(),
                if (query.length >= 2 && !_searching)
                  Text(
                    '${visibleRecords.length} found',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                  ),
              ],
            ),
          ),
          Expanded(
            child: query.length < 2
                ? const _SearchHint()
                : _searching
                    ? const Center(child: CircularProgressIndicator())
                    : visibleRecords.isEmpty
                        ? _NoSearchResults(filter: _activeFilter)
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: visibleRecords.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 7),
                            itemBuilder: (context, index) {
                              final record = visibleRecords[index];
                              return Material(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(14),
                                child: ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 3,
                                  ),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      record.icon,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 21,
                                    ),
                                  ),
                                  title: Text(
                                    record.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${record.type}  ·  ${record.subtitle}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  trailing: Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Theme.of(context).hintColor,
                                  ),
                                  onTap: () => _openRecord(record),
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

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search_rounded,
              size: 48,
              color: Theme.of(context).hintColor.withValues(alpha: .65),
            ),
            const SizedBox(height: 12),
            Text(
              'Search your saved records',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              'Type at least 2 characters to find transactions, wallets, categories and other records.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  final String filter;

  const _NoSearchResults({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 46,
              color: Theme.of(context).hintColor.withValues(alpha: .65),
            ),
            const SizedBox(height: 10),
            Text(
              filter == 'All' ? 'No matching records found' : 'No matching $filter records',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Try another name, amount, number or detail.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchRecordDetailScreen extends StatelessWidget {
  final _SearchRecord record;
  final String? relatedLabel;
  final VoidCallback? onRelatedTap;

  const _SearchRecordDetailScreen({
    required this.record,
    this.relatedLabel,
    this.onRelatedTap,
  });

  String _label(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _displayValue(dynamic value) {
    if (value is bool) return value ? 'Yes' : 'No';
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    const hiddenKeys = {
      'id',
      'icon',
      'icon_code',
      'created_at',
      'updated_at',
      'wallet_id',
      'to_wallet_id',
      'sale_wallet_id',
      'party_id',
    };
    final details = record.data.entries.where((entry) {
      if (hiddenKeys.contains(entry.key)) return false;
      if (entry.value == null || entry.value.toString().trim().isEmpty) return false;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          record.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(record.icon, color: Theme.of(context).colorScheme.primary, size: 25),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.type,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          record.title,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        if (record.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            record.subtitle,
                            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: details.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No additional details available.'),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < details.length; index++) ...[
                        if (index > 0)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 112,
                                child: Text(
                                  _label(details[index].key),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).hintColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _displayValue(details[index].value),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (onRelatedTap != null && relatedLabel != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRelatedTap,
                icon: Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(relatedLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
