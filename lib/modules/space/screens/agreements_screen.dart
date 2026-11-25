import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/modules/space/services/my_space_service.dart';
import 'package:my_finance/modules/space/services/agreement_template_service.dart';
import 'package:my_finance/modules/space/services/agreement_pdf_service.dart';
import 'package:my_finance/modules/space/services/agreement_territory_service.dart';
import 'package:my_finance/modules/space/screens/agreement_templates_screen.dart';

class AgreementsScreen extends StatefulWidget {
  const AgreementsScreen({super.key});

  @override
  State<AgreementsScreen> createState() => AgreementsScreenState();
}

class AgreementsScreenState extends State<AgreementsScreen> {
  Future<List<Map<String, Object?>>>? _records;

  @override
  void initState() {
    super.initState();
    refreshAgreements();
  }

  void refreshAgreements() {
    _records = MySpaceService.instance.getAgreements();
    if (mounted) setState(() {});
  }

  Future<void> _openForm([Map<String, Object?>? record]) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AgreementFormScreen(record: record),
    ));
    refreshAgreements();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: _records,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) return Center(child: Text('Unable to load Agreements: ${snapshot.error}'));
      final rows = snapshot.data ?? [];
      if (rows.isEmpty) {
        return Center(child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.handshake_outlined, size: 58, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text('No agreements yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            Text('Keep agreements, parties, dates and important terms together.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add), label: const Text('Add Agreement')),
          ]),
        ));
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = rows[index];
          final subtitle = [row['category'], row['party_one'], row['party_two'], row['status']]
            .where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ');
          return Card(child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.handshake_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer)),
            title: Text(row['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(subtitle.isEmpty ? (row['description']?.toString() ?? '') : subtitle,
              maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _showDetails(context, row),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  await _openForm(row);
                } else if (value == 'terminate') {
                  await _terminateAgreement(row);
                } else if (value == 'reinstate') {
                  await _reinstateAgreement(row);
                } else if (value == 'delete') {
                  final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                    title: const Text('Delete agreement?'),
                    content: Text('“${row['title']}” will be permanently removed.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                    ],
                  ));
                  if (yes == true) {
                    await MySpaceService.instance.deleteAgreement(row['id'] as int);
                    refreshAgreements();
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (row['status']?.toString() == 'Terminated')
                  const PopupMenuItem(
                    value: 'reinstate',
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.restore_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Reinstate'),
                    ]),
                  )
                else
                  const PopupMenuItem(
                    value: 'terminate',
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.block_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Terminate'),
                    ]),
                  ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ));
        },
      );
    },
  );

  Future<void> _terminateAgreement(Map<String, Object?> row) async {
    final dateController = TextEditingController(
      text: DateTime.now().toIso8601String().split('T').first,
    );
    String? selectedReason;
    var saving = false;
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Terminate Agreement'),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '“${row['title']}” will be marked as Terminated. This will not delete the agreement.',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Termination Date',
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  onTap: () async {
                    final initial = DateTime.tryParse(dateController.text) ?? DateTime.now();
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: initial,
                      firstDate: DateTime(1950),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      dateController.text = picked.toIso8601String().split('T').first;
                      setDialogState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Termination Reason',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    'Mutual Agreement',
                    'Contract Breach',
                    'Payment Issues',
                    'Rights Reversion',
                    'Early Termination',
                    'Other',
                  ].map((reason) => DropdownMenuItem(
                    value: reason,
                    child: Text(reason),
                  )).toList(),
                  onChanged: (value) => setDialogState(() => selectedReason = value),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: saving || dateController.text.trim().isEmpty || selectedReason == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.block_outlined),
                label: const Text('Terminate Agreement'),
              ),
            ],
          ),
        ),
      );
      if (result != true || !mounted) return;
      await MySpaceService.instance.terminateAgreement(
        row['id'] as int,
        terminationDate: dateController.text.trim(),
        reason: selectedReason!,
      );
      refreshAgreements();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agreement terminated successfully.')),
        );
      }
    } finally {
      dateController.dispose();
    }
  }

  Future<void> _reinstateAgreement(Map<String, Object?> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reinstate Agreement?'),
        content: Text('“${row['title']}” will be restored from Terminated status. Its active status will be recalculated using its signing and expiry dates.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Reinstate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await MySpaceService.instance.reinstateAgreement(row['id'] as int);
    refreshAgreements();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agreement reinstated successfully.')),
      );
    }
  }

  void _showDetails(BuildContext context, Map<String, Object?> row) {
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
            Text(row['title']?.toString() ?? '', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => AgreementPdfService.instance.printAgreement(row),
                icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Preview / Print PDF')),
              OutlinedButton.icon(
                onPressed: () => AgreementPdfService.instance.shareAgreement(row),
                icon: const Icon(Icons.share_outlined), label: const Text('Share PDF')),
            ]),
            const SizedBox(height: 12),
            for (final field in <String, String>{
              'Type': 'category', 'First Party': 'party_one', 'Second Party': 'party_two',
              'Status': 'status', 'Signing Date': 'signing_date', 'End / Expiry Date': 'end_date',
              'Termination Date': 'termination_date', 'Termination Reason': 'termination_reason',
              'Details': 'description', 'Notes': 'notes',
            }.entries)
              if ((row[field.value]?.toString() ?? '').trim().isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(field.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 3), Text(row[field.value].toString()),
                  ],
                )),
          ],
        )),
      )),
    );
  }
}

