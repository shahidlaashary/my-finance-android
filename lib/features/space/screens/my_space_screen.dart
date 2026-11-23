import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/features/space/screens/space_audio_player_screen.dart';
import 'package:my_finance/features/space/screens/space_pdf_reader_screen.dart';
import 'package:my_finance/features/space/screens/space_epub_reader_screen.dart';
import 'package:my_finance/features/space/screens/space_tools_screen.dart';
import 'package:my_finance/features/space/screens/space_video_player_screen.dart';
import 'package:my_finance/features/space/screens/space_documents_screen.dart';
import 'package:my_finance/features/space/screens/work_records_screen.dart';
import 'package:my_finance/features/space/screens/work_screen.dart';
import 'package:my_finance/features/space/screens/youtube_explore_screen.dart';
import 'package:my_finance/features/space/services/my_space_service.dart';
import 'package:my_finance/features/space/services/space_documents_service.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

const IconData books_space_outlined = Icons.menu_book_rounded;

class MySpaceScreen extends StatefulWidget {
  const MySpaceScreen({super.key});

  @override
  State<MySpaceScreen> createState() => _MySpaceScreenState();
}

class _MySpaceScreenState extends State<MySpaceScreen> {
  final _space = MySpaceService.instance;
  final _documentsKey = GlobalKey<SpaceDocumentsScreenState>();
  final _workKey = GlobalKey<WorkScreenState>();
  late Future<List<Map<String, Object?>>> _allItems;
  late Future<List<Map<String, Object?>>> _bookItems;
  late Future<List<Map<String, Object?>>> _audioItems;
  late Future<List<Map<String, Object?>>> _photosItems;
  late Future<List<Map<String, Object?>>> _videosItems;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _allItems = _space.getItems();
    _bookItems = _space.getItems(fileType: 'book');
    _audioItems = _space.getItems(fileType: 'audio');
    _photosItems = _space.getItems(fileType: 'photos');
    _videosItems = _space.getItems(fileType: 'videos');
  }

  Future<void> _openWorkRecordForm(String section) async {
    if (!mounted) return;
    setState(() => _selectedTabIndex = 7);
    _workKey.currentState?.showWorkSection(section);
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => WorkRecordFormScreen(section: section),
    ));
    if (!mounted) return;
    _workKey.currentState?.refreshWorkRecords(section);
  }

  Future<void> _openSpaceSearch() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _SpaceSearchScreen(
          space: _space,
          onOpen: _openItem,
          onOpenDocument: (document) => _documentsKey.currentState?.openDocumentFromSearch(document),
        ),
      ),
    );
  }

  Future<void> _addFile({String? mediaType}) async {
    const bookExts = ['pdf', 'epub'];
    const musicExts = ['mp3', 'm4a', 'wav', 'flac'];
    const photosExts = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];
    const videosExts = ['mp4', 'm4v', 'mov', 'mkv', 'avi', 'webm', '3gp'];
    final allowed = mediaType == 'book' ? bookExts
        : mediaType == 'audio' ? musicExts
        : mediaType == 'photos' ? photosExts
        : mediaType == 'videos' ? videosExts
        : [...bookExts, ...musicExts, ...photosExts, ...videosExts];
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
        try { await _space.addFile(File(path), picked.name); added++; }
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This space file is missing.')));
      return;
    }

    final extension = p.extension(path).toLowerCase();
    if (item['file_type'] == 'audio') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SpaceAudioPlayerScreen(item: item)));
    } else if (item['file_type'] == 'videos') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SpaceVideoPlayerScreen(item: item)));
    } else if (item['file_type'] == 'photos') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
        appBar: AppBar(title: Text(item['title'] as String)),
        body: Center(child: InteractiveViewer(minScale: 0.5, maxScale: 5, child: Image.file(File(path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('Unable to display this photo.')))),
      )));
    } else if (extension == '.pdf') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SpacePdfReaderScreen(item: item)));
    } else if (extension == '.epub') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SpaceEpubReaderScreen(item: item)));
    } else {
      await OpenFilex.open(path);
    }
    if (mounted) setState(_refresh);
  }

  Future<void> _moveItemToFolder(Map<String, Object?> item) async {
    final folders = await _space.getCollections();
    if (!mounted) return;
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a folder first in Space Tools.')));
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
    await _space.moveItemToCollection(item['id'] as int, selected);
    if (mounted) {
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File moved to folder.')));
    }
  }

  Future<void> _deleteItem(Map<String, Object?> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from My Space?'),
        content: Text('“${item['title']}” will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _space.deleteItem(item);
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
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Unable to load My Space: ${snapshot.error}')));
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_special_outlined, size: 64, color: colors.primary),
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
            final isPhoto = type == 'photos';
            final isVideo = type == 'videos';
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
        title: Text(appText(context, 'My Space', 'مائی اسپیس')),
        actions: [
          IconButton(tooltip: 'Search My Space', icon: const Icon(Icons.search_rounded), onPressed: _openSpaceSearch),
          IconButton(tooltip: 'Explore videos', icon: const Icon(Icons.ondemand_video_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const YouTubeExploreScreen()))),
          IconButton(tooltip: 'Playlists, folders and storage', icon: const Icon(Icons.tune_rounded), onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const SpaceToolsScreen())); if (mounted) setState(_refresh); }),
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
                _navItem(0, books_space_outlined, 'All'),
                _navItem(1, Icons.menu_book_outlined, 'Books'),
                _navItem(2, Icons.handshake_outlined, 'Deals'), // Empty placeholder reserved for future use.
                _navItem(3, Icons.description_outlined, 'Docs'),
                Expanded(
                  child: PopupMenuButton<String>(
                    tooltip: 'Add to My Space',
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
                        // Reserved placeholder; no Deal/Agreement workflow is launched here.
                      } else if (type == 'work') {
                        _openWorkRecordForm('projects');
                      } else {
                        _addFile(mediaType: type);
                      }
                    },
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 4),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 0, maxWidth: 160),
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
                      _addMenuItem('photos', Icons.photo_outlined, 'Add Photo'),
                      _addMenuItem('videos', Icons.video_library_outlined, 'Add Video'),
                      _addMenuItem('work', Icons.work_outline_rounded, 'Add Work'),
                    ],
                  ),
                ),
                _navItem(4, Icons.headphones_outlined, 'Music'),
                _navItem(5, Icons.photo_outlined, 'Photos'),
                _navItem(6, Icons.video_library_outlined, 'Videos'),
                _navItem(7, Icons.work_outline_rounded, 'Work'),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildItems(_allItems, 'Your space is empty', 'Add books, agreements, docs, music, photos, videos and projects.'),
          _buildItems(_bookItems, 'No books yet', 'Add PDF or EPUB books to your space.'),
          const SizedBox.shrink(),
          SpaceDocumentsScreen(key: _documentsKey),
          _buildItems(_audioItems, 'No music yet', 'Add audio files to your space.'),
          _buildItems(_photosItems, 'No photos yet', 'Add JPG, PNG, WEBP, GIF or BMP photos.'),
          _buildItems(_videosItems, 'No videos yet', 'Add MP4, MOV, MKV, AVI or WEBM videos.'),
          WorkScreen(key: _workKey),
        ],
      ),
    );
}

  
  PopupMenuItem<String> _addMenuItem(String value, IconData icon, String label) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: value,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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

