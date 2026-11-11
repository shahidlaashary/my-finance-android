import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/budget_model.dart';
import '../services/budget_service.dart';\nimport '../services/category_service.dart';
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}
class _BudgetsScreenState extends State<BudgetsScreen> {
  final NumberFormat _format = NumberFormat('#,##0.00');
  List<BudgetModel> _budgets = [];
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
      final budgets = await BudgetService.getBudgets();
      final categoryItems = await CategoryService.getCategories('expense');\n      final categories = categoryItems.map((item) => {'name': item.name}).toList();\n      final dbPath = await getDatabasesPath();\n      final db = await openDatabase(p.join(dbPath, 'my_finance.db'));\n      final wallets = await db.query('wallets');
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
  String _categoryName(int? id) {
    if (id == null) return 'All Categories';
    final matches = _categories.where(
      (category) => category['id'] == id,
    );
    if (matches.isEmpty) return 'Unknown Category';
    return matches.first['name'].toString();
  }
  Future<void> _showBudgetDialog({
    BudgetModel? budget,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: budget?.name ?? '',
    );
    final amountController = TextEditingController(
      text: budget == null ? '' : budget.limitAmount.toString(),
    );
    String? category = budget?.category;
    String currency = budget?.currency ?? _currencies.first;
    String period = budget?.period ?? 'Monthly';
    DateTime startDate = budget == null
        ? DateTime(DateTime.now().year, DateTime.now().month, 1)
        : budget.startDate;
    DateTime endDate = budget == null
        ? DateTime(DateTime.now().year, DateTime.now().month + 1, 0)
        : budget.endDate;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                budget == null ? 'Create Budget' : 'Edit Budget',
              ),
              content: SizedBox(
                width: 450,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Budget Name',
                            prefixIcon: Icon(Icons.account_balance_wallet),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter budget name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: amountController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Budget Limit',
                          ),
                          validator: (value) {
                            final amount = double.tryParse(value ?? '');
                            if (amount == null ||
                                !amount.isFinite ||
                                amount <= 0) {
                              return 'Enter a valid budget amount';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          value: category,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Categories'),
                            ),
                            ..._categories.map((category) {
                              return DropdownMenuItem<String?>(
                                value: category['name'].toString(),
                                child: Text(
                                  category['name'].toString(),
                                ),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              category = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: period,
                          decoration: const InputDecoration(
                            labelText: 'Budget Period',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Daily',
                              child: Text('Daily'),
                            ),
                            DropdownMenuItem(
                              value: 'Weekly',
                              child: Text('Weekly'),
                            ),
                            DropdownMenuItem(
                              value: 'Monthly',
                              child: Text('Monthly'),
                            ),
                            DropdownMenuItem(
                              value: 'Yearly',
                              child: Text('Yearly'),
                            ),
                            DropdownMenuItem(
                              value: 'Custom',
                              child: Text('Custom'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              period = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: currency,
                          decoration: const InputDecoration(
                            labelText: 'Currency',
                          ),
                          items: _currencies.map((value) {
                            return DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              currency = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Start Date'),
                          subtitle: Text(
                            DateFormat('dd MMM yyyy').format(startDate),
                          ),
                          trailing: const Icon(Icons.calendar_month),
                          onTap: () async {
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (selected != null) {
                              setDialogState(() {
                                startDate = selected;
                              });
                            }
                          },
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('End Date'),
                          subtitle: Text(
                            DateFormat('dd MMM yyyy').format(endDate),
                          ),
                          trailing: const Icon(Icons.calendar_month),
                          onTap: () async {
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: endDate,
                              firstDate: startDate,
                              lastDate: DateTime(2100),
                            );
                            if (selected != null) {
                              setDialogState(() {
                                endDate = selected;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    if (endDate.isBefore(startDate)) {
                      _message('End date cannot be before start date.');
                      return;
                    }
                    try {
                      final model = BudgetModel(
                        id: budget?.id,
                        name: nameController.text.trim(),
                        category: category,
                        limitAmount: double.parse(amountController.text),
                        spentAmount: budget?.spentAmount ?? 0,
                        period: period,
                        startDate: startDate,
                        endDate: endDate,
                        currency: currency,
                        isActive: budget?.isActive ?? true,
                        createdAt: budget?.createdAt ?? DateTime.now(),
                      );
                      if (budget == null) {
                        await BudgetService.addBudget(model);
                      } else {
                        await BudgetService.updateBudget(model);
                      }
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      await _loadData();
                      _message(
                        budget == null
                            ? 'Budget created successfully.'
                            : 'Budget updated successfully.',
                      );
                    } catch (e) {
                      _message('Error: $e');
                    }
                  },
                  child: Text(
                    budget == null ? 'Create Budget' : 'Update Budget',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();
    amountController.dispose();
  }
  Future<void> _toggleBudget(BudgetModel budget) async {
    if (budget.id == null) return;
    try {
      await BudgetService.setBudgetStatus(
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
  Future<void> _deleteBudget(BudgetModel budget) async {
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
      await BudgetService.deleteBudget(budget.id!);
      await _loadData();
      _message('Budget deleted.');
    } catch (e) {
      _message('Error: $e');
    }
  }
  Widget _budgetCard(BudgetModel budget) {
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