class AgreementFormScreen extends StatefulWidget {
  const AgreementFormScreen({super.key, this.record});
  final Map<String, Object?>? record;

  @override
  State<AgreementFormScreen> createState() => _AgreementFormScreenState();
}

class _AgreementFormScreenState extends State<AgreementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title, _category, _partyOne, _partyTwo, _end, _description, _notes;
  late String _status;
  bool _saving = false;
  String _signatureData = '';
  String _signatureDataTwo = '';
  bool _isTerminated = false;
  int? _templateId;
  int? _selectedLabelId;
  String _templateTitleSnapshot = '';
  String _templateBodySnapshot = '';
  late Future<List<Map<String, Object?>>> _templateOptions;
  late final TextEditingController _labelName, _address, _territory, _termYears, _tracks, _designation, _signingDate, _witnessName, _terminationDate, _terminationReason;
  final List<Map<String, String>> _selectedAttachments = [];
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final r = widget.record ?? {};
    _title = TextEditingController(text: r['title']?.toString() ?? '');
    _category = TextEditingController(text: r['category']?.toString() ?? '');
    _partyOne = TextEditingController(text: r['party_one']?.toString() ?? '');
    _partyTwo = TextEditingController(text: r['party_two']?.toString() ?? '');
    _end = TextEditingController(text: r['end_date']?.toString() ?? '');
    _description = TextEditingController(text: r['description']?.toString() ?? '');
    _notes = TextEditingController(text: r['notes']?.toString() ?? '');
    _status = r['status']?.toString() ?? 'Draft';
    _signatureData = r['signature_data']?.toString() ?? '';
    _signatureDataTwo = r['signature_data_two']?.toString() ?? '';
    _isTerminated = r['status']?.toString() == 'Terminated';
    _templateId = r['template_id'] as int?;
    _templateTitleSnapshot = r['template_title_snapshot']?.toString() ?? '';
    _templateBodySnapshot = r['template_body_snapshot']?.toString() ?? '';
    _labelName = TextEditingController(text: r['label_name']?.toString() ?? '');
    _selectedLabelId = r['label_id'] as int?;
    _address = TextEditingController(text: r['address']?.toString() ?? '');
    _territory = TextEditingController(text: r['territory']?.toString() ?? 'Worldwide');
    _termYears = TextEditingController(text: r['term_years']?.toString() ?? '10');
    _tracks = TextEditingController(text: r['track_details']?.toString() ?? '');
    _designation = TextEditingController(text: r['designation']?.toString() ?? '');
    _signingDate = TextEditingController(text: r['signing_date']?.toString() ?? '');
    _witnessName = TextEditingController(text: r['witness_name']?.toString() ?? '');
    _terminationDate = TextEditingController(text: r['termination_date']?.toString() ?? '');
    _terminationReason = TextEditingController(text: r['termination_reason']?.toString() ?? '');
    _templateOptions = AgreementTemplateService.instance.getTemplates();
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _partyOne, _partyTwo, _end, _description, _notes,
      _labelName, _address, _territory, _termYears, _tracks, _designation, _signingDate, _witnessName, _terminationDate, _terminationReason]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _addAttachment(String path, String name) async {
    if (!_selectedAttachments.any((item) => item['path'] == path) && mounted) {
      setState(() => _selectedAttachments.add({'path': path, 'name': name}));
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
    if (result == null) return;
    for (final file in result.files) {
      if (file.path != null) await _addAttachment(file.path!, file.name);
    }
  }

  Future<void> _takePhoto() async {
    final photo = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (photo != null) await _addAttachment(photo.path, photo.name);
  }

  Future<void> _pickGallery() async {
    final photos = await _imagePicker.pickMultiImage(imageQuality: 90);
    for (final photo in photos) { await _addAttachment(photo.path, photo.name); }
  }

  Widget _field(TextEditingController controller, String label, {int lines = 1, bool required = false}) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
      controller: controller, maxLines: lines,
      onChanged: (_) { if (mounted) setState(() {}); },
      decoration: InputDecoration(
        labelText: label, border: const OutlineInputBorder(), isDense: true,
        suffixIcon: label == 'Notes' ? PopupMenuButton<String>(
          tooltip: 'Attach files', icon: const Icon(Icons.attach_file_rounded),
          onSelected: (value) {
            if (value == 'files') _pickFiles();
            if (value == 'camera') _takePhoto();
            if (value == 'gallery') _pickGallery();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'files', child: Text('Browse Files')),
            PopupMenuItem(value: 'camera', child: Text('Scan / Camera')),
            PopupMenuItem(value: 'gallery', child: Text('Gallery')),
          ],
        ) : null,
      ),
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'Required' : null : null,
    ));

  Future<void> _selectTerritories() async {
    final selected = _territory.text.trim().isEmpty || _territory.text.trim() == 'Worldwide'
        ? <String>{'Worldwide'}
        : _territory.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toSet();
    final searchController = TextEditingController();
    final continents = AgreementTerritoryService.regions.entries.take(6).toList();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = searchController.text.trim().toLowerCase();
          final worldwideMatches = 'worldwide'.contains(query);
          final visibleContinents = continents.where((entry) =>
              entry.key.toLowerCase().contains(query) ||
              entry.value.any((country) => country.toLowerCase().contains(query))).toList();
          void toggle(String name, bool? value) {
            setDialogState(() {
              if (name == 'Worldwide' && value == true) {
                selected..clear()..add('Worldwide');
                return;
              }
              selected.remove('Worldwide');
              if (value == true) {
                selected.add(name);
              } else {
                selected.remove(name);
              }
              if (selected.isEmpty) selected.add('Worldwide');
            });
          }

          return AlertDialog(
            title: const Text('Select Territories'),
            content: SizedBox(
              width: 420,
              height: 460,
              child: Column(children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search continents or countries',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () { searchController.clear(); setDialogState(() {}); },
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                Expanded(child: ListView(
                  children: [
                    if (worldwideMatches)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Worldwide', style: TextStyle(fontWeight: FontWeight.w600)),
                        value: selected.contains('Worldwide'),
                        onChanged: (value) => toggle('Worldwide', value),
                      ),
                    ...visibleContinents.map((entry) {
                      final continent = entry.key;
                      final countries = entry.value.where((country) =>
                          query.isEmpty ||
                          continent.toLowerCase().contains(query) ||
                          country.toLowerCase().contains(query)).toList();
                      final allSelected = selected.contains(continent) ||
                          (entry.value.isNotEmpty && entry.value.every(selected.contains));
                      final someSelected = selected.contains(continent) ||
                          entry.value.any(selected.contains);
                      return ExpansionTile(
                        key: PageStorageKey<String>('territory-$continent'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(left: 12),
                        initiallyExpanded: query.isNotEmpty,
                        title: Text(continent, style: const TextStyle(fontWeight: FontWeight.w600)),
                        leading: Checkbox(
                          value: allSelected ? true : (someSelected ? null : false),
                          tristate: true,
                          onChanged: (value) {
                            setDialogState(() {
                              selected.remove('Worldwide');
                              if (value == true) {
                                selected.removeWhere(entry.value.contains);
                                selected.add(continent);
                              } else {
                                selected.remove(continent);
                                selected.removeWhere(entry.value.contains);
                              }
                              if (selected.isEmpty) selected.add('Worldwide');
                            });
                          },
                        ),
                        children: countries.map((country) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(country),
                          value: selected.contains(continent) || selected.contains(country),
                          onChanged: (value) {
                            selected.remove(continent);
                            toggle(country, value);
                          },
                        )).toList(),
                      );
                    }),
                  ],
                )),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    selected.contains('Worldwide') ? 'Worldwide' : selected.length.toString() + ' selected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, selected),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    searchController.dispose();
    if (result != null && mounted) {
      setState(() => _territory.text = AgreementTerritoryService.normalizeForPdf(result));
    }
  }

  Future<void> _captureSignature({required bool secondParty}) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _AgreementSignatureDialog(),
    );
    if (result != null && mounted) setState(() {
      if (secondParty) { _signatureDataTwo = result; } else { _signatureData = result; }
    });
  }

  DateTime? get _signingDateValue => DateTime.tryParse(_signingDate.text);
  DateTime? get _calculatedExpiryDate {
    final enteredExpiry = DateTime.tryParse(_end.text);
    if (enteredExpiry != null) return enteredExpiry;
    final signed = _signingDateValue;
    if (signed == null) return null;
    final years = int.tryParse(_termYears.text) ?? 10;
    return DateTime(signed.year + years, signed.month, signed.day);
  }
  String get _effectiveStatus {
    if (_isTerminated) return 'Terminated';
    final signed = _signingDateValue;
    if (signed == null) return 'Draft';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final signingDay = DateTime(signed.year, signed.month, signed.day);
    if (today.isBefore(signingDay)) return 'Draft';
    final expiry = _calculatedExpiryDate;
    if (expiry != null && !today.isBefore(expiry)) return 'Expired';
    return 'Active';
  }

  Future<void> _terminateAgreement() async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Terminate Agreement?'),
      content: const Text('This agreement will be marked Terminated. Record the termination date and an optional reason.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terminate')),
      ],
    ));
    if (yes == true && mounted) setState(() {
      _isTerminated = true;
      if (_terminationDate.text.isEmpty) {
        final now = DateTime.now();
        _terminationDate.text = now.toIso8601String().split('T').first;
      }
    });
  }

  Future<void> _manageLabels() async {
    final service = MySpaceService.instance;
    var companies = await service.getAgreementCompanies();
    var labels = await service.getAgreementLabels();
    if (!mounted) return;
    final labelController = TextEditingController();
    int? companyId = companies.isEmpty ? null : companies.first['id'] as int;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Manage Companies & Labels'),
        content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: DropdownButtonFormField<int>(
              value: companies.any((e) => e['id'] == companyId) ? companyId : null,
              decoration: const InputDecoration(labelText: 'Company', border: OutlineInputBorder(), isDense: true),
              items: companies.map((e) => DropdownMenuItem<int>(value: e['id'] as int, child: Text(e['name'].toString()))).toList(),
              onChanged: (v) => setDialogState(() => companyId = v),
            )),
            IconButton(tooltip: 'Create Company', icon: const Icon(Icons.add_business_outlined),
              onPressed: () async {
                final name = await showDialog<String>(context: dialogContext, builder: (ctx) {
                  final controller = TextEditingController();
                  return AlertDialog(title: const Text('Create Company'),
                    content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Company Name')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Create')),
                    ]);
                });
                if (name != null && name.trim().isNotEmpty) {
                  await service.createAgreementCompany(name);
                  companies = await service.getAgreementCompanies();
                  for (final company in companies) {
                    if (company['name'].toString().toLowerCase() == name.toLowerCase()) companyId = company['id'] as int;
                  }
                  setDialogState(() {});
                }
              }),
          ]),
          const SizedBox(height: 10),
          TextField(controller: labelController, onChanged: (_) => setDialogState(() {}),
            decoration: const InputDecoration(labelText: 'New Label Name', border: OutlineInputBorder(), isDense: true)),
          Align(alignment: Alignment.centerRight, child: FilledButton.icon(
            onPressed: companyId == null || labelController.text.trim().isEmpty ? null : () async {
              try {
                await service.createAgreementLabel(companyId: companyId!, name: labelController.text);
                labelController.clear();
                labels = await service.getAgreementLabels();
                setDialogState(() {});
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to add label: $e')));
              }
            },
            icon: const Icon(Icons.add), label: const Text('Add Label'),
          )),
          const Divider(),
          Align(alignment: Alignment.centerLeft, child: Text('Companies', style: Theme.of(context).textTheme.titleSmall)),
          SizedBox(height: 90, child: ListView(shrinkWrap: true, children: companies.map((company) => ListTile(
            dense: true, title: Text(company['name'].toString()),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
              await service.deleteAgreementCompany(company['id'] as int);
              companies = await service.getAgreementCompanies();
              labels = await service.getAgreementLabels();
              companyId = companies.isEmpty ? null : companies.first['id'] as int;
              setDialogState(() {});
            }),
          )).toList())),
          Align(alignment: Alignment.centerLeft, child: Text('Labels', style: Theme.of(context).textTheme.titleSmall)),
          SizedBox(height: 180, child: ListView(shrinkWrap: true, children: labels.map((label) => ListTile(
            dense: true, title: Text(label['name'].toString()), subtitle: Text(label['company_name'].toString()),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
              await service.deleteAgreementLabel(label['id'] as int);
              labels = await service.getAgreementLabels();
              setDialogState(() {});
            }),
          )).toList())),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
      ),
    ));
    labelController.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_signingDate.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signing Date is required.')));
      return;
    }
    if (_isTerminated && _terminationDate.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Termination Date is required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await MySpaceService.instance.saveAgreement({
        'id': widget.record?['id'], 'title': _title.text, 'category': _category.text,
        'party_one': _partyOne.text, 'party_two': _partyTwo.text, 'status': _effectiveStatus,
        'end_date': _end.text,
        'description': _description.text, 'notes': _notes.text,
        'signature_data': _signatureData,
        'signature_data_two': _signatureDataTwo,
        'signing_date': _signingDate.text,
        'termination_date': _terminationDate.text,
        'termination_reason': _terminationReason.text,
        'template_id': _templateId,
        'template_title_snapshot': _templateTitleSnapshot,
        'template_body_snapshot': _templateBodySnapshot,
        'label_name': _labelName.text, 'label_id': _selectedLabelId, 'address': _address.text,
        'territory': _territory.text, 'term_years': _termYears.text,
        'track_details': _tracks.text, 'designation': _designation.text,
        'witness_name': _witnessName.text,
      });
      var failures = 0;
      for (final file in _selectedAttachments) {
        try {
          await AttachmentService.addAttachment(
            ownerType: AttachmentOwnerTypes.agreement, ownerId: id,
            sourcePath: file['path']!, originalFileName: file['name'],
          );
        } catch (_) { failures++; }
      }
      if (!mounted) return;
      if (failures > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$failures attachment(s) could not be added.')));
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to save: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    DateTime initial = DateTime.tryParse(controller.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      controller.text = picked.toIso8601String().split('T').first;
      setState(() {});
    }
  }

  Widget _dateField(TextEditingController controller, String label, {bool optional = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: () => _pickDate(controller),
        decoration: InputDecoration(
          labelText: label,
          hintText: optional ? 'Optional' : 'Select date',
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (optional && controller.text.isNotEmpty)
              IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(controller.clear)),
            const Icon(Icons.calendar_month_outlined),
            const SizedBox(width: 10),
          ]),
        ),
      ),
    );

  Future<void> _previewAgreement() async {
    final data = <String, Object?>{
      'title': _title.text,
      'category': _category.text,
      'party_one': _partyOne.text,
      'party_two': _partyTwo.text,
      'status': _effectiveStatus,
      'end_date': _end.text,
      'description': _description.text,
      'notes': _notes.text,
      'signature_data': _signatureData,
      'signature_data_two': _signatureDataTwo,
      'signing_date': _signingDate.text,
      'termination_date': _terminationDate.text,
      'termination_reason': _terminationReason.text,
      'template_id': _templateId,
      'template_title_snapshot': _templateTitleSnapshot,
      'template_body_snapshot': _templateBodySnapshot,
      'label_name': _labelName.text,
      'address': _address.text,
      'territory': _territory.text,
      'term_years': _termYears.text,
      'track_details': _tracks.text,
      'designation': _designation.text,
      'witness_name': _witnessName.text,
    };
    await AgreementPdfService.instance.printAgreement(data);
  }

  @override
  Widget build(BuildContext context) {
    const terms = ['2', '5', '10', '15', '20'];
    const designations = ['Owner', 'Authorized'];
    final selectedTerm = terms.contains(_termYears.text) ? _termYears.text : '10';

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.record == null ? 'Add' : 'Edit'} Agreement'),
        actions: [IconButton(
          tooltip: 'Manage Templates',
          icon: const Icon(Icons.library_books_outlined),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementTemplatesScreen())),
        )],
      ),
      body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: [
        FutureBuilder<List<Map<String, Object?>>>(
          future: _templateOptions,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator());
            }
            final allTemplates = snapshot.data ?? [];
            final types = allTemplates.map((t) => (t['agreement_type']?.toString().trim().isNotEmpty ?? false)
                ? t['agreement_type'].toString().trim() : 'General').toSet().toList()..sort();
            final selectedType = types.contains(_category.text) ? _category.text : null;
            final matchingTemplates = selectedType == null ? <Map<String, Object?>>[] : allTemplates.where((t) =>
              ((t['agreement_type']?.toString().trim().isNotEmpty ?? false) ? t['agreement_type'].toString().trim() : 'General') == selectedType).toList();
            final selectedTemplateExists = matchingTemplates.any((t) => t['id'] == _templateId);
            return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Agreement Type', border: OutlineInputBorder(), isDense: true),
                items: types.map((type) => DropdownMenuItem(value: type, child: Text(type, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (type) => setState(() {
                  _category.text = type ?? '';
                  _templateId = null;
                  _templateTitleSnapshot = '';
                  _templateBodySnapshot = '';
                }),
              )),
              const SizedBox(width: 10),
              Expanded(child: DropdownButtonFormField<int>(
                value: selectedTemplateExists ? _templateId : null,
                decoration: const InputDecoration(labelText: 'Agreement Template', border: OutlineInputBorder(), isDense: true),
                hint: Text(selectedType == null ? 'Select type first' : 'Select template'),
                items: matchingTemplates.map((t) => DropdownMenuItem<int>(value: t['id'] as int, child: Text(t['title'].toString(), overflow: TextOverflow.ellipsis))).toList(),
                onChanged: selectedType == null ? null : (id) {
                  if (id == null) return;
                  final selected = matchingTemplates.firstWhere((t) => t['id'] == id);
                  setState(() {
                    _templateId = id;
                    _templateTitleSnapshot = selected['title'].toString();
                    _templateBodySnapshot = selected['body'].toString();
                    _title.text = _templateTitleSnapshot;
                  });
                },
              )),
            ]));
          },
        ),
        if (_templateId == null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 28), child: Column(children: [
            Icon(Icons.description_outlined, size: 42, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            const Text('Select Agreement Type and Agreement Template to open its form.', textAlign: TextAlign.center),
          ]))
        else ...[
        _field(_title, 'Agreement Title', required: true),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: _field(_partyOne, 'First Party')),
            const SizedBox(width: 10),
            Expanded(child: _field(_partyTwo, 'Second Party')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _captureSignature(secondParty: false),
                icon: const Icon(Icons.draw_outlined),
                label: Text(_signatureData.isEmpty ? 'First Party Signature' : 'Update First Signature'),
              ),
              if (_signatureData.isNotEmpty)
                const Text('Signature captured.', style: TextStyle(fontSize: 12)),
            ])),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _captureSignature(secondParty: true),
                icon: const Icon(Icons.draw_outlined),
                label: Text(_signatureDataTwo.isEmpty ? 'Second Party Signature' : 'Update Second Signature'),
              ),
              if (_signatureDataTwo.isNotEmpty)
                const Text('Signature captured.', style: TextStyle(fontSize: 12)),
            ])),
          ]),
        ),
        _field(_address, 'Address', lines: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Builder(builder: (context) => FutureBuilder<List<Map<String, Object?>>>(
              future: MySpaceService.instance.getAgreementLabels(),
              builder: (context, snapshot) {
                final labels = snapshot.data ?? [];
                final exists = labels.any((e) => e['id'] == _selectedLabelId);
                return DropdownButtonFormField<int>(
                  value: exists ? _selectedLabelId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Label Name', hintText: 'Select Label', border: OutlineInputBorder(), isDense: true),
                  items: labels.map((e) => DropdownMenuItem<int>(
                    value: e['id'] as int,
                    child: Text('${e['name']} • ${e['company_name']}', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (id) {
                    final selected = labels.where((e) => e['id'] == id);
                    setState(() {
                      _selectedLabelId = id;
                      if (selected.isNotEmpty) _labelName.text = selected.first['name'].toString();
                    });
                  },
                );
              },
            ))),
            IconButton(tooltip: 'Manage Companies & Labels', onPressed: _manageLabels, icon: const Icon(Icons.add_business_outlined)),
            const SizedBox(width: 4),
            Expanded(child: DropdownButtonFormField<String>(
              value: designations.contains(_designation.text) ? _designation.text : null,
              decoration: const InputDecoration(labelText: 'Designation', border: OutlineInputBorder(), isDense: true),
              items: designations.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => _designation.text = v ?? 'Owner'),
            )),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: InkWell(
                onTap: _selectTerritories,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Territory',
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(
                    _territory.text.trim().isEmpty ? 'Worldwide' : _territory.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: selectedTerm,
                decoration: const InputDecoration(labelText: 'Agreement Term', border: OutlineInputBorder(), isDense: true),
                items: terms.map((v) => DropdownMenuItem(value: v, child: Text('$v Years'))).toList(),
                onChanged: (v) => setState(() => _termYears.text = v ?? '10'),
              ),
            ),
          ]),
        ),
        _field(_tracks, 'Track Details (one track per line)', lines: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _dateField(_signingDate, 'Signing Date')),
            const SizedBox(width: 10),
            Expanded(child: _dateField(_end, 'End / Expiry Date', optional: true)),
          ]),
        ),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Agreement Status (automatic)', border: OutlineInputBorder(), isDense: true),
          child: Text(_effectiveStatus, style: const TextStyle(fontWeight: FontWeight.w600)),
        )),
        if (widget.record != null && !_isTerminated)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: OutlinedButton.icon(
            onPressed: _saving ? null : _terminateAgreement,
            icon: const Icon(Icons.block_outlined), label: const Text('Terminate Agreement'),
          )),
        if (_isTerminated) ...[
          _dateField(_terminationDate, 'Termination Date'),
          _field(_terminationReason, 'Termination Reason (optional)', lines: 2),
        ],
        _field(_witnessName, 'Witness Name (optional)'),
        _field(_description, 'Additional Agreement Details / Terms', lines: 3),
        _field(_notes, 'Notes', lines: 2),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Edit Agreement Clauses'),
          subtitle: const Text('Template clauses are included automatically; expand to edit wording'),
          children: [
            TextFormField(
              key: ValueKey('clauses-$_templateId'),
              initialValue: _templateBodySnapshot,
              minLines: 8,
              maxLines: null,
              onChanged: (value) => _templateBodySnapshot = value,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                hintText: 'Edit the agreement clauses here',
              ),
            ),
          ],
        ),
        if (_selectedAttachments.isNotEmpty) ..._selectedAttachments.asMap().entries.map((entry) => ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(entry.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _selectedAttachments.removeAt(entry.key))),
        )),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _previewAgreement,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Preview'),
          )),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save'),
          )),
        ]),
        ],
      ])),
    );
  }
}

