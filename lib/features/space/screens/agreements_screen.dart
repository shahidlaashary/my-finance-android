import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/features/space/services/my_space_service.dart';
import 'package:my_finance/features/space/services/agreement_template_service.dart';
import 'package:my_finance/features/space/services/agreement_pdf_service.dart';
import 'package:my_finance/features/space/screens/agreement_templates_screen.dart';

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
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ));
        },
      );
    },
  );

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
              'Status': 'status', 'Start Date': 'start_date', 'End Date': 'end_date',
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
  late final TextEditingController _title, _category, _partyOne, _partyTwo, _start, _end, _description, _notes;
  late String _status;
  bool _saving = false;
  int? _templateId;
  String _templateTitleSnapshot = '';
  String _templateBodySnapshot = '';
  late Future<List<Map<String, Object?>>> _templateOptions;
  late final TextEditingController _labelName, _address, _territory, _termYears, _tracks, _designation, _agreementDate, _witnessName;
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
    _start = TextEditingController(text: r['start_date']?.toString() ?? '');
    _end = TextEditingController(text: r['end_date']?.toString() ?? '');
    _description = TextEditingController(text: r['description']?.toString() ?? '');
    _notes = TextEditingController(text: r['notes']?.toString() ?? '');
    _status = r['status']?.toString() ?? 'Draft';
    _templateId = r['template_id'] as int?;
    _templateTitleSnapshot = r['template_title_snapshot']?.toString() ?? '';
    _templateBodySnapshot = r['template_body_snapshot']?.toString() ?? '';
    _labelName = TextEditingController(text: r['label_name']?.toString() ?? '');
    _address = TextEditingController(text: r['address']?.toString() ?? '');
    _territory = TextEditingController(text: r['territory']?.toString() ?? 'Worldwide');
    _termYears = TextEditingController(text: r['term_years']?.toString() ?? '10');
    _tracks = TextEditingController(text: r['track_details']?.toString() ?? '');
    _designation = TextEditingController(text: r['designation']?.toString() ?? '');
    _agreementDate = TextEditingController(text: r['agreement_date']?.toString() ?? '');
    _witnessName = TextEditingController(text: r['witness_name']?.toString() ?? '');
    _templateOptions = AgreementTemplateService.instance.getTemplates();
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _partyOne, _partyTwo, _start, _end, _description, _notes,
      _labelName, _address, _territory, _termYears, _tracks, _designation, _agreementDate, _witnessName]) { c.dispose(); }
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await MySpaceService.instance.saveAgreement({
        'id': widget.record?['id'], 'title': _title.text, 'category': _category.text,
        'party_one': _partyOne.text, 'party_two': _partyTwo.text, 'status': _status,
        'start_date': _start.text, 'end_date': _end.text,
        'description': _description.text, 'notes': _notes.text,
        'template_id': _templateId,
        'template_title_snapshot': _templateTitleSnapshot,
        'template_body_snapshot': _templateBodySnapshot,
        'label_name': _labelName.text, 'address': _address.text,
        'territory': _territory.text, 'term_years': _termYears.text,
        'track_details': _tracks.text, 'designation': _designation.text,
        'agreement_date': _agreementDate.text, 'witness_name': _witnessName.text,
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

  @override
  Widget build(BuildContext context) {
    const statuses = ['Draft', 'Active', 'Expired', 'Terminated'];
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
            final templates = snapshot.data ?? [];
            if (templates.isEmpty) return const SizedBox.shrink();
            if (_templateId == null && _templateBodySnapshot.isEmpty) {
              final first = templates.first;
              _templateId = first['id'] as int;
              _templateTitleSnapshot = first['title'].toString();
              _templateBodySnapshot = first['body'].toString();
              if (_title.text.isEmpty) _title.text = _templateTitleSnapshot;
            }
            return Padding(padding: const EdgeInsets.only(bottom: 12), child: DropdownButtonFormField<int>(
              value: templates.any((t) => t['id'] == _templateId) ? _templateId : null,
              decoration: const InputDecoration(labelText: 'Agreement Template', border: OutlineInputBorder(), isDense: true),
              items: templates.map((t) => DropdownMenuItem<int>(value: t['id'] as int, child: Text(t['title'].toString()))).toList(),
              onChanged: (id) {
                final selected = templates.firstWhere((t) => t['id'] == id);
                setState(() {
                  _templateId = id;
                  _templateTitleSnapshot = selected['title'].toString();
                  _templateBodySnapshot = selected['body'].toString();
                  if (_title.text.isEmpty || _title.text == 'Music Rights Agreement') _title.text = _templateTitleSnapshot;
                });
              },
            ));
          },
        ),
        _field(_title, 'Agreement Title', required: true),
        _field(_category, 'Agreement Type'),
        _field(_partyOne, 'First Party'),
        _field(_partyTwo, 'Second Party / Label'),
        _field(_labelName, 'Label Name'),
        _field(_address, 'Artist / First Party Address', lines: 2),
        _field(_territory, 'Territory'),
        _field(_termYears, 'Agreement Term (Years)'),
        _field(_tracks, 'Track Details (one track per line)', lines: 4),
        _field(_designation, 'Designation'),
        _field(_agreementDate, 'Agreement Date'),
        DropdownButtonFormField<String>(
          value: statuses.contains(_status) ? _status : statuses.first,
          decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
          items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: (v) => setState(() => _status = v ?? statuses.first),
        ),
        const SizedBox(height: 12),
        _field(_start, 'Start Date'),
        _field(_end, 'End / Expiry Date (optional)'),
        _field(_witnessName, 'Witness Name'),
        _field(_description, 'Additional Agreement Details / Terms', lines: 4),
        _field(_notes, 'Notes', lines: 3),
        if (_selectedAttachments.isNotEmpty) ..._selectedAttachments.asMap().entries.map((entry) => ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(entry.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _selectedAttachments.removeAt(entry.key))),
        )),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ])),
    );
  }
}
