import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:my_finance/features/library/services/my_library_service.dart';

class LibraryPdfReaderScreen extends StatefulWidget {
  final Map<String, Object?> item;
  const LibraryPdfReaderScreen({super.key, required this.item});

  @override
  State<LibraryPdfReaderScreen> createState() => _LibraryPdfReaderScreenState();
}

class _LibraryPdfReaderScreenState extends State<LibraryPdfReaderScreen> {
  PdfControllerPinch? _controller;
  String? _error;
  int _currentPage = 1;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _openDocument();
  }

  Future<void> _openDocument() async {
    try {
      final path = widget.item['file_path'] as String;
      if (!await File(path).exists()) throw Exception('PDF file is missing.');
      final savedPage = (widget.item['last_page'] as int?) ?? 1;
      final document = await PdfDocument.openFile(path);
      final pageCount = document.pagesCount;
      final initialPage = savedPage.clamp(1, pageCount);
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
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _savePage(int page) async {
    final id = widget.item['id'] as int?;
    if (id == null) return;
    try {
      await MyLibraryService.instance.saveReadingPage(id, page);
    } catch (_) {
      // Reading remains available if progress storage fails.
    }
  }

  @override
  void dispose() {
    _savePage(_currentPage);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item['title'] as String? ?? 'PDF Reader', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_pageCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('$_currentPage / $_pageCount'),
              ),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Unable to open PDF: $_error', textAlign: TextAlign.center)))
          : _controller == null
              ? const Center(child: CircularProgressIndicator())
              : PdfViewPinch(
                  controller: _controller!,
                  onPageChanged: (page) {
                    setState(() => _currentPage = page);
                    _savePage(page);
                  },
                ),
    );
  }
}
