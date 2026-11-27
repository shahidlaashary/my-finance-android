import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'package:my_finance/modules/finance/models/budgets_model.dart';
import 'package:my_finance/modules/finance/services/budgets_service.dart';
import 'package:my_finance/modules/finance/services/category_service.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';

/// Budget create form hosted inside the shared PlusActionSheet.
class BudgetEntryForm extends StatefulWidget {
  const BudgetEntryForm({super.key});
  @override
  State<BudgetEntryForm> createState() => _BudgetEntryFormState();
}

class _BudgetEntryFormState extends State<BudgetEntryForm> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  List<String> _currencies = ['PKR'];
  List<String> _categories = [];
  String? _category;
  String _currency = 'PKR';
  String _period = 'Monthly';
  DateTime _start = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _end = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
  bool _loading = true, _saving = false;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _name.dispose(); _amount.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final wallets = await WalletService.getWallets();
      final categories = await CategoryService.getCategories('expense');
      if (!mounted) return;
      final currencies = wallets.map((w) => (w['currency'] ?? 'PKR').toString()).toSet().toList();
      setState(() {
        _currencies = currencies.isEmpty ? ['PKR'] : currencies;
        _currency = _currencies.first;
        _categories = categories.map((c) => c.name).toList();
        _loading = false;
      });
    } catch (e) { if (mounted) setState(() => _loading = false); _message('Error loading budget options: $e'); }
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon, size: 19), isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
  );

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context, initialDate: start ? _start : _end,
      firstDate: start ? DateTime(2000) : _start, lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() {
      if (start) { _start = picked; if (_end.isBefore(_start)) _end = _start; }
      else { _end = picked; }
    });
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate() || _end.isBefore(_start)) {
      if (_end.isBefore(_start)) _message('End date cannot be before start date.');
      return;
    }
    setState(() => _saving = true);
    try {
      await BudgetsService.addBudget(BudgetsModel(
        name: _name.text.trim(), category: _category,
        limitAmount: double.parse(_amount.text), period: _period,
        startDate: _start, endDate: _end, currency: _currency,
        createdAt: DateTime.now(),
      ));
      await SoundSettingsService.instance.play('save');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { _message('Error: $e'); setState(() => _saving = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Form(key: _key, child: SingleChildScrollView(
      primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextFormField(controller: _name, decoration: _dec('Budget Name', Icons.pie_chart_outline),
          validator: (v) => v == null || v.trim().isEmpty ? 'Enter budget name' : null),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec('Budget Limit', Icons.currency_exchange),
            validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid budget amount' : null; })),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(value: _currency, isExpanded: true,
            decoration: _dec('Currency', Icons.payments_outlined),
            items: _currencies.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) { if (v != null) setState(() => _currency = v); })),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String?>(value: _category, isExpanded: true,
            decoration: _dec('Category', Icons.category_outlined),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('All Categories')),
              ..._categories.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))],
            onChanged: (v) => setState(() => _category = v))),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(value: _period, isExpanded: true,
            decoration: _dec('Budget Period', Icons.calendar_view_month),
            items: ['Daily','Weekly','Monthly','Yearly','Custom'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) { if (v != null) setState(() => _period = v); })),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: InkWell(onTap: () => _pickDate(true), borderRadius: BorderRadius.circular(12),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.calendar_month, color: Theme.of(context).colorScheme.primary, size: 18), const SizedBox(width: 6), const Text('Start Date', style: TextStyle(fontWeight: FontWeight.w600))]),
              const SizedBox(height: 5), Text(DateFormat('dd MMM yyyy').format(_start), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ])))),
          const SizedBox(width: 12),
          Expanded(child: InkWell(onTap: () => _pickDate(false), borderRadius: BorderRadius.circular(12),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.event, color: Theme.of(context).colorScheme.primary, size: 18), const SizedBox(width: 6), const Text('End Date', style: TextStyle(fontWeight: FontWeight.w600))]),
              const SizedBox(height: 5), Text(DateFormat('dd MMM yyyy').format(_end), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ])))),
        ]),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create Budget')),
      ]),
    ));
  }
}
