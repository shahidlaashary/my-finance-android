import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_finance/modules/space/services/my_space_service.dart';

class SpaceToolsScreen extends StatefulWidget {
  const SpaceToolsScreen({super.key});

  @override
  State<SpaceToolsScreen> createState() => _SpaceToolsScreenState();
}

class _SpaceToolsScreenState extends State<SpaceToolsScreen> {
  final _space = MySpaceService.instance;
  Future<List<Map<String, Object?>>>? _playlists;
  Future<List<Map<String, Object?>>>? _collections;
  Future<Map<String, Object>>? _storage;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _playlists = _space.getPlaylists();
    _collections = _space.getCollections();
    _storage = _space.getStorageInformation();
  }

  Future<String?> _askName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, maxLength: 60,
          decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> _createPlaylist() async {
    final name = await _askName('New playlist');
    if (name == null) return;
    try {
      await _space.createPlaylist(name);
      if (mounted) setState(_refresh);
    } catch (e) {
      _message('Could not create playlist: $e');
    }
  }

  Future<void> _createFolder() async {
    final name = await _askName('New folder / collection');
    if (name == null) return;
    try {
      await _space.createCollection(name);
      if (mounted) setState(_refresh);
    } catch (e) {
      _message('Could not create folder: $e');
    }
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatBytes(Object? value) {
    final bytes = (value as num?)?.toDouble() ?? 0;
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<Map<String, dynamic>?> _deviceStorage() async {
    if (!Platform.isAndroid) return null;
    try {
      return await const MethodChannel('my_finance/sound').invokeMapMethod<String, dynamic>('getStorageInfo');
    } catch (_) {
      return null;
    }
  }

  Future<void> _addAudioToPlaylist(int playlistId) async {
    final items = await _space.getItems(fileType: 'audio');
    if (!mounted) return;
    if (items.isEmpty) {
      _message('Add audio files to My Space first.');
      return;
    }
    final selected = <int>{};
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add audio to playlist'),
        content: SizedBox(width: double.maxFinite, height: 340,
          child: ListView(children: items.map((item) {
            final id = item['id'] as int;
            return CheckboxListTile(
              value: selected.contains(id),
              title: Text(item['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
              onChanged: (value) => setDialogState(() {
                if (value == true) { selected.add(id); } else { selected.remove(id); }
              }),
            );
          }).toList()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Add (${selected.length})')),
        ],
      )),
    );
    if (result == true) {
      for (final id in selected) {
        await _space.addItemToPlaylist(playlistId, id);
      }
      _message('${selected.length} audio item(s) added.');
    }
  }

  Widget _playlistsTab() => FutureBuilder<List<Map<String, Object?>>>(
    future: _playlists,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text('Unable to load playlists: ${snapshot.error}'));
      final items = snapshot.data ?? [];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(onPressed: _createPlaylist, icon: const Icon(Icons.playlist_add), label: const Text('Create playlist')),
          const SizedBox(height: 12),
          if (items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No playlists yet. Create one to organize your audio.')),
          ...items.map((item) {
            final id = item['id'] as int;
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.queue_music)),
              title: Text(item['name'] as String),
              subtitle: const Text('Audio playlist'),
              onTap: () => _addAudioToPlaylist(id),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'add') await _addAudioToPlaylist(id);
                  if (value == 'delete') {
                    await _space.deletePlaylist(id);
                    if (mounted) setState(_refresh);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('Add audio')),
                  PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                ],
              ),
            ));
          }),
        ],
      );
    },
  );

  Widget _foldersTab() => FutureBuilder<List<Map<String, Object?>>>(
    future: _collections,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text('Unable to load folders: ${snapshot.error}'));
      final folders = snapshot.data ?? [];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(onPressed: _createFolder, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('Create folder / collection')),
          const SizedBox(height: 12),
          if (folders.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No folders yet. Create folders to organize your books and audio.')),
          ...folders.map((folder) {
            final id = folder['id'] as int;
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
              title: Text(folder['name'] as String),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'rename') {
                    final name = await _askName('Rename folder', initial: folder['name'] as String);
                    if (name != null) await _space.renameCollection(id, name);
                  } else if (value == 'delete') {
                    await _space.deleteCollection(id);
                  }
                  if (mounted) setState(_refresh);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete folder')),
                ],
              ),
            ));
          }),
          const Padding(padding: EdgeInsets.only(top: 12), child: Text('Folder assignment and moving files can be added from each space item menu in the next UI pass.')),
        ],
      );
    },
  );

  Widget _storageTab() => FutureBuilder<Map<String, Object>>(
    future: _storage,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text('Unable to calculate Space storage: ${snapshot.error}'));
      final data = snapshot.data ?? {};
      return FutureBuilder<Map<String, dynamic>?>(
        future: _deviceStorage(),
        builder: (context, device) {
          final total = data['total_count'] ?? 0;
          final books = data['book_count'] ?? 0;
          final audio = data['audio_count'] ?? 0;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('My Space storage', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_formatBytes(data['total_bytes']), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 14),
              _statRow('Total files', '$total'),
              _statRow('Books (PDF / EPUB)', '$books'),
              _statRow('Audio files', '$audio'),
            ]))),
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Device storage', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (device.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator()
              else if (device.data == null)
                const Text('Device storage details are unavailable on this platform. Space storage is still measured accurately.'),
              if (device.data != null) ...[
                _statRow('Free space', _formatBytes(device.data!['freeBytes'])),
                _statRow('Total capacity', _formatBytes(device.data!['totalBytes'])),
              ],
            ]))),
            const SizedBox(height: 8),
            TextButton.icon(onPressed: () => setState(_refresh), icon: const Icon(Icons.refresh), label: const Text('Refresh storage')),
          ]);
        },
      );
    },
  );

  Widget _statRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(title: const Text('Space Tools'), bottom: const TabBar(tabs: [
        Tab(text: 'Playlists', icon: Icon(Icons.queue_music)),
        Tab(text: 'Folders', icon: Icon(Icons.folder_outlined)),
        Tab(text: 'Storage', icon: Icon(Icons.storage)),
      ])),
      body: TabBarView(children: [_playlistsTab(), _foldersTab(), _storageTab()]),
    ),
  );
}
