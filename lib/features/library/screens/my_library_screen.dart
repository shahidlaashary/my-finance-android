import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/library/screens/library_audio_player_screen.dart';
import 'package:my_finance/features/library/screens/library_pdf_reader_screen.dart';
import 'package:my_finance/features/library/screens/library_tools_screen.dart';
import 'package:my_finance/features/library/services/my_library_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

class MyLibraryScreen extends StatefulWidget {
  const MyLibraryScreen({super.key});

  @override
  State<MyLibraryScreen> createState() => _MyLibraryScreenState();
}

class _MyLibraryScreenState extends State<MyLibraryScreen> {
  final _library = MyLibraryService.instance;
  late Future<List<Map<String, Object?>>> _allItems;
  late Future<List<Map<String, Object?>>> _bookItems;
  late Future<List<Map<String, Object?>>> _audioItems;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _allItems = _library.getItems();
    _bookItems = _library.getItems(fileType: 'book');
    _audioItems = _library.getItems(fileType: 'audio');
  }

  Future<void> _addFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        withData: false,
        allowedExtensions: ['pdf', 'epub', 'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
      );
      if (result == null || result.files.isEmpty) return;
      var added = 0;
      final failures = <String>[];
      for (final picked in result.files) {
        final path = picked.path;
        if (path == null) { failures.add(picked.name); continue; }
        try { await _library.addFile(File(path), picked.name); added++; }
        catch (_) { failures.add(picked.name); }
      }
      if (!mounted) return;
      setState(_refresh);
      final message = failures.isEmpty ? '$added file(s) imported successfully.' : '$added imported; ' + failures.length.toString() + ' failed: ' + failures.take(3).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to add file: $e')));
    }
  }

  Future<void> _openItem(Map<String, Object?> item) async {
    final path = item['file_path'] as String;
    if (!await File(path).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This library file is missing.')));
      return;
    }

    final extension = p.extension(path).toLowerCase();
    if (item['file_type'] == 'audio') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryAudioPlayerScreen(item: item)));
    } else if (extension == '.pdf') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryPdfReaderScreen(item: item)));
    } else {
      // EPUB currently opens with a compatible reader installed on the device.
      await OpenFilex.open(path);
    }
    if (mounted) setState(_refresh);
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
    try {
      await _library.deleteItem(item);
      if (mounted) setState(_refresh);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to remove file: $e')));
    }
  }

  Widget _buildItems(Future<List<Map<String, Object?>>> future, String emptyTitle, String emptyMessage) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Unable to load My Library: ${snapshot.error}')));
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
                  Text(emptyTitle, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(emptyMessage, textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 18),
                  FilledButton.icon(onPressed: _addFile, icon: const Icon(Icons.add), label: const Text('Add file')),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final isAudio = item['file_type'] == 'audio';
            final size = (item['file_size'] as int) / (1024 * 1024);
            final progress = isAudio
                ? ((item['last_position_ms'] as int? ?? 0) > 0 ? ' • Resume available' : '')
                : ((item['last_page'] as int? ?? 1) > 1 ? ' • Page ${item['last_page']}' : '');
            return Card(
              child: ListTile(
                onTap: () => _openItem(item),
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: Icon(isAudio ? Icons.headphones_rounded : Icons.menu_book_rounded, color: colors.onPrimaryContainer),
                ),
                title: Text(item['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${isAudio ? 'Audio' : 'Book'} • ${size.toStringAsFixed(1)} MB$progress', maxLines: 2),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(appText(context, 'My Library', 'میری لائبریری')),
          actions: [IconButton(tooltip: 'Playlists, folders and storage', icon: const Icon(Icons.tune_rounded), onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryToolsScreen())); if (mounted) setState(_refresh); })],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'All', icon: Icon(Icons.library_books_outlined)),
              Tab(text: 'Books', icon: Icon(Icons.menu_book_outlined)),
              Tab(text: 'Music', icon: Icon(Icons.headphones_outlined)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addFile,
          icon: const Icon(Icons.add_rounded),
          label: Text(appText(context, 'Add Book / Music', 'کتاب / میوزک شامل کریں')),
        ),
        body: TabBarView(
          children: [
            _buildItems(_allItems, 'Your library is empty', 'Add PDF or EPUB books and audio files. Added files are copied into My Finance app storage.'),
            _buildItems(_bookItems, 'No books yet', 'Add PDF or EPUB books to your library.'),
            _buildItems(_audioItems, 'No music yet', 'Add audio files to your library.'),
          ],
        ),
      ),
    );
  }
}
