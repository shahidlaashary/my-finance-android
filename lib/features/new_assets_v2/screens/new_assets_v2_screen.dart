import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';

import '../models/new_asset_record.dart';
import '../services/new_assets_service.dart';

/// Standalone UI for the parallel New Assets System v2.
/// It is intentionally not wired into the legacy Assets tab yet.
class NewAssetsV2Screen extends StatefulWidget {
  const NewAssetsV2Screen({super.key});

  @override
  State<NewAssetsV2Screen> createState() => _NewAssetsV2ScreenState();
}

class _NewAssetsV2ScreenState extends State<NewAssetsV2Screen> {
  final _service = NewAssetsService.instance;
  List<NewAssetRecord> _assets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final assets = await _service.getAssets(includeSold: true);
      if (mounted) setState(() { _assets = assets; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _message(e);
    }
  }

  void _message(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _openAdd() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NewAssetV2FormScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _openDetails(NewAssetRecord asset) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => NewAssetV2DetailsScreen(asset: asset)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = _assets.where((a) => !a.isSold).toList();
    final sold = _assets.where((a) => a.isSold).length;
    final currencyTotals = <String, double>{};
    for (final asset in active) {
      currencyTotals.update(asset.currency, (v) => v + asset.currentValue,
          ifAbsent: () => asset.currentValue);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Assets v2'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Asset'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _SummaryPanel(
                    count: active.length,
                    soldCount: sold,
                    totals: currencyTotals,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('My Assets',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                      Text('${active.length} active',
                          style: TextStyle(color: Theme.of(context).hintColor)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_assets.isEmpty)
                    const _EmptyAssets()
                  else
                    ..._assets.map((asset) => _AssetTile(
                          asset: asset,
                          onTap: () => _openDetails(asset),
                        )),
                ],
              ),
            ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.count,
    required this.soldCount,
    required this.totals,
  });

  final int count;
  final int soldCount;
  final Map<String, double> totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current Asset Value',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (totals.isEmpty)
            const Text('—', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800))
          else
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: totals.entries.map((entry) => Text(
                '${entry.key} ${NumberFormat('#,##0.##').format(entry.value)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              )).toList(),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              _SummaryMetric(label: 'Active Assets', value: '$count'),
              const SizedBox(width: 24),
              _SummaryMetric(label: 'Sold Assets', value: '$soldCount'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ],
      );
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset, required this.onTap});
  final NewAssetRecord asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final difference = asset.currentValue - asset.purchaseAmount;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: .6)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.real_estate_agent_outlined, color: theme.colorScheme.primary),
        ),
        title: Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${asset.category} • ${asset.paymentType} • ${DateFormat('dd MMM yyyy').format(asset.purchaseDate)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${asset.currency} ${NumberFormat('#,##0.##').format(asset.currentValue)}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(asset.isSold ? 'Sold' : '${difference >= 0 ? '+' : ''}${NumberFormat('#,##0.##').format(difference)}',
                style: TextStyle(fontSize: 11,
                    color: asset.isSold ? theme.hintColor : (difference >= 0 ? Colors.green : theme.colorScheme.error))),
          ],
        ),
      ),
    );
  }
}

class _EmptyAssets extends StatelessWidget {
  const _EmptyAssets();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 54),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            const Text('No assets added yet', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Add your first asset to start tracking its value.',
                style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
      );
}

class NewAssetV2FormScreen extends StatefulWidget {
  const NewAssetV2FormScreen({super.key});

  @override
  State<NewAssetV2FormScreen> createState() => _NewAssetV2FormScreenState();
}

