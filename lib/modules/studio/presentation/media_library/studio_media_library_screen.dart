import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/material.dart';

import '../../application/services/studio_media_import_service.dart';
import '../../application/services/studio_media_library_service.dart';
import '../../domain/entities/studio_media_file.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';

class StudioMediaLibraryScreen extends StatefulWidget {
  const StudioMediaLibraryScreen({super.key});

  @override
  State<StudioMediaLibraryScreen> createState() =>
      _StudioMediaLibraryScreenState();
}

enum _MediaFilter { all, audio, video }

class _StudioMediaLibraryScreenState extends State<StudioMediaLibraryScreen> {
  final _searchController = TextEditingController();
  final _library = StudioMediaLibraryService();
  final _storage = StudioStorageManager();

  _MediaFilter _filter = _MediaFilter.all;
  List<StudioMediaFile> _files = const [];
  bool _loading = true;
  bool _importing = false;
  String? _loadError;
  int? _storageBytes;

  StudioMediaImportService get _importService => StudioMediaImportService(
        storageManager: _storage,
        mediaLibrary: _library,
      );

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_load);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_load)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final type = switch (_filter) {
        _MediaFilter.all => null,
        _MediaFilter.audio => StudioMediaType.audio,
        _MediaFilter.video => StudioMediaType.video,
      };
      final results = await _library.browse(
        mediaType: type,
        search: _searchController.text,
        limit: 200,
      );
      final bytes = await _storage.calculateTotalBytes();
      if (!mounted) return;
      setState(() {
        _files = results;
        _storageBytes = bytes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _changeFilter(_MediaFilter filter) {
    setState(() => _filter = filter);
    _load();
  }

  Future<void> _pickAndImport(StudioMediaType type) async {
    if (_importing) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type == StudioMediaType.audio ? FileType.audio : FileType.video,
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;

      final selected = result.files.single;
      final sourcePath = selected.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        _showMessage('The selected file could not be accessed.');
        return;
      }

      setState(() => _importing = true);
      final imported = await _importService.importFile(
        sourcePath: sourcePath,
        mediaType: type,
      );
      if (!mounted) return;
      _showMessage('${imported.originalName} imported successfully.');
      await _load();
    } catch (error) {
      if (mounted) _showMessage('Import failed: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _deleteMedia(StudioMediaFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete media file?'),
        content: Text('Delete "${file.originalName}" and its generated fingerprints from Studio storage? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _library.deleteManagedMedia(file.id, storageManager: _storage);
      if (!mounted) return;
      _showMessage('Media file and its fingerprints deleted.');
      await _load();
    } catch (error) {
      if (mounted) _showMessage('Could not delete media: $error');
    }
  }

  void _showDetails(StudioMediaFile file) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.originalName,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                _DetailRow(label: 'Type', value: file.mediaType.name.toUpperCase()),
                _DetailRow(label: 'Size', value: _formatBytes(file.fileSizeBytes)),
                _DetailRow(label: 'Format', value: file.fileExtension ?? 'Unknown'),
                _DetailRow(label: 'Status', value: file.importStatus.name),
                _DetailRow(label: 'MIME type', value: file.mimeType ?? 'Unknown'),
                _DetailRow(
                  label: 'Imported',
                  value: file.createdAt.toLocal().toString().split('.').first,
                ),
                if (file.checksumSha256 != null) ...[
                  const SizedBox(height: 8),
                  Text('SHA-256', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  SelectableText(
                    file.checksumSha256!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                Text('Managed file', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText(file.storagePath,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final result = await OpenFilex.open(file.storagePath);
                        if (result.type != ResultType.done && mounted) {
                          _showMessage('Could not open media file: ${result.message}');
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open file'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteMedia(file);
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Library'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search audio and video',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == _MediaFilter.all,
                  onSelected: (_) => _changeFilter(_MediaFilter.all),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Audio'),
                  selected: _filter == _MediaFilter.audio,
                  onSelected: (_) => _changeFilter(_MediaFilter.audio),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Video'),
                  selected: _filter == _MediaFilter.video,
                  onSelected: (_) => _changeFilter(_MediaFilter.video),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_files.length} files • ${_storageBytes == null ? '—' : _formatBytes(_storageBytes!)} managed storage',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ),
                if (_importing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? _ErrorState(message: _loadError!, onRetry: _load)
                    : _files.isEmpty
                        ? _EmptyState(
                            filter: _filter,
                            onImportAudio: () =>
                                _pickAndImport(StudioMediaType.audio),
                            onImportVideo: () =>
                                _pickAndImport(StudioMediaType.video),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                              itemCount: _files.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, indent: 68),
                              itemBuilder: (context, index) {
                                final file = _files[index];
                                final isVideo =
                                    file.mediaType == StudioMediaType.video;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        colors.secondaryContainer,
                                    child: Icon(
                                      isVideo
                                          ? Icons.videocam_outlined
                                          : Icons.music_note_rounded,
                                      color: colors.onSecondaryContainer,
                                    ),
                                  ),
                                  title: Text(
                                    file.originalName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${isVideo ? 'Video' : 'Audio'} • ${_formatBytes(file.fileSizeBytes)} • ${file.importStatus.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing:
                                      const Icon(Icons.chevron_right_rounded),
                                  onTap: () => _showDetails(file),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: _files.isEmpty
          ? null
          : PopupMenuButton<StudioMediaType>(
              tooltip: 'Import media',
              onSelected: _pickAndImport,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: StudioMediaType.audio,
                  child: ListTile(
                    leading: Icon(Icons.audio_file_outlined),
                    title: Text('Import Audio'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: StudioMediaType.video,
                  child: ListTile(
                    leading: Icon(Icons.video_file_outlined),
                    title: Text('Import Video'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              icon: const Icon(Icons.add_rounded),
            ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.filter,
    required this.onImportAudio,
    required this.onImportVideo,
  });

  final _MediaFilter filter;
  final VoidCallback onImportAudio;
  final VoidCallback onImportVideo;

  @override
  Widget build(BuildContext context) {
    final showAudio = filter != _MediaFilter.video;
    final showVideo = filter != _MediaFilter.audio;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.perm_media_outlined,
                size: 54,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text('No media files yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'Import audio or video files. Studio keeps managed copies in its own storage.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (showAudio)
                  FilledButton.tonalIcon(
                    onPressed: onImportAudio,
                    icon: const Icon(Icons.audio_file_outlined),
                    label: const Text('Import Audio'),
                  ),
                if (showVideo)
                  FilledButton.tonalIcon(
                    onPressed: onImportVideo,
                    icon: const Icon(Icons.video_file_outlined),
                    label: const Text('Import Video'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            const Text('Could not load the Studio media library'),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
