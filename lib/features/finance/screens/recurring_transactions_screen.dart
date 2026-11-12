import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:my_finance/features/finance/models/recurring_transaction_model.dart';
import 'package:my_finance/features/finance/services/recurring_transaction_service.dart';
import 'package:my_finance/features/finance/services/category_service.dart';

class RecurringTransactionsScreen extends StatefulWidget {
  const RecurringTransactionsScreen({super.key});

  @override
  State<RecurringTransactionsScreen> createState() =>
      _RecurringTransactionsScreenState();
}

class _RecurringTransactionsScreenState
    extends State<RecurringTransactionsScreen> {
  final RecurringTransactionService _service =
      RecurringTransactionService();

  List<RecurringTransactionModel> _items = [];
  List<Map<String, dynamic>> _wallets = [];
  List<Map<String, dynamic>> _categories = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final dbPath = await getDatabasesPath();
      final db = await openDatabase(p.join(dbPath, 'my_finance.db'));

      final wallets = await db.query(
        'wallets',
        orderBy: 'name ASC',
      );

      final categoryItems = [
        ...await CategoryService.getCategories('income'),
        ...await CategoryService.getCategories('expense'),
      ];
      final categories = categoryItems
          .map((item) => {'name': item.name, 'type': item.type})
          .toList();

      final items = await _service.getRecurringTransactions();

      if (!mounted) return;

      setState(() {
        _wallets = wallets;
        _categories = categories;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      _showMessage('Data load error: $e', isError: true);
    }
  }

  String _money(double amount, String currency) {
    return '$currency ${amount.toStringAsFixed(2)}';
  }

  String _date(DateTime? value) {
    if (value == null) return 'Not set';

    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
  }

  String _accountName(int? id) {
    if (id == null) return 'Unknown account';

    final matches = _wallets.where(
      (account) => account['id'] == id,
    );

    if (matches.isEmpty) return 'Unknown account';

    return matches.first['name'].toString();
  }

  String _currency(int? id) {
    if (id == null) return '';

    final matches = _wallets.where(
      (account) => account['id'] == id,
    );

    if (matches.isEmpty) return '';

    return (matches.first['currency'] ?? 'PKR').toString();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<void> _processDue() async {
    try {
      final count = await _service.processDueTransactions();

      await _loadData();

      final failed = _service.lastProcessingErrors;
      if (failed.isEmpty) {
        _showMessage('$count recurring transaction(s) processed.');
      } else {
        _showMessage(
          '$count transaction(s) processed; ${failed.length} schedule(s) paused due to errors. Open and edit them, then resume.',
          isError: true,
        );
      }
    } catch (e) {
      _showMessage('Processing failed: $e', isError: true);
    }
  }

  Future<void> _toggleStatus(
    RecurringTransactionModel item,
  ) async {
    if (item.id == null) return;

    try {
      await _service.setRecurringTransactionStatus(
        item.id!,
        !item.isActive,
      );

      await _loadData();
    } catch (e) {
      _showMessage('Status update failed: $e', isError: true);
    }
  }

  Future<void> _deleteItem(
    RecurringTransactionModel item,
  ) async {
    if (item.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: const Text(
          'Are you sure you want to delete this recurring schedule?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.deleteRecurringTransaction(item.id!);
      await _loadData();
      _showMessage('Schedule deleted successfully.');
    } catch (e) {
      _showMessage('Delete failed: $e', isError: true);
    }
  }

  Future<void> _openForm({
    RecurringTransactionModel? existing,
  }) async {
    if (_wallets.isEmpty) {
      _showMessage(
        'Please create an account before adding a recurring transaction.',
        isError: true,
      );
      return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.94,
        child: _RecurringTransactionDialog(
          wallets: _wallets,
          categories: _categories,
          existing: existing,
        ),
      ),
    );

    if (result == true) {
      await _loadData();
    }
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.repeat,
              size: 65,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 15),
            const Text(
              'No recurring transactions yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a schedule for regular income, expenses or transfers.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add Schedule'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transactionCard(RecurringTransactionModel item) {
    final isIncome = item.type.toLowerCase() == 'income';
    final isTransfer = item.isTransfer;

    final color = isIncome
        ? Colors.green
        : isTransfer
            ? Colors.blue
            : Colors.red;

    final icon = isIncome
        ? Icons.arrow_downward
        : isTransfer
            ? Icons.swap_horiz
            : Icons.arrow_upward;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.type.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _money(item.amount, _currency(item.walletId)),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _detailRow(
              Icons.account_balance_wallet,
              'Account',
              _accountName(item.walletId),
            ),
            if (isTransfer)
              _detailRow(
                Icons.account_balance,
                'Destination',
                _accountName(item.toWalletId),
              ),
            _detailRow(
              Icons.repeat,
              'Frequency',
              item.frequency.toUpperCase(),
            ),
            _detailRow(
              Icons.calendar_today,
              'Start date',
              _date(item.startDate),
            ),
            _detailRow(
              Icons.event,
              'Next run',
              _date(item.nextRunDate),
            ),
            if (item.endDate != null)
              _detailRow(
                Icons.event_busy,
                'End date',
                _date(item.endDate),
              ),
            if (item.note.isNotEmpty)
              _detailRow(
                Icons.notes,
                'Note',
                item.note,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: item.isActive
                        ? Colors.green.withOpacity(0.12)
                        : Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.isActive ? 'Active' : 'Paused',
                    style: TextStyle(
                      color: item.isActive
                          ? Colors.green
                          : Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => _openForm(existing: item),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: item.isActive ? 'Pause' : 'Resume',
                  onPressed: () => _toggleStatus(item),
                  icon: Icon(
                    item.isActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _deleteItem(item),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.grey),
          const SizedBox(width: 9),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.grey),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _items.where((e) => e.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Transactions'),
        actions: [
          IconButton(
            tooltip: 'Process Due Transactions',
            onPressed: _processDue,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add Schedule'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: _items.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.65,
                          child: _emptyState(),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.repeat,
                                  size: 32,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Recurring Schedules',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_items.length} total schedules',
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    Text(
                                      '$activeCount',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                    const Text(
                                      'Active',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Your Schedules',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._items.map(_transactionCard),
                        const SizedBox(height: 75),
                      ],
                    ),
            ),
    );
  }
}

class _RecurringTransactionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> categories;
  final RecurringTransactionModel? existing;

  const _RecurringTransactionDialog({
    required this.wallets,
    required this.categories,
    this.existing,
  });

  @override
  State<_RecurringTransactionDialog> createState() =>
      _RecurringTransactionDialogState();
}

class _RecurringTransactionDialogState
    extends State<_RecurringTransactionDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  late String _type;
  late String _frequency;

  int? _walletId;
  int? _toWalletId;
  String? _category;

  late DateTime _startDate;
  DateTime? _endDate;

  bool _saving = false;

  bool get _isTransfer => _type == 'transfer';

  @override
  void initState() {
    super.initState();

    final item = widget.existing;

    _titleController = TextEditingController(
      text: item?.title ?? '',
    );

    _amountController = TextEditingController(
      text: item?.amount.toString() ?? '',
    );

    _noteController = TextEditingController(
      text: item?.note ?? '',
    );

    _type = item?.type.toLowerCase() ?? 'expense';
    _frequency = item?.frequency.toLowerCase() ?? 'monthly';

    _walletId = item?.walletId;
    _toWalletId = item?.toWalletId;
    _category = item?.category;

    _startDate = item?.startDate ?? DateTime.now();
    _endDate = item?.endDate;

    if (!_accountExists(_walletId)) {
      _walletId = null;
    }

    if (!_accountExists(_toWalletId)) {
      _toWalletId = null;
    }
  }

  bool _accountExists(int? id) {
    if (id == null) return false;

    return widget.wallets.any(
      (account) => account['id'] == id,
    );
  }

  List<Map<String, dynamic>> get _availableCategories {
    if (_isTransfer) return [];

    return widget.categories.where((category) {
      return category['type'].toString().toLowerCase() == _type;
    }).toList();
  }

  Future<void> _pickDate({required bool isEndDate}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isEndDate
          ? (_endDate ?? _startDate)
          : _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected == null) return;

    setState(() {
      if (isEndDate) {
        _endDate = selected;
      } else {
        _startDate = selected;

        if (_endDate != null && _endDate!.isBefore(_startDate)) {
          _endDate = null;
        }
      }
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_walletId == null) {
      _message('Please select an account.');
      return;
    }

    if (_isTransfer) {
      if (_toWalletId == null) {
        _message('Please select destination account.');
        return;
      }

      if (_toWalletId == _walletId) {
        _message('Source and destination wallets must be different.');
        return;
      }

      final source = widget.wallets.firstWhere(
        (a) => a['id'] == _walletId,
      );

      final destination = widget.wallets.firstWhere(
        (a) => a['id'] == _toWalletId,
      );

      if (source['currency'] != destination['currency']) {
        _message('Transfer wallets must have the same currency.');
        return;
      }
    }

    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      _message('End date cannot be before start date.');
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());

    if (amount == null || amount <= 0) {
      _message('Please enter a valid amount.');
      return;
    }

    setState(() => _saving = true);

    try {
      final model = RecurringTransactionModel(
        id: widget.existing?.id,
        title: _titleController.text.trim(),
        type: _type,
        amount: amount,
        walletId: _walletId!,
        toWalletId: _isTransfer ? _toWalletId : null,
        category: _isTransfer ? null : _category,
        note: _noteController.text.trim(),
        frequency: _frequency,
        startDate: _startDate,
        endDate: _endDate,
        nextRunDate: widget.existing?.nextRunDate ?? _startDate,
        isActive: widget.existing?.isActive ?? true,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

      if (widget.existing == null) {
        await RecurringTransactionService().addRecurringTransaction(
          model,
        );
      } else {
        await RecurringTransactionService().updateRecurringTransaction(
          model,
        );
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      _message('Save failed: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {IconData? icon}) {
    return InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)), contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13));
  }

  @override
  Widget build(BuildContext context) {
    final categories = _availableCategories;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 8), child: Row(children: [Expanded(child: Text(widget.existing == null ? 'Add Schedule' : 'Edit Schedule', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))), IconButton(onPressed: _saving ? null : () => Navigator.pop(context, false), icon: const Icon(Icons.close))])),
        Container(width: 42, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(8))),
        Expanded(child: SingleChildScrollView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: EdgeInsets.fromLTRB(18, 18, 18, 20 + bottomInset), child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(segments: const [ButtonSegment(value: 'income', label: Text('Income')), ButtonSegment(value: 'expense', label: Text('Expense')), ButtonSegment(value: 'transfer', label: Text('Transfer'))], selected: {_type}, onSelectionChanged: _saving ? null : (value) => setState(() { _type = value.first; _category = null; _toWalletId = null; })),
          const SizedBox(height: 14),
          TextFormField(controller: _titleController, decoration: _decoration('Schedule Title', icon: Icons.title), validator: (value) => value == null || value.trim().isEmpty ? 'Please enter a title.' : null),
          const SizedBox(height: 12),
          if (_isTransfer) ...[
            Row(children: [
              Expanded(child: TextFormField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Amount', icon: Icons.payments_outlined), validator: (value) { final amount = double.tryParse(value ?? ''); return amount == null || amount <= 0 ? 'Enter a valid amount.' : null; })),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<int>(value: _walletId, isExpanded: true, decoration: _decoration('From Wallet', icon: Icons.account_balance_wallet_outlined), items: widget.wallets.map((account) => DropdownMenuItem<int>(value: account['id'] as int, child: Text('${account['name']} (${account['currency'] ?? 'PKR'})', overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setState(() { _walletId = value; if (_toWalletId == value) _toWalletId = null; }), validator: (value) => value == null ? 'Select wallet' : null)),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<int>(value: _toWalletId, isExpanded: true, decoration: _decoration('To Wallet', icon: Icons.account_balance_outlined), items: widget.wallets.where((a) => a['id'] != _walletId).map((account) => DropdownMenuItem<int>(value: account['id'] as int, child: Text('${account['name']} (${account['currency'] ?? 'PKR'})', overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setState(() => _toWalletId = value), validator: (value) => value == null ? 'Select wallet' : null)),
            ]),
          ] else ...[
            Row(children: [
              Expanded(child: TextFormField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _decoration('Amount', icon: Icons.payments_outlined), validator: (value) { final amount = double.tryParse(value ?? ''); return amount == null || amount <= 0 ? 'Enter a valid amount.' : null; })),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<int>(value: _walletId, isExpanded: true, decoration: _decoration('Wallet', icon: Icons.account_balance_wallet_outlined), items: widget.wallets.map((account) => DropdownMenuItem<int>(value: account['id'] as int, child: Text('${account['name']} (${account['currency'] ?? 'PKR'})', overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setState(() => _walletId = value), validator: (value) => value == null ? 'Select wallet' : null)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(value: categories.any((item) => item['name'] == _category) ? _category : null, isExpanded: true, decoration: _decoration('Category', icon: Icons.category_outlined), hint: const Text('Optional'), items: categories.map((item) => DropdownMenuItem<String>(value: item['name'].toString(), child: Text(item['name'].toString(), overflow: TextOverflow.ellipsis))).toList(), onChanged: (value) => setState(() => _category = value))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _noteController, decoration: _decoration('Notes (Optional)', icon: Icons.notes_rounded))),
            ]),
          ],
          if (_isTransfer) ...[const SizedBox(height: 12), TextFormField(controller: _noteController, maxLines: 2, decoration: _decoration('Notes (Optional)', icon: Icons.notes_rounded))],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(value: _frequency, isExpanded: true, decoration: _decoration('Repeat Schedule', icon: Icons.repeat_rounded), items: const [DropdownMenuItem(value: 'daily', child: Text('Daily')), DropdownMenuItem(value: 'weekly', child: Text('Weekly')), DropdownMenuItem(value: 'monthly', child: Text('Monthly')), DropdownMenuItem(value: 'yearly', child: Text('Yearly'))], onChanged: (value) { if (value != null) setState(() => _frequency = value); }),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: InkWell(onTap: () => _pickDate(isEndDate: false), borderRadius: BorderRadius.circular(12), child: InputDecorator(decoration: _decoration('Start Date', icon: Icons.calendar_month_outlined), child: Text(_formatDate(_startDate))))),
            const SizedBox(width: 10),
            Expanded(child: InkWell(onTap: () => _pickDate(isEndDate: true), borderRadius: BorderRadius.circular(12), child: InputDecorator(decoration: _decoration('End Date (Optional)', icon: Icons.event_outlined).copyWith(suffixIcon: _endDate == null ? null : IconButton(onPressed: () => setState(() => _endDate = null), icon: const Icon(Icons.close))), child: Text(_endDate == null ? 'No end date' : _formatDate(_endDate!))))),
          ]),
        ]))),
        Padding(padding: EdgeInsets.fromLTRB(18, 10, 18, 14 + MediaQuery.of(context).padding.bottom), child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.pop(context, false), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: const Text('Cancel'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: _saving ? null : _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.existing == null ? 'Save Schedule' : 'Update Schedule'))),
        ])),
      ]),
    );
  }}