class _SpaceSearchScreen extends StatefulWidget {
  const _SpaceSearchScreen({required this.space, required this.onOpen, required this.onOpenDocument});
  final MySpaceService space;
  final Future<void> Function(Map<String, Object?> item) onOpen;
  final void Function(SpaceDocumentModel document) onOpenDocument;
  @override
  State<_SpaceSearchScreen> createState() => _SpaceSearchScreenState();
}

class _SpaceSearchScreenState extends State<_SpaceSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<_SpaceSearchResult> _results = [];
  String _type = 'All';
  String _documentCategory = 'All';
  String _documentStatusFilter = 'All';
  bool _loading = false;
  String? _error;
  int _request = 0;
  static const _types = <String, String>{
    'All': 'All', 'book': 'Books', 'document': 'Docs', 'audio': 'Music',
    'photos': 'Photos', 'videos': 'Videos', 'agreements': 'Agreements', 'projects': 'Projects',
  };
  static const _categories = [
    'All', 'Personal', 'Vehicle', 'Education', 'Property',
    'Financial', 'Bills & Receipts', 'Business', 'Other',
  ];
  static const _documentStatusOptions = ['All', 'Favorites', 'Expiring Soon', 'Expired'];

  @override
  void dispose() { _debounce?.cancel(); _controller.dispose(); super.dispose(); }

  String _normalise(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[\u200c\u200d]'), '')
      .replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _containsAllTerms(String value, String search) {
    final text = _normalise(value);
    return _normalise(search).split(' ').where((term) => term.isNotEmpty).every(text.contains);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() { _request++; _results = []; _loading = false; _error = null; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    final request = ++_request;
    setState(() { _loading = true; _error = null; });
    try {
      final results = <_SpaceSearchResult>[];
      if (_type == 'All' || ['book', 'audio', 'photos', 'videos'].contains(_type)) {
        final items = await widget.space.getItems();
        for (final item in items) {
          final type = item['file_type']?.toString() ?? '';
          if (_type != 'All' && type != _type) continue;
          final searchable = [item['title'], item['original_name'], item['file_name'], item['file_path']]
              .whereType<Object>().join(' ');
          if (_containsAllTerms(searchable, q)) results.add(_SpaceSearchResult.media(item));
        }
      }
      if (_type == 'All' || _type == 'document') {
        final documents = await SpaceDocumentsService.instance.getDocuments(
          category: _documentCategory, filter: _documentStatusFilter,
        );
        for (final document in documents) {
          final searchable = [
            document.title, document.documentNumber, document.category, document.notes,
            document.issueDate?.toIso8601String() ?? '',
            document.expiryDate?.toIso8601String() ?? '',
          ].join(' ');
          if (_containsAllTerms(searchable, q)) results.add(_SpaceSearchResult.document(document));
        }
      }
      for (final section in ['agreements', 'projects']) {
        if (_type != 'All' && _type != section) continue;
        final records = await widget.space.getWorkRecords(section);
        for (final record in records) {
          final searchable = [
            record['title'], record['category'], record['party_one'], record['party_two'],
            record['status'], record['start_date'], record['end_date'],
            record['description'], record['notes'],
          ].whereType<Object>().join(' ');
          if (_containsAllTerms(searchable, q)) results.add(_SpaceSearchResult.record(record, section));
        }
      }
      results.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      if (!mounted || request != _request) return;
      setState(() { _results = results; _loading = false; });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() { _loading = false; _error = 'Search could not be completed. Please try again.'; });
    }
  }

  void _changeType(String value) {
    setState(() => _type = value);
    if (_controller.text.trim().isNotEmpty) _runSearch();
  }

  Future<void> _showFilters() async {
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Document filters', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              Text('Category', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _categories.map((value) => ChoiceChip(
                label: Text(value), selected: _documentCategory == value,
                onSelected: (_) => setSheetState(() => _documentCategory = value),
              )).toList()),
              const SizedBox(height: 16),
              Text('Status', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: _documentStatusOptions.map((value) => ChoiceChip(
                label: Text(value), selected: _documentStatusFilter == value,
                onSelected: (_) => setSheetState(() => _documentStatusFilter = value),
              )).toList()),
              const SizedBox(height: 18),
              Row(children: [
                TextButton(onPressed: () => setSheetState(() {
                  _documentCategory = 'All'; _documentStatusFilter = 'All';
                }), child: const Text('Reset')),
                const Spacer(),
                FilledButton(onPressed: () {
                  Navigator.pop(sheetContext);
                  if (_controller.text.trim().isNotEmpty) _runSearch();
                  setState(() {});
                }, child: const Text('Apply')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildResult(_SpaceSearchResult result) {
    if (result.document != null) {
      final document = result.document!;
      final detail = [
        document.category,
        if (document.documentNumber.isNotEmpty) document.documentNumber,
        if (document.isFavorite) 'Favorite',
      ].join(' • ');
      return ListTile(
        leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
        title: Text(document.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () { Navigator.pop(context); widget.onOpenDocument(document); },
      );
    }
    if (result.section != null) {
      final record = result.record!;
      final isAgreement = result.section == 'agreements';
      final detail = [
        record['category'], record['status'],
        if (isAgreement) record['party_one'], if (isAgreement) record['party_two'],
      ].whereType<Object>().where((v) => v.toString().trim().isNotEmpty).join(' • ');
      return ListTile(
        leading: CircleAvatar(child: Icon(isAgreement ? Icons.handshake_outlined : Icons.work_outline_rounded)),
        title: Text(record['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text((isAgreement ? 'Agreement' : 'Project') + (detail.isEmpty ? '' : ' • ' + detail),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () {
          Navigator.pop(context);
          showModalBottomSheet<void>(
            context: context, isScrollControlled: true, showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: SingleChildScrollView(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(record['title']?.toString() ?? '', style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    for (final field in <String, String>{
                      'Category': 'category', 'Status': 'status',
                      'First Party': 'party_one', 'Second Party': 'party_two',
                      'Start Date': 'start_date', 'End Date': 'end_date',
                      'Description': 'description', 'Notes': 'notes',
                    }.entries)
                      if ((record[field.value]?.toString() ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(field.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(record[field.value].toString()),
                          ]),
                        ),
                  ],
                )),
              ),
            ),
          );
        },
      );
    }
    final item = result.item!;
    final type = item['file_type']?.toString() ?? '';
    final icon = type == 'audio' ? Icons.headphones_rounded
        : type == 'photos' ? Icons.image_rounded
        : type == 'videos' ? Icons.video_library_rounded : Icons.menu_book_rounded;
    final label = type == 'audio' ? 'Music' : type == 'photos' ? 'Photo'
        : type == 'videos' ? 'Video' : 'Book';
    return ListTile(
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(item['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(label),
      onTap: () { Navigator.pop(context); widget.onOpen(item); },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search My Space'),
        actions: [IconButton(
          tooltip: 'Document filters', onPressed: _showFilters,
          icon: const Icon(Icons.tune_rounded),
        )],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: TextField(
            controller: _controller, autofocus: true, onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) { _debounce?.cancel(); _runSearch(); },
            decoration: InputDecoration(
              hintText: 'Search My Space',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _controller.text.isEmpty ? null : IconButton(
                tooltip: 'Clear search',
                onPressed: () { _controller.clear(); _onQueryChanged(''); },
                icon: const Icon(Icons.close_rounded),
              ),
              isDense: true, filled: true,
              fillColor: colors.surfaceContainerHighest.withValues(alpha: .45),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _types.entries.map((entry) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(entry.value), selected: _type == entry.key,
                onSelected: (_) => _changeType(entry.key), visualDensity: VisualDensity.compact,
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator())
              : _error != null ? Center(child: Text(_error!))
              : _controller.text.trim().isEmpty ? const SizedBox.shrink()
              : _results.isEmpty ? const Center(child: Text('No matching items found.'))
              : ListView.separated(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (_, index) => _buildResult(_results[index]),
                ),
        ),
      ]),
    );
  }
}

class _SpaceSearchResult {
  final Map<String, Object?>? item;
  final SpaceDocumentModel? document;
  final Map<String, Object?>? record;
  final String? section;
  const _SpaceSearchResult._({this.item, this.document, this.record, this.section});
  factory _SpaceSearchResult.media(Map<String, Object?> item) => _SpaceSearchResult._(item: item);
  factory _SpaceSearchResult.document(SpaceDocumentModel document) => _SpaceSearchResult._(document: document);
  factory _SpaceSearchResult.record(Map<String, Object?> record, String section) =>
      _SpaceSearchResult._(record: record, section: section);
  String get title => document?.title ?? record?['title']?.toString() ?? item?['title']?.toString() ?? '';
}
