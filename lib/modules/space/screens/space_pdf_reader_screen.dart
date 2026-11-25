import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:my_finance/modules/space/services/my_space_service.dart';

class SpacePdfReaderScreen extends StatefulWidget {
  final Map<String, Object?>? item;
  final String? filePath;
  final String? documentTitle;

  const SpacePdfReaderScreen({super.key, required Map<String, Object?> item})
      : item = item, filePath = null, documentTitle = null;

  const SpacePdfReaderScreen.fromFile({
    super.key,
    required this.filePath,
    required this.documentTitle,
  }) : item = null;

  @override
  State<SpacePdfReaderScreen> createState() => _SpacePdfReaderScreenState();
}

class _SpacePdfReaderScreenState extends State<SpacePdfReaderScreen> {
  PdfControllerPinch? _controller;
  String? _error;
  int _currentPage = 1;
  int _pageCount = 0;
  bool _loading = true;

  String get _path => widget.filePath ?? widget.item?['file_path'] as String;
  String get _title => widget.documentTitle ??
      widget.item?['title'] as String? ?? 'PDF Reader';
  int? get _spaceItemId => widget.item?['id'] as int?;

  @override
  void initState() {
    super.initState();
    _openDocument();
  }

  Future<void> _openDocument() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await File(_path).exists()) throw Exception('PDF file is missing.');
      final savedPage = (widget.item?['last_page'] as int?) ?? 1;
      final document = await PdfDocument.openFile(_path);
      final pageCount = document.pagesCount;
      if (pageCount < 1) throw Exception('This PDF has no readable pages.');
      final initialPage = savedPage.clamp(1, pageCount).toInt();
      final controller = PdfControllerPinch(
        document: Future.value(document),
        initialPage: initialPage,
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _currentPage = initialPage;
        _pageCount = pageCount;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _savePage(int page) async {
    final id = _spaceItemId;
    if (id == null) return;
    try {
      await MySpaceService.instance.saveReadingPage(id, page);
    } catch (_) {
      // Reading remains available if progress storage fails.
    }
  }

  Future<void> _previousPage() async {
    if (_controller != null && _currentPage > 1) await _controller!.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  Future<void> _nextPage() async {
    if (_controller != null && _currentPage < _pageCount) await _controller!.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _savePage(_currentPage);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: const [],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, size: 52, color: colors.error),
                    const SizedBox(height: 12),
                    Text('Unable to open PDF\n$_error', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _openDocument,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : _loading || _controller == null
              ? const Center(child: CircularProgressIndicator())
              : PdfViewPinch(
                  controller: _controller!,
                  onPageChanged: (page) {
                    if (!mounted) return;
                    setState(() => _currentPage = page);
                    _savePage(page);
                  },
                ),
      bottomNavigationBar: _pageCount == 0 || _error != null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed: _currentPage > 1 ? _previousPage : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Page $_currentPage of $_pageCount',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: _currentPage / _pageCount,
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed: _currentPage < _pageCount ? _nextPage : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
