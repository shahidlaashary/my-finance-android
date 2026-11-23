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
  final RepaymentModel? existingRepayment;
  const LoanRepaymentEntryForm({super.key, required this.loan, this.existingRepayment});
  @override
  State<LoanRepaymentEntryForm> createState() => _LoanRepaymentEntryFormState();
}

class _LoanRepaymentEntryFormState extends State<LoanRepaymentEntryForm> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _manualRate = TextEditingController();
  final _picker = ImagePicker();
  final List<Map<String, String>> _attachments = [];
  List<Map<String, dynamic>> _wallets = [];
  int? _walletId;
  DateTime _date = DateTime.now();
  bool _loading = true, _saving = false, _useManualRate = false;
  double? _loanRate, _walletRate;
  LoansModel get _loan => widget.loan;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingRepayment;
    if (existing != null) {
      _amount.text = existing.amount.toStringAsFixed(2);
      _notes.text = existing.notes;
      _walletId = existing.walletId;
      _date = DateTime.tryParse(existing.repaymentDate) ?? DateTime.now();
      _useManualRate = existing.isManualRate;
      if (existing.isManualRate) _manualRate.text = existing.exchangeRate.toString();
    }
    _loadWallets();
  }
  @override
  void dispose() { _amount.dispose(); _notes.dispose(); _manualRate.dispose(); super.dispose(); }

  Future<void> _loadWallets() async {
    try {
      final wallets = await FinanceDB.instance.getWallets();
      final matching = wallets;
      if (!mounted) return;
      setState(() { _wallets = matching; if (matching.isNotEmpty && !matching.any((w) => (w['id'] as num).toInt() == _walletId)) _walletId = (matching.first['id'] as num).toInt(); _loading = false; });
      if (matching.isNotEmpty) await _loadRates();
    } catch (e) { if (mounted) setState(() => _loading = false); _message(e); }
  }

  String get _walletCurrency => (_wallets.firstWhere((w) => (w['id'] as num).toInt() == _walletId, orElse: () => {'currency': _loan.currency})['currency']?.toString() ?? _loan.currency).toUpperCase();
  double? get _convertedAmount {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) return null;
    if (_useManualRate) {
      final rate = double.tryParse(_manualRate.text.trim());
      return rate == null || !rate.isFinite || rate <= 0 ? null : amount * rate;
    }
    if (_loan.currency.toUpperCase() == _walletCurrency) return amount;
    if (_loanRate == null || _walletRate == null || _walletRate! <= 0) return null;
    return amount * _loanRate! / _walletRate!;
  }

  Future<void> _loadRates() async {
    try {
      final wallet = _wallets.firstWhere(
        (w) => (w['id'] as num).toInt() == _walletId,
      );
      final loanCurrency = _loan.currency.trim().toUpperCase();
      final walletCurrency =
          (wallet['currency']?.toString() ?? 'PKR').trim().toUpperCase();

      // Same-currency repayments need no exchange-rate lookup at all.
      if (loanCurrency == walletCurrency) {
        if (mounted) setState(() { _loanRate = 1.0; _walletRate = 1.0; });
        return;
      }

      var loanRate = await FinanceDB.instance.getExchangeRate(loanCurrency);
      var walletRate = await FinanceDB.instance.getExchangeRate(walletCurrency);

      // Reuse the Exchange Rates module's provider and save any missing rates.
      if (loanRate == null || walletRate == null) {
        await FinanceDB.instance.refreshMissingExchangeRatesOnline(
          currencies: [loanCurrency, walletCurrency],
        );
        loanRate = await FinanceDB.instance.getExchangeRate(loanCurrency);
        walletRate = await FinanceDB.instance.getExchangeRate(walletCurrency);
      }

      if (mounted) setState(() { _loanRate = loanRate; _walletRate = walletRate; });
    } catch (_) {
      if (mounted) setState(() { _loanRate = null; _walletRate = null; });
    }
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
    final allowedOutstanding = _loan.remainingAmount + (widget.existingRepayment?.amount ?? 0);
    if (amount > allowedOutstanding + 0.000001) { _message('Amount exceeds outstanding balance.'); return; }
    if (_walletId == null) { _message('Please select a wallet.'); return; }
    final convertedAmount = _convertedAmount;
    if (convertedAmount == null) { _message(_useManualRate ? 'Enter a valid manual exchange rate.' : 'Exchange rate is unavailable for the selected currencies.'); return; }
    setState(() => _saving = true);
    try {
      final repayment = RepaymentModel(
        id: widget.existingRepayment?.id,
        loanId: _loan.id!, amount: amount, walletId: _walletId!,
        repaymentDate: DateFormat('yyyy-MM-dd').format(_date),
        walletCurrency: _walletCurrency, walletAmount: convertedAmount,
        exchangeRate: _useManualRate ? double.parse(_manualRate.text.trim()) : (_loan.currency.toUpperCase() == _walletCurrency ? 1.0 : (_loanRate! / _walletRate!)),
        isManualRate: _useManualRate,
        paymentMethod: 'cash', notes: _notes.text.trim(),
        createdAt: widget.existingRepayment?.createdAt ?? DateTime.now().toIso8601String(),
      );
      final int id;
      if (widget.existingRepayment == null) {
        id = await LoansService.addRepayment(repayment);
      } else {
        await LoansService.updateRepayment(repayment);
        id = widget.existingRepayment!.id!;
      }
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
      title: Text(widget.existingRepayment == null ? (isGiven ? 'Receive Repayment' : 'Pay Back Loan') : 'Edit Repayment'),
      content: const Text('Create at least one wallet first.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close'))],
    );
    return AlertDialog(
      title: Text(widget.existingRepayment == null ? (isGiven ? 'Receive Repayment' : 'Pay Back Loan') : 'Edit Repayment'),
      content: SizedBox(width: 420, child: Form(key: _key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.centerLeft, child: Text('Outstanding: ' + _loan.currency + ' ' + _loan.remainingAmount.toStringAsFixed(2))),
        const SizedBox(height: 12),
        TextFormField(controller: _amount, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Repayment Amount *'), onChanged: (_) => setState(() {}), validator: (v) { final n = double.tryParse(v?.trim() ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid amount.' : null; }),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: _walletId, isExpanded: true, decoration: InputDecoration(labelText: isGiven ? 'Receiving Wallet *' : 'Paying Wallet *'), items: _wallets.map((w) => DropdownMenuItem<int>(value: (w['id'] as num).toInt(), child: Text(w['name'].toString() + ' (' + w['currency'].toString() + ')'))).toList(), onChanged: (v) async { setState(() => _walletId = v); await _loadRates(); setState(() {}); }),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Use Manual Rate'), subtitle: const Text('Override the app exchange rate for this repayment'), value: _useManualRate, onChanged: (v) => setState(() => _useManualRate = v)),
        if (_useManualRate)
          TextFormField(controller: _manualRate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: '1 ${_loan.currency.toUpperCase()} = ? $_walletCurrency', hintText: 'Enter wallet currency per 1 loan currency', suffixText: _walletCurrency), onChanged: (_) => setState(() {}), validator: (v) { if (!_useManualRate) return null; final n = double.tryParse(v?.trim() ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid rate.' : null; }),
        if (!_useManualRate && (_loanRate == null || _walletRate == null))
          const Align(alignment: Alignment.centerLeft, child: Text('Exchange rate unavailable. Set the required currency rates or use a manual rate.', style: TextStyle(color: Colors.red, fontSize: 12))),
        if (_convertedAmount != null)
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 6), child: Text('Wallet ${isGiven ? 'credit' : 'deduction'}: $_walletCurrency ${_convertedAmount!.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)))),

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
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.existingRepayment == null ? (isGiven ? 'Save Repayment' : 'Save Payment') : 'Update Entry')),
      ],
    );
  }
}
