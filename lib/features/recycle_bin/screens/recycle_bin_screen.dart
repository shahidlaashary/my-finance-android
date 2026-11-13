import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});
  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String tr(String s) => appText(context, s, s);
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final rows = await RecycleBinService.getItems();
      if (mounted) setState(() { _items = rows; _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); _message(e.toString()); }
  }
  void _message(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  Future<void> _restore(Map<String, dynamic> item) async {
    try { await RecycleBinService.restore(item['id'] as int); await _load(); _message(tr('Item restored successfully.')); }
    catch (e) { _message(e.toString()); }
  }
  Future<void> _delete(Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(tr('Delete permanently?')),
      content: Text(tr('This item cannot be recovered after permanent deletion.')),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Delete permanently')))],
    ));
    if (yes != true) return;
    await RecycleBinService.permanentlyDelete(item['id'] as int);
    await _load();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Recycle Bin'))),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _items.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.delete_outline_rounded, size: 58, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 12), Text(tr('Recycle Bin is empty'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6), Text(tr('Deleted items will appear here when moved to the Recycle Bin.'), textAlign: TextAlign.center),
      ])))
      : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _items.length, itemBuilder: (context, i) {
        final item = _items[i];
        final date = DateTime.tryParse(item['deleted_at']?.toString() ?? '');
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.delete_outline)),
          title: Text(item['entity_title']?.toString() ?? tr('Deleted item'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${tr(item['entity_type']?.toString() ?? 'Item')} • ${date == null ? '' : DateFormat.yMMMd().add_jm().format(date)}'),
          trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'restore') _restore(item); if (v == 'delete') _delete(item); },
            itemBuilder: (_) => [PopupMenuItem(value: 'restore', child: Text(tr('Restore'))), PopupMenuItem(value: 'delete', child: Text(tr('Delete permanently')))]),
        ));
      }),
  );
}
