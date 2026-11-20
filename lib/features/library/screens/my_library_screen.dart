import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/library/services/my_library_service.dart';
import 'package:open_filex/open_filex.dart';

class MyLibraryScreen extends StatefulWidget {
  const MyLibraryScreen({super.key});

  @override
  State<MyLibraryScreen> createState() => _MyLibraryScreenState();
}

class _MyLibraryScreenState extends State<MyLibraryScreen> {
  final _library = MyLibraryService.instance;
  late Future<List<Map<String, Object?>>> _items;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _items = _library.getItems();
  }

  Future<void> _addFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'epub', 'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final path = picked.path;
      if (path == null) throw Exception('The selected file could not be accessed.');
      await _library.addFile(File(path), picked.name);
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appText(context, 'Added to My Library', 'My Library میں شامل کر دیا گیا'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add file: $e')),
      );
    }
  }

  Future<void> _openItem(Map<String, Object?> item) async {
    final path = item['file_path'] as String;
    if (!await File(path).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This library file is missing.')),
      );
      return;
    }
    await OpenFilex.open(path);
  }

  Future<void> _deleteItem(Map<String, Object?> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from My Library?'),
        content: Text('“${item['title']}” will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    await _library.deleteItem(item);
    if (mounted) setState(_refresh);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context, 'My Library', 'میری لائبریری')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFile,
        icon: const Icon(Icons.add_rounded),
        label: Text(appText(context, 'Add Book / Music', 'کتاب / میوزک شامل کریں')),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load My Library: ${snapshot.error}'));
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_library_outlined, size: 64, color: colors.primary),
                    const SizedBox(height: 16),
                    Text('Your library is empty', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Add PDF or EPUB books and audio files. Added files are copied into My Finance app storage.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _addFile,
                      icon: const Icon(Icons.add),
                      label: const Text('Add your first file'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final isAudio = item['file_type'] == 'audio';
              final size = (item['file_size'] as int) / (1024 * 1024);
              return Card(
                child: ListTile(
                  onTap: () => _openItem(item),
                  leading: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(isAudio ? Icons.headphones_rounded : Icons.menu_book_rounded, color: colors.onPrimaryContainer),
                  ),
                  title: Text(item['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${isAudio ? 'Audio' : 'Book'} • ${size.toStringAsFixed(1)} MB'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'open') _openItem(item);
                      if (value == 'delete') _deleteItem(item);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('Open')),
                      PopupMenuItem(value: 'delete', child: Text('Remove')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
