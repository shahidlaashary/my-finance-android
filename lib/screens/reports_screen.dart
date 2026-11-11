
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/reports_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ReportsService _service = ReportsService();

  DateTime _startDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  DateTime _endDate = DateTime.now();

  String? _selectedCurrency;

  bool _loading = true;
  String? _error;

  List<String> _currencies = [];
  List<Map<String, dynamic>> _summary = [];
  List<Map<String, dynamic>> _trend = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _wallets = [];
  List<Map<String, dynamic>> _balances = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.getAvailableCurrencies(),
        _service.getSummary(
          startDate: _startDate,
          endDate: _endDate,
        ),
        _service.getMonthlyTrend(
          startDate: _startDate,
          endDate: _endDate,
          currency: _selectedCurrency,
        ),
        _service.getCategoryBreakdown(
          startDate: _startDate,
          endDate: _endDate,
          type: 'expense',
          currency: _selectedCurrency,
        ),
        _service.getAccountBreakdown(
          startDate: _startDate,
          endDate: _endDate,
        ),
        _service.getBalancesByCurrency(),
        _service.getTransactionHistory(
          startDate: _startDate,
          endDate: _endDate,
          currency: _selectedCurrency,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _currencies = results[0] as List<String>;
        _summary = results[1] as List<Map<String, dynamic>>;
        _trend = results[2] as List<Map<String, dynamic>>;
        _categories = results[3] as List<Map<String, dynamic>>;
        _wallets = results[4] as List<Map<String, dynamic>>;
        _balances = results[5] as List<Map<String, dynamic>>;
        _history = results[6] as List<Map<String, dynamic>>;

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  double _number(dynamic value) {
    return (value as num?)?.toDouble() ?? 0.0;
  }

  String _money(dynamic amount, [String? currency]) {
    final value = NumberFormat('#,##0.00').format(
      _number(amount),
    );

    return '${currency ?? _selectedCurrency ?? 'PKR'} $value';
  }

  String _dateFormat(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  Future<void> _pickStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: _endDate,
    );

    if (selected == null) return;

    setState(() {
      _startDate = selected;
    });

    _loadReports();
  }

  Future<void> _pickEndDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );

    if (selected == null) return;

    setState(() {
      _endDate = selected;
    });

    _loadReports();
  }

  void _setPeriod(String period) {
    final now = DateTime.now();

    setState(() {
      if (period == 'This Month') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = now;
      } else if (period == 'Last Month') {
        _startDate = DateTime(now.year, now.month - 1, 1);
        _endDate = DateTime(now.year, now.month, 0);
      } else if (period == 'Last 30 Days') {
        _startDate = now.subtract(const Duration(days: 29));
        _endDate = now;
      } else if (period == 'This Year') {
        _startDate = DateTime(now.year, 1, 1);
        _endDate = now;
      }
    });

    _loadReports();
  }

  List<Map<String, dynamic>> get _filteredSummary {
    if (_selectedCurrency == null) {
      return _summary;
    }

    return _summary
        .where(
          (item) => item['currency'] == _selectedCurrency,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        actions: [
          IconButton(
            onPressed: _loadReports,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh reports',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _loadReports,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildFilters(),
                      const SizedBox(height: 20),
                      _buildSummaryCards(),
                      const SizedBox(height: 24),
                      _buildBalanceSection(),
                      const SizedBox(height: 24),
                      _buildMonthlyTrend(theme),
                      const SizedBox(height: 24),
                      _buildCategorySection(),
                      const SizedBox(height: 24),
                      _buildAccountSection(),
                      const SizedBox(height: 24),
                      _buildTransactionHistory(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to load reports',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadReports,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Report Filters',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<String?>(
              value: _selectedCurrency,
              decoration: const InputDecoration(
                labelText: 'Currency',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_exchange),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All Currencies'),
                ),
                ..._currencies.map(
                  (currency) => DropdownMenuItem<String?>(
                    value: currency,
                    child: Text(currency),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedCurrency = value;
                });
                _loadReports();
              },
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStartDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _dateFormat(_startDate),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEndDate,
                    icon: const Icon(Icons.event),
                    label: Text(
                      _dateFormat(_endDate),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'This Month',
                'Last Month',
                'Last 30 Days',
                'This Year',
              ].map((period) {
                return ActionChip(
                  label: Text(period),
                  onPressed: () => _setPeriod(period),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Currency ke mutabiq mali khulasa.
  Widget _buildSummaryCards() {
    final currencies = _filteredSummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Financial Summary',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        if (currencies.isEmpty)
          _emptyMessage('No financial summary available'),

        ...currencies.map((item) {
          final currency =
              item['currency']?.toString() ?? 'PKR';

          final income = _number(item['income']);
          final expense = _number(item['expense']);
          final transfers = _number(item['transfers']);
          final net = income - expense;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: 8,
                  bottom: 8,
                ),
                child: Text(
                  'Currency: $currency',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              _summaryCard(
                title: 'Total Income',
                amount: income,
                currency: currency,
                color: Colors.green,
                icon: Icons.trending_up,
              ),

              _summaryCard(
                title: 'Total Expenses',
                amount: expense,
                currency: currency,
                color: Colors.red,
                icon: Icons.trending_down,
              ),

              _summaryCard(
                title: 'Net Balance',
                amount: net,
                currency: currency,
                color: net >= 0
                    ? Colors.blue
                    : Colors.orange,
                icon: Icons.account_balance_wallet,
              ),

              _summaryCard(
                title: 'Transfers',
                amount: transfers,
                currency: currency,
                color: Colors.purple,
                icon: Icons.swap_horiz,
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required double amount,
    required String currency,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(
          _money(amount, currency),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceSection() {
    final items = _selectedCurrency == null
        ? _balances
        : _balances
            .where(
              (item) =>
                  item['currency'] == _selectedCurrency,
            )
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current Account Balances',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        if (items.isEmpty)
          _emptyMessage('No account balances available'),

        ...items.map((item) {
          final currency = item['currency']?.toString() ?? '';

          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.account_balance),
              ),
              title: Text(currency),
              subtitle: Text(
                '${item['account_count']} wallets',
              ),
              trailing: Text(
                _money(
                  item['total_balance'],
                  currency,
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMonthlyTrend(ThemeData theme) {
    final data = _trend;

    // Har currency ke liye alag scale istemal karein.
    final currencyGroups = <String, List<Map<String, dynamic>>>{};

    for (final item in data) {
      final currency = item['currency']?.toString() ?? '';
      currencyGroups.putIfAbsent(currency, () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Monthly Income & Expense Trend',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _legend('Income', Colors.green),
                    const SizedBox(width: 20),
                    _legend('Expense', Colors.red),
                  ],
                ),
                const SizedBox(height: 20),

                if (data.isEmpty)
                  _emptyMessage('No monthly data available')
                else
                  ...currencyGroups.entries.map((group) {
                    final currency = group.key;
                    final currencyData = group.value;

                    final maximum = currencyData.fold<double>(
                      0,
                      (value, item) {
                        final income = _number(item['income']);
                        final expense = _number(item['expense']);
                        final current = income > expense
                            ? income
                            : expense;

                        return current > value ? current : value;
                      },
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 12,
                            top: 8,
                          ),
                          child: Text(
                            currency.isEmpty
                                ? 'Currency'
                                : currency,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),

                        ...currencyData.map((item) {
                          final income = _number(item['income']);
                          final expense = _number(item['expense']);

                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: 18,
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['month']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                _trendBar(
                                  label: 'Income',
                                  amount: income,
                                  maximum: maximum,
                                  color: Colors.green,
                                ),

                                const SizedBox(height: 6),

                                _trendBar(
                                  label: 'Expense',
                                  amount: expense,
                                  maximum: maximum,
                                  color: Colors.red,
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  Widget _trendBar({
    required String label,
    required double amount,
    required double maximum,
    required Color color,
  }) {
    final progress = maximum <= 0
        ? 0.0
        : (amount / maximum).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 65,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: color,
              backgroundColor: color.withOpacity(0.12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          NumberFormat.compact().format(amount),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Expense by Category',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        if (_categories.isEmpty)
          _emptyMessage('No category expenses found'),

        ..._categories.map((item) {
          final currency =
              item['currency']?.toString() ?? '';

          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.category),
              ),
              title: Text(
                item['category_name']?.toString() ??
                    'Uncategorized',
              ),
              subtitle: Text(
                '${item['transaction_count']} transactions',
              ),
              trailing: Text(
                _money(item['total'], currency),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAccountSection() {
    final items = _selectedCurrency == null
        ? _wallets
        : _wallets
            .where(
              (item) =>
                  item['currency'] == _selectedCurrency,
            )
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Account-wise Summary',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        if (items.isEmpty)
          _emptyMessage('No account activity found'),

        ...items.map((item) {
          final currency =
              item['currency']?.toString() ?? '';

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    item['wallet_name']?.toString() ??
                        'Account',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  _accountValue(
                    'Income',
                    item['income'],
                    currency,
                    Colors.green,
                  ),

                  _accountValue(
                    'Expense',
                    item['expense'],
                    currency,
                    Colors.red,
                  ),

                  _accountValue(
                    'Transfers',
                    item['transfers'],
                    currency,
                    Colors.purple,
                  ),

                  const Divider(),

                  _accountValue(
                    'Net',
                    item['net'],
                    currency,
                    Colors.blue,
                  ),

                  const SizedBox(height: 4),

                  Text(
                    '${item['transaction_count']} transactions',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _accountValue(
    String label,
    dynamic amount,
    String currency,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            _money(amount, currency),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transaction History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        if (_history.isEmpty)
          _emptyMessage('No transactions found'),

        ..._history.map((item) {
          final type = item['type']?.toString() ?? '';
          final normalized = type.toLowerCase();

          final isIncome = normalized == 'income';
          final isExpense = normalized == 'expense';

          final color = isIncome
              ? Colors.green
              : isExpense
                  ? Colors.red
                  : Colors.purple;

          final icon = isIncome
              ? Icons.arrow_downward
              : isExpense
                  ? Icons.arrow_upward
                  : Icons.swap_horiz;

          final currency =
              item['currency']?.toString() ?? '';

          final amount = _money(
            item['amount'],
            currency,
          );

          final dateText = item['date'] == null
              ? ''
              : item['date'].toString().split('T').first;

          final note = item['note']?.toString() ?? '';

          final category =
              item['category_name']?.toString() ?? '';

          final account =
              item['wallet_name']?.toString() ?? '';

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(0.12),
                child: Icon(icon, color: color),
              ),
              title: Text(
                note.isNotEmpty ? note : type,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  account,
                  if (category.isNotEmpty) category,
                  dateText,
                ].where((value) => value.isNotEmpty).join(' • '),
                maxLines: 2,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    type,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _emptyMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}
