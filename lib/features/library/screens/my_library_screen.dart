import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/library/screens/library_audio_player_screen.dart';
import 'package:my_finance/features/library/screens/library_pdf_reader_screen.dart';
import 'package:my_finance/features/library/screens/library_epub_reader_screen.dart';
import 'package:my_finance/features/library/screens/library_tools_screen.dart';
import 'package:my_finance/features/library/screens/library_video_player_screen.dart';
import 'package:my_finance/features/library/screens/library_documents_screen.dart';
import 'package:my_finance/features/library/screens/library_records_screen.dart';
import 'package:my_finance/features/library/services/my_library_service.dart';
import 'package:my_finance/features/library/services/library_documents_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

class MyLibraryScreen extends StatefulWidget {
  const MyLibraryScreen({super.key});

  @override
  State<MyLibraryScreen> createState() => _MyLibraryScreenState();
}

class _MyLibraryScreenState extends State<MyLibraryScreen> {
  final _library = MyLibraryService.instance;
  final _documentsKey = GlobalKey<LibraryDocumentsScreenState>();
  final _dealsKey = GlobalKey<LibraryRecordsScreenState>();
  final _projectsKey = GlobalKey<LibraryRecordsScreenState>();
  late Future<List<Map<String, Object?>>> _allItems;
  late Future<List<Map<String, Object?>>> _bookItems;
  late Future<List<Map<String, Object?>>> _audioItems;
  late Future<List<Map<String, Object?>>> _photoItems;
  late Future<List<Map<String, Object?>>> _videoItems;
  int _selectedTabIndex = 0;

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

