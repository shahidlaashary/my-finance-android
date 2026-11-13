import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:my_finance/features/finance/models/goals_model.dart';
import 'package:my_finance/features/finance/services/goals_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'package:my_finance/core/localization/app_text.dart';
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}
class _GoalsScreenState extends State<GoalsScreen> {
  final NumberFormat _numberFormat = NumberFormat('#,##0.00');
  List<GoalsModel> _goals = [];
  List<Map<String, dynamic>> _wallets = [];
  Map<String, double> _savedByCurrency = {};
  Map<String, double> _targetByCurrency = {};
  bool _loading = true;
  bool _hideBalances = false;
  String _money(double amount) => _hideBalances ? '••••••' : _numberFormat.format(amount);
  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    _loadData();
  }
  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
    if (mounted) setState(() => _loading = true);
    try {
      final hideBalances = await GeneralPreferences.instance.hideBalances;
      final dbPath = await getDatabasesPath();
      final db = await openDatabase(p.join(dbPath, 'my_finance.db'));
      final wallets = await db.query(
        'wallets',
        orderBy: 'name ASC',
      );
      final goals = await GoalsService.getGoals();
      final saved = await GoalsService.getTotalSavedByCurrency();
      final target = await GoalsService.getTotalTargetByCurrency();
      if (!mounted) return;
      setState(() {
        _hideBalances = hideBalances;
        _wallets = wallets;
        _goals = goals;
        _savedByCurrency = saved;
        _targetByCurrency = target;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Error loading savings: $e');
    }
  }
  List<DropdownMenuItem<int?>> _accountItems() {
    return [
      DropdownMenuItem<int?>(
        value: null,
        child: Text(appText(context, "No linked account", "No linked account")),
      ),
      ..._wallets.map((account) {
        final id = account['id'] as int;
        final name = account['name'].toString();
        final currency = account['currency']?.toString() ?? 'PKR';
        return DropdownMenuItem<int?>(
          value: id,
          child: Text('$name ($currency)'),
        );
      }),
    ];
  }
  Future<void> _showGoalDialog({GoalsModel? goal}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: goal?.name ?? '');
    final targetController = TextEditingController(text: goal?.targetAmount.toString() ?? '');
    final notesController = TextEditingController(text: goal?.notes ?? '');
    DateTime startDate = goal?.startDate ?? goal?.createdAt ?? DateTime.now();
    DateTime targetDate = goal?.targetDate ?? DateTime.now().add(const Duration(days: 30));
    if (startDate.isAfter(targetDate)) {
      startDate = targetDate;
    }
    int? walletId = goal?.walletId;
    InputDecoration decoration(String label, IconData icon) => InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 19),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E9E5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF147D59), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13), isDense: true);

    await showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true,
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
              child: Form(key: formKey, child: SingleChildScrollView(primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD9E0DC), borderRadius: BorderRadius.circular(10)))),
                  SizedBox(height: 12),
                  Row(children: [Expanded(child: Text(goal == null ? 'New Goal' : 'Edit Goal', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF202B25)))),
                    IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded), color: Colors.grey)]),
                  SizedBox(height: 10),
                  TextFormField(controller: nameController, decoration: decoration('Goal Name', Icons.flag_outlined),
                    validator: (v) => v == null || v.trim().isEmpty ? appText(context, 'Enter goal name', 'ہدف کا نام درج کریں') : null),
                  SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextFormField(
                      controller: targetController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: decoration('Target Amount', Icons.savings_outlined),
                      validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid target amount' : null; },
                    )),
                    SizedBox(width: 10),
                    Expanded(child: DropdownButtonFormField<int?>(
                      value: walletId, isExpanded: true,
                      decoration: decoration('Linked Account', Icons.account_balance_wallet_outlined),
                      items: _accountItems(), onChanged: (v) => setSheetState(() => walletId = v),
                    )),
                  ]),
                  SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final v = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime(2000),
                          lastDate: targetDate,
                        );
                        if (v != null) setSheetState(() => startDate = v);
                      },
                      child: InputDecorator(
                        decoration: decoration('Start Date', Icons.calendar_today_outlined),
                        child: Text(DateFormat('dd MMM yyyy').format(startDate),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    )),
                    SizedBox(width: 10),
                    Expanded(child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final v = await showDatePicker(
                          context: context,
                          initialDate: targetDate,
                          firstDate: startDate,
                          lastDate: DateTime(2100),
                        );
                        if (v != null) setSheetState(() => targetDate = v);
                      },
                      child: InputDecorator(
                        decoration: decoration('Target Date', Icons.event_outlined),
                        child: Text(DateFormat('dd MMM yyyy').format(targetDate),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    )),
                  ]),
                  SizedBox(height: 12),
                  TextFormField(controller: notesController, maxLines: 2, decoration: decoration('Notes (optional)', Icons.notes_outlined)),
                  SizedBox(height: 16),
                  Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext), child: Text(appText(context, 'Cancel', 'منسوخ کریں')))), SizedBox(width: 10),
                    Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.check_rounded), label: Text(goal == null ? 'Create Goal' : 'Update Goal'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF147D59), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        if (startDate.isAfter(targetDate)) {
                          _message('Start date cannot be after target date.');
                          return;
                        }
                        try {
                          final model = GoalsModel(id: goal?.id, name: nameController.text.trim(), targetAmount: double.parse(targetController.text),
                            savedAmount: goal?.savedAmount ?? 0, startDate: startDate, targetDate: targetDate, walletId: walletId, notes: notesController.text.trim(),
                            isCompleted: goal?.isCompleted ?? false, createdAt: goal?.createdAt ?? DateTime.now());
                          if (goal == null) await GoalsService.addGoal(model); else await GoalsService.updateGoal(model);
                          if (!sheetContext.mounted) return;
                          Navigator.pop(sheetContext); await _loadData();
                          _message(goal == null ? 'Savings goal created.' : 'Savings goal updated.');
                        } catch (e) { _message('Error: $e'); }
                      }))]),
                ]))),
          ))));
      }),
    );
    nameController.dispose(); targetController.dispose(); notesController.dispose();
  }
  Future<void> _showContributionDialog(
    GoalsModel goal,
  ) async {
    if (goal.id == null) return;
    if (goal.walletId == null) {
      _message('Please edit this goal and select a linked account first.');
      return;
    }
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(appText(context, 'Add Savings', 'بچت شامل کریں')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: appText(context, "Contribution Amount", "Contribution Amount"),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            ElevatedButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                if (value == null || !value.isFinite || value <= 0) return;
                Navigator.pop(context, value);
              },
              child: Text(appText(context, 'Continue', 'جاری رکھیں')),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (amount == null) return;
    try {
      await GoalsService.addContribution(
        goalId: goal.id!,
        walletId: goal.walletId!,
        amount: amount,
      );
      await _loadData();
      _message('Savings contribution added.');
    } catch (e) {
      _message('Error adding savings: $e');
    }
  }
  Future<void> _withdraw(GoalsModel goal) async {
    if (goal.id == null) return;
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(appText(context, 'Withdraw Savings', 'بچت نکالیں')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: appText(context, "Withdrawal Amount", "Withdrawal Amount"),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            ElevatedButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                if (value == null || !value.isFinite || value <= 0) return;
                Navigator.pop(context, value);
              },
              child: Text(appText(context, 'Withdraw', 'نکالیں')),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (amount == null) return;
    try {
      await GoalsService.withdraw(
        goalId: goal.id!,
        amount: amount,
      );
      await _loadData();
      _message('Withdrawal completed.');
    } catch (e) {
      _message('Error withdrawing savings: $e');
    }
  }
  Future<void> _deleteGoal(GoalsModel goal) async {
    if (goal.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(appText(context, 'Delete Savings Goal', 'بچت کا ہدف حذف کریں')),
          content: Text(
            'Delete "${goal.name}" and its savings history?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: Text(appText(context, "Delete", "Delete")),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    try {
      await GoalsService.deleteGoal(goal.id!);
      await _loadData();
      _message('Savings goal deleted.');
    } catch (e) {
      _message('Error deleting goal: $e');
    }
  }
  Widget _summaryCard(
    String title,
    double amount,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 25),
            SizedBox(height: 9),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 5),
            Text(
              _money(amount),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _currencySummary() {
    final currencies = <String>{
      ..._savedByCurrency.keys,
      ..._targetByCurrency.keys,
    }.toList()
      ..sort();
    if (currencies.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(appText(context, "Savings Summary by Currency", "Savings Summary by Currency"),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...currencies.map((currency) {
          final saved = _savedByCurrency[currency] ?? 0;
          final target = _targetByCurrency[currency] ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  currency,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.65,
                  children: [
                    _summaryCard(
                      'Total Saved ($currency)',
                      saved,
                      Icons.savings,
                      Colors.green,
                    ),
                    _summaryCard(
                      'Total Target ($currency)',
                      target,
                      Icons.flag,
                      Colors.blue,
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
  Widget _goalCard(GoalsModel goal) {
    final progress = goal.targetAmount <= 0
        ? 0.0
        : (goal.savedAmount / goal.targetAmount).clamp(0.0, 1.0);
    final remaining =
        (goal.targetAmount - goal.savedAmount).clamp(0.0, double.infinity);
    final completed = goal.savedAmount >= goal.targetAmount;
    final targetDate = goal.targetDate ?? DateTime.now();
    final linkedAccount = _wallets.where(
      (account) => account['id'] == goal.walletId,
    );
    final accountLabel = linkedAccount.isEmpty
        ? 'No linked account'
        : '${linkedAccount.first['name']} '
            '(${linkedAccount.first['currency'] ?? 'PKR'})';
    final currency = linkedAccount.isEmpty
        ? 'Unassigned'
        : linkedAccount.first['currency']?.toString() ?? 'PKR';
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
                  backgroundColor: Color(0xFFE4F3EC),
                  child: Icon(
                    Icons.savings,
                    color: Color(0xFF147D59),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${DateFormat('dd MMM yyyy').format(goal.startDate ?? goal.createdAt ?? targetDate)}  →  ${DateFormat('dd MMM yyyy').format(targetDate)}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showGoalDialog(goal: goal);
                    } else if (value == 'delete') {
                      _deleteGoal(goal);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(appText(context, 'Edit Goal', 'ہدف میں ترمیم کریں')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(appText(context, "Delete Goal", "Delete Goal")),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 14),
            Text(
              'Account: $accountLabel',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(appText(context, 'Saved Amount', 'محفوظ شدہ رقم')),
                Text(
                  '${_money(goal.savedAmount)} $currency',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: completed ? Colors.green : const Color(0xFF147D59),
              ),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(progress * 100).toStringAsFixed(1)}% ${appText(context, 'completed', 'مکمل')}'),
                Text('${appText(context, 'Target:', 'ہدف:')} ${_money(goal.targetAmount)} $currency'),
              ],
            ),
            SizedBox(height: 10),
            Text(
              completed
                  ? 'Goal completed!'
                  : 'Remaining: ${_money(remaining)} $currency',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: completed ? Colors.green : Colors.blueGrey,
              ),
            ),
            if (goal.notes.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                goal.notes,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _showContributionDialog(goal),
                  icon: const Icon(Icons.add),
                  label: Text(appText(context, 'Add Savings', 'بچت شامل کریں')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _withdraw(goal),
                  icon: const Icon(Icons.remove),
                  label: Text(appText(context, 'Withdraw', 'نکالیں')),
                ),
              ],
            ),
            if (goal.id != null) ...[
              const Divider(height: 24),
              AttachmentSection(
                ownerType: 'goal',
                ownerId: goal.id!,
              ),
            ],
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF202A26),
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: Text(appText(context, 'My Goals', 'میرے اہداف'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF202A26))),
        actions: buildSharedAppBarActions(context),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGoalDialog(),
        backgroundColor: const Color(0xFF147D59),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(appText(context, 'New Goal', 'نیا ہدف')),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  _currencySummary(),
                  if (_goals.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.savings_outlined,
                            size: 55,
                            color: const Color(0xFF147D59),
                          ),
                          SizedBox(height: 12),
                          Text(appText(context, "No savings goals yet.", "No savings goals yet."),
                            style: TextStyle(color: Color(0xFF7B8781)),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._goals.map(_goalCard),
                ],
              ),
            ),
    );
  }
}
