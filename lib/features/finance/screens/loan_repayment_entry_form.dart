import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/core/models/attachment_model.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/models/repayment_model.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';

/// Dedicated form for repayments against ordinary or asset-linked loans.
class LoanRepaymentEntryForm extends StatefulWidget {
  final LoansModel loan;
  const LoanRepaymentEntryForm({super.key, required this.loan});
  @override
  State<LoanRepaymentEntryForm> createState() => _LoanRepaymentEntryFormState();
}

class _LoanRepaymentEntryFormState extends State<LoanRepaymentEntryForm> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _picker = ImagePicker();
  final List<Map<String, String>> _attachments = [];
  List<Map<String, dynamic>> _wallets = [];
  int? _walletId;
  DateTime _date = DateTime.now();
  bool _loading = true, _saving = false;
  LoansModel get _loan => widget.loan;

  @override
  void initState() { super.initState(); _loadWallets(); }
  @override
  void dispose() { _amount.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _loadWallets() async {
    try {
      final wallets = await FinanceDB.instance.getWallets();
      final matching = wallets.where((w) => (w['currency']?.toString() ?? 'PKR').toUpperCase() == _loan.currency.toUpperCase()).toList();
      if (!mounted) return;
      setState(() { _wallets = matching; if (matching.isNotEmpty) _walletId = (matching.first['id'] as num).toInt(); _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); _message(e); }
  }

  void _message(Object error) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final f = await _picker.pickImage(source: source, imageQuality: 85);
        if (f != null && mounted) setState(() => _attachments.add({'path': f.path, 'name': f.name}));
      } else {
        final files = await _picker.pickMultiImage(imageQuality: 85);
        if (mounted) setState(() => _attachments.addAll(files.map((f) => {'path': f.path, 'name': f.name})));
      }
    } catch (e) { if (mounted) _message(e); }
  }

  Future<void> _pickPdfs() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true);
      if (result != null && mounted) setState(() => _attachments.addAll(result.files.where((f) => f.path != null).map((f) => {'path': f.path!, 'name': f.name})));
    } catch (e) { if (mounted) _message(e); }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || !amount.isFinite || amount <= 0) return;
    if (amount > _loan.remainingAmount + 0.000001) { _message('Amount exceeds outstanding balance.'); return; }
    if (_walletId == null) { _message('Create a ' + _loan.currency + ' wallet first.'); return; }
    setState(() => _saving = true);
    try {
      final id = await LoansService.addRepayment(RepaymentModel(
        loanId: _loan.id!, amount: amount, walletId: _walletId!,
        repaymentDate: DateFormat('yyyy-MM-dd').format(_date),
        paymentMethod: 'cash', notes: _notes.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      ));
      var failures = 0;
      for (final file in _attachments) {
        try {
          await AttachmentService.addAttachment(ownerType: AttachmentOwnerTypes.repayment, ownerId: id, sourcePath: file['path']!, originalFileName: file['name']!);
        } catch (_) { failures++; }
      }
      await SoundSettingsService.instance.play('update');
      if (!mounted) return;
      if (failures > 0) _message('Repayment saved, but ' + failures.toString() + ' attachment(s) could not be added.');
      Navigator.of(context).pop(true);
    } catch (e) { await SoundSettingsService.instance.play('error'); if (mounted) { setState(() => _saving = false); _message(e); } }
  }

  @override
  Widget build(BuildContext context) {
    final isGiven = _loan.loanType == 'given';
    if (_loading) return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));
    if (_wallets.isEmpty) return AlertDialog(
      title: Text(isGiven ? 'Receive Repayment' : 'Pay Back Loan'),
      content: Text('Create a ' + _loan.currency + ' wallet first.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close'))],
    );
    return AlertDialog(
      title: Text(isGiven ? 'Receive Repayment' : 'Pay Back Loan'),
      content: SizedBox(width: 420, child: Form(key: _key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.centerLeft, child: Text('Outstanding: ' + _loan.currency + ' ' + _loan.remainingAmount.toStringAsFixed(2))),
        const SizedBox(height: 12),
        TextFormField(controller: _amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Repayment Amount *'), validator: (v) { final n = double.tryParse(v?.trim() ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid amount.' : null; }),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: _walletId, isExpanded: true, decoration: InputDecoration(labelText: isGiven ? 'Receiving Wallet *' : 'Paying Wallet *'), items: _wallets.map((w) => DropdownMenuItem<int>(value: (w['id'] as num).toInt(), child: Text(w['name'].toString() + ' (' + w['currency'].toString() + ')'))).toList(), onChanged: (v) => setState(() => _walletId = v)),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Repayment Date'), subtitle: Text(DateFormat('dd MMM yyyy').format(_date)), trailing: const Icon(Icons.calendar_month), onTap: _pickDate),
        TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: Text('Attachments', style: Theme.of(context).textTheme.titleSmall)),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera')),
          OutlinedButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery')),
          OutlinedButton.icon(onPressed: _pickPdfs, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF')),
        ]),
        if (_attachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._attachments.asMap().entries.map((e) => ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(e.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _attachments.removeAt(e.key))))),
        ],
      ])))),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(isGiven ? 'Save Repayment' : 'Save Payment')),
      ],
    );
  }
}
