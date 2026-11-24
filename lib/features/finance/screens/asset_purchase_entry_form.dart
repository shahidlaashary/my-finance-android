import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';

class AssetPurchaseEntryForm extends StatefulWidget {
  const AssetPurchaseEntryForm({super.key});
  @override
  State<AssetPurchaseEntryForm> createState() => _AssetPurchaseEntryFormState();
}

class _AssetPurchaseEntryFormState extends State<AssetPurchaseEntryForm> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController(), _purchase = TextEditingController(), _current = TextEditingController(), _notes = TextEditingController();
  final _picker = ImagePicker();
  final _service = AssetsService();
  final List<PlatformFile> _pdfs = [];
  List<Map<String, dynamic>> _wallets = [], _parties = [];
  int? _walletId, _partyId;
  String _category = 'Property', _payment = 'Wallet';
  bool _includeBalance = false, _loading = true, _saving = false;
  DateTime _purchaseDate = DateTime.now();
  XFile? _image;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _name.dispose(); _purchase.dispose(); _current.dispose(); _notes.dispose(); super.dispose(); }
  Future<void> _load() async {
    try {
      final wallets = await FinanceDB.instance.getWallets();
      final parties = await LoansService.getParties();
      if (!mounted) return;
      setState(() { _wallets = wallets; _parties = parties; if (wallets.isNotEmpty) _walletId = wallets.first['id'] as int; _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); _msg(e); }
  }
  void _msg(Object e) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
  InputDecoration _dec(String label, {IconData? icon}) => InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)), contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13));
  Map<String, dynamic>? get _wallet { for (final w in _wallets) { if (w['id'] == _walletId) return w; } return null; }

  Future<void> _createParty() async {
    final name = TextEditingController(), phone = TextEditingController();
    String currency = await FinanceDB.instance.getBaseCurrency();
    if (!CurrencyCatalog.supported.contains(currency.toUpperCase())) currency = 'PKR';
    if (!mounted) { name.dispose(); phone.dispose(); return; }
    final key = GlobalKey<FormState>();
    final result = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Create Party'),
        content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Party name *'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter party name.' : null),
          TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
          DropdownButtonFormField<String>(isExpanded: true, value: currency, decoration: const InputDecoration(labelText: 'Currency'),
            items: CurrencyCatalog.supported.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) { if (v != null) setDialogState(() => currency = v); }),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('Save')),
        ],
      ),
    ));
    if (result == true) {
      try {
        final id = await LoansService.addParty(name: name.text.trim(), phone: phone.text.trim(), currency: currency);
        final parties = await LoansService.getParties();
        if (mounted) setState(() { _parties = parties; _partyId = id; });
      } catch (e) { _msg(e); }
    }
    name.dispose(); phone.dispose();
  }
  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _purchaseDate, firstDate: DateTime(1950), lastDate: DateTime.now());
    if (d != null && mounted) setState(() => _purchaseDate = d);
  }
  Future<void> _attachments() async {
    final choice = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Wrap(children: [
      ListTile(title: const Text('Camera'), leading: const Icon(Icons.camera_alt_outlined), onTap: () => Navigator.pop(ctx, 'camera')),
      ListTile(title: const Text('Gallery'), leading: const Icon(Icons.image_outlined), onTap: () => Navigator.pop(ctx, 'image')),
      ListTile(title: const Text('Add PDFs'), leading: const Icon(Icons.picture_as_pdf_outlined), onTap: () => Navigator.pop(ctx, 'pdf')),
    ])));
    if (choice == 'image' || choice == 'camera') { final f = await _picker.pickImage(source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 85); if (f != null && mounted) setState(() => _image = f); }
    if (choice == 'pdf') { final f = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true); if (f != null && mounted) setState(() => _pdfs.addAll(f.files.where((x) => x.path != null))); }
  }
  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;

    final purchase = double.tryParse(_purchase.text.trim());
    final current = double.tryParse(_current.text.trim());
    if (purchase == null || current == null || (_payment == 'Wallet' && _walletId == null)) return;
    if (_payment == 'Loan' && _partyId == null) {
      _msg('Select a party for loan-funded asset.');
      return;
    }
    final party = _partyId == null
        ? null
        : _parties.firstWhere((p) => (p['id'] as num).toInt() == _partyId);
    final currency = _payment == 'Loan'
        ? (party?['currency']?.toString() ?? 'PKR').toUpperCase()
        : (_wallet?['currency']?.toString() ?? 'PKR').toUpperCase();

    final attachments = <Map<String, String>>[];
    if (_image != null) {
      attachments.add({'path': _image!.path, 'name': _image!.name});
    }
    for (final file in _pdfs) {
      if (file.path == null) {
        _msg('A selected PDF is unavailable. Please remove it and select it again.');
        return;
      }
      attachments.add({'path': file.path!, 'name': file.name});
    }

    setState(() => _saving = true);
    try {
      await _service.addAssetWithAttachments(
        AssetsModel(
          name: _name.text.trim(),
          category: _category,
          purchasePrice: purchase,
          currentValue: current,
          purchaseDate: _purchaseDate,
          walletId: _walletId ?? 0,
          paymentType: _payment,
          partyId: _payment == 'Loan' ? _partyId : null,
          currency: currency,
          notes: _notes.text.trim(),
          includeInConsolidatedBalance: _includeBalance,
          createdAt: DateTime.now(),
        ),
        attachments,
      );

      await SoundSettingsService.instance.play('save');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Asset and attachments saved successfully.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      await SoundSettingsService.instance.play('error');
      if (mounted) _msg(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Form(key: _key, child: SingleChildScrollView(primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: const EdgeInsets.fromLTRB(18, 8, 18, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(controller: _name, decoration: _dec('Asset name *', icon: Icons.inventory_2_outlined), validator: (v) => v == null || v.trim().isEmpty ? 'Enter asset name.' : null),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _category,
            isExpanded: true,
            decoration: _dec('Category'),
            items: const ['Property','Vehicles','Gold','Jewellery','Electronics','Investments','Livestock','Business'].map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { if (v != null) setState(() => _category = v); },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _payment,
            isExpanded: true,
            decoration: _dec('Payment type'),
            items: const ['Wallet','Loan'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _payment = v ?? 'Wallet'),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      if (_payment == 'Loan') ...[
        DropdownButtonFormField<String>(
          value: _partyId?.toString(),
          isExpanded: true,
          decoration: _dec('Loan party *', icon: Icons.person_outline),
          hint: Text(_parties.isEmpty ? 'Create Party' : 'Select Party'),
          items: [
            ..._parties.map((p) => DropdownMenuItem<String>(
              value: (p['id'] as num).toInt().toString(),
              child: Text(p['name'].toString()),
            )),
            const DropdownMenuItem<String>(
              value: '__create_party__',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_add_alt_1, size: 18),
                SizedBox(width: 8),
                Text('Create Party'),
              ]),
            ),
          ],
          onChanged: (value) {
            if (value == '__create_party__') {
              setState(() => _partyId = null);
              _createParty();
              return;
            }
            setState(() => _partyId = int.tryParse(value ?? ''));
          },
          validator: (_) => _payment == 'Loan' && _partyId == null ? 'Select a party.' : null,
        ),
      ] else ...[
        if (_wallets.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No wallet available. Add a wallet or choose Loan payment type.'),
          ),
        DropdownButtonFormField<int>(value: _walletId, isExpanded: true, decoration: _dec('Wallet', icon: Icons.account_balance_wallet_outlined), items: _wallets.map((w) => DropdownMenuItem<int>(value: w['id'] as int, child: Text('${w['name']} (${w['currency']})', overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() => _walletId = v), validator: (v) => v == null ? 'Select a wallet.' : null),
      ],
      const SizedBox(height: 12),
      Row(children:[
        Expanded(child:TextFormField(controller: _purchase, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec('Purchase price *'), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid purchase price.' : null; })),
        const SizedBox(width:12),
        Expanded(child:TextFormField(controller: _current, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec('Current value *'), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 ? 'Enter a valid current value.' : null; })),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: _dec('Purchase date'),
              child: Row(
                children: [
                  Expanded(child: Text(DateFormat('dd MMM yyyy').format(_purchaseDate), overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.calendar_today_outlined, size: 18),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              const Expanded(
                child: Text('Add Asset In Consolidated', style: TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              Switch(
                value: _includeBalance,
                onChanged: (v) => setState(() => _includeBalance = v),
              ),
            ],
          ),
        ),
      ]),
      const SizedBox(height: 12),
      TextFormField(controller: _notes, maxLines: 2, decoration: _dec('Notes (Optional)').copyWith(suffixIcon: IconButton(onPressed: _attachments, icon: const Icon(Icons.attach_file_rounded)))),
      if (_image != null || _pdfs.isNotEmpty) Text('${_image == null ? '' : '1 image, '}${_pdfs.length} PDF(s)', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 16),
      FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Asset')),
    ])));
  }
}