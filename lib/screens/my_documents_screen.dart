import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../models/attachment_model.dart';
import '../services/attachment_service.dart';
import '../services/my_documents_service.dart';
import '../widgets/attachment_section.dart';

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  static const List<String> _categories = [
    'Personal',
    'Vehicle',
    'Education',
    'Property',
    'Financial',
    'Bills & Receipts',
    'Business',
    'Other',
  ];

  final _service = MyDocumentsService.instance;
  final _searchController = TextEditingController();
  List<MyDocumentModel> _documents = [];
  bool _loading = true;
  String _category = 'All';
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _searchController.addListener(_loadDocuments);
  }

  @override
  void dispose() {
    _searchController.removeListener(_loadDocuments);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    try {
      final items = await _service.getDocuments(
        search: _searchController.text,
        category: _category,
        filter: _filter,
      );
      if (!mounted) return;
      setState(() {
        _documents = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Documents load nahi ho sake: $error');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  int get _expiringCount {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _documents.where((document) {
      final expiry = document.expiryDate;
      if (expiry == null) return false;
      final days = DateTime(expiry.year, expiry.month, expiry.day)
          .difference(today).inDays;
      return days >= 0 && days <= document.reminderDays;
    }).length;
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Personal': return Icons.badge_outlined;
      case 'Vehicle': return Icons.directions_car_outlined;
      case 'Education': return Icons.school_outlined;
      case 'Property': return Icons.home_work_outlined;
      case 'Financial': return Icons.account_balance_outlined;
      case 'Bills & Receipts': return Icons.receipt_long_outlined;
      case 'Business': return Icons.business_center_outlined;
      default: return Icons.folder_outlined;
    }
  }

  Color _expiryColor(MyDocumentModel document) {
    final expiry = document.expiryDate;
    if (expiry == null) return AppColorsForDocuments.muted;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(expiry.year, expiry.month, expiry.day)
        .difference(today).inDays;
    if (days < 0) return Colors.red;
    if (days <= document.reminderDays) return Colors.orange.shade800;
    return AppColorsForDocuments.primary;
  }

  String _expiryLabel(MyDocumentModel document) {
    final expiry = document.expiryDate;
    if (expiry == null) return 'No expiry date';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(expiry.year, expiry.month, expiry.day)
        .difference(today).inDays;
    if (days < 0) return 'Expired • ${DateFormat('dd MMM yyyy').format(expiry)}';
    if (days == 0) return 'Expires today';
    if (days <= document.reminderDays) return 'Expires in $days days';
    return 'Expiry • ${DateFormat('dd MMM yyyy').format(expiry)}';
  }

  Future<void> _showDocumentForm({MyDocumentModel? document}) async {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(text: document?.title ?? '');
    final numberController = TextEditingController(text: document?.documentNumber ?? '');
    final notesController = TextEditingController(text: document?.notes ?? '');
    String category = document?.category ?? _categories.first;
    DateTime? issueDate = document?.issueDate;
    DateTime? expiryDate = document?.expiryDate;
    int reminderDays = document?.reminderDays ?? 30;
    final List<Map<String, String>> selectedFiles = [];
    final imagePicker = ImagePicker();

    InputDecoration decoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 19),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E9E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF147D59), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      isDense: true,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
          final screenHeight = MediaQuery.sizeOf(context).height;
          final maxHeight = keyboardHeight > 0
              ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * .95
              : screenHeight * .86;

          Future<void> chooseFiles() async {
            try {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: [
                  'pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic',
                  'doc', 'docx', 'xls', 'xlsx', 'txt', 'ppt', 'pptx',
                ],
                allowMultiple: true,
              );
              if (result == null) return;
              setSheetState(() {
                for (final file in result.files) {
                  if (file.path != null &&
                      !selectedFiles.any((item) => item['path'] == file.path)) {
                    selectedFiles.add({'path': file.path!, 'name': file.name});
                  }
                }
              });
            } catch (error) {
              _message('File select nahi ho saki: $error');
            }
          }

          Future<void> takePhoto() async {
            try {
              final photo = await imagePicker.pickImage(
                source: ImageSource.camera,
                imageQuality: 90,
              );
              if (photo == null) return;
              setSheetState(() => selectedFiles.add({
                'path': photo.path,
                'name': photo.name,
              }));
            } catch (error) {
              _message('Camera error: $error');
            }
          }

          Future<DateTime?> pickDate(DateTime? initial) async {
            return showDatePicker(
              context: context,
              initialDate: initial ?? DateTime.now(),
              firstDate: DateTime(1950),
              lastDate: DateTime(2100),
            );
          }

          Widget dateField(String label, DateTime? value, bool isExpiry) {
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await pickDate(value);
                  if (picked != null) {
                    setSheetState(() {
                      if (isExpiry) {
                        expiryDate = picked;
                      } else {
                        issueDate = picked;
                      }
                    });
                  }
                },
                child: InputDecorator(
                  decoration: decoration(label, Icons.calendar_month_outlined),
                  child: Text(
                    value == null ? 'Not set' : DateFormat('dd MMM yyyy').format(value),
                    style: TextStyle(
                      fontSize: 13,
                      color: value == null ? Colors.grey : const Color(0xFF202B25),
                    ),
                  ),
                ),
              ),
            );
          }

          return AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      primary: false,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 38, height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9E0DC),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  document == null ? 'Add Document' : 'Edit Document',
                                  style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800,
                                    color: Color(0xFF202B25),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close_rounded),
                                color: Colors.grey,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: titleController,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: decoration('Document Name', Icons.description_outlined),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Enter document name' : null,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: category,
                            isExpanded: true,
                            decoration: decoration('Category', Icons.category_outlined),
                            items: _categories.map((value) => DropdownMenuItem(
                              value: value, child: Text(value),
                            )).toList(),
                            onChanged: (value) {
                              if (value != null) setSheetState(() => category = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: numberController,
                            decoration: decoration('Document Number (Optional)', Icons.numbers_rounded),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              dateField('Issue Date', issueDate, false),
                              const SizedBox(width: 10),
                              dateField('Expiry Date', expiryDate, true),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: reminderDays,
                            isExpanded: true,
                            decoration: decoration('Expiry Alert Window', Icons.notifications_active_outlined),
                            items: const [
                              DropdownMenuItem(value: 7, child: Text('7 days before')),
                              DropdownMenuItem(value: 15, child: Text('15 days before')),
                              DropdownMenuItem(value: 30, child: Text('30 days before')),
                              DropdownMenuItem(value: 60, child: Text('60 days before')),
                              DropdownMenuItem(value: 90, child: Text('90 days before')),
                            ],
                            onChanged: (value) {
                              if (value != null) setSheetState(() => reminderDays = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: notesController,
                            minLines: 2,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: decoration('Notes (Optional)', Icons.notes_rounded),
                          ),
                          const SizedBox(height: 14),
                          const Text('Attach Files', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8, runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: chooseFiles,
                                icon: const Icon(Icons.attach_file_rounded),
                                label: const Text('Browse Files'),
                              ),
                              OutlinedButton.icon(
                                onPressed: takePhoto,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: const Text('Scan / Camera'),
                              ),
                            ],
                          ),
                          if (selectedFiles.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ...selectedFiles.asMap().entries.map((entry) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF147D59)),
                              title: Text(entry.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                icon: const Icon(Icons.close_rounded, size: 19),
                                onPressed: () => setSheetState(() => selectedFiles.removeAt(entry.key)),
                              ),
                            )),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.check_rounded),
                                  label: Text(document == null ? 'Save Document' : 'Update Document'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF147D59),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                  ),
                                  onPressed: () async {
                                    if (!formKey.currentState!.validate()) return;
                                    if (issueDate != null && expiryDate != null &&
                                        expiryDate!.isBefore(issueDate!)) {
                                      _message('Expiry date cannot be before issue date.');
                                      return;
                                    }
                                    final now = DateTime.now();
                                    final model = MyDocumentModel(
                                      id: document?.id,
                                      title: titleController.text.trim(),
                                      category: category,
                                      documentNumber: numberController.text.trim(),
                                      issueDate: issueDate,
                                      expiryDate: expiryDate,
                                      reminderDays: reminderDays,
                                      notes: notesController.text.trim(),
                                      isFavorite: document?.isFavorite ?? false,
                                      createdAt: document?.createdAt ?? now,
                                      updatedAt: now,
                                    );
                                    try {
                                      int id;
                                      if (document == null) {
                                        id = await _service.addDocument(model);
                                      } else {
                                        await _service.updateDocument(model);
                                        id = document.id!;
                                      }
                                      var failedFiles = 0;
                                      for (final file in selectedFiles) {
                                        try {
                                          await AttachmentService.addAttachment(
                                            ownerType: AttachmentOwnerTypes.document,
                                            ownerId: id,
                                            sourcePath: file['path']!,
                                            originalFileName: file['name'],
                                          );
                                        } catch (_) {
                                          failedFiles++;
                                        }
                                      }
                                      if (!sheetContext.mounted) return;
                                      Navigator.pop(sheetContext);
                                      await _loadDocuments();
                                      _message(failedFiles == 0
                                          ? (document == null ? 'Document saved successfully.' : 'Document updated successfully.')
                                          : 'Document saved, but $failedFiles file(s) could not be attached.');
                                    } catch (error) {
                                      _message('Save error: $error');
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    titleController.dispose();
    numberController.dispose();
    notesController.dispose();
  }

  Future<void> _toggleFavorite(MyDocumentModel document) async {
    await _service.toggleFavorite(document);
    await _loadDocuments();
  }

  Future<void> _deleteDocument(MyDocumentModel document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Document?'),
        content: Text('Delete "${document.title}" and its attached files?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || document.id == null) return;
    try {
      await AttachmentService.deleteOwnerAttachments(
        ownerType: AttachmentOwnerTypes.document,
        ownerId: document.id!,
      );
      await _service.deleteDocument(document.id!);
      await _loadDocuments();
      _message('Document deleted.');
    } catch (error) {
      _message('Delete error: $error');
    }
  }

  void _openDetails(MyDocumentModel document) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DocumentDetailsScreen(
          document: document,
          onEdit: () async {
            if (!mounted) return;
            await _showDocumentForm(document: document);
          },
        ),
      ),
    ).then((_) => _loadDocuments());
  }

  Widget _summaryCard(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Container(
              width: 37, height: 37,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  Text(label, style: const TextStyle(fontSize: 10, color: AppColorsForDocuments.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentCard(MyDocumentModel document) {
    final expiryColor = _expiryColor(document);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        leading: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: AppColorsForDocuments.primary.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(_categoryIcon(document.category), color: AppColorsForDocuments.primary),
        ),
        title: Text(document.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(document.category, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 3),
              Text(_expiryLabel(document), style: TextStyle(
                fontSize: 11, color: expiryColor, fontWeight: FontWeight.w600,
              )),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'open') _openDetails(document);
            if (value == 'edit') _showDocumentForm(document: document);
            if (value == 'favorite') _toggleFavorite(document);
            if (value == 'delete') _deleteDocument(document);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: Text('View Details')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'favorite', child: Text(document.isFavorite ? 'Remove Favorite' : 'Add to Favorites')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
          child: Icon(
            document.isFavorite ? Icons.star_rounded : Icons.more_vert_rounded,
            color: document.isFavorite ? Colors.amber.shade700 : AppColorsForDocuments.muted,
          ),
        ),
        onTap: () => _openDetails(document),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsForDocuments.background,
      appBar: AppBar(
        backgroundColor: AppColorsForDocuments.background,
        elevation: 0,
        title: const Text('My Documents', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Add Document',
            onPressed: () => _showDocumentForm(),
            icon: const Icon(Icons.add_rounded, size: 29),
          ),
          const SizedBox(width: 5),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showDocumentForm(),
        backgroundColor: AppColorsForDocuments.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Document'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                _summaryCard('Documents', _documents.length, Icons.folder_copy_outlined, AppColorsForDocuments.primary),
                const SizedBox(width: 10),
                _summaryCard('Expiring Soon', _expiringCount, Icons.event_busy_outlined, Colors.orange),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search documents...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty ? null : IconButton(
                  onPressed: () => _searchController.clear(),
                  icon: const Icon(Icons.close_rounded),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: ['All', 'Favorites', 'Expiring Soon', 'Expired'].map((filter) {
                final selected = _filter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _filter = filter);
                      _loadDocuments();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: ['All', ..._categories].map((category) {
                final selected = _category == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _category = category);
                      _loadDocuments();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _documents.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open_rounded, size: 54, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text('No documents found', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 5),
                              const Text('Add your first document to keep important files in one place.',
                                textAlign: TextAlign.center, style: TextStyle(color: AppColorsForDocuments.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                        itemCount: _documents.length,
                        itemBuilder: (_, index) => _documentCard(_documents[index]),
                      ),
          ),
        ],
      ),
    );
  }
}

class _DocumentDetailsScreen extends StatelessWidget {
  final MyDocumentModel document;
  final VoidCallback onEdit;

  const _DocumentDetailsScreen({required this.document, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    Widget detail(String label, String value, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColorsForDocuments.primary),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColorsForDocuments.muted)),
              const SizedBox(height: 3),
              Text(value.isEmpty ? 'Not provided' : value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          )),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColorsForDocuments.background,
      appBar: AppBar(
        backgroundColor: AppColorsForDocuments.background,
        title: const Text('Document Details', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(document.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(document.category, style: const TextStyle(color: AppColorsForDocuments.muted)),
                  const Divider(height: 24),
                  detail('Document Number', document.documentNumber, Icons.numbers_rounded),
                  detail('Issue Date', document.issueDate == null ? '' : dateFormat.format(document.issueDate!), Icons.calendar_month_outlined),
                  detail('Expiry Date', document.expiryDate == null ? '' : dateFormat.format(document.expiryDate!), Icons.event_outlined),
                  detail('Expiry Alert Window', '${document.reminderDays} days before expiry', Icons.notifications_active_outlined),
                  detail('Notes', document.notes, Icons.notes_rounded),
                ],
              ),
            ),
          ),
          if (document.id != null)
            AttachmentSection(
              ownerType: AttachmentOwnerTypes.document,
              ownerId: document.id!,
            ),
        ],
      ),
    );
  }
}

class AppColorsForDocuments {
  static const Color primary = Color(0xFF147D59);
  static const Color background = Color(0xFFF5F7F6);
  static const Color muted = Color(0xFF7B8781);
}
