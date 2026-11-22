import 'dart:io';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import 'package:my_finance/core/models/attachment_model.dart';
import 'package:my_finance/core/services/attachment_service.dart';
import 'package:my_finance/features/space/services/space_documents_service.dart';
import 'package:my_finance/shared/widgets/attachment_section.dart';

class SpaceDocumentsScreen extends StatefulWidget {
  const SpaceDocumentsScreen({super.key});

  @override
  State<SpaceDocumentsScreen> createState() => SpaceDocumentsScreenState();
}

class SpaceDocumentsScreenState extends State<SpaceDocumentsScreen> {
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

  final _service = SpaceDocumentsService.instance;
  List<SpaceDocumentModel> _documents = [];
  bool _loading = true;
  String _category = 'All';
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    AppRefreshController.revision.addListener(_onAppDataChanged);
    _loadDocuments();
  }

  Future<void> showAddDocumentForm() => _showDocumentForm();

  void openDocumentFromSearch(SpaceDocumentModel document) => _openDetails(document);

  void _onAppDataChanged() {
    if (mounted) _loadDocuments();
  }

  @override
  void dispose() {
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    try {
      final items = await _service.getDocuments(
        category: _category,
        filter: _statusFilter,
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

  Color _expiryColor(SpaceDocumentModel document) {
    final expiry = document.expiryDate;
    if (expiry == null) return Theme.of(context).hintColor;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(expiry.year, expiry.month, expiry.day)
        .difference(today).inDays;
    if (days < 0) return Theme.of(context).colorScheme.error;
    if (days <= document.reminderDays) return Theme.of(context).colorScheme.tertiary;
    return Theme.of(context).colorScheme.primary;
  }

  String _expiryLabel(SpaceDocumentModel document) {
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

  Future<void> _showDocumentForm({SpaceDocumentModel? document}) async {
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
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
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

          Future<void> chooseGallery() async {
            try {
              final photos = await imagePicker.pickMultiImage(imageQuality: 90);
              if (photos.isEmpty) return;
              setSheetState(() {
                for (final photo in photos) {
                  if (!selectedFiles.any((item) => item['path'] == photo.path)) {
                    selectedFiles.add({'path': photo.path, 'name': photo.name});
                  }
                }
              });
            } catch (error) {
              _message('Gallery error: $error');
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
                      color: value == null ? Theme.of(context).hintColor : Theme.of(context).colorScheme.onSurface,
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
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
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
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  document == null ? 'Add Document' : 'Edit Document',
                                  style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: Icon(Icons.close_rounded),
                                color: Theme.of(context).hintColor,
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          TextFormField(
                            controller: titleController,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: decoration('Document Name', Icons.description_outlined),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Enter document name' : null,
                          ),
                          SizedBox(height: 12),
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
                          SizedBox(height: 12),
                          TextFormField(
                            controller: numberController,
                            decoration: decoration('Document Number (Optional)', Icons.numbers_rounded),
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              dateField('Issue Date', issueDate, false),
                              SizedBox(width: 10),
                              dateField('Expiry Date', expiryDate, true),
                            ],
                          ),
                          SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: reminderDays,
                            isExpanded: true,
                            decoration: decoration('Expiry Alert Window', Icons.notifications_active_outlined),
                            items: [
                              DropdownMenuItem(value: 7, child: Text(appText(context, "7 days before", "7 days before"))),
                              DropdownMenuItem(value: 15, child: Text(appText(context, "15 days before", "15 days before"))),
                              DropdownMenuItem(value: 30, child: Text(appText(context, "30 days before", "30 days before"))),
                              DropdownMenuItem(value: 60, child: Text(appText(context, "60 days before", "60 days before"))),
                              DropdownMenuItem(value: 90, child: Text(appText(context, "90 days before", "90 days before"))),
                            ],
                            onChanged: (value) {
                              if (value != null) setSheetState(() => reminderDays = value);
                            },
                          ),
                          SizedBox(height: 12),
                          TextFormField(
                            controller: notesController,
                            minLines: 2,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: decoration('Notes (Optional)', Icons.notes_rounded).copyWith(
                              suffixIcon: PopupMenuButton<String>(
                                tooltip: 'Attach files',
                                icon: const Icon(Icons.attach_file_rounded),
                                onSelected: (value) {
                                  if (value == 'files') chooseFiles();
                                  if (value == 'camera') takePhoto();
                                  if (value == 'gallery') chooseGallery();
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'files', child: Text('Browse Files')),
                                  PopupMenuItem(value: 'camera', child: Text('Scan / Camera')),
                                  PopupMenuItem(value: 'gallery', child: Text('Gallery')),
                                ],
                              ),
                            ),
                          ),
                          if (selectedFiles.isNotEmpty) ...[
                            SizedBox(height: 6),
                            ...selectedFiles.asMap().entries.map((entry) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.insert_drive_file_outlined, color: Theme.of(context).colorScheme.primary),
                              title: Text(entry.value['name']!, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                icon: Icon(Icons.close_rounded, size: 19),
                                onPressed: () => setSheetState(() => selectedFiles.removeAt(entry.key)),
                              ),
                            )),
                          ],
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: Icon(Icons.check_rounded),
                                  label: Text(document == null ? 'Save Document' : 'Update Document'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                                    final model = SpaceDocumentModel(
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

  Future<void> _toggleFavorite(SpaceDocumentModel document) async {
    await _service.toggleFavorite(document);
    await _loadDocuments();
  }

  Future<void> _deleteDocument(SpaceDocumentModel document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appText(context, 'Delete Document?', 'دستاویز حذف کریں؟')),
        content: Text('Delete "${document.title}" and its attached files?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(appText(context, 'Cancel', 'منسوخ کریں')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(appText(context, "Delete", "Delete")),
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

  void _openDetails(SpaceDocumentModel document) {
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

  IconData _filterOptionIcon(String option) {
    switch (option) {
      case 'Favorites': return Icons.star_outline_rounded;
      case 'Expiring Soon': return Icons.event_busy_outlined;
      case 'Expired': return Icons.event_available_outlined;
      case 'Personal': return Icons.badge_outlined;
      case 'Vehicle': return Icons.directions_car_outlined;
      case 'Education': return Icons.school_outlined;
      case 'Property': return Icons.home_work_outlined;
      case 'Financial': return Icons.account_balance_outlined;
      case 'Bills & Receipts': return Icons.receipt_long_outlined;
      case 'Business': return Icons.business_center_outlined;
      case 'Other': return Icons.folder_open_outlined;
      case 'All': return Icons.grid_view_rounded;
      default: return Icons.folder_outlined;
    }
  }

  Widget _compactFilterDropdown({
    required String label,
    required String value,
    required IconData icon,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return PopupMenuButton<String>(
          tooltip: label,
          position: PopupMenuPosition.under,
          offset: const Offset(0, 4),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: constraints.maxWidth),
          color: colors.surface,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(color: colors.outlineVariant.withValues(alpha: .8)),
          ),
          onSelected: onChanged,
          itemBuilder: (menuContext) => options.map((option) {
            final selected = option == value;
            final optionIcon = _filterOptionIcon(option);
            return PopupMenuItem<String>(
              value: option,
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(optionIcon, size: 17,
                    color: selected ? colors.primary : colors.onSurfaceVariant),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(option, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? colors.primary : colors.onSurface)),
                  ),
                  if (selected) Icon(Icons.check_rounded, size: 17, color: colors.primary),
                ],
              ),
            );
          }).toList(),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: .8)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: colors.primary),
                SizedBox(width: 7),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 8,
                        letterSpacing: .65, fontWeight: FontWeight.w800,
                        color: Theme.of(context).hintColor)),
                      SizedBox(height: 1),
                      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5,
                          fontWeight: FontWeight.w700, color: colors.onSurface)),
                    ],
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: colors.primary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryCard(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .65),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value', style: TextStyle(fontSize: 17, height: 1.05,
                    fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, height: 1.1,
                      color: Theme.of(context).hintColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentCard(SpaceDocumentModel document) {
    final expiryColor = _expiryColor(document);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        leading: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(_categoryIcon(document.category), color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(document.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(document.category, style: TextStyle(fontSize: 11)),
              SizedBox(height: 3),
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
            PopupMenuItem(value: 'open', child: Text(appText(context, "View Details", "View Details"))),
            PopupMenuItem(value: 'edit', child: Text(appText(context, 'Edit', 'ترمیم کریں'))),
            PopupMenuItem(value: 'favorite', child: Text(document.isFavorite ? 'Remove Favorite' : 'Add to Favorites')),
            PopupMenuItem(value: 'delete', child: Text(appText(context, "Delete", "Delete"))),
          ],
          child: Icon(
            document.isFavorite ? Icons.star_rounded : Icons.more_vert_rounded,
            color: document.isFavorite ? Theme.of(context).colorScheme.tertiary : Theme.of(context).hintColor,
          ),
        ),
        onTap: () => _openDetails(document),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                _summaryCard('Documents', _documents.length, Icons.folder_copy_outlined, Theme.of(context).colorScheme.primary),
                SizedBox(width: 10),
                _summaryCard('Expiring Soon', _expiringCount, Icons.event_busy_outlined, Theme.of(context).colorScheme.tertiary),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: _compactFilterDropdown(
                    label: 'STATUS',
                    value: _statusFilter,
                    icon: Icons.filter_list_rounded,
                    options: const ['All', 'Favorites', 'Expiring Soon', 'Expired'],
                    onChanged: (value) {
                      setState(() => _statusFilter = value);
                      _loadDocuments();
                    },
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _compactFilterDropdown(
                    label: 'CATEGORY',
                    value: _category,
                    icon: Icons.folder_outlined,
                    options: ['All', ..._categories],
                    onChanged: (value) {
                      setState(() => _category = value);
                      _loadDocuments();
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 4),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : _documents.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open_rounded, size: 54, color: Theme.of(context).hintColor),
                              SizedBox(height: 12),
                              Text(appText(context, "No documents found", "No documents found"), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              SizedBox(height: 5),
                              Text(appText(context, "Add your first document to keep important files in one place.", "Add your first document to keep important files in one place."),
                                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
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
  final SpaceDocumentModel document;
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
          Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
          SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
              SizedBox(height: 3),
              Text(value.isEmpty ? 'Not provided' : value, style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          )),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(appText(context, "Document Details", "Document Details"), style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: onEdit, icon: Icon(Icons.edit_outlined))],
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
                  Text(document.title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  SizedBox(height: 5),
                  Text(document.category, style: TextStyle(color: Theme.of(context).hintColor)),
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

