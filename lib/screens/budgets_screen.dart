import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/budgets_model.dart';
import '../services/budgets_service.dart';
import '../services/category_service.dart';
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}
class _BudgetsScreenState extends State<BudgetsScreen> {
  final NumberFormat _format = NumberFormat('#,##0.00');
  List<BudgetsModel> _budgets = [];
  List<Map<String, dynamic>> _categories = [];
  List<String> _currencies = ['PKR'];
  bool _loading = true;
  String _filter = 'All';
  String _money(double amount) => _format.format(amount);
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final budgets = await BudgetsService.getBudgets();
      final categoryItems = await CategoryService.getCategories('expense');
      final categories = categoryItems.map((item) => {'name': item.name}).toList();
      final dbPath = await getDatabasesPath();
      final db = await openDatabase(p.join(dbPath, 'my_finance.db'));
      final wallets = await db.query('wallets');
      final currencies = wallets
          .map((e) => e['currency']?.toString() ?? 'PKR')
          .toSet()
          .toList();
      if (!mounted) return;
      setState(() {
        _budgets = budgets;
        _categories = categories;
        _currencies = currencies.isEmpty ? ['PKR'] : currencies;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Error loading budgets: $e');
    }
  }
  String _categoryName(String? name) => name == null || name.isEmpty ? 'All Categories' : name;
  Future<void> _showBudgetDialog({BudgetsModel? budget}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: budget?.name ?? '');
    final amountController = TextEditingController(text: budget?.limitAmount.toString() ?? '');
    String? category = budget?.category;
    String currency = budget?.currency ?? _currencies.first;
    String period = budget?.period ?? 'Monthly';
    DateTime startDate = budget == null ? DateTime(DateTime.now().year, DateTime.now().month, 1) : budget.startDate;
    DateTime endDate = budget == null ? DateTime(DateTime.now().year, DateTime.now().month + 1, 0) : budget.endDate;
    InputDecoration decoration(String label, IconData icon) => InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 19),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E9E5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF147D59), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13), isDense: true);

    await showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent, elevation: 0,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheetState) {
        final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
        final screenHeight = MediaQuery.sizeOf(context).height;
        final maxHeight = keyboardHeight > 0 ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * .95 : screenHeight * .72;
        return AnimatedPadding(duration: const Duration(milliseconds: 220), curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: SafeArea(top: false, child: ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Form(key: formKey, child: SingleChildScrollView(primary: false,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD9E0DC), borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 12),
                  Row(children: [Expanded(child: Text(budget == null ? 'Create Budget' : 'Edit Budget', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF202B25)))),
                    IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded), color: Colors.grey)]),
                  const SizedBox(height: 10),
                  TextFormField(controller: nameController, decoration: decoration('Budget Name', Icons.pie_chart_outline),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Enter budget name' : null),
                  const SizedBox(height: 12),
                  TextFormField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: decoration('Budget Limit', Icons.currency_exchange),
                    validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid budget amount' : null; }),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(value: category, isExpanded: true, decoration: decoration('Category', Icons.category_outlined),
                    items: [const DropdownMenuItem<String?>(value: null, child: Text('All Categories')),
                      ..._categories.map((c) => DropdownMenuItem<String?>(value: c['name'].toString(), child: Text(c['name'].toString())))],
                    onChanged: (v) => setSheetState(() => category = v)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(value: period, isExpanded: true, decoration: decoration('Budget Period', Icons.calendar_view_month),
                    items: const ['Daily','Weekly','Monthly','Yearly','Custom'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) { if (v != null) setSheetState(() => period = v); }),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(value: currency, isExpanded: true, decoration: decoration('Currency', Icons.payments_outlined),
                    items: _currencies.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) { if (v != null) setSheetState(() => currency = v); }),
                  ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.calendar_month, color: Color(0xFF147D59)),
                    title: const Text('Start Date'), subtitle: Text(DateFormat('dd MMM yyyy').format(startDate)), trailing: const Icon(Icons.edit_calendar),
                    onTap: () async { final v = await showDatePicker(context: context, initialDate: startDate, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (v != null) setSheetState(() => startDate = v); }),
                  ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event, color: Color(0xFF147D59)),
                    title: const Text('End Date'), subtitle: Text(DateFormat('dd MMM yyyy').format(endDate)), trailing: const Icon(Icons.edit_calendar),
                    onTap: () async { final v = await showDatePicker(context: context, initialDate: endDate, firstDate: startDate, lastDate: DateTime(2100); if (v != null) setSheetState(() => endDate = v); }),
                  const SizedBox(height: 12),
                  Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Cancel'))), const SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.check_rounded), label: Text(budget == null ? 'Create Budget' : 'Update Budget'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF147D59), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        if (endDate.isBefore(startDate)) { _message('End date cannot be before start date.'); return; }
                        try {
                          final model = BudgetsModel(id: budget?.id, name: nameController.text.trim(), category: category,
                            limitAmount: double.parse(amountController.text), spentAmount: budget?.spentAmount ?? 0, period: period,
                            startDate: startDate, endDate: endDate, currency: currency, isActive: budget?.isActive ?? true, createdAt: budget?.createdAt ?? DateTime.now());
                          if (budget == null) await BudgetsService.addBudget(model); else await BudgetsService.updateBudget(model);
                          if (!sheetContext.mounted) return;
                          Navigator.pop(sheetContext); await _loadData();
                          _message(budget == null ? 'Budget created successfully.' : 'Budget updated successfully.');
                        } catch (e) { _message('Error: $e'); }
                      }))]),
                ]))),
          ));
      }),
    );
    nameController.dispose(); amountController.dispose();
  }
  Future<void> _toggleBudget(BudgetsModel budget) async {
    if (budget.id == null) return;
    try {
      await BudgetsService.setBudgetStatus(
        budget.id!,
        !budget.isActive,
      );
      await _loadData();
      _message(
        budget.isActive ? 'Budget paused.' : 'Budget activated.',
      );
    } catch (e) {
      _message('Error: $e');
    }
  }
  Future<void> _deleteBudget(BudgetsModel budget) async {
    if (budget.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Budget'),
          content: Text(
            'Are you sure you want to delete "${budget.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    try {
      await BudgetsService.deleteBudget(budget.id!);
      await _loadData();
      _message('Budget deleted.');
    } catch (e) {
      _message('Error: $e');
    }
  }
  Widget _budgetCard(BudgetsModel budget) {
    final spent = budget.spentAmount;
    final limit = budget.limitAmount;
    final progress = limit <= 0
        ? 0.0
        : (spent / limit).clamp(0.0, 1.0);
    final exceeded = spent > limit;
    final remaining = limit - spent;
    final color = exceeded
        ? Colors.red
        : progress >= 0.8
            ? Colors.orange
            : Colors.green;
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE6F1EC),
                  child: Icon(
                    Icons.pie_chart,
                    color: Color(0xFF147D59),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        budget.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${budget.period} • ${_categoryName(budget.category)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showBudgetDialog(budget: budget);
                    } else if (value == 'toggle') {
                      _toggleBudget(budget);
                    } else if (value == 'delete') {
                      _deleteBudget(budget);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit Budget'),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        budget.isActive ? 'Pause Budget' : 'Activate Budget',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Budget'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Spent: ${budget.currency} ${_money(spent)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Limit: ${budget.currency} ${_money(limit)}',
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).toStringAsFixed(1)}% used',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  exceeded
                      ? 'Exceeded: ${budget.currency} ${_money(-remaining)}'
                      : 'Remaining: ${budget.currency} ${_money(remaining)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${DateFormat('dd MMM yyyy').format(budget.startDate)}  —  ${DateFormat('dd MMM yyyy').format(budget.endDate)}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            if (!budget.isActive)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Chip(
                  label: Text('Paused'),
                  backgroundColor: Color(0xFFFFF0D9),
                ),
              ),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final visibleBudgets = _budgets.where((budget) {
      if (_filter == 'Active') return budget.isActive;
      if (_filter == 'Paused') return !budget.isActive;
      return true;
    }).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        title: const Text('Budgets'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBudgetDialog(),
        backgroundColor: const Color(0xFF147D59),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Budget'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'All',
                          label: Text('All'),
                        ),
                        ButtonSegment(
                          value: 'Active',
                          label: Text('Active'),
                        ),
                        ButtonSegment(
                          value: 'Paused',
                          label: Text('Paused'),
                        ),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _filter = selection.first;
                        });
                      },
                    ),
                  ),
                  if (visibleBudgets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.pie_chart_outline,
                            size: 55,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No budgets found.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    ...visibleBudgets.map(_budgetCard),
                ],
              ),
            ),
    );
  }
}