class _NewAssetV2FormScreenState extends State<NewAssetV2FormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _purchase = TextEditingController();
  final _current = TextEditingController();
  final _notes = TextEditingController();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _wallets = [];
  List<Map<String, dynamic>> _parties = [];
  int? _walletId;
  int? _partyId;
  String _category = 'Property';
  String _paymentType = 'Wallet';
  String _currency = 'PKR';
  DateTime _purchaseDate = DateTime.now();
  bool _includeBalance = false;
  bool _loading = true;
  bool _saving = false;
  final List<PlatformFile> _pdfs = [];
  XFile? _photo;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _name.dispose();
    _purchase.dispose();
    _current.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final wallets = await FinanceDB.instance.getWallets();
      final parties = await LoansService.getParties();
      final base = await FinanceDB.instance.getBaseCurrency();
      if (!mounted) return;
      setState(() {
        _wallets = wallets;
        _parties = parties;
        _currency = base;
        _walletId = wallets.isEmpty ? null : (wallets.first['id'] as num).toInt();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showError(e);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Map<String, dynamic>? get _selectedWallet {
    for (final wallet in _wallets) {
      if ((wallet['id'] as num).toInt() == _walletId) return wallet;
    }
    return null;
  }

  Map<String, dynamic>? get _selectedParty {
    for (final party in _parties) {
      if ((party['id'] as num).toInt() == _partyId) return party;
    }
    return null;
  }

  Future<void> _createParty() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    var partyCurrency = _currency;
    final key = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Party'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Party name'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter party name.' : null),
              TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone),
              DropdownButtonFormField<String>(
                value: partyCurrency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: CurrencyCatalog.supported.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) { if (v != null) partyCurrency = v; },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (key.currentState?.validate() == true) Navigator.pop(dialogContext, true);
          }, child: const Text('Save')),
        ],
      ),
    );
    if (result == true) {
      try {
        final id = await LoansService.addParty(
          name: name.text.trim(),
          phone: phone.text.trim(),
          currency: partyCurrency,
        );
        final parties = await LoansService.getParties();
        if (mounted) setState(() { _parties = parties; _partyId = id; _currency = partyCurrency; });
      } catch (e) {
        _showError(e);
      }
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _pickAttachments() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.photo_outlined), title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery')),
          ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('PDF files'),
              onTap: () => Navigator.pop(ctx, 'pdf')),
        ]),
      ),
    );
    if (choice == 'camera' || choice == 'gallery') {
      final photo = await _picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
      );
      if (photo != null && mounted) setState(() => _photo = photo);
    } else if (choice == 'pdf') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true,
      );
      if (result != null && mounted) {
        setState(() => _pdfs.addAll(result.files.where((file) => file.path != null)));
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _formKey.currentState?.validate() != true) return;
    final purchase = double.tryParse(_purchase.text.trim());
    final current = double.tryParse(_current.text.trim());
    if (purchase == null || current == null) return;

    if (_paymentType == 'Wallet') {
      if (_selectedWallet == null) { _showError(StateError('Select a wallet.')); return; }
      _currency = (_selectedWallet!['currency']?.toString() ?? 'PKR').toUpperCase();
    } else {
      if (_selectedParty == null) { _showError(StateError('Select a loan party.')); return; }
      _currency = (_selectedParty!['currency']?.toString() ?? 'PKR').toUpperCase();
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final id = await NewAssetsService.instance.createAsset(NewAssetRecord(
        name: _name.text.trim(),
        category: _category,
        currency: _currency,
        purchaseAmount: purchase,
        currentValue: current,
        purchaseDate: _purchaseDate,
        paymentType: _paymentType,
        walletId: _paymentType == 'Wallet' ? _walletId : null,
        partyId: _paymentType == 'Loan' ? _partyId : null,
        includeInConsolidatedBalance: _includeBalance,
        notes: _notes.text.trim(),
        createdAt: now,
        updatedAt: now,
      ));

      if (_photo != null) {
        await NewAssetsService.instance.addAttachment(
          assetId: id, filePath: _photo!.path, fileName: _photo!.name, mimeType: 'image',
        );
      }
      for (final file in _pdfs) {
        if (file.path == null) continue;
        await NewAssetsService.instance.addAttachment(
          assetId: id, filePath: file.path!, fileName: file.name, mimeType: 'application/pdf',
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Asset')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            TextFormField(
              controller: _name,
              decoration: _dec('Asset name *', icon: Icons.inventory_2_outlined),
              validator: (v) => v == null || v.trim().isEmpty ? 'Enter asset name.' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: _dec('Category'),
              items: const ['Property', 'Vehicles', 'Gold', 'Jewellery', 'Electronics', 'Investments', 'Livestock', 'Business', 'Other']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() => _category = v); },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _paymentType,
              decoration: _dec('Purchase payment type'),
              items: const ['Wallet', 'Loan'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => _paymentType = v ?? 'Wallet'),
            ),
            if (_paymentType == 'Wallet') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _walletId,
                isExpanded: true,
                decoration: _dec('Payment wallet'),
                items: _wallets.map((w) => DropdownMenuItem(
                  value: (w['id'] as num).toInt(),
                  child: Text('${w['name']} (${w['currency']})', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() => _walletId = v),
                validator: (_) => _paymentType == 'Wallet' && _walletId == null ? 'Add/select a wallet.' : null,
              ),
            ] else ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(onPressed: _createParty,
                    icon: const Icon(Icons.person_add_alt_1), label: const Text('Create Party')),
              ),
              DropdownButtonFormField<int>(
                value: _partyId,
                isExpanded: true,
                decoration: _dec('Loan party'),
                items: _parties.map((p) => DropdownMenuItem(
                  value: (p['id'] as num).toInt(), child: Text(p['name'].toString()),
                )).toList(),
                onChanged: (v) => setState(() => _partyId = v),
                validator: (_) => _paymentType == 'Loan' && _partyId == null ? 'Select a party.' : null,
              ),
              const SizedBox(height: 4),
              Text('No wallet is needed at purchase time. A wallet will be selected when repayment is recorded.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _purchase,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _dec('Purchase amount *'),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                return n == null || !n.isFinite || n <= 0 ? 'Enter a valid amount.' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _current,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _dec('Current value *'),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                return n == null || !n.isFinite || n < 0 ? 'Enter a valid value.' : null;
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Purchase date'),
              subtitle: Text(DateFormat('dd MMM yyyy').format(_purchaseDate)),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () async {
                final date = await showDatePicker(
                  context: context, initialDate: _purchaseDate,
                  firstDate: DateTime(1950), lastDate: DateTime.now(),
                );
                if (date != null && mounted) setState(() => _purchaseDate = date);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include in Consolidated Balance'),
              subtitle: const Text('Sold assets will be excluded automatically.'),
              value: _includeBalance,
              onChanged: (v) => setState(() => _includeBalance = v),
            ),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: _dec('Notes (Optional)', icon: Icons.notes_outlined),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickAttachments,
              icon: const Icon(Icons.attach_file_rounded),
              label: Text('Attachments (${(_photo == null ? 0 : 1) + _pdfs.length})'),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: const Text('Save Asset'),
            ),
          ],
        ),
      ),
    );
  }
}

