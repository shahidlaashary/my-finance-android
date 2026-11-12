
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/preferences/app_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';

import 'package:my_finance/core/models/attachment_model.dart';
import 'package:my_finance/core/services/attachment_service.dart';

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
  final ImagePicker _imagePicker = ImagePicker();

  List<AttachmentModel> _attachments = [];
  bool _loading = true;
  bool _processing = false;

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
      _showMessage('Attachments load nahi ho sakin: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addFile(String path, String fileName) async {
    try {
      await AttachmentService.addAttachment(
        ownerType: widget.ownerType,
        ownerId: widget.ownerId,
        sourcePath: path,
        originalFileName: fileName,
      );

      await _loadAttachments();
      _showMessage('Attachment successfully add ho gayi.');
    } catch (error) {
      _showMessage('Attachment add nahi hui: $error');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null) return;

      await _addFile(photo.path, photo.name);
    } catch (error) {
      _showMessage('Camera error: $error');
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final photos = await _imagePicker.pickMultiImage(
        imageQuality: 85,
      );

      for (final photo in photos) {
        await _addFile(photo.path, photo.name);
      }
    } catch (error) {
      _showMessage('Gallery error: $error');
    }
  }

  Future<void> _pickPdfs() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );

      if (result == null) return;

      for (final file in result.files) {
        final path = file.path;

        if (path != null) {
          await _addFile(path, file.name);
        }
      }
    } catch (error) {
      _showMessage('PDF select nahi ho saki: $error');
    }
  }

  Future<void> _replaceAttachment(
    AttachmentModel oldAttachment,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'heic',
          'pdf',
        ],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path;

      if (path == null) {
        _showMessage('Selected file ka path nahi mila.');
        return;
      }

      // Sab se pehle nayi file save hogi.
      final newAttachment = await AttachmentService.addAttachment(
        ownerType: widget.ownerType,
        ownerId: widget.ownerId,
        sourcePath: path,
        originalFileName: file.name,
      );

      // Nayi file save ho jane ke baad purani file delete hogi.
      if (oldAttachment.id != null) {
        await AttachmentService.deleteAttachment(
          oldAttachment.id!,
        );
      }

      await _loadAttachments();
      _showMessage('Attachment replace ho gayi.');
    } catch (error) {
      _showMessage('Replacement error: $error');
    }
  }

  Future<void> _deleteAttachment(
    AttachmentModel attachment,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.translate(context, 'Delete Attachment')),
        content: Text(AppStrings.translate(context, 'Kya aap is attachment ko delete karna chahte hain?'),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: Text(AppStrings.translate(context, 'Cancel')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: Text(AppStrings.translate(context, 'Delete')),
          ),
        ],
      ),
    );

    if (confirm != true || attachment.id == null) return;

    try {
      await AttachmentService.deleteAttachment(
        attachment.id!,
      );

      await _loadAttachments();
      _showMessage('Attachment delete ho gayi.');
    } catch (error) {
      _showMessage('Delete error: $error');
    }
  }

  Future<void> _openAttachment(
    AttachmentModel attachment,
  ) async {
    try {
      final file = File(attachment.filePath);

      if (!await file.exists()) {
        _showMessage('Attachment file device par nahi mili.');
        return;
      }

      if (attachment.fileType == 'image') {
        _showImagePreview(attachment);
        return;
      }

      final result = await OpenFilex.open(
        attachment.filePath,
      );

      if (!result.type.toString().toLowerCase().contains('done')) {
        _showMessage(
          result.message.isNotEmpty
              ? result.message
              : 'File open nahi ho saki.',
        );
      }
    } catch (error) {
      _showMessage('File open error: $error');
    }
  }

  void _showImagePreview(AttachmentModel attachment) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.file(
                  File(attachment.filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(AppStrings.translate(context, 'Image preview available nahi.')),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
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

  Widget _buildAddButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: _processing ? null : onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_file),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(AppStrings.translate(context, 'Attachments'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(AppStrings.translate(context, '${_attachments.length}')),
              ],
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS)
                  _buildAddButton(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onPressed: _takePhoto,
                  ),
                _buildAddButton(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onPressed: _pickPhotos,
                ),
                _buildAddButton(
                  icon: Icons.picture_as_pdf,
                  label: 'Add PDFs',
                  onPressed: _pickPdfs,
                ),
              ],
            ),

            const Divider(height: 24),

            if (_loading)
              const Center(
                child: CircularProgressIndicator(),
              )
            else if (_attachments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(AppStrings.translate(context, 'No attachments added yet.')),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _attachments.length,
                itemBuilder: (context, index) {
                  final attachment = _attachments[index];
                  final isImage =
                      attachment.fileType == 'image';

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isImage
                          ? Icons.image
                          : attachment.fileType == 'pdf'
                              ? Icons.picture_as_pdf
                              : Icons.insert_drive_file,
                      color: isImage
                          ? Colors.blue
                          : attachment.fileType == 'pdf'
                              ? Colors.red
                              : null,
                    ),
                    title: Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(AppStrings.translate(context, '${attachment.fileType.toUpperCase()} • ')
                      '${_formatSize(attachment.fileSize)}',
                    ),
                    onTap: () => _openAttachment(attachment),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'open') {
                          _openAttachment(attachment);
                        } else if (value == 'replace') {
                          _replaceAttachment(attachment);
                        } else if (value == 'delete') {
                          _deleteAttachment(attachment);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'open',
                          child: Text(AppStrings.translate(context, 'Open / Preview')),
                        ),
                        PopupMenuItem(
                          value: 'replace',
                          child: Text(AppStrings.translate(context, 'Replace')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(AppStrings.translate(context, 'Delete')),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
