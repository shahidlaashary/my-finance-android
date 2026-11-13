import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/installments/services/installment_service.dart';

class InstallmentsScreen extends StatefulWidget {
  const InstallmentsScreen({super.key});
  @override
  State<InstallmentsScreen> createState() => _InstallmentsScreenState();
}

class _InstallmentsScreenState extends State<InstallmentsScreen> {
  List<Map<String, dynamic>> _contracts = [];
  List<Map<String, dynamic>> _wallets = [];
  bool _loading = true;
  String _filter = 'all';
  final _money = NumberFormat('#,##0.00');
  String _date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _cash(double n) => _money.format(n);

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        InstallmentService.getContracts(),
        FinanceDB.instance.db.then((db) => db.query('wallets', orderBy: 'name')),
      ]);
      if (!mounted) return;
      setState(() {
        _contracts = values[0] as List<Map<String, dynamic>>;
        _wallets = values[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _message('Could not load installment records: $e');
    }
  }

  void _message(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  String _currency(int id) {
    final w = _wallets.where((x) => x['id'] == id);
    return w.isEmpty ? 'PKR' : (w.first['currency']?.toString() ?? 'PKR').toUpperCase();
  }

  Future<void> _addContract(String direction) async {
    if (_wallets.isEmpty) { _message('Please create an account first.'); return; }
    final item = TextEditingController();
    final party = TextEditingController();
    final phone = TextEditingController();
    final total = TextEditingController();
    final advance = TextEditingController(text: '0');
    final installment = TextEditingController();
    final notes = TextEditingController();
    int walletId = _wallets.first['id'] as int;
    String frequency = 'Monthly';
    DateTime start = DateTime.now();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(direction == 'sell' ? 'Sell on Installments' : 'Buy on Installments'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: item, decoration: const InputDecoration(labelText: 'Item / Product name *'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
            TextFormField(controller: party, decoration: InputDecoration(labelText: direction == 'sell' ? 'Customer name *' : 'Seller name *'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
            TextField(controller: total, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Total price *')),
            TextField(controller: advance, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Advance payment')),
            TextField(controller: installment, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Each installment *')),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(value: walletId, isExpanded: true, decoration: const InputDecoration(labelText: 'Linked account'),
              items: _wallets.map((w) => DropdownMenuItem(value: w['id'] as int, child: Text('${w['name']} (${w['currency'] ?? 'PKR'})'))).toList(),
              onChanged: (v) { if (v != null) setD(() => walletId = v); }),
            DropdownButtonFormField<String>(value: frequency, decoration: const InputDecoration(labelText: 'Installment frequency'),
              items: ['Weekly', 'Bi-weekly', 'Monthly'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setD(() => frequency = v); }),
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('First installment date'),
              subtitle: Text(_date(start)), trailing: const Icon(Icons.calendar_month),
              onTap: () async { final d = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setD(() => start = d); }),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
          ]),
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Create Plan')),
        ],
      ),
    ));
    if (result == true) {
      try {
        await InstallmentService.addContract(
          direction: direction, itemName: item.text, partyName: party.text, phone: phone.text,
          totalAmount: double.parse(total.text), advance: double.tryParse(advance.text) ?? 0,
          walletId: walletId, installmentAmount: double.parse(installment.text),
          frequency: frequency, startDate: _date(start), notes: notes.text,
        );
        await _load();
        _message('Installment plan created successfully.');
      } catch (e) { _message(e.toString().replaceFirst('Exception: ', '')); }
    }
    for (final c in [item, party, phone, total, advance, installment, notes]) { c.dispose(); }
  }

  Future<void> _recordPayment(Map<String, dynamic> c) async {
    final amount = TextEditingController(text: _money((c['installment_amount'] as num).toDouble().clamp(0, (c['total_amount'] as num).toDouble() - (c['paid_amount'] as num).toDouble())));
    final note = TextEditingController();
    DateTime date = DateTime.now();
    final result = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(c['direction'] == 'sell' ? 'Receive Installment' : 'Pay Installment'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${c['item_name']} • Balance: ${_currency(c['wallet_id'] as int)} ${_cash((c['total_amount'] as num).toDouble() - (c['paid_amount'] as num).toDouble())}'),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Payment amount')),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Payment date'), subtitle: Text(_date(date)), trailing: const Icon(Icons.calendar_month),
            onTap: () async { final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100)); if (d != null) setD(() => date = d); }),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Payment'))],
      ),
    ));
    if (result == true) {
      try {
        await InstallmentService.addPayment(contractId: c['id'] as int,
          amount: double.parse(amount.text), date: _date(date), note: note.text);
        await _load(); _message('Payment recorded.');
      } catch (e) { _message(e.toString().replaceFirst('Exception: ', '')); }
    }
    amount.dispose(); note.dispose();
  }

  Future<void> _details(Map<String, dynamic> c) async {
    final payments = await InstallmentService.getPayments(c['id'] as int);
    if (!mounted) return;
    final total = (c['total_amount'] as num).toDouble();
    final paid = (c['paid_amount'] as num).toDouble();
    final remaining = (total - paid).clamp(0.0, total);
    await showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        child: SizedBox(height: MediaQuery.of(ctx).size.height * .72, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['item_name'].toString(), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text('${c['direction'] == 'sell' ? 'Customer' : 'Seller'}: ${c['party_name']} • ${c['phone'] ?? ''}'),
          const SizedBox(height: 14),
          Row(children: [Expanded(child: _metric('Total', '${_currency(c['wallet_id'] as int)} ${_cash(total)}')),
            Expanded(child: _metric('Paid', _cash(paid))), Expanded(child: _metric('Remaining', _cash(remaining)))]),
          const SizedBox(height: 14),
          LinearProgressIndicator(value: total == 0 ? 0 : (paid / total).clamp(0.0, 1.0)),
          const SizedBox(height: 18),
          const Text('Payment history', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(child: payments.isEmpty ? const Center(child: Text('No payments recorded yet.')) :
            ListView.builder(itemCount: payments.length, itemBuilder: (_, i) {
              final p = payments[i];
              return ListTile(dense: true, leading: const CircleAvatar(child: Icon(Icons.check_rounded, size: 18)),
                title: Text('${_currency(c['wallet_id'] as int)} ${_cash((p['amount'] as num).toDouble())}'),
                subtitle: Text('${p['payment_date']} • ${p['note'] ?? ''}'));
            })),
          if (remaining > 0) SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () { Navigator.pop(ctx); _recordPayment(c); },
            icon: const Icon(Icons.payments_outlined), label: Text(c['direction'] == 'sell' ? 'Receive Payment' : 'Pay Installment'))),
        ])))));
  }

  Widget _metric(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
    const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
  ]);

  @override
  Widget build(BuildContext context) {
    final active = _contracts.where((c) => c['status'] == 'active').toList();
    final filtered = _filter == 'all' ? _contracts : _contracts.where((c) => c['direction'] == _filter).toList();
    final receivable = active.where((c) => c['direction'] == 'sell').fold<double>(0, (s, c) => s + (c['total_amount'] as num).toDouble() - (c['paid_amount'] as num).toDouble());
    final payable = active.where((c) => c['direction'] == 'buy').fold<double>(0, (s, c) => s + (c['total_amount'] as num).toDouble() - (c['paid_amount'] as num).toDouble());
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Installment Manager')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showAddMenu(), icon: const Icon(Icons.add), label: const Text('New Plan')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
            gradient: LinearGradient(colors: [primary, Color.lerp(primary, Colors.black, .24)!]),
            borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('INSTALLMENT OVERVIEW', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 14),
              Row(children: [Expanded(child: _whiteMetric('To Receive', receivable)), Expanded(child: _whiteMetric('To Pay', payable))]),
              const SizedBox(height: 14),
              Text('${active.length} active plans • ${_contracts.length} total records', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
          const SizedBox(height: 18),
          SegmentedButton<String>(segments: const [
            ButtonSegment(value: 'all', label: Text('All')),
            ButtonSegment(value: 'sell', label: Text('Giving')),
            ButtonSegment(value: 'buy', label: Text('Taking')),
          ], selected: {_filter}, onSelectionChanged: (v) => setState(() => _filter = v.first)),
          const SizedBox(height: 14),
          if (filtered.isEmpty) Container(padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [Icon(Icons.receipt_long_outlined, size: 42, color: primary),
              const SizedBox(height: 10), const Text('No installment plans yet', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4), const Text('Create a plan to track buying or selling on installments.', textAlign: TextAlign.center)]))
          else ...filtered.map((c) => _contractCard(c)),
        ])),
    );
  }

  Widget _whiteMetric(String label, double value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    const SizedBox(height: 4), Text(_cash(value), style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
  ]);

  Widget _contractCard(Map<String, dynamic> c) {
    final sell = c['direction'] == 'sell';
    final total = (c['total_amount'] as num).toDouble();
    final paid = (c['paid_amount'] as num).toDouble();
    final remaining = (total - paid).clamp(0.0, total);
    final progress = total <= 0 ? 0.0 : (paid / total).clamp(0.0, 1.0);
    final color = sell ? Colors.teal : Colors.deepOrange;
    return Card(margin: const EdgeInsets.only(bottom: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => _details(c),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(sell ? Icons.north_east_rounded : Icons.south_west_rounded, color: color)),
            const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['item_name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${c['party_name']} • ${sell ? 'Giving' : 'Taking'}', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ])),
            Text(c['status'] == 'completed' ? 'PAID' : 'ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c['status'] == 'completed' ? Colors.green : color)),
          ]),
          const SizedBox(height: 13),
          Row(children: [Expanded(child: _metric('Total', '${_currency(c['wallet_id'] as int)} ${_cash(total)}')),
            Expanded(child: _metric('Paid', _cash(paid))), Expanded(child: _metric('Remaining', _cash(remaining)))]),
          const SizedBox(height: 10), ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: progress, minHeight: 7, color: color)),
          const SizedBox(height: 7),
          Row(children: [Text('${(progress * 100).toStringAsFixed(0)}% complete', style: const TextStyle(fontSize: 11)),
            const Spacer(), Text('${_cash((c['installment_amount'] as num).toDouble())} / ${c['frequency']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))]),
          if (remaining > 0) Align(alignment: Alignment.centerRight, child: TextButton.icon(
            onPressed: () => _recordPayment(c), icon: const Icon(Icons.add_card_rounded, size: 18),
            label: Text(sell ? 'Receive installment' : 'Pay installment'))),
        ]))));
  }

  void _showAddMenu() {
    showModalBottomSheet(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Create Installment Plan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ListTile(leading: const CircleAvatar(child: Icon(Icons.north_east_rounded)), title: const Text('Give / Sell on Installments'),
          subtitle: const Text('Track payments you will receive'), onTap: () { Navigator.pop(ctx); _addContract('sell'); }),
        ListTile(leading: const CircleAvatar(child: Icon(Icons.south_west_rounded)), title: const Text('Take / Buy on Installments'),
          subtitle: const Text('Track payments you need to make'), onTap: () { Navigator.pop(ctx); _addContract('buy'); }),
      ]))));
  }
}
