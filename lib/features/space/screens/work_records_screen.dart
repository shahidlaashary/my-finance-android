import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/features/space/services/my_space_service.dart';

class WorkRecordsScreen extends StatefulWidget {
  const WorkRecordsScreen({super.key, required this.section});
  final String section;

  @override
  State<WorkRecordsScreen> createState() => WorkRecordsScreenState();
}

class WorkRecordsScreenState extends State<WorkRecordsScreen> {
  Future<List<Map<String, Object?>>>? _records;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    _records = MySpaceService.instance.getWorkRecords(widget.section);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final agreements = widget.section == 'agreements';
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Unable to load ${agreements ? 'Agreements' : 'Projects'}: ${snapshot.error}'));
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(agreements ? Icons.handshake_outlined : Icons.work_outline_rounded,
                    size: 58, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 14),
                Text(agreements ? 'No agreements yet' : 'No projects yet',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 7),
                Text(agreements
                    ? 'Keep agreements, parties, dates and important terms together.'
                    : 'Organize project details, timelines and progress in one place.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            final subtitle = agreements
                ? [row['category'], row['party_one'], row['party_two'], row['status']]
                    .where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ')
                : [row['category'], row['status'], row['start_date'], row['end_date']]
                    .where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ');
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(agreements ? Icons.handshake_outlined : Icons.work_outline_rounded,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                title: Text(row['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(subtitle.isEmpty ? (row['description']?.toString() ?? '') : subtitle,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _showDetails(context, row, agreements),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => WorkRecordFormScreen(section: widget.section, record: row)));
                      refresh();
                    } else if (value == 'delete') {
                      final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                        title: const Text('Delete item?'),
                        content: Text('“${row['title']}” will be permanently removed.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ));
                      if (yes == true) {
                        await MySpaceService.instance.deleteWorkRecord(widget.section, row['id'] as int);
                        refresh();
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDetails(BuildContext context, Map<String, Object?> row, bool agreements) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(row['title']?.toString() ?? '', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              _detail('Type', row['category']),
              if (agreements) ...[
                _detail('First Party', row['party_one']),
                _detail('Second Party', row['party_two']),
              ],
              _detail('Status', row['status']),
              _detail('Start Date', row['start_date']),
              _detail('End Date', row['end_date']),
              _detail('Details', row['description']),
              _detail('Notes', row['notes']),
            ],
          )),
        ),
      ),
    );
  }

  Widget _detail(String label, Object? value) {
    final text = value?.toString() ?? '';
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 3),
        Text(text),
      ]),
    );
  }
}

class WorkRecordFormScreen extends StatefulWidget {
  const WorkRecordFormScreen({super.key, required this.section, this.record});
  final String section;
  final Map<String, Object?>? record;

  @override
  State<WorkRecordFormScreen> createState() => _WorkRecordFormScreenState();
}

class _WorkRecordFormScreenState extends State<WorkRecordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _partyOne;
  late final TextEditingController _partyTwo;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  late String _status;
  bool _saving = false;
  final List<Map<String, String>> _selectedAttachments = [];
  final ImagePicker _imagePicker = ImagePicker();

  bool get _agreements => widget.section == 'agreements';

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
    _status = r['status']?.toString() ?? (_agreements ? 'Draft' : 'Planning');
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _partyOne, _partyTwo, _start, _end, _description, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addSelectedAttachment(String path, String name) async {
    if (_selectedAttachments.any((item) => item['path'] == path)) return;
    if (!mounted) return;
    setState(() => _selectedAttachments.add({'path': path, 'name': name}));
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic',
          'doc', 'docx', 'xls', 'xlsx', 'txt', 'ppt', 'pptx',
        ],
      );
      if (result == null) return;
      for (final file in result.files) {
        if (file.path != null) await _addSelectedAttachment(file.path!, file.name);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File select nahi ho saki: $error')),
      );
    }
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 90);
      if (photo != null) await _addSelectedAttachment(photo.path, photo.name);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $error')),
      );
    }
  }

  Future<void> _chooseGallery() async {
    try {
      final photos = await _imagePicker.pickMultiImage(imageQuality: 90);
      for (final photo in photos) {
        await _addSelectedAttachment(photo.path, photo.name);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gallery error: $error')),
      );
    }
  }

  Widget _field(TextEditingController c, String label, {int lines = 1, bool required = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          maxLines: lines,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: label == 'Notes'
                ? PopupMenuButton<String>(
                    tooltip: 'Attach files',
                    icon: const Icon(Icons.attach_file_rounded),
                    onSelected: (value) {
                      if (value == 'files') _pickAttachments();
                      if (value == 'camera') _takePhoto();
                      if (value == 'gallery') _chooseGallery();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'files', child: Text('Browse Files')),
                      PopupMenuItem(value: 'camera', child: Text('Scan / Camera')),
                      PopupMenuItem(value: 'gallery', child: Text('Gallery')),
                    ],
                  )
                : null,
          ),
          validator: required ? (v) => v == null || v.trim().isEmpty ? 'Required' : null : null,
        ),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final recordId = await MySpaceService.instance.saveWorkRecord(widget.section, {
        'id': widget.record?['id'],
        'title': _title.text,
        'category': _category.text,
        'party_one': _partyOne.text,
        'party_two': _partyTwo.text,
        'status': _status,
        'start_date': _start.text,
        'end_date': _end.text,
        'description': _description.text,
        'notes': _notes.text,
      });
      var failedAttachments = 0;
      for (final file in _selectedAttachments) {
        try {
          await AttachmentService.addAttachment(
            ownerType: widget.section == 'agreements'
                ? AttachmentOwnerTypes.agreement
                : AttachmentOwnerTypes.project,
            ownerId: recordId,
            sourcePath: file['path']!,
            originalFileName: file['name'],
          );
        } catch (_) {
          failedAttachments++;
        }
      }
      if (mounted) {
        if (failedAttachments > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Record saved, but $failedAttachments file(s) could not be attached.')),
          );
        }
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _agreements
        ? ['Draft', 'Active', 'Expired', 'Terminated']
        : ['Planning', 'Active', 'On Hold', 'Completed'];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.record == null ? 'Add' : 'Edit'} ${_agreements ? 'Agreement' : 'Project'}')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _field(_title, _agreements ? 'Agreement Title' : 'Project Name', required: true),
          _field(_category, _agreements ? 'Agreement Type' : 'Project Category'),
          if (_agreements) ...[
            _field(_partyOne, 'First Party'),
            _field(_partyTwo, 'Second Party'),
          ],
          DropdownButtonFormField<String>(
            value: statuses.contains(_status) ? _status : statuses.first,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
            items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _status = v ?? statuses.first),
          ),
          const SizedBox(height: 12),
          _field(_start, 'Start Date'),
          _field(_end, _agreements ? 'End / Expiry Date (optional)' : 'Target End Date (optional)'),
          _field(_description, _agreements ? 'Agreement Details / Terms' : 'Project Description', lines: 4),
          _field(_notes, 'Notes', lines: 3),
          if (_selectedAttachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 0, bottom: 8),
              child: Column(
                children: _selectedAttachments.asMap().entries.map((entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(entry.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _selectedAttachments.removeAt(entry.key)),
                  ),
                )).toList(),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ]),
      ),
    );
  }
}