class NewAssetV2DetailsScreen extends StatefulWidget {
  const NewAssetV2DetailsScreen({super.key, required this.asset});
  final NewAssetRecord asset;

  @override
  State<NewAssetV2DetailsScreen> createState() => _NewAssetV2DetailsScreenState();
}

class _NewAssetV2DetailsScreenState extends State<NewAssetV2DetailsScreen> {
  List<Map<String, Object?>> _events = [];
  List<Map<String, Object?>> _attachments = [];
  late NewAssetRecord _asset;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _asset = widget.asset;
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await NewAssetsService.instance.getEvents(_asset.id!);
      final attachments = await NewAssetsService.instance.getAttachments(_asset.id!);
      final refreshed = await NewAssetsService.instance.getAsset(_asset.id!);
      if (!mounted) return;
      setState(() {
        _events = events;
        _attachments = attachments;
        if (refreshed != null) _asset = refreshed;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat('#,##0.##');
    return Scaffold(
      appBar: AppBar(title: const Text('Asset Details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_asset.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('${_asset.category} • ${_asset.paymentType} • ${_asset.currency}'),
                    const SizedBox(height: 18),
                    const Text('Current Value'),
                    Text('${_asset.currency} ${format.format(_asset.currentValue)}',
                        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('Purchase: ${_asset.currency} ${format.format(_asset.purchaseAmount)}'),
                    Text('Purchase date: ${DateFormat('dd MMM yyyy').format(_asset.purchaseDate)}'),
                    if (_asset.includeInConsolidatedBalance)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Chip(label: Text('Included in Consolidated Balance')),
                      ),
                  ]),
                ),
                const SizedBox(height: 18),
                const Text('Activity & Entries', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (_events.isEmpty)
                  const Text('No activity recorded yet.')
                else
                  ..._events.map((event) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
                    title: Text((event['event_type'] ?? 'Activity').toString().replaceAll('_', ' ').toUpperCase()),
                    subtitle: Text(event['note']?.toString() ?? ''),
                    trailing: Text('${event['currency']} ${format.format((event['amount'] as num).toDouble())}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  )),
                const SizedBox(height: 16),
                const Text('Attachments', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                if (_attachments.isEmpty)
                  const ListTile(contentPadding: EdgeInsets.zero, title: Text('No attachments'))
                else
                  ..._attachments.map((file) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(file['mime_type'] == 'application/pdf'
                        ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                    title: Text(file['file_name']?.toString() ?? 'Attachment'),
                    subtitle: Text(file['file_path']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  )),
                if (_asset.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Notes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(_asset.notes),
                ],
              ],
            ),
    );
  }
}
