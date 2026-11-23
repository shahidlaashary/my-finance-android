import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/database/finance_database.dart';
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

  const AssetSaleEntryForm({super.key, required this.asset, required this.wallets, required this.parties, required this.onCreateParty});

  @override
  State<AssetSaleEntryForm> createState() => _AssetSaleEntryFormState();
}

class _AssetSaleEntryFormState extends State<AssetSaleEntryForm> {
  late final TextEditingController _price;
  final _manualWalletAmount = TextEditingController();
  late List<Map<String, dynamic>> _parties;
  DateTime _date = DateTime.now();
  int? _walletId, _partyId;
  String _paymentType = 'Wallet';
  bool _manualAmount = false, _loadingRate = false;
  double? _assetRate, _walletRate;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: widget.asset.currentValue.toString());
    _parties = List<Map<String, dynamic>>.from(widget.parties);
    _walletId = widget.wallets.any((w) => (w['id'] as num).toInt() == widget.asset.walletId)
        ? widget.asset.walletId
        : (widget.wallets.isEmpty ? null : (widget.wallets.first['id'] as num).toInt());
    _loadRates();
  }

  @override
  void dispose() { _price.dispose(); _manualWalletAmount.dispose(); super.dispose(); }

  Map<String, dynamic>? get _wallet => widget.wallets.cast<Map<String, dynamic>?>().firstWhere(
    (w) => w != null && (w['id'] as num).toInt() == _walletId,
    orElse: () => null,
  );
  String get _walletCurrency => (_wallet?['currency']?.toString() ?? widget.asset.currency).toUpperCase();
  String get _assetCurrency => widget.asset.currency.toUpperCase();
  double? get _walletCredit {
    final amount = double.tryParse(_price.text.trim());
    if (amount == null || !amount.isFinite || amount < 0) return null;
    if (_walletCurrency == _assetCurrency) return amount;
    if (_manualAmount) {
      final manual = double.tryParse(_manualWalletAmount.text.trim());
      return manual != null && manual.isFinite && manual > 0 ? manual : null;
    }
    if (_assetRate == null || _walletRate == null || _walletRate! <= 0) return null;
    return amount * _assetRate! / _walletRate!;
  }

  Future<void> _loadRates() async {
    if (_walletCurrency == _assetCurrency) {
      if (mounted) setState(() { _assetRate = 1; _walletRate = 1; });
      return;
    }
    setState(() => _loadingRate = true);
    try {
      var assetRate = await FinanceDB.instance.getExchangeRate(_assetCurrency);
      var walletRate = await FinanceDB.instance.getExchangeRate(_walletCurrency);
      if (assetRate == null || walletRate == null) {
        await FinanceDB.instance.refreshMissingExchangeRatesOnline(currencies: [_assetCurrency, _walletCurrency]);
        assetRate = await FinanceDB.instance.getExchangeRate(_assetCurrency);
        walletRate = await FinanceDB.instance.getExchangeRate(_walletCurrency);
      }
      if (mounted) setState(() { _assetRate = assetRate; _walletRate = walletRate; _loadingRate = false; });
    } catch (_) {
      if (mounted) setState(() { _assetRate = null; _walletRate = null; _loadingRate = false; });
    }
  }

  List<Map<String, dynamic>> get _matchingParties => _parties.where((p) =>
    (p['currency']?.toString() ?? 'PKR').toUpperCase() == _assetCurrency
  ).toList();

  Future<void> _createParty() async {
    final created = await widget.onCreateParty(initialCurrency: widget.asset.currency, lockCurrency: true);
    if (created == null || !mounted) return;
    if ((created['currency']?.toString() ?? 'PKR').toUpperCase() != _assetCurrency) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Buyer party currency must match $_assetCurrency.')));
      return;
    }
    setState(() {
      final id = (created['id'] as num).toInt();
      if (!_parties.any((p) => (p['id'] as num).toInt() == id)) _parties.add(created);
      _partyId = id;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _date.isBefore(widget.asset.purchaseDate) ? widget.asset.purchaseDate : _date, firstDate: widget.asset.purchaseDate, lastDate: DateTime.now());
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _confirm() {
    final price = double.tryParse(_price.text.trim());
    if (price == null || !price.isFinite || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid sale price.')));
      return;
    }
    if (_paymentType == 'Loan' && _partyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Select a buyer party with $_assetCurrency currency.')));
      return;
    }
    if (_paymentType == 'Wallet' && _walletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a receiving wallet.')));
      return;
    }
    final walletCredit = _paymentType == 'Wallet' ? _walletCredit : null;
    if (_paymentType == 'Wallet' && walletCredit == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_manualAmount ? 'Enter a valid amount received in $_walletCurrency.' : 'Exchange rate is unavailable for the selected currencies.')));
      return;
    }
    Navigator.pop(context, {
      'price': price, 'date': _date, 'walletId': _walletId ?? 0,
      'paymentType': _paymentType, 'partyId': _partyId,
      'walletAmount': walletCredit ?? 0.0, 'walletCurrency': _walletCurrency,
      'exchangeRate': _paymentType == 'Wallet' ? (walletCredit! / (price == 0 ? 1 : price)) : 1.0,
      'isManualRate': _paymentType == 'Wallet' && _manualAmount && _walletCurrency != _assetCurrency,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(appText(context, 'Sell Asset', 'اثاثہ فروخت کریں')),
    content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Sale Price ($_assetCurrency)')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _paymentType, isExpanded: true, decoration: const InputDecoration(labelText: 'Payment Type'),
        items: const ['Wallet', 'Loan'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _paymentType = v ?? 'Wallet'),
      ),
      const SizedBox(height: 8),
      if (_paymentType == 'Loan') ...[
        DropdownButtonFormField<int>(
          value: _partyId, isExpanded: true, decoration: const InputDecoration(labelText: 'Buyer Party *'),
          items: _matchingParties.map((p) => DropdownMenuItem<int>(value: (p['id'] as num).toInt(), child: Text('${p['name']} • ${p['currency'] ?? 'PKR'}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _partyId = v),
        ),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _createParty, icon: const Icon(Icons.person_add_alt_1, size: 18), label: const Text('Create Party'))),
      ] else ...[
        DropdownButtonFormField<int>(
          value: _walletId, isExpanded: true, decoration: const InputDecoration(labelText: 'Receiving Wallet'),
          items: widget.wallets.map((w) => DropdownMenuItem<int>(value: (w['id'] as num).toInt(), child: Text('${w['name']} (${w['currency'] ?? 'PKR'})'))).toList(),
          onChanged: (v) { setState(() { _walletId = v; _manualAmount = false; _manualWalletAmount.clear(); }); _loadRates(); },
        ),
        if (_walletCurrency != _assetCurrency) ...[
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Manual Wallet Amount'), subtitle: const Text('Enter the exact amount received in the selected wallet'), value: _manualAmount, onChanged: (v) => setState(() => _manualAmount = v)),
          if (_manualAmount)
            TextField(controller: _manualWalletAmount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Amount Received ($_walletCurrency)', suffixText: _walletCurrency)),
          if (!_manualAmount && (_assetRate == null || _walletRate == null))
            const Align(alignment: Alignment.centerLeft, child: Text('Exchange rate unavailable. Set rates or enter a manual wallet amount.', style: TextStyle(color: Colors.red, fontSize: 12))),
          if (_manualAmount && _assetRate != null && _walletRate != null)
            Align(alignment: Alignment.centerLeft, child: Text('Automatic reference: ${_walletCurrency} ${(_assetRate! / _walletRate!).toStringAsFixed(4)} per $_assetCurrency', style: const TextStyle(fontSize: 11))),
        ],
        if (_walletCredit != null)
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text('Wallet credit: $_walletCurrency ${_walletCredit!.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)))),
        if (_loadingRate) const LinearProgressIndicator(),
      ],
      ListTile(contentPadding: EdgeInsets.zero, title: Text(appText(context, 'Sale Date', 'فروخت کی تاریخ')), subtitle: Text(DateFormat('dd MMM yyyy').format(_date)), trailing: const Icon(Icons.calendar_month), onTap: _pickDate),
    ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(appText(context, 'Cancel', 'منسوخ کریں'))),
      FilledButton(onPressed: _confirm, child: Text(appText(context, 'Confirm Sale', 'فروخت کی تصدیق کریں'))),
    ],
  );
}
