import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';

class LoanEntryForm extends StatefulWidget {
  const LoanEntryForm({super.key});
  @override
  State<LoanEntryForm> createState() => _LoanEntryFormState();
}

class _LoanEntryFormState extends State<LoanEntryForm> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _picker = ImagePicker();
  final List<PlatformFile> _pdfs = [];
  List<Map<String, dynamic>> _wallets = [], _parties = [];
  int? _walletId, _partyId;
  String _type = 'given';
  DateTime _date = DateTime.now(), _due = DateTime.now().add(const Duration(days: 30));
  XFile? _image;
  bool _loading = true, _saving = false;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _amount.dispose(); _notes.dispose(); super.dispose(); }

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
          DropdownButtonFormField<String>(value: currency, decoration: const InputDecoration(labelText: 'Currency'),
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
        if (mounted) setState(() { _parties = parties; _partyId = id; final match = _wallets.where((w) => (w['currency']?.toString() ?? 'PKR').toUpperCase() == currency.toUpperCase()); if (match.isNotEmpty) _walletId = (match.first['id'] as num).toInt(); });
      } catch (e) { _msg(e); }
    }
    name.dispose(); phone.dispose();
  }
  Future<void> _pickDate(bool due) async {
    final initial = due ? _due : _date;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null && mounted) setState(() { if (due) { _due = picked; } else { _date = picked; } });
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
    if (!_key.currentState!.validate()) return;
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0 || _walletId == null || _partyId == null) return;
    final party = _parties.firstWhere((p) => (p['id'] as num).toInt() == _partyId);
    final currency = (party['currency']?.toString() ?? 'PKR').toUpperCase();
    if ((_wallet?['currency']?.toString() ?? 'PKR').toUpperCase() != currency) { _msg('Select a $currency wallet.'); return; }
    setState(() => _saving = true);
    try {
      final id = await LoansService.addLoan(LoansModel(partyId: _partyId, loanType: _type, amount: amount, remainingAmount: amount, walletId: _walletId!, currency: currency, lendingDate: DateFormat('yyyy-MM-dd').format(_date), dueDate: DateFormat('yyyy-MM-dd').format(_due), notes: _notes.text.trim(), createdAt: DateTime.now().toIso8601String()));
      if (_image != null) await AttachmentService.addAttachment(ownerType: AttachmentOwnerTypes.loan, ownerId: id, sourcePath: _image!.path, originalFileName: _image!.name);
      for (final f in _pdfs) { if (f.path != null) await AttachmentService.addAttachment(ownerType: AttachmentOwnerTypes.loan, ownerId: id, sourcePath: f.path!, originalFileName: f.name); }
      await SoundSettingsService.instance.play('save');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loan saved successfully.')));
      Navigator.pop(context, true);
    } catch (e) { await SoundSettingsService.instance.play('error'); if (mounted) { _msg(e); setState(() => _saving = false); } }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_wallets.isEmpty) return const Center(child: Text('Add a wallet first.'));
    if (_parties.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Add a party to create a loan.'), TextButton.icon(onPressed: _createParty, icon: const Icon(Icons.person_add_alt_1), label: const Text('Create Party'))])));
    return Form(key: _key, child: SingleChildScrollView(primary: false, keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: const EdgeInsets.fromLTRB(18, 8, 18, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<String>(segments: const [ButtonSegment(value: 'given', label: Text('Given')), ButtonSegment(value: 'taken', label: Text('Taken'))], selected: {_type}, onSelectionChanged: (v) => setState(() => _type = v.first)),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _createParty, icon: const Icon(Icons.person_add_alt_1), label: const Text('Create Party'))),
      DropdownButtonFormField<int>(value: _partyId, isExpanded: true, decoration: _dec('Party *', icon: Icons.person_outline), items: _parties.map((p) => DropdownMenuItem<int>(value: (p['id'] as num).toInt(), child: Text(p['name'].toString()))).toList(), onChanged: (v) => setState(() { _partyId = v; final p = _parties.firstWhere((x) => (x['id'] as num).toInt() == v); final c = (p['currency']?.toString() ?? 'PKR').toUpperCase(); final match = _wallets.where((w) => (w['currency']?.toString() ?? 'PKR').toUpperCase() == c); if (match.isNotEmpty) _walletId = (match.first['id'] as num).toInt(); }), validator: (v) => v == null ? 'Select a party.' : null),
      const SizedBox(height: 12),
      TextFormField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: _dec('Amount', icon: Icons.payments_outlined), validator: (v) { final n = double.tryParse(v?.trim() ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid amount.' : null; }),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(value: _walletId, isExpanded: true, decoration: _dec('Wallet', icon: Icons.account_balance_wallet_outlined), items: _wallets.map((w) => DropdownMenuItem<int>(value: w['id'] as int, child: Text('${w['name']} (${w['currency']})', overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() => _walletId = v)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Lending date'), subtitle: Text(DateFormat('dd MMM yyyy').format(_date)), onTap: () => _pickDate(false)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Due date'), subtitle: Text(DateFormat('dd MMM yyyy').format(_due)), onTap: () => _pickDate(true)),
      TextFormField(controller: _notes, maxLines: 2, decoration: _dec('Notes (Optional)').copyWith(suffixIcon: IconButton(onPressed: _attachments, icon: const Icon(Icons.attach_file_rounded)))),
      if (_image != null || _pdfs.isNotEmpty) Text('${_image == null ? '' : '1 image, '}${_pdfs.length} PDF(s)', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 16),
      FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Loan')),
    ])));
  }
}