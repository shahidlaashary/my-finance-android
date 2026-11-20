import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/models/budgets_model.dart';
import 'package:my_finance/features/finance/services/budgets_service.dart';
import 'package:my_finance/features/finance/services/category_service.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
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
  bool _hideBalances = false;
  String _filter = 'All';
  String _money(double amount) => _hideBalances ? '••••••' : _format.format(amount);
  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    AppRefreshController.revision.addListener(_onAppDataChanged);
    _loadData();
  }
  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  void _onAppDataChanged() {
    if (mounted) _loadData();
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
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final hideBalances = await GeneralPreferences.instance.hideBalances;
      final budgets = await BudgetsService.getBudgets();
      final categoryItems = await CategoryService.getCategories('expense');
      final categories = categoryItems.map((item) => {'name': item.name}).toList();
      // Wallet currencies central FinanceDB connection se load hoti hain.
      final db = FinanceDB.instance.db;
      final wallets = await db.query('wallets');
      final currencies = wallets
          .map((e) => e['currency']?.toString() ?? 'PKR')
          .toSet()
          .toList();
      if (!mounted) return;
      setState(() {
        _hideBalances = hideBalances;
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
    int? attachmentBudgetId = budget?.id;
    bool savedInThisSession = false;
    DateTime startDate = budget == null ? DateTime(DateTime.now().year, DateTime.now().month, 1) : budget.startDate;
    DateTime endDate = budget == null ? DateTime(DateTime.now().year, DateTime.now().month + 1, 0) : budget.endDate;
    InputDecoration decoration(String label, IconData icon) => InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 19),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)),
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
            child: Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Form(key: formKey, child: SingleChildScrollView(primary: false,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(10)))),
                  SizedBox(height: 12),
                  Row(children: [Expanded(child: Text(budget == null ? 'Create Budget' : 'Edit Budget', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface))),
                    IconButton(onPressed: () => Navigator.pop(sheetContext), icon: Icon(Icons.close_rounded), color: Theme.of(context).hintColor)]),
                  SizedBox(height: 10),
                  TextFormField(controller: nameController, decoration: decoration('Budget Name', Icons.pie_chart_outline),
                    validator: (v) => v == null || v.trim().isEmpty ? appText(context, 'Enter budget name', 'بجٹ کا نام درج کریں') : null),
                  SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextFormField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: decoration('Budget Limit', Icons.currency_exchange),
                      validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid budget amount' : null; },
                    )),
                    SizedBox(width: 10),
                    Expanded(child: DropdownButtonFormField<String>(
                      value: currency, isExpanded: true,
                      decoration: decoration('Currency', Icons.payments_outlined),
                      items: _currencies.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) { if (v != null) setSheetState(() => currency = v); },
                    )),
                  ]),
                  SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: DropdownButtonFormField<String?>(
                      value: category, isExpanded: true,
                      decoration: decoration('Category', Icons.category_outlined),
                      items: [DropdownMenuItem<String?>(value: null, child: Text(appText(context, 'All Categories', 'تمام زمرے'))),
                        ..._categories.map((c) => DropdownMenuItem<String?>(value: c['name'].toString(), child: Text(c['name'].toString(), overflow: TextOverflow.ellipsis)))],
                      onChanged: (v) => setSheetState(() => category = v),
                    )),
                    SizedBox(width: 10),
                    Expanded(child: DropdownButtonFormField<String>(
                      value: period, isExpanded: true,
                      decoration: decoration('Budget Period', Icons.calendar_view_month),
                      items: ['Daily','Weekly','Monthly','Yearly','Custom'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) { if (v != null) setSheetState(() => period = v); },
                    )),
                  ]),
                  SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final v = await showDatePicker(context: context, initialDate: startDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                        if (v != null) setSheetState(() { startDate = v; if (endDate.isBefore(startDate)) endDate = startDate; });
                      },
                      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary, size: 18), SizedBox(width: 6), Text(appText(context, "Start Date", "Start Date"), style: TextStyle(fontWeight: FontWeight.w600))]),
                        SizedBox(height: 5), Text(DateFormat('dd MMM yyyy').format(startDate), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                      ])),
                    )),
                    SizedBox(width: 12),
                    Expanded(child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final v = await showDatePicker(context: context, initialDate: endDate, firstDate: startDate, lastDate: DateTime(2100));
                        if (v != null) setSheetState(() => endDate = v);
                      },
                      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Icon(Icons.event, color: Theme.of(context).colorScheme.primary, size: 18), SizedBox(width: 6), Text(appText(context, "End Date", "End Date"), style: TextStyle(fontWeight: FontWeight.w600))]),
                        SizedBox(height: 5), Text(DateFormat('dd MMM yyyy').format(endDate), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                      ])),
                    )),
                  ]),
                  if (attachmentBudgetId != null) ...[
                    const SizedBox(height: 8),
                    AttachmentSection(ownerType: 'budget', ownerId: attachmentBudgetId!),
                  ],
                  SizedBox(height: 12),
                  Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext), child: Text(appText(context, 'Cancel', 'منسوخ کریں')))), SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(icon: Icon(Icons.check_rounded), label: Text(savedInThisSession ? 'Done' : budget == null ? 'Create Budget' : 'Update Budget'),
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary, padding: const EdgeInsets.symmetric(vertical: 13)),
                      onPressed: () async {
                        if (savedInThisSession) {
                          Navigator.pop(sheetContext);
                          await _loadData();
                          return;
                        }
                        if (!formKey.currentState!.validate()) return;
                        if (endDate.isBefore(startDate)) { _message('End date cannot be before start date.'); return; }
                        try {
                          final model = BudgetsModel(id: attachmentBudgetId, name: nameController.text.trim(), category: category,
                            limitAmount: double.parse(amountController.text), spentAmount: budget?.spentAmount ?? 0, period: period,
                            startDate: startDate, endDate: endDate, currency: currency, isActive: budget?.isActive ?? true, createdAt: budget?.createdAt ?? DateTime.now());
                          if (attachmentBudgetId == null) {
                            attachmentBudgetId = await BudgetsService.addBudget(model);
                          } else {
                            await BudgetsService.updateBudget(model);
                          }
                          if (!sheetContext.mounted) return;
                          setSheetState(() => savedInThisSession = true);
                          await _loadData();
                          _message(budget == null ? 'Budget created successfully. You can add attachments below.' : 'Budget updated successfully. You can manage attachments below.');
                        } catch (e) { _message('Error: $e'); }
                      }))]),
                ]))),
          ))));
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
          title: Text(appText(context, 'Delete Budget', 'بجٹ حذف کریں')),
          content: Text(
            'Are you sure you want to delete "${budget.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(appText(context, "Delete", "Delete")),
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
        ? Theme.of(context).colorScheme.error
        : progress >= 0.8
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.secondary;
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
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.pie_chart,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        budget.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${budget.period} • ${_categoryName(budget.category)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
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
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(appText(context, 'Edit Budget', 'بجٹ میں ترمیم کریں')),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        budget.isActive ? 'Pause Budget' : 'Activate Budget',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(appText(context, 'Delete Budget', 'بجٹ حذف کریں')),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Spent: ${budget.currency} ${_money(spent)}',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Limit: ${budget.currency} ${_money(limit)}',
                ),
              ],
            ),
            SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                color: color,
              ),
            ),
            SizedBox(height: 8),
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
            SizedBox(height: 10),
            Text(
              '${DateFormat('dd MMM yyyy').format(budget.startDate)}  —  ${DateFormat('dd MMM yyyy').format(budget.endDate)}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
            if (!budget.isActive)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Chip(
                  label: Text(appText(context, 'Paused', 'روکا گیا')),
                  backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: GeneralPreferences.instance.personalizedHeaderTitle(context, Text(appText(context, "My Budgets", "My Budgets"), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface))),
        actions: buildSharedAppBarActions(context),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBudgetDialog(),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        icon: Icon(Icons.add),
        label: Text(appText(context, 'New Budget', 'نیا بجٹ')),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'All',
                          label: Text(appText(context, 'All', 'تمام')),
                        ),
                        ButtonSegment(
                          value: 'Active',
                          label: Text(appText(context, 'Active', 'فعال')),
                        ),
                        ButtonSegment(
                          value: 'Paused',
                          label: Text(appText(context, 'Paused', 'روکا گیا')),
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
                    Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.pie_chart_outline,
                            size: 55,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          SizedBox(height: 12),
                          Text(appText(context, "No budgets found.", "No budgets found."),
                            style: TextStyle(color: Theme.of(context).hintColor),
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
