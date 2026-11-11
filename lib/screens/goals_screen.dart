import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/savings_goal_model.dart';
import '../services/savings_service.dart';
import '../widgets/attachment_section.dart';
class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});
  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}
class _SavingsScreenState extends State<SavingsScreen> {
  final NumberFormat _numberFormat = NumberFormat('#,##0.00');
  List<SavingsGoalModel> _goals = [];
  List<Map<String, dynamic>> _wallets = [];
  Map<String, double> _savedByCurrency = {};
  Map<String, double> _targetByCurrency = {};
  bool _loading = true;
  String _money(double amount) => _numberFormat.format(amount);
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
    if (mounted) setState(() => _loading = true);
    try {
      final dbPath = await getDatabasesPath();
      final db = await openDatabase(p.join(dbPath, 'my_finance.db'));
      final wallets = await db.query(
        'wallets',
        orderBy: 'name ASC',
      );
      final goals = await SavingsService.getGoals();
      final saved = await SavingsService.getTotalSavedByCurrency();
      final target = await SavingsService.getTotalTargetByCurrency();
      if (!mounted) return;
      setState(() {
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
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('No linked account'),
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
  Future<void> _showGoalDialog({
    SavingsGoalModel? goal,
  }) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: goal?.name ?? '',
    );
    final targetController = TextEditingController(
      text: goal == null ? '' : goal.targetAmount.toString(),
    );
    final notesController = TextEditingController(
      text: goal?.notes ?? '',
    );
    DateTime targetDate = goal?.targetDate ??
        DateTime.now().add(const Duration(days: 30));
    int? walletId = goal?.walletId;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                goal == null ? 'Create Savings Goal' : 'Edit Savings Goal',
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
                            labelText: 'Goal Name',
                            prefixIcon: Icon(Icons.flag),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter goal name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: targetController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Target Amount',
                            prefixIcon: Icon(Icons.savings),
                          ),
                          validator: (value) {
                            final amount = double.tryParse(value ?? '');
                            if (amount == null ||
                                !amount.isFinite ||
                                amount <= 0) {
                              return 'Enter a valid target amount';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          value: walletId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Linked Account',
                          ),
                          items: _accountItems(),
                          onChanged: (value) {
                            setDialogState(() {
                              walletId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Target Date'),
                          subtitle: Text(
                            DateFormat('dd MMM yyyy').format(targetDate),
                          ),
                          trailing: const Icon(Icons.calendar_month),
                          onTap: () async {
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: targetDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (selected != null) {
                              setDialogState(() {
                                targetDate = selected;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: notesController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                          ),
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
                    try {
                      final model = SavingsGoalModel(
                        id: goal?.id,
                        name: nameController.text.trim(),
                        targetAmount: double.parse(targetController.text),
                        savedAmount: goal?.savedAmount ?? 0,
                        targetDate: targetDate,
                        walletId: walletId,
                        notes: notesController.text.trim(),
                        isCompleted: goal?.isCompleted ?? false,
                        createdAt: goal?.createdAt ?? DateTime.now(),
                      );
                      if (goal == null) {
                        await SavingsService.addGoal(model);
                      } else {
                        await SavingsService.updateGoal(model);
                      }
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      await _loadData();
                      _message(
                        goal == null
                            ? 'Savings goal created.'
                            : 'Savings goal updated.',
                      );
                    } catch (e) {
                      _message('Error: $e');
                    }
                  },
                  child: Text(goal == null ? 'Create' : 'Update'),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();
    targetController.dispose();
    notesController.dispose();
  }
  Future<void> _showContributionDialog(
    SavingsGoalModel goal,
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
          title: const Text('Add Savings'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Contribution Amount',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                if (value == null || !value.isFinite || value <= 0) return;
                Navigator.pop(context, value);
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (amount == null) return;
    try {
      await SavingsService.addContribution(
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
  Future<void> _withdraw(SavingsGoalModel goal) async {
    if (goal.id == null) return;
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Withdraw Savings'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Withdrawal Amount',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = double.tryParse(controller.text);
                if (value == null || !value.isFinite || value <= 0) return;
                Navigator.pop(context, value);
              },
              child: const Text('Withdraw'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (amount == null) return;
    try {
      await SavingsService.withdraw(
        goalId: goal.id!,
        amount: amount,
      );
      await _loadData();
      _message('Withdrawal completed.');
    } catch (e) {
      _message('Error withdrawing savings: $e');
    }
  }
  Future<void> _deleteGoal(SavingsGoalModel goal) async {
    if (goal.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Savings Goal'),
          content: Text(
            'Delete "${goal.name}" and its savings history?',
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
      await SavingsService.deleteGoal(goal.id!);
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
            const SizedBox(height: 9),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 5),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Savings Summary by Currency',
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
  Widget _goalCard(SavingsGoalModel goal) {
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
                const SizedBox(width: 12),
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
                        'Target: ${DateFormat('dd MMM yyyy').format(targetDate)}',
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
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit Goal'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Goal'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Account: $accountLabel',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Saved Amount'),
                Text(
                  '${_money(goal.savedAmount)} $currency',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: completed ? Colors.green : const Color(0xFF147D59),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(progress * 100).toStringAsFixed(1)}% completed'),
                Text('Target: ${_money(goal.targetAmount)} $currency'),
              ],
            ),
            const SizedBox(height: 10),
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
              const SizedBox(height: 8),
              Text(
                goal.notes,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _showContributionDialog(goal),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Savings'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _withdraw(goal),
                  icon: const Icon(Icons.remove),
                  label: const Text('Withdraw'),
                ),
              ],
            ),
            if (goal.id != null) ...[
              const Divider(height: 24),
              AttachmentSection(
                ownerType: 'savings_goal',
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
        title: const Text('Savings Goals'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGoalDialog(),
        backgroundColor: const Color(0xFF147D59),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Goal'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  _currencySummary(),
                  if (_goals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.savings_outlined,
                            size: 55,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No savings goals yet.',
                            style: TextStyle(color: Colors.grey),
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
