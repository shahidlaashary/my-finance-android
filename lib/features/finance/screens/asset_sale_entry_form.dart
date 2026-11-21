import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';

typedef CreateAssetSaleParty = Future<Map<String, dynamic>?> Function({
  required String initialCurrency,
  required bool lockCurrency,
});

class AssetSaleEntryForm extends StatefulWidget {
  final AssetsModel asset;
  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> parties;
  final CreateAssetSaleParty onCreateParty;

  const AssetSaleEntryForm({
    super.key,
    required this.asset,
    required this.wallets,
    required this.parties,
    required this.onCreateParty,
  });

  @override
  State<AssetSaleEntryForm> createState() => _AssetSaleEntryFormState();
}

class _AssetSaleEntryFormState extends State<AssetSaleEntryForm> {
  late final TextEditingController _price;
  late List<Map<String, dynamic>> _parties;
  DateTime _date = DateTime.now();
  int? _walletId, _partyId;
  String _paymentType = 'Wallet';

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: widget.asset.currentValue.toString());
    _parties = List<Map<String, dynamic>>.from(widget.parties);
    _walletId = widget.asset.walletId;
  }

  @override
  void dispose() { _price.dispose(); super.dispose(); }

  List<Map<String, dynamic>> get _matchingWallets => widget.wallets.where((w) =>
    (w['currency']?.toString() ?? 'PKR').toUpperCase() == widget.asset.currency.toUpperCase()
  ).toList();

  List<Map<String, dynamic>> get _matchingParties => _parties.where((p) =>
    (p['currency']?.toString() ?? 'PKR').toUpperCase() == widget.asset.currency.toUpperCase()
  ).toList();

  Future<void> _createParty() async {
    final created = await widget.onCreateParty(initialCurrency: widget.asset.currency, lockCurrency: true);
    if (created == null || !mounted) return;
    if ((created['currency']?.toString() ?? 'PKR').toUpperCase() != widget.asset.currency.toUpperCase()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Buyer party currency must match ' + widget.asset.currency + '.')));
      return;
    }
    setState(() {
      final id = (created['id'] as num).toInt();
      if (!_parties.any((p) => (p['id'] as num).toInt() == id)) _parties.add(created);
      _partyId = id;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(widget.asset.purchaseDate) ? widget.asset.purchaseDate : _date,
      firstDate: widget.asset.purchaseDate,
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _confirm() {
    final price = double.tryParse(_price.text.trim());
    if (price == null || !price.isFinite || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid sale price.')));
      return;
    }
    if (_paymentType == 'Loan' && _partyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Select a buyer party with ' + widget.asset.currency + ' currency.')));
      return;
    }
    if (_paymentType != 'Loan' && _walletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Select a sale wallet in ' + widget.asset.currency + '.')));
      return;
    }
    Navigator.pop(context, {
      'price': price,
      'date': _date,
      'walletId': _walletId ?? 0,
      'paymentType': _paymentType,
      'partyId': _partyId,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(appText(context, 'Sell Asset', 'اثاثہ فروخت کریں')),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: appText(context, 'Sale Price', 'Sale Price')),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _paymentType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Payment Type'),
            items: const ['Cash', 'Bank', 'Wallet', 'Loan'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _paymentType = v ?? 'Wallet'),
          ),
          const SizedBox(height: 8),
          if (_paymentType == 'Loan') ...[
            DropdownButtonFormField<int>(
              value: _partyId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Buyer Party *'),
              items: _matchingParties.map((p) => DropdownMenuItem<int>(
                value: (p['id'] as num).toInt(),
                child: Text(p['name'].toString() + ' • ' + (p['currency']?.toString() ?? 'PKR'), overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setState(() => _partyId = v),
            ),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _createParty, icon: const Icon(Icons.person_add_alt_1, size: 18), label: const Text('Create Party'))),
          ] else
            DropdownButtonFormField<int>(
              value: _walletId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sale Wallet'),
              items: _matchingWallets.map((w) => DropdownMenuItem<int>(
                value: (w['id'] as num).toInt(),
                child: Text(w['name'].toString() + ' (' + (w['currency']?.toString() ?? 'PKR') + ')'),
              )).toList(),
              onChanged: (v) => setState(() => _walletId = v),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(appText(context, 'Sale Date', 'فروخت کی تاریخ')),
            subtitle: Text(DateFormat('dd MMM yyyy').format(_date)),
            trailing: const Icon(Icons.calendar_month),
            onTap: _pickDate,
          ),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(appText(context, 'Cancel', 'منسوخ کریں'))),
      FilledButton(onPressed: _confirm, child: Text(appText(context, 'Confirm Sale', 'فروخت کی تصدیق کریں'))),
    ],
  );
}