  Future<void> _openRecordForm(String section) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => LibraryRecordFormScreen(section: section),
    ));
    if (!mounted) return;
    if (section == 'deals') _dealsKey.currentState?.refresh();
    if (section == 'projects') _projectsKey.currentState?.refresh();
  }

  Future<void> _openLibrarySearch() async {
    await showSearch<Object?>(
      context: context,
      delegate: _LibrarySearchDelegate(
        library: _library,
        onOpen: _openItem,
        onOpenDocument: (document) => _documentsKey.currentState?.openDocumentFromSearch(document),
      ),
    );
  }

  Future<void> _addFile({String? mediaType}) async {
    const bookExts = ['pdf', 'epub'];
    const musicExts = ['mp3', 'm4a', 'wav', 'flac'];
    const photoExts = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];
    const videoExts = ['mp4', 'm4v', 'mov', 'mkv', 'avi', 'webm', '3gp'];
    final allowed = mediaType == 'book' ? bookExts
        : mediaType == 'audio' ? musicExts
        : mediaType == 'photo' ? photoExts
        : mediaType == 'video' ? videoExts
        : [...bookExts, ...musicExts, ...photoExts, ...videoExts];
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        withData: false,
        allowedExtensions: allowed,
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
    } else if (extension == '.epub') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryEpubReaderScreen(item: item)));
    } else {
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(appText(context, 'My Library', 'میری لائبریری')),
        actions: [
          IconButton(tooltip: 'Search My Library', icon: const Icon(Icons.search_rounded), onPressed: _openLibrarySearch),
          IconButton(tooltip: 'Playlists, folders and storage', icon: const Icon(Icons.tune_rounded), onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const LibraryToolsScreen())); if (mounted) setState(_refresh); }),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.055), blurRadius: 14, offset: const Offset(0, -3))],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                _navItem(0, Icons.library_books_outlined, 'All'),
                _navItem(1, Icons.menu_book_outlined, 'Books'),
                _navItem(2, Icons.handshake_outlined, 'Deals'),
                _navItem(3, Icons.description_outlined, 'Docs'),
                Expanded(
                  child: PopupMenuButton<String>(
                    tooltip: 'Add to My Library',
                    icon: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 28),
                    ),
                    onSelected: (type) {
                      if (type == 'document') {
                        _documentsKey.currentState?.showAddDocumentForm();
                      } else if (type == 'deal') {
                        _openRecordForm('deals');
                      } else if (type == 'project') {
                        _openRecordForm('projects');
                      } else {
                        _addFile(mediaType: type);
                      }
                    },
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 4),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 0, maxWidth: 230),
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .8)),
                    ),
                    itemBuilder: (_) => [
                      _addMenuItem('book', Icons.menu_book_outlined, 'Add Book'),
                      _addMenuItem('deal', Icons.handshake_outlined, 'Add Deal'),
                      _addMenuItem('audio', Icons.music_note_outlined, 'Add Music'),
                      _addMenuItem('document', Icons.description_outlined, 'Add Doc'),
                      _addMenuItem('photo', Icons.photo_outlined, 'Add Photo'),
                      _addMenuItem('video', Icons.video_library_outlined, 'Add Video'),
                      _addMenuItem('project', Icons.work_outline_rounded, 'Add Project'),
                    ],
                  ),
                ),
                _navItem(4, Icons.headphones_outlined, 'Music'),
                _navItem(5, Icons.photo_outlined, 'Photo'),
                _navItem(6, Icons.work_outline_rounded, 'Projects'),
                _navItem(7, Icons.video_library_outlined, 'Video'),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildItems(_allItems, 'Your library is empty', 'Add books, deals, docs, music, photos, videos and projects.'),
          _buildItems(_bookItems, 'No books yet', 'Add PDF or EPUB books to your library.'),
          LibraryRecordsScreen(key: _dealsKey, section: 'deals'),
          LibraryDocumentsScreen(key: _documentsKey),
          _buildItems(_audioItems, 'No music yet', 'Add audio files to your library.'),
          _buildItems(_photoItems, 'No photos yet', 'Add JPG, PNG, WEBP, GIF or BMP photos.'),
          LibraryRecordsScreen(key: _projectsKey, section: 'projects'),
          _buildItems(_videoItems, 'No videos yet', 'Add MP4, MOV, MKV, AVI or WEBM videos.'),
        ],
      ),
    );
}

  
  PopupMenuItem<String> _addMenuItem(String value, IconData icon, String label) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 9),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _selectedTabIndex == index;
    final color = selected ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: SizedBox(
          height: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibrarySearchDelegate extends SearchDelegate<Object?> {
  _LibrarySearchDelegate({required this.library, required this.onOpen, required this.onOpenDocument});

  final MyLibraryService library;
  final Future<void> Function(Map<String, Object?> item) onOpen;
  final void Function(LibraryDocumentModel document) onOpenDocument;

  String _type = 'All';
  String _documentCategory = 'All';
  String _documentFilter = 'All';

  static const _categories = ['All', 'Personal', 'Vehicle', 'Education', 'Property', 'Financial', 'Bills & Receipts', 'Business', 'Other'];
  static const _documentFilters = ['All', 'Favorites', 'Expiring Soon', 'Expired'];

  @override
  String get searchFieldLabel => 'Search books, docs, music, photos, videos';

  @override
  List<Widget> buildActions(BuildContext context) => [
    PopupMenuButton<String>(
      tooltip: 'Search filters',
      icon: const Icon(Icons.filter_list_rounded),
      onSelected: (value) { _type = value; showSuggestions(context); },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'All', child: Text('All Library')),
        PopupMenuItem(value: 'book', child: Text('Books')),
        PopupMenuItem(value: 'document', child: Text('My Docs')),
        PopupMenuItem(value: 'audio', child: Text('Music')),
        PopupMenuItem(value: 'photo', child: Text('Photos')),
        PopupMenuItem(value: 'video', child: Text('Videos')),
      ],
    ),
    PopupMenuButton<String>(
      tooltip: 'Document category and status',
      icon: const Icon(Icons.tune_rounded),
      onSelected: (value) {
        if (value.startsWith('category:')) {
          _documentCategory = value.substring(9);
        } else {
          _documentFilter = value.substring(7);
        }
        showSuggestions(context);
      },
      itemBuilder: (_) => [
        const PopupMenuItem<String>(enabled: false, child: Text('DOCUMENT CATEGORY')),
        ..._categories.map((value) => PopupMenuItem(
          value: 'category:$value',
          child: Row(children: [
            const Icon(Icons.folder_outlined, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(value)),
            if (_documentCategory == value) const Icon(Icons.check, size: 18),
          ]),
        )),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(enabled: false, child: Text('DOCUMENT STATUS')),
        ..._documentFilters.map((value) => PopupMenuItem(
          value: 'status:$value',
          child: Row(children: [
            const Icon(Icons.filter_alt_outlined, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(value)),
            if (_documentFilter == value) const Icon(Icons.check, size: 18),
          ]),
        )),
      ],
    ),
    IconButton(
      icon: const Icon(Icons.close_rounded),
      tooltip: 'Close search',
      onPressed: () => close(context, null),
    ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back_rounded),
    tooltip: 'Close search',
    onPressed: () => close(context, null),
  );

  String _normalise(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[\u200c\u200d]'), '')
      .replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _containsAllTerms(String value, String search) {
    final text = _normalise(value);
    return _normalise(search).split(' ').where((term) => term.isNotEmpty).every(text.contains);
  }

  Future<List<_LibrarySearchResult>> _matches() async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final results = <_LibrarySearchResult>[];

    if (_type != 'document') {
      final items = await library.getItems();
      for (final item in items) {
        final type = item['file_type']?.toString() ?? '';
        if (_type != 'All' && type != _type) continue;
        final searchable = [
          item['title']?.toString() ?? '',
          item['original_name']?.toString() ?? '',
          item['file_name']?.toString() ?? '',
          item['file_path']?.toString() ?? '',
        ].join(' ');
        if (_containsAllTerms(searchable, q)) results.add(_LibrarySearchResult.media(item));
      }
    }

    if (_type == 'All' || _type == 'document') {
      final documents = await LibraryDocumentsService.instance.getDocuments(
        category: _documentCategory,
        filter: _documentFilter,
      );
      for (final document in documents) {
        final searchable = [
          document.title, document.documentNumber, document.category, document.notes,
          document.issueDate?.toIso8601String() ?? '',
          document.expiryDate?.toIso8601String() ?? '',
        ].join(' ');
        if (_containsAllTerms(searchable, q)) results.add(_LibrarySearchResult.document(document));
      }
    }
    return results;
  }

  Widget _filterSummary(BuildContext context) {
    final chips = <String>[
      if (_type != 'All') _type == 'document' ? 'My Docs' : _type[0].toUpperCase() + _type.substring(1),
      if (_documentCategory != 'All') _documentCategory,
      if (_documentFilter != 'All') _documentFilter,
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: [
        for (final chip in chips)
          InputChip(
            label: Text(chip, style: const TextStyle(fontSize: 11)),
            onDeleted: () {
              if (['My Docs', 'Books', 'Music', 'Photos', 'Videos'].contains(chip)) {
                _type = 'All';
              } else if (_categories.contains(chip)) {
                _documentCategory = 'All';
              } else {
                _documentFilter = 'All';
              }
              showSuggestions(context);
            },
          ),
        ActionChip(
          avatar: const Icon(Icons.restart_alt_rounded, size: 15),
          label: const Text('Reset', style: TextStyle(fontSize: 11)),
          onPressed: () {
            _type = 'All'; _documentCategory = 'All'; _documentFilter = 'All';
            showSuggestions(context);
          },
        ),
      ]),
    );
  }

  Widget _results(BuildContext context) => Column(children: [
    _filterSummary(context),
    Expanded(
      child: FutureBuilder<List<_LibrarySearchResult>>(
        future: _matches(),
        builder: (context, snapshot) {
          if (query.trim().isEmpty) return const Center(child: Text('Search across Books, My Docs, Music, Photos and Videos.'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return const Center(child: Text('Search failed. Please try again.'));
          final results = snapshot.data ?? [];
          if (results.isEmpty) return const Center(child: Text('No matching items found. Try another keyword or filter.'));
          return ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final result = results[index];
              if (result.document != null) {
                final document = result.document!;
                final detail = document.documentNumber.isEmpty ? document.category : document.category + ' • ' + document.documentNumber;
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
                  title: Text(document.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('My Docs • ' + detail, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () { close(context, document); onOpenDocument(document); },
                );
              }
              final item = result.item!;
              final type = item['file_type']?.toString() ?? '';
              final icon = type == 'audio' ? Icons.headphones_rounded
                  : type == 'photo' ? Icons.image_rounded
                  : type == 'video' ? Icons.video_library_rounded : Icons.menu_book_rounded;
              final label = type == 'audio' ? 'Music' : type == 'photo' ? 'Photo' : type == 'video' ? 'Video' : 'Book';
              return ListTile(
                leading: CircleAvatar(child: Icon(icon)),
                title: Text(item['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(label),
                onTap: () { close(context, item); onOpen(item); },
              );
            },
          );
        },
      ),
    ),
  ]);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  @override
  Widget buildResults(BuildContext context) => _results(context);
}

class _LibrarySearchResult {
  final Map<String, Object?>? item;
  final LibraryDocumentModel? document;
  const _LibrarySearchResult._({this.item, this.document});
  factory _LibrarySearchResult.media(Map<String, Object?> item) => _LibrarySearchResult._(item: item);
  factory _LibrarySearchResult.document(LibraryDocumentModel document) => _LibrarySearchResult._(document: document);
}
