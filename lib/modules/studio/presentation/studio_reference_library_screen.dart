import 'package:flutter/material.dart';

import '../application/services/studio_fingerprint_catalogue_service.dart';
import '../application/services/studio_media_library_service.dart';
import '../domain/entities/studio_fingerprint.dart';
import '../domain/entities/studio_media_file.dart';
import '../infrastructure/storage/studio_storage_manager.dart';

/// Browse generated Content ID references and manage their catalogue status.
class StudioReferenceLibraryScreen extends StatefulWidget {
  const StudioReferenceLibraryScreen({super.key});

  @override
  State<StudioReferenceLibraryScreen> createState() =>
      _StudioReferenceLibraryScreenState();
}

class _StudioReferenceLibraryScreenState
    extends State<StudioReferenceLibraryScreen> {
  final _catalogue = StudioFingerprintCatalogueService();
  final _mediaLibrary = StudioMediaLibraryService();
  final _storage = StudioStorageManager();
  final _searchController = TextEditingController();

  List<StudioFingerprint> _fingerprints = [];
  Map<String, StudioMediaFile> _mediaById = {};
  String _filter = 'All';
  String _search = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(() {
      if (mounted) setState(() => _search = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _catalogue.getAll(limit: 1000),
        _mediaLibrary.browse(limit: 1000),
      ]);
      final fingerprints = results[0] as List<StudioFingerprint>;
      final media = results[1] as List<StudioMediaFile>;
      if (!mounted) return;
      setState(() {
        _fingerprints = fingerprints;
        _mediaById = {for (final item in media) item.id: item};
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Map<String, int> _duplicateCounts() {
    final counts = <String, int>{};
    for (final item in _fingerprints) {
      final checksum = item.checksumSha256;
      if (checksum == null || checksum.isEmpty) continue;
      final key = '${item.algorithmKey}|${item.algorithmVersion}|$checksum';
      counts.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  List<StudioFingerprint> get _visibleFingerprints {
    final duplicateCounts = _duplicateCounts();
    return _fingerprints.where((item) {
      final media = _mediaById[item.mediaFileId];
      if (_filter == 'Audio' && item.mediaType != StudioMediaType.audio) {
        return false;
      }
      if (_filter == 'Visual' && item.mediaType != StudioMediaType.video) {
        return false;
      }
      if (_filter == 'Duplicates') {
        final checksum = item.checksumSha256;
        if (checksum == null || checksum.isEmpty) return false;
        final key = '${item.algorithmKey}|${item.algorithmVersion}|$checksum';
        if ((duplicateCounts[key] ?? 0) < 2) return false;
      }
      if (_search.isEmpty) return true;
      final name = media?.originalName ?? item.mediaFileId;
      return name.toLowerCase().contains(_search.toLowerCase()) ||
          item.algorithmKey.toLowerCase().contains(_search.toLowerCase()) ||
          item.status.name.toLowerCase().contains(_search.toLowerCase());
    }).toList(growable: false);
  }

  Future<void> _changeStatus(
    StudioFingerprint fingerprint,
    StudioFingerprintStatus status,
  ) async {
    try {
      await _catalogue.updateStatus(fingerprint.id, status);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update reference: $error')),
      );
    }
  }


  Future<void> _showDetails(StudioFingerprint fingerprint) async {
    try {
      final segments = await _catalogue.getSegments(fingerprint.id);
      if (!mounted) return;
      final mediaName = _mediaById[fingerprint.mediaFileId]?.originalName ??
          fingerprint.mediaFileId;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Reference details',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(mediaName),
                  const SizedBox(height: 14),
                  _detailRow('Type', fingerprint.mediaType.name),
                  _detailRow('Algorithm', fingerprint.algorithmKey),
                  _detailRow('Version', fingerprint.algorithmVersion),
                  _detailRow('Format', fingerprint.fingerprintFormat),
                  _detailRow('Status', fingerprint.status.name),
                  _detailRow('Signatures / frames', fingerprint.frameCount.toString()),
                  _detailRow('Segments', segments.length.toString()),
                  _detailRow('Duration', fingerprint.durationMs == null
                      ? 'Unknown'
                      : '${(fingerprint.durationMs! / 1000).toStringAsFixed(1)} sec'),
                  if (fingerprint.sampleRate != null)
                    _detailRow('Sample rate', '${fingerprint.sampleRate} Hz'),
                  if (fingerprint.channels != null)
                    _detailRow('Channels', fingerprint.channels.toString()),
                  _detailRow('SHA-256', fingerprint.checksumSha256 ?? 'Unavailable'),
                  _detailRow('Created', fingerprint.createdAt.toLocal().toString()),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load reference details: $error')),
      );
    }
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 112, child: Text(label,
                style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: SelectableText(value,
                style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      );

  Future<void> _deleteReference(StudioFingerprint fingerprint) async {
    final name = _mediaById[fingerprint.mediaFileId]?.originalName ??
        fingerprint.mediaFileId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove reference?'),
        content: Text('Remove the fingerprint for "$name"? The imported media file will remain in Studio.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _catalogue.remove(fingerprint.id);
      try {
        await _storage.deleteManagedFile(fingerprint.dataFilePath);
      } catch (_) {
        // An orphaned managed artifact is harmless and can be cleaned later.
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reference removed. Original media was kept.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove reference: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleFingerprints;
    final duplicates = _duplicateCounts();
    final duplicateCount = duplicates.values
        .where((count) => count > 1)
        .fold<int>(0, (sum, count) => sum + count);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reference Library'),
        actions: [
          IconButton(
            tooltip: 'Refresh references',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Content ID references',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            )),
                    const SizedBox(height: 5),
                    Text(
                      'Fingerprints generated from your managed Studio media. Audio and visual references stay indexed independently.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _metric(context, 'References', _fingerprints.length),
                        const SizedBox(width: 18),
                        _metric(context, 'Duplicate entries', duplicateCount),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search media or algorithm',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: ['All', 'Audio', 'Visual', 'Duplicates'].map((filter) {
                return FilterChip(
                  label: Text(filter),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline_rounded),
                  title: const Text('Reference library could not load'),
                  subtitle: Text(_error!),
                  trailing: IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              )
            else if (visible.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      const Icon(Icons.fingerprint_rounded, size: 34),
                      const SizedBox(height: 8),
                      Text(
                        _fingerprints.isEmpty
                            ? 'No references generated yet'
                            : 'No references match this search',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _fingerprints.isEmpty
                            ? 'Run Audio Match or Visual Match on imported media to create references.'
                            : 'Try another name or select a different media filter.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Text(
                '${visible.length} references',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              ...visible.map((fingerprint) {
                final media = _mediaById[fingerprint.mediaFileId];
                final checksum = fingerprint.checksumSha256;
                final key = checksum == null
                    ? null
                    : '${fingerprint.algorithmKey}|${fingerprint.algorithmVersion}|$checksum';
                final isDuplicate = key != null && (duplicates[key] ?? 0) > 1;
                final isAudio = fingerprint.mediaType == StudioMediaType.audio;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(13, 7, 8, 7),
                    leading: CircleAvatar(
                      child: Icon(isAudio
                          ? Icons.graphic_eq_rounded
                          : Icons.video_camera_back_outlined),
                    ),
                    title: Text(
                      media?.originalName ?? 'Missing source media',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 3),
                        Text(
                          '${isAudio ? 'Audio Match' : 'Visual Match'} • ${fingerprint.algorithmVersion} • ${fingerprint.frameCount} signatures',
                        ),
                        Text(
                          'Status: ${fingerprint.status.name} • ${fingerprint.createdAt.toLocal().toString().split('.').first}',
                        ),
                        if (isDuplicate)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Exact fingerprint duplicate • ${duplicates[key]} entries',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.tertiary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onTap: () => _showDetails(fingerprint),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Reference actions',
                      onSelected: (action) {
                        if (action == 'details') {
                          _showDetails(fingerprint);
                        } else if (action == 'delete') {
                          _deleteReference(fingerprint);
                        } else {
                          _changeStatus(fingerprint,
                            StudioFingerprintStatus.values.firstWhere(
                              (status) => status.name == action));
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'details',
                            child: Text('View details')),
                        ...StudioFingerprintStatus.values.map((status) =>
                          PopupMenuItem(value: status.name,
                              child: Text('Set ${status.name}'))),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 'delete',
                            child: Text('Remove reference')),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, int value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value.toString(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
