
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/attachment_model.dart';
import '../services/attachment_service.dart';

class AttachmentSection extends StatefulWidget {
  final String ownerType;
  final int ownerId;

  const AttachmentSection({
    super.key,
    required this.ownerType,
    required this.ownerId,
  });

  @override
  State<AttachmentSection> createState() => _AttachmentSectionState();
}

class _AttachmentSectionState extends State<AttachmentSection> {
  final ImagePicker _picker = ImagePicker();

  List<AttachmentModel> _attachments = [];
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    try {
      final items = await AttachmentService.getAttachments(
        ownerType: widget.ownerType,
        ownerId: widget.ownerId,
      );

      if (!mounted) return;

      setState(() {
        _attachments = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _addImage(ImageSource source) async {
    if (_adding) return;

    setState(() => _adding = true);

    try {
      if (source == ImageSource.camera) {
        final image = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );

        if (image != null) {
          await _saveImage(image);
        }
      } else {
        final images = await _picker.pickMultiImage(
          imageQuality: 85,
        );

        for (final image in images) {
          await _saveImage(image);
        }
      }

      await _loadAttachments();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _saveImage(XFile image) async {
    await AttachmentService.addAttachment(
      ownerType: widget.ownerType,
      ownerId: widget.ownerId,
      sourcePath: image.path,
      originalFileName: image.name,
    );
  }

  Future<void> _addPdf() async {
    if (_adding) return;

    setState(() => _adding = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
        withData: false,
      );

      if (result != null) {
        for (final file in result.files) {
          final path = file.path;
          if (path == null) continue;

          await AttachmentService.addAttachment(
            ownerType: widget.ownerType,
            ownerId: widget.ownerId,
            sourcePath: path,
            originalFileName: file.name,
          );
        }
      }

      await _loadAttachments();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Attachment error: $error')),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose Multiple Photos'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Choose Multiple PDFs'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addPdf();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteAttachment(AttachmentModel attachment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Attachment?'),
        content: Text('Delete "${attachment.fileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || attachment.id == null) return;

    try {
      await AttachmentService.deleteAttachment(attachment.id!);
      await _loadAttachments();
    } catch (error) {
      _showError(error);
    }
  }

  void _previewImage(AttachmentModel attachment) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                attachment.fileName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: Image.file(
                File(attachment.filePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Image could not be opened.'),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Attachments',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _adding ? null : _showAddOptions,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        if (_adding) const LinearProgressIndicator(),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_attachments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No attachments added yet.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ..._attachments.map((attachment) {
            final isImage = attachment.fileType == 'image';
            final isPdf = attachment.fileType == 'pdf';

            return Card(
              child: ListTile(
                leading: isImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(attachment.filePath),
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.broken_image);
                          },
                        ),
                      )
                    : Icon(
                        isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                        color: isPdf ? Colors.red : Colors.grey,
                        size: 36,
                      ),
                title: Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_formatSize(attachment.fileSize)),
                onTap: isImage ? () => _previewImage(attachment) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteAttachment(attachment),
                ),
              ),
            );
          }),
      ],
    );
  }
}
