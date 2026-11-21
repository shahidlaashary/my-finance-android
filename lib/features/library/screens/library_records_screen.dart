import 'package:flutter/material.dart';
import 'package:my_finance/features/library/services/my_library_service.dart';

class SpaceRecordsScreen extends StatefulWidget {
  const SpaceRecordsScreen({super.key, required this.section});
  final String section;

  @override
  State<SpaceRecordsScreen> createState() => SpaceRecordsScreenState();
}

class SpaceRecordsScreenState extends State<SpaceRecordsScreen> {
  Future<List<Map<String, Object?>>>? _records;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    _records = MyLibraryService.instance.getSectionRecords(widget.section);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final deals = widget.section == 'deals';
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Unable to load ${deals ? 'Deals' : 'Projects'}: ${snapshot.error}'));
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(deals ? Icons.handshake_outlined : Icons.work_outline_rounded,
                    size: 58, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 14),
                Text(deals ? 'No deals yet' : 'No projects yet',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 7),
                Text(deals
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
            final subtitle = deals
                ? [row['category'], row['party_one'], row['party_two'], row['status']]
                    .where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ')
                : [row['category'], row['status'], row['start_date'], row['end_date']]
                    .where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ');
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(deals ? Icons.handshake_outlined : Icons.work_outline_rounded,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                title: Text(row['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(subtitle.isEmpty ? (row['description']?.toString() ?? '') : subtitle,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _showDetails(context, row, deals),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => SpaceRecordFormScreen(section: widget.section, record: row)));
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
                        await MyLibraryService.instance.deleteSectionRecord(widget.section, row['id'] as int);
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

  void _showDetails(BuildContext context, Map<String, Object?> row, bool deals) {
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
              if (deals) ...[
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

class SpaceRecordFormScreen extends StatefulWidget {
  const SpaceRecordFormScreen({super.key, required this.section, this.record});
  final String section;
  final Map<String, Object?>? record;

  @override
  State<SpaceRecordFormScreen> createState() => _SpaceRecordFormScreenState();
}

class _SpaceRecordFormScreenState extends State<SpaceRecordFormScreen> {
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

  bool get _deals => widget.section == 'deals';

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
    _status = r['status']?.toString() ?? (_deals ? 'Draft' : 'Planning');
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _partyOne, _partyTwo, _start, _end, _description, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController c, String label, {int lines = 1, bool required = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          validator: required ? (v) => v == null || v.trim().isEmpty ? 'Required' : null : null,
        ),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await MyLibraryService.instance.saveSectionRecord(widget.section, {
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
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _deals
        ? ['Draft', 'Active', 'Expired', 'Terminated']
        : ['Planning', 'Active', 'On Hold', 'Completed'];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.record == null ? 'Add' : 'Edit'} ${_deals ? 'Deal' : 'Project'}')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _field(_title, _deals ? 'Agreement Title' : 'Project Name', required: true),
          _field(_category, _deals ? 'Agreement Type' : 'Project Category'),
          if (_deals) ...[
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
          _field(_end, _deals ? 'End / Expiry Date (optional)' : 'Target End Date (optional)'),
          _field(_description, _deals ? 'Agreement Details / Terms' : 'Project Description', lines: 4),
          _field(_notes, 'Notes', lines: 3),
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
