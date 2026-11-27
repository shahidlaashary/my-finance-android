import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'package:my_finance/core/files/attachment_service.dart';
import 'package:my_finance/modules/finance/models/goals_model.dart';
import 'package:my_finance/modules/finance/services/goals_service.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';

/// Savings goal create form hosted inside the shared PlusActionSheet.
class GoalEntryForm extends StatefulWidget {
  const GoalEntryForm({super.key});
  @override
  State<GoalEntryForm> createState() => _GoalEntryFormState();
}

class _GoalEntryFormState extends State<GoalEntryForm> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _notes = TextEditingController();
  final List<Map<String, String>> _attachments = [];
  List<Map<String, dynamic>> _wallets = [];
  int? _walletId;
  DateTime _start = DateTime.now(), _targetDate = DateTime.now().add(const Duration(days: 30));
  bool _loading = true, _saving = false;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _name.dispose(); _target.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final wallets = await WalletService.getWallets(orderBy: 'name ASC');
      if (!mounted) return;
      setState(() { _wallets = wallets; _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); _message('Error loading wallets: $e'); }
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
    final picked = await showDatePicker(context: context,
      initialDate: start ? _start : _targetDate,
      firstDate: start ? DateTime(2000) : _start, lastDate: DateTime(2100));
    if (picked != null && mounted) setState(() { if (start) _start = picked; else _targetDate = picked; });
  }

  Future<void> _addFile(String path, String name) async {
    if (File(path).existsSync() && mounted) setState(() => _attachments.add({'path': path, 'name': name}));
  }

  Future<void> _pickAttachments(String type) async {
    if (type == 'camera') {
      final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      if (file != null) await _addFile(file.path, file.name);
    } else if (type == 'gallery') {
      final files = await ImagePicker().pickMultiImage(imageQuality: 85);
      for (final file in files) { await _addFile(file.path, file.name); }
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true);
      if (result != null) for (final file in result.files) { if (file.path != null) await _addFile(file.path!, file.name); }
    }
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    if (_start.isAfter(_targetDate)) { _message('Start date cannot be after target date.'); return; }
    setState(() => _saving = true);
    try {
      final id = await GoalsService.addGoal(GoalsModel(
        name: _name.text.trim(), targetAmount: double.parse(_target.text),
        startDate: _start, targetDate: _targetDate, walletId: _walletId,
        notes: _notes.text.trim(), createdAt: DateTime.now(),
      ));
      await SoundSettingsService.instance.play('save');
      var failed = 0;
      for (final file in _attachments) {
        try {
          await AttachmentService.addAttachment(ownerType: 'goal', ownerId: id,
            sourcePath: file['path']!, originalFileName: file['name']);
        } catch (_) { failed++; }
      }
      if (!mounted) return;
      if (failed > 0) _message('$failed attachment(s) could not be saved. You can add them from the goal card.');
      Navigator.pop(context, true);
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
        TextFormField(controller: _name, decoration: _dec('Goal Name', Icons.flag_outlined),
          validator: (v) => v == null || v.trim().isEmpty ? 'Enter goal name' : null),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextFormField(controller: _target, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec('Target Amount', Icons.savings_outlined),
            validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid target amount' : null; })),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<int?>(value: _walletId, isExpanded: true,
            decoration: _dec('Linked Wallet', Icons.account_balance_wallet_outlined),
            items: [const DropdownMenuItem<int?>(value: null, child: Text('No linked wallet')),
              ..._wallets.map((w) => DropdownMenuItem<int?>(value: (w['id'] as num).toInt(), child: Text('${w['name']} (${w['currency'] ?? 'PKR'})', overflow: TextOverflow.ellipsis)))],
            onChanged: (v) => setState(() => _walletId = v))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: InkWell(onTap: () => _pickDate(true), child: InputDecorator(
            decoration: _dec('Start Date', Icons.calendar_today_outlined),
            child: Text(DateFormat('dd MMM yyyy').format(_start), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))))),
          const SizedBox(width: 10),
          Expanded(child: InkWell(onTap: () => _pickDate(false), child: InputDecorator(
            decoration: _dec('Target Date', Icons.event_outlined),
            child: Text(DateFormat('dd MMM yyyy').format(_targetDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))))),
        ]),
        const SizedBox(height: 12),
        TextFormField(controller: _notes, maxLines: 2, decoration: _dec('Notes (optional)', Icons.notes_outlined)),
        const SizedBox(height: 10),
        Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.attach_file, size: 19), const SizedBox(width: 8), const Expanded(child: Text('Attachments', style: TextStyle(fontWeight: FontWeight.w700))), Text('${_attachments.length}')]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: () => _pickAttachments('camera'), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera')),
            OutlinedButton.icon(onPressed: () => _pickAttachments('gallery'), icon: const Icon(Icons.photo_library_outlined), label: const Text('Gallery')),
            OutlinedButton.icon(onPressed: () => _pickAttachments('pdf'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Add PDFs')),
          ]),
          if (_attachments.isNotEmpty) ...[
            const Divider(height: 18),
            ..._attachments.asMap().entries.map((entry) => ListTile(dense: true, contentPadding: EdgeInsets.zero,
              leading: Icon(entry.value['name']!.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
              title: Text(entry.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(icon: const Icon(Icons.close_rounded, size: 19), onPressed: () => setState(() => _attachments.removeAt(entry.key))))),
          ],
        ]))),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create Goal')),
      ]),
    ));
  }
}
