import 'dart:io';

import 'package:epub_view/epub_view.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/features/library/services/my_library_service.dart';

/// Native in-app EPUB reader for books stored in My Library.
class LibraryEpubReaderScreen extends StatefulWidget {
  const LibraryEpubReaderScreen({super.key, required this.item});

  final Map<String, Object?> item;

  @override
  State<LibraryEpubReaderScreen> createState() => _LibraryEpubReaderScreenState();
}

class _LibraryEpubReaderScreenState extends State<LibraryEpubReaderScreen> {
  late final EpubController _controller;
  String? _error;
  bool _loaded = false;
  bool _saving = false;

  String get _path => widget.item['file_path'] as String;
  String get _title => widget.item['title'] as String? ?? 'EPUB Reader';
  int? get _itemId => widget.item['id'] as int?;

  @override
  void initState() {
    super.initState();
    final savedCfi = widget.item['last_epub_cfi'] as String?;
    _controller = EpubController(
      document: EpubDocument.openFile(_path),
      epubCfi: savedCfi?.isNotEmpty == true ? savedCfi : null,
    );
    _checkFile();
  }

  Future<void> _checkFile() async {
    if (!await File(_path).exists() && mounted) {
      setState(() {
        _error = 'This EPUB file is missing from My Library storage.';
        _loaded = false;
      });
    }
  }

  Future<void> _saveProgress() async {
    final id = _itemId;
    if (id == null || _saving) return;
    final cfi = _controller.generateEpubCfi();
    if (cfi == null || cfi.isEmpty) return;
    _saving = true;
    try {
      await MyLibraryService.instance.saveEpubPosition(id, cfi);
    } catch (_) {
      // Reading remains available if saving progress fails.
    } finally {
      _saving = false;
    }
  }

  @override
  void dispose() {
    _saveProgress();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_loaded)
              EpubViewActualChapter(
                controller: _controller,
                builder: (chapterValue) {
                  final chapter = chapterValue?.chapter?.Title?.replaceAll('\n', '').trim() ?? '';
                  return Text(
                    chapter.isEmpty ? 'EPUB Book' : chapter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Text(
                  'Contents',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: EpubViewTableOfContents(
                  controller: _controller,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_outlined, size: 54, color: colors.error),
                    const SizedBox(height: 14),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back to My Library'),
                    ),
                  ],
                ),
              ),
            )
          : EpubView(
              controller: _controller,
              onDocumentLoaded: (_) {
                if (mounted) setState(() => _loaded = true);
              },
              onChapterChanged: (_) => _saveProgress(),
              onDocumentError: (error) {
                if (mounted) {
                  setState(() {
                    _error = 'Unable to open this EPUB file. The file may be damaged or use an unsupported format.\n$error';
                  });
                }
              },
            ),
    );
  }
}
