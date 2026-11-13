import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/finance/services/debt_payoff_service.dart';
import 'package:my_finance/features/finance/services/transactions_service.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';

class DebtPayoffScreen extends StatefulWidget {
  const DebtPayoffScreen({super.key});
  @override
  State<DebtPayoffScreen> createState() => _DebtPayoffScreenState();
}

class _DebtPayoffScreenState extends State<DebtPayoffScreen> {
  List<DebtRecord> _debts = [];
  List<Map<String, dynamic>> _wallets = [];
  bool _loading = true;
  bool _hideBalances = false;
  final _extraController = TextEditingController(text: '0');
  String _strategy = 'Avalanche';

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_preferencesChanged);
    _load();
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_preferencesChanged);
    _extraController.dispose();
    super.dispose();
  }

  Future<void> _preferencesChanged() async {
    final hidden = await GeneralPreferences.instance.hideBalances;
    if (mounted && hidden != _hideBalances) setState(() => _hideBalances = hidden);
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        DebtPayoffService.getDebts(),
        TransactionsService.getAccounts(),
        GeneralPreferences.instance.hideBalances,
      ]);
      if (!mounted) return;
      setState(() {
        _debts = results[0] as List<DebtRecord>;
        _wallets = results[1] as List<Map<String, dynamic>>;
        _hideBalances = results[2] as bool;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Could not load debt data: $e');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _money(double n) => _hideBalances ? '••••••' : n.toStringAsFixed(2);
  String _currency(int walletId) {
    for (final w in _wallets) {
      if ((w['id'] as num).toInt() == walletId) return (w['currency']?.toString() ?? 'PKR').toUpperCase();
    }
    return 'PKR';
  }
  bool _isOverdue(DebtRecord debt) {
    if (debt.isPaid || debt.dueDate == null) return false;
    final due = DateTime.tryParse(debt.dueDate!);
    if (due == null) return false;
    final today = DateTime.now();
    return due.isBefore(DateTime(today.year, today.month, today.day));
  }

  String _walletName(int id) {
    for (final w in _wallets) {
      if ((w['id'] as num).toInt() == id) return w['name']?.toString() ?? 'Account';
    }
    return 'Account';
  }

  Future<void> _editDebt([DebtRecord? debt]) async {
    if (_wallets.isEmpty) {
      _message('Please create an account first.');
      return;
    }
    final name = TextEditingController(text: debt?.name ?? '');
    final lender = TextEditingController(text: debt?.lender ?? '');
    final phone = TextEditingController(text: debt?.phone ?? '');
    final amount = TextEditingController(text: debt?.originalAmount.toString() ?? '');
    final outstanding = TextEditingController(text: debt?.balance.toString() ?? '');
    final rate = TextEditingController(text: debt?.annualInterestRate.toString() ?? '0');
    final minimum = TextEditingController(text: debt?.minimumPayment.toString() ?? '0');
    final notes = TextEditingController(text: debt?.notes ?? '');
    int walletId = debt?.walletId ?? (_wallets.first['id'] as num).toInt();
    DateTime start = DateTime.tryParse(debt?.startDate ?? '') ?? DateTime.now();
    DateTime? due = DateTime.tryParse(debt?.dueDate ?? '');
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.94),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(children: [
                Expanded(child: Text(debt == null ? 'Add New Debt' : 'Edit Debt', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: 'Debt Name *')),
          TextField(controller: lender, decoration: InputDecoration(labelText: 'Lender / Party *')),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Phone (optional)')),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Original Debt Amount *')),
          TextField(controller: outstanding, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Current Outstanding Balance *', helperText: 'Update this when the lender adds interest or charges.')),
          TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Annual Interest Rate (%)')),
          TextField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Minimum Monthly Payment')),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: walletId, isExpanded: true, decoration: InputDecoration(labelText: 'Currency / Linked Account'),
            items: _wallets.map((w) => DropdownMenuItem<int>(value: (w['id'] as num).toInt(), child: Text('${w['name']} (${(w['currency'] ?? 'PKR').toString().toUpperCase()})'))).toList(),
            onChanged: (v) { if (v != null) setDialog(() => walletId = v); },
          ),
          ListTile(contentPadding: EdgeInsets.zero, title: Text(appText(context, "Start Date", "Start Date")), subtitle: Text(_date(start)), trailing: const Icon(Icons.calendar_month), onTap: () async { final d = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setDialog(() => start = d); }),
          ListTile(contentPadding: EdgeInsets.zero, title: Text(appText(context, "Due Date", "Due Date")), subtitle: Text(due == null ? 'Not set' : _date(due!)), trailing: const Icon(Icons.event), onTap: () async { final d = await showDatePicker(context: ctx, initialDate: due ?? start, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setDialog(() => due = d); }),
          TextField(controller: notes, maxLines: 2, decoration: InputDecoration(labelText: 'Notes')),
              ]),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(appText(context, "Cancel", "Cancel")))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(appText(context, "Save", "Save")))),
              ]),
            ),
          ]),
        ),
      )),
    );
    if (result == true) {
      final principal = double.tryParse(amount.text.trim());
      final currentBalance = double.tryParse(outstanding.text.trim());
      final interest = double.tryParse(rate.text.trim()) ?? 0;
      final minPay = double.tryParse(minimum.text.trim()) ?? 0;
      if (name.text.trim().isEmpty || lender.text.trim().isEmpty || principal == null || !principal.isFinite || principal <= 0 || currentBalance == null || !currentBalance.isFinite || currentBalance < 0 || currentBalance > principal || interest < 0 || minPay < 0) {
        _message('Please enter valid debt details.'); 
      } else {
        try {
          await DebtPayoffService.saveDebt(DebtRecord(
            id: debt?.id, name: name.text.trim(), lender: lender.text.trim(), phone: phone.text.trim(),
            originalAmount: principal, balance: currentBalance,
            annualInterestRate: interest, minimumPayment: minPay, walletId: walletId,
            startDate: _date(start), dueDate: due == null ? null : _date(due!), notes: notes.text.trim(),
          ));
          await _load();
          _message('Debt saved.');
        } catch (e) { _message('Could not save debt: $e'); }
      }
    }
    name.dispose(); lender.dispose(); phone.dispose(); amount.dispose(); outstanding.dispose(); rate.dispose(); minimum.dispose(); notes.dispose();
  }

  Future<void> _payDebt(DebtRecord debt) async {
    final amount = TextEditingController();
    final notes = TextEditingController();
    final matchingWallets = _wallets.where((w) => (w['currency']?.toString() ?? 'PKR').toUpperCase() == _currency(debt.walletId)).toList();
    if (matchingWallets.isEmpty) { _message('No account found for this debt currency.'); return; }
    int walletId = (matchingWallets.first['id'] as num).toInt();
    DateTime paidOn = DateTime.now();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.94),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(children: [
                Expanded(child: Text('Record Payment • ${debt.name}', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close)),
              ]),
            ),
            Flexible(child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Outstanding: ${_currency(debt.walletId)} ${_money(debt.balance)}'),
        TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Payment Amount *')),
        DropdownButtonFormField<int>(value: walletId, isExpanded: true, decoration: InputDecoration(labelText: 'Pay From Account'), items: matchingWallets.map((w) => DropdownMenuItem<int>(value: (w['id'] as num).toInt(), child: Text('${w['name']}'))).toList(), onChanged: (v) { if (v != null) setDialog(() => walletId = v); }),
        ListTile(contentPadding: EdgeInsets.zero, title: Text(appText(context, "Payment Date", "Payment Date")), subtitle: Text(_date(paidOn)), trailing: const Icon(Icons.calendar_month), onTap: () async { final d = await showDatePicker(context: ctx, initialDate: paidOn, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setDialog(() => paidOn = d); }),
        TextField(controller: notes, decoration: InputDecoration(labelText: 'Notes (optional)')),
              ]),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(appText(context, "Cancel", "Cancel")))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(appText(context, "Save Payment", "Save Payment")))),
              ]),
            ),
          ]),
        ),
      )),
    );
    if (result == true) {
      final value = double.tryParse(amount.text.trim());
      if (value == null || !value.isFinite || value <= 0 || value > debt.balance + 0.000001) {
        _message('Enter a valid amount not greater than the outstanding debt.');
      } else {
        try {
          await DebtPayoffService.addPayment(DebtPayment(debtId: debt.id!, amount: value, walletId: walletId, paymentDate: _date(paidOn), notes: notes.text.trim()));
          await _load();
          _message('Payment recorded and account balance updated.');
        } catch (e) { _message('Payment failed: $e'); }
      }
    }
    amount.dispose(); notes.dispose();
  }

  Future<void> _details(DebtRecord debt) async {
    if (debt.id == null) return;
    await showDialog<void>(context: context, builder: (ctx) => Dialog(child: SizedBox(width: 520, child: Padding(
      padding: const EdgeInsets.all(18), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Expanded(child: Text(debt.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
        Text('Lender: ${debt.lender}'), if (debt.phone.isNotEmpty) Text('Phone: ${debt.phone}'),
        Text('Original: ${_currency(debt.walletId)} ${_money(debt.originalAmount)}'),
        Text('Outstanding: ${_currency(debt.walletId)} ${_money(debt.balance)}'),
        Text('Paid: ${_currency(debt.walletId)} ${_money(debt.paidAmount)}'),
        Text('Interest: ${debt.annualInterestRate.toStringAsFixed(2)}% p.a. • Minimum: ${_money(debt.minimumPayment)} / month'),
        Text('Account: ${_walletName(debt.walletId)}'), Text('Start: ${debt.startDate} • Due: ${debt.dueDate ?? 'Not set'}'),
        if (debt.notes.isNotEmpty) Text('Notes: ${debt.notes}'),
        const Divider(height: 26), Text(appText(context, "Payment History", "Payment History"), style: TextStyle(fontWeight: FontWeight.bold)),
        FutureBuilder<List<DebtPayment>>(future: DebtPayoffService.getPayments(debt.id!), builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Text('Unable to load payments: ${snap.error}');
          final items = snap.data ?? [];
          if (items.isEmpty) return Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text(appText(context, "No payments yet.", "No payments yet.")));
          return Column(children: items.map((p) => ListTile(
            contentPadding: EdgeInsets.zero, title: Text('${_currency(debt.walletId)} ${_money(p.amount)}'),
            subtitle: Text('${p.paymentDate} • ${p.notes.isEmpty ? 'Payment' : p.notes}'),
            trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Delete payment', onPressed: () async {
              final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(appText(context, "Delete payment?", "Delete payment?")), content: Text(appText(context, "This will restore the amount to the account and debt balance.", "This will restore the amount to the account and debt balance.")), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(appText(context, "Cancel", "Cancel"))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(appText(context, "Delete", "Delete")))]));
              if (ok == true && p.id != null) { try { await DebtPayoffService.deletePayment(p.id!); if (ctx.mounted) Navigator.pop(ctx); await _load(); } catch (e) { _message('Could not delete payment: $e'); } }
            }),
          )).toList());
        }),
      ])),
    ))));
  }

  ({int months, double interest}) _estimate(List<DebtRecord> source, double extra, String strategy) {
    final debts = source.where((d) => d.balance > 0).map((d) => {
      'balance': d.balance, 'rate': d.annualInterestRate, 'minimum': d.minimumPayment,
    }).toList();
    if (debts.isEmpty) return (months: 0, interest: 0);
    if (debts.any((d) => (d['minimum'] as double) <= (d['balance'] as double) * (d['rate'] as double) / 1200) && extra <= 0) return (months: 0, interest: 0);
    var interestTotal = 0.0;
    for (var month = 1; month <= 600; month++) {
      for (final d in debts) {
        final interest = (d['balance'] as double) * (d['rate'] as double) / 1200;
        d['balance'] = (d['balance'] as double) + interest;
        interestTotal += interest;
      }
      var budget = extra;
      for (final d in debts) {
        final bal = d['balance'] as double;
        final pay = math.min(bal, d['minimum'] as double).toDouble();
        d['balance'] = bal - pay;
        budget += math.max(0.0, (d['minimum'] as double) - pay).toDouble();
      }
      debts.sort((a, b) => strategy == 'Snowball'
        ? (a['balance'] as double).compareTo(b['balance'] as double)
        : (b['rate'] as double).compareTo(a['rate'] as double));
      for (final d in debts) {
        if (budget <= 0) break;
        final bal = d['balance'] as double;
        final pay = math.min(bal, budget).toDouble();
        d['balance'] = bal - pay;
        budget -= pay;
      }
      debts.removeWhere((d) => (d['balance'] as double) <= 0.005);
      if (debts.isEmpty) return (months: month, interest: interestTotal);
    }
    return (months: 600, interest: interestTotal);
  }

  @override
  Widget build(BuildContext context) {
    final active = _debts.where((d) => !d.isPaid).toList();
    final currencies = <String>{for (final d in active) _currency(d.walletId)};
    final extra = double.tryParse(_extraController.text.trim()) ?? 0;
    final estimates = {for (final currency in currencies) currency: _estimate(active.where((d) => _currency(d.walletId) == currency).toList(), extra, _strategy)};
    return Scaffold(
      appBar: AppBar(title: Text(appText(context, "Debt Payoff Planner", "Debt Payoff Planner"), style: TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _editDebt(), icon: const Icon(Icons.add), label: Text(appText(context, "Add Debt", "Add Debt"))),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(appText(context, "Outstanding Debt", "Outstanding Debt"), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (currencies.isEmpty) Text(appText(context, "No outstanding debt", "No outstanding debt")) else ...currencies.map((c) {
              final total = active.where((d) => _currency(d.walletId) == c).fold<double>(0, (s, d) => s + d.balance);
              return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('$c ${_money(total)}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)));
            }),
            Text('${active.length} active • ${_debts.where((d) => d.isPaid).length} paid off', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]))),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: Text(appText(context, "Your Debts", "Your Debts"), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))), TextButton.icon(onPressed: () => _editDebt(), icon: const Icon(Icons.add), label: Text(appText(context, "Add", "Add")))]),
          if (active.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(_debts.isEmpty ? 'No debts added yet. Tap Add Debt to get started.' : 'All debts have been paid off.')))),
          ...active.map((d) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), if (_isOverdue(d)) Chip(label: Text(appText(context, "Overdue", "Overdue"), style: TextStyle(color: Colors.white)), backgroundColor: Colors.red)]),
            Text('Lender: ${d.lender} • ${_currency(d.walletId)}'),
            if (d.dueDate != null) Text('Due: ${d.dueDate}'),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Remaining: ${_money(d.balance)}', style: const TextStyle(fontWeight: FontWeight.w700)), Text('Original: ${_money(d.originalAmount)}')]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: d.progress, minHeight: 8)),
            const SizedBox(height: 5),
            Text('${(d.progress * 100).toStringAsFixed(1)}% paid • ${d.annualInterestRate.toStringAsFixed(2)}% interest • Min ${_money(d.minimumPayment)}/mo', style: Theme.of(context).textTheme.bodySmall),
            Wrap(spacing: 4, children: [
              TextButton.icon(onPressed: () => _details(d), icon: const Icon(Icons.history), label: Text(appText(context, "Details", "Details"))),
              TextButton.icon(onPressed: d.isPaid ? null : () => _payDebt(d), icon: const Icon(Icons.payments_outlined), label: Text(appText(context, "Pay", "Pay"))),
              IconButton(tooltip: 'Edit debt', onPressed: () => _editDebt(d), icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: 'Delete debt', onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(appText(context, "Delete this debt?", "Delete this debt?")), content: Text(appText(context, "Recorded payments will be reversed back into their accounts.", "Recorded payments will be reversed back into their accounts.")), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(appText(context, "Cancel", "Cancel"))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(appText(context, "Delete", "Delete")))]));
                if (ok == true && d.id != null) { try { await DebtPayoffService.deleteDebt(d.id!); await _load(); } catch (e) { _message('Could not delete debt: $e'); } }
              }, icon: const Icon(Icons.delete_outline, color: Colors.red)),
            ]),
          ])))),
          const SizedBox(height: 12),
          Text(appText(context, "Payoff Strategy Calculator", "Payoff Strategy Calculator"), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(appText(context, "Choose how to prioritize your debts. Estimates assume monthly payments and fixed interest rates.", "Choose how to prioritize your debts. Estimates assume monthly payments and fixed interest rates.")),
            const SizedBox(height: 10),
            SegmentedButton<String>(segments: [ButtonSegment(value: 'Avalanche', label: Text(appText(context, "Avalanche", "Avalanche"))), ButtonSegment(value: 'Snowball', label: Text(appText(context, "Snowball", "Snowball")))], selected: {_strategy}, onSelectionChanged: (v) => setState(() => _strategy = v.first)),
            const SizedBox(height: 8),
            Text(_strategy == 'Avalanche' ? 'Avalanche: highest interest rate first to reduce estimated interest.' : 'Snowball: smallest outstanding balance first for faster wins.'),
            TextField(controller: _extraController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Extra monthly payment', helperText: 'Added on top of minimum payments'), onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            if (active.isEmpty) Text(appText(context, "Add an active debt to calculate a payoff plan.", "Add an active debt to calculate a payoff plan.")) else ...estimates.entries.map((entry) {
              final result = entry.value;
              return Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (result.months == 0) Text(appText(context, "Increase the monthly payment; current minimums may not cover estimated interest.", "Increase the monthly payment; current minimums may not cover estimated interest.")) else Text('Estimated payoff: ${result.months} months • Interest: ${_money(result.interest)}'),
              ]));
            }),
            const SizedBox(height: 4),
            Text(appText(context, "Interest is included in estimates only. Payment entries reduce the current balance directly; update the outstanding balance when the lender posts interest or fees.", "Interest is included in estimates only. Payment entries reduce the current balance directly; update the outstanding balance when the lender posts interest or fees."), style: Theme.of(context).textTheme.bodySmall),
          ]))),
          const SizedBox(height: 12),
          if (_debts.any((d) => d.isPaid)) Text(appText(context, "Completed Debts", "Completed Debts"), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ..._debts.where((d) => d.isPaid).map((d) => ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: Text(d.name), subtitle: Text('Paid off • ${d.lender}'))),
        ]),
      ),
    );
  }
}
