import 'package:flutter/material.dart';
import '../application/services/studio_catalogue_rights_service.dart';

class StudioCatalogueRightsScreen extends StatefulWidget {
  const StudioCatalogueRightsScreen({super.key, required this.section});
  final String section;

  @override
  State<StudioCatalogueRightsScreen> createState() => _StudioCatalogueRightsScreenState();
}

class _StudioCatalogueRightsScreenState extends State<StudioCatalogueRightsScreen> {
  final _service = StudioCatalogueRightsService();
  bool _loading = true;
  List<Map<String, Object?>> _items = [];
  String? _error;

  bool get _rights => widget.section == 'Rights Management';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = _rights ? await _service.holders() : await _service.tracks();
      if (!mounted) return;
      setState(() { _items = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _add() async {
    final nameController = TextEditingController();
    final typeController = TextEditingController(text: 'individual');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_rights ? 'Add rights holder' : 'Add catalogue track'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameController, autofocus: true,
            decoration: InputDecoration(labelText: _rights ? 'Holder name' : 'Track title')),
          if (_rights) TextField(controller: typeController,
            decoration: const InputDecoration(labelText: 'Holder type (individual/business)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    final name = nameController.text.trim();
    final holderType = typeController.text.trim();
    nameController.dispose();
    typeController.dispose();
    if (ok != true || name.isEmpty) return;
    try {
      if (_rights) {
        await _service.addHolder(name: name, type: holderType.isEmpty ? 'individual' : holderType);
      } else {
        await _service.addTrack(name);
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.section)),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!)))
          : RefreshIndicator(
              onRefresh: _reload,
              child: _items.isEmpty
                ? ListView(children: const [SizedBox(height: 200), Center(child: Text('No records yet. Tap + to add.'))])
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final row = _items[i];
                      final title = _rights ? (row['name'] ?? '') : (row['title'] ?? '');
                      final subtitle = _rights ? (row['holder_type'] ?? '') : (row['id'] ?? '');
                      return ListTile(title: Text(title.toString()), subtitle: Text(subtitle.toString()));
                    },
                  ),
            ),
    );
  }
}
