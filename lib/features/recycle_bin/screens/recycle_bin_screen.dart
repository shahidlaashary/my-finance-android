import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/recycle_bin/services/recycle_bin_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';
import 'dart:convert';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});
  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  Timer? _countdownTimer;
  String tr(String s) => appText(context, s, s);
  @override
  void initState() {
    super.initState();
    _load();
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }
  @override
  void dispose() { _countdownTimer?.cancel(); super.dispose(); }
  String _remaining(Map<String, dynamic> item) {
    final deletedAt = DateTime.tryParse(item['deleted_at']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(item['expires_at']?.toString() ?? '') ??
        (deletedAt?.add(const Duration(days: RecycleBinService.retentionDays)));
    if (expiresAt == null) return tr('Expiry unavailable');
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) return tr('Expires soon');
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    if (days > 0) return '$days ${tr('days')} $hours ${tr('hours')} ${tr('remaining')}';
    if (hours > 0) return '$hours ${tr('hours')} $minutes ${tr('minutes')} ${tr('remaining')}';
    return '$minutes ${tr('minutes')} ${tr('remaining')}';
  }
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
    try {
      await RecycleBinService.permanentlyDelete(item['id'] as int);
      await _load();
    } catch (e) {
      _message(e.toString());
    }
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
      : RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _items.length,
          itemBuilder: (context, i) {
            final item = _items[i];
            final date = DateTime.tryParse(item['deleted_at']?.toString() ?? '');
            final color = item['source_table'] == 'transactions' ? const Color(0xFF3979C6) : const Color(0xFF147D59);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE8EEE9)), boxShadow: [BoxShadow(color: const Color(0xFF183D2D).withValues(alpha: 0.035), blurRadius: 12, offset: const Offset(0, 3))]),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecycleBinDetailScreen(item: item))),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 5, 11),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(13)), child: Icon(Icons.delete_outline_rounded, color: color)),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item['entity_title']?.toString() ?? tr('Deleted item'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(tr(item['entity_type']?.toString() ?? 'Item'), style: const TextStyle(fontSize: 11.5, color: Color(0xFF7B8781))),
                      const SizedBox(height: 4),
                      Text(date == null ? tr('Unknown date') : DateFormat('dd MMM yyyy  •  hh:mm a').format(date), style: const TextStyle(fontSize: 10.5, color: Color(0xFF9AA49F))),
                      const SizedBox(height: 4),
                      Text('${tr('Auto-delete in')}: ${_remaining(item)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Color(0xFFD18A32), fontWeight: FontWeight.w600)),
                    ])),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_horiz, color: Color(0xFF89958E)),
                      onSelected: (v) { if (v == 'restore') _restore(item); if (v == 'delete') _delete(item); },
                      itemBuilder: (_) => [PopupMenuItem(value: 'restore', child: Text(tr('Restore'))), PopupMenuItem(value: 'delete', child: Text(tr('Delete permanently')))],
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA49F)),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
  );
}


class RecycleBinDetailScreen extends StatelessWidget {
  const RecycleBinDetailScreen({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final tr = (String s) => appText(context, s, s);
    Map<String, dynamic> record = {};
    try { record = Map<String, dynamic>.from(jsonDecode(item['payload']?.toString() ?? '{}') as Map); } catch (_) {}
    const owners = {'transactions':'transaction','assets':'asset','loans':'loan','goals':'goal','loan_repayments':'repayment','my_documents_records':'document'};
    final owner = owners[item['source_table']];
    final sourceId = int.tryParse(item['source_id']?.toString() ?? '');
    final deleted = DateTime.tryParse(item['deleted_at']?.toString() ?? '');
    final expiry = DateTime.tryParse(item['expires_at']?.toString() ?? '');
    String label(String s) => s.split('_').map((p) => p.isEmpty ? p : p[0].toUpperCase()+p.substring(1)).join(' ');
    String val(dynamic v) => v == null ? '—' : v is String && v.isEmpty ? '—' : v is Map || v is List ? jsonEncode(v) : v.toString();
    final fields = record.entries.where((e) => !e.key.startsWith('_') && e.key != 'id' && e.value != null).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Deleted Item Details'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF3979C6).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF3979C6).withValues(alpha: 0.2))), child: Column(children: [
          const CircleAvatar(radius: 25, backgroundColor: Color(0x1F3979C6), child: Icon(Icons.delete_outline_rounded, color: Color(0xFF3979C6))),
          const SizedBox(height: 10),
          Text(item['entity_title']?.toString() ?? tr('Deleted item'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(tr(item['entity_type']?.toString() ?? 'Item'), style: const TextStyle(color: Color(0xFF718078))),
        ])),
        const SizedBox(height: 16),
        _section(context, tr('Deletion Information'), [
          _row(tr('Deleted'), deleted == null ? '—' : DateFormat('dd MMM yyyy, hh:mm a').format(deleted)),
          _row(tr('Auto-delete date'), expiry == null ? '—' : DateFormat('dd MMM yyyy, hh:mm a').format(expiry)),
          _row(tr('Record ID'), item['source_id']?.toString() ?? '—'),
        ]),
        const SizedBox(height: 16),
        _section(context, tr('Original Details'), fields.isEmpty ? [_row(tr('Details'), tr('No additional details available'))] : fields.map((e) => _row(label(e.key), val(e.value))).toList()),
        if (owner != null && sourceId != null) ...[
          const SizedBox(height: 16),
          _section(context, tr('Attachments'), [AttachmentSection(ownerType: owner, ownerId: sourceId)]),
        ],
      ]),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE8EEE9))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)), const SizedBox(height: 9), ...children]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 4, child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7B8781)))),
      const SizedBox(width: 10),
      Expanded(flex: 6, child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
    ]),
  );
}