class _AgreementSignatureDialog extends StatefulWidget {
  const _AgreementSignatureDialog();

  @override
  State<_AgreementSignatureDialog> createState() => _AgreementSignatureDialogState();
}

class _AgreementSignatureDialogState extends State<_AgreementSignatureDialog> {
  final _key = GlobalKey();
  final List<Offset?> _points = [];

  Future<void> _finish() async {
    final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || _points.whereType<Offset>().isEmpty) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null || !mounted) return;
    Navigator.pop(context, base64Encode(bytes.buffer.asUint8List()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Draw Signature'),
    content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Sign inside the box using your finger or stylus.'),
      const SizedBox(height: 10),
      RepaintBoundary(key: _key, child: GestureDetector(
        onPanStart: (d) => setState(() => _points.add(d.localPosition)),
        onPanUpdate: (d) => setState(() => _points.add(d.localPosition)),
        onPanEnd: (_) => setState(() => _points.add(null)),
        child: Container(
          height: 170, width: double.infinity,
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey)),
          child: CustomPaint(painter: _AgreementSignaturePainter(_points)),
        ),
      )),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(
        onPressed: () => setState(_points.clear),
        icon: const Icon(Icons.refresh), label: const Text('Clear')),
      ),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _points.whereType<Offset>().isEmpty ? null : _finish,
        child: const Text('Use Signature')),
    ],
  );
}

class _AgreementSignaturePainter extends CustomPainter {
  const _AgreementSignaturePainter(this.points);
  final List<Offset?> points;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      if (a != null && b != null) canvas.drawLine(a, b, paint);
    }
  }
  @override
  bool shouldRepaint(covariant _AgreementSignaturePainter oldDelegate) => true;
}
