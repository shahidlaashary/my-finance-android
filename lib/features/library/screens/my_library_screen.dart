import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/library/screens/library_audio_player_screen.dart';
import 'package:my_finance/features/library/screens/library_pdf_reader_screen.dart';
import 'package:my_finance/features/library/screens/library_tools_screen.dart';
import 'package:my_finance/features/library/screens/library_video_player_screen.dart';
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
  late Future<List<Map<String, Object?>>> _photoItems;
  late Future<List<Map<String, Object?>>> _videoItems;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _allItems = _library.getItems();
    _bookItems = _library.getItems(fileType: 'book');
    _audioItems = _library.getItems(fileType: 'audio');
    _photoItems = _library.getItems(fileType: 'photo');
    _videoItems = _library.getItems(fileType: 'video');
  }

  Future<void> _openLibrarySearch() async {
    await showSearch<Map<String, Object?>?>(
      context: context,
      delegate: _LibrarySearchDelegate(
        library: _library,
        onOpen: _openItem,
      ),
    );
  }

  Future<void> _addFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        withData: false,
        allowedExtensions: ['pdf', 'epub', 'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac', 'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'mp4', 'm4v', 'mov', 'mkv', 'avi', 'webm', '3gp'],
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
    } else if (item['file_type'] == 'video') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryVideoPlayerScreen(item: item)));
    } else if (item['file_type'] == 'photo') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
        appBar: AppBar(title: Text(item['title'] as String)),
        body: Center(child: InteractiveViewer(minScale: 0.5, maxScale: 5, child: Image.file(File(path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('Unable to display this photo.')))),
      )));
    } else if (extension == '.pdf') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryPdfReaderScreen(item: item)));
    } else {
      // EPUB currently opens with a compatible reader installed on the device.
      await OpenFilex.open(path);
    }
    if (mounted) setState(_refresh);
  }

  Future<void> _moveItemToFolder(Map<String, Object?> item) async {
    final folders = await _library.getCollections();
    if (!mounted) return;
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a folder first in Library Tools.')));
      return;
    }
    final current = item['collection_id'] as int?;
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to folder'),
        children: folders.map((folder) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, folder['id'] as int),
          child: Row(children: [
            const Icon(Icons.folder_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(folder['name'] as String)),
            if (current == folder['id']) const Icon(Icons.check, color: Colors.green),
          ]),
        )).toList(),
      ),
    );
    if (selected == null) return;
    await _library.moveItemToCollection(item['id'] as int, selected);
    if (mounted) {
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File moved to folder.')));
    }
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
            final type = item['file_type'] as String;
            final isAudio = type == 'audio';
            final isPhoto = type == 'photo';
            final isVideo = type == 'video';
            final size = (item['file_size'] as int) / (1024 * 1024);
            final progress = isAudio
                ? ((item['last_position_ms'] as int? ?? 0) > 0 ? ' • Resume available' : '')
                : type == 'book' ? ((item['last_page'] as int? ?? 1) > 1 ? ' • Page ${item['last_page']}' : '') : '';
            return Card(
              child: ListTile(
                onTap: () => _openItem(item),
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: isPhoto
                      ? ClipOval(child: Image.file(File(item['file_path'] as String), width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: colors.onPrimaryContainer)))
                      : Icon(isAudio ? Icons.headphones_rounded : isVideo ? Icons.video_library_outlined : Icons.menu_book_rounded, color: colors.onPrimaryContainer),
                ),
                title: Text(item['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${isAudio ? 'Music' : isPhoto ? 'Photo' : isVideo ? 'Video' : 'Book'} • ${size.toStringAsFixed(1)} MB$progress', maxLines: 2),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'open') _openItem(item);
                    if (value == 'delete') _deleteItem(item);
                    if (value == 'folder') _moveItemToFolder(item);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'open', child: Text('Open')),
                    PopupMenuItem(value: 'folder', child: Text('Move to folder')),
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
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(appText(context, 'My Library', 'میری لائبریری')),
          actions: [
          IconButton(
            tooltip: 'Search My Library',
            icon: const Icon(Icons.search_rounded),
            onPressed: _openLibrarySearch,
          ),
          IconButton(tooltip: 'Playlists, folders and storage', icon: const Icon(Icons.tune_rounded), onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryToolsScreen())); if (mounted) setState(_refresh); }),
        ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addFile,
          icon: const Icon(Icons.add_rounded),
          label: Text(appText(context, 'Add Media', 'میڈیا شامل کریں')),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.055),
                blurRadius: 14,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 66,
              child: TabBar(
                indicatorColor: Colors.transparent,
                dividerColor: Colors.transparent,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).hintColor,
                labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                tabs: const [
                  Tab(icon: Icon(Icons.library_books_outlined, size: 22), text: 'All'),
                  Tab(icon: Icon(Icons.menu_book_outlined, size: 22), text: 'Books'),
                  Tab(icon: Icon(Icons.headphones_outlined, size: 22), text: 'Music'),
                  Tab(icon: Icon(Icons.photo_outlined, size: 22), text: 'Photos'),
                  Tab(icon: Icon(Icons.video_library_outlined, size: 22), text: 'Videos'),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildItems(_allItems, 'Your library is empty', 'Add books, music, photos and videos. Added files are copied into My Finance app storage.'),
            _buildItems(_bookItems, 'No books yet', 'Add PDF or EPUB books to your library.'),
            _buildItems(_audioItems, 'No music yet', 'Add audio files to your library.'),
            _buildItems(_photoItems, 'No photos yet', 'Add JPG, PNG, WEBP, GIF or BMP photos.'),
            _buildItems(_videoItems, 'No videos yet', 'Add MP4, MOV, MKV, AVI or WEBM videos.'),
          ],
        ),
      ),
    );
  }

class _LibrarySearchDelegate extends SearchDelegate<Map<String, Object?>?> {
  _LibrarySearchDelegate({required this.library, required this.onOpen});

  final MyLibraryService library;
  final Future<void> Function(Map<String, Object?> item) onOpen;

  @override
  String get searchFieldLabel => 'Search books, music, photos, videos';

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear_rounded), tooltip: 'Clear search', onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back_rounded),
    tooltip: 'Close search',
    onPressed: () => close(context, null),
  );

  Future<List<Map<String, Object?>>> _matches() async {
    final items = await library.getItems();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return items.where((item) => (item['title'] as String? ?? '').toLowerCase().contains(q)).toList();
  }

  Widget _results(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: _matches(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return const Center(child: Text('Search failed.'));
      final items = snapshot.data ?? [];
      if (items.isEmpty) return const Center(child: Text('No matching media found.'));
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final type = item['file_type'] as String? ?? '';
          final icon = type == 'audio' ? Icons.headphones_rounded : type == 'photo' ? Icons.image_rounded : type == 'video' ? Icons.video_library_rounded : Icons.menu_book_rounded;
          return ListTile(
            leading: Icon(icon),
            title: Text(item['title'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(type == 'audio' ? 'Music' : type == 'photo' ? 'Photo' : type == 'video' ? 'Video' : 'Book'),
            onTap: () {
              close(context, item);
              onOpen(item);
            },
          );
        },
      );
    },
  );

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  @override
  Widget buildResults(BuildContext context) => _results(context);
}

}
