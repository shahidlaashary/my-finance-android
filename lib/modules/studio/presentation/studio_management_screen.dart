import 'package:flutter/material.dart';

import '../application/services/studio_processing_queue_service.dart';
import '../application/services/studio_reports_service.dart';
import '../application/services/studio_storage_health_service.dart';
import '../application/services/studio_media_library_service.dart';
import '../infrastructure/storage/studio_storage_manager.dart';

class StudioManagementScreen extends StatefulWidget {
  const StudioManagementScreen({super.key});

  @override
  State<StudioManagementScreen> createState() => _StudioManagementScreenState();
}

class _StudioManagementScreenState extends State<StudioManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late Future<_Diagnostics> _diagnostics;
  late Future<List<Map<String, Object?>>> _jobs;
  final _queue = StudioProcessingQueueService();
  bool _batchRunning = false;
  bool _cancelBatchRequested = false;
  String? _batchProgress;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _diagnostics = _loadDiagnostics();
    _jobs = _queue.jobs();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<_Diagnostics> _loadDiagnostics() async {
    final summary = await StudioReportsService().load();
    final storage = StudioStorageManager();
    final health = await StudioStorageHealthService(
      storageManager: storage,
      mediaLibrary: StudioMediaLibraryService(),
    ).inspect();
    // Loading the report requires a successful database connection, so a
    // completed diagnostics snapshot confirms the database is connected.
    return _Diagnostics(summary, health);
  }

  Future<void> _runLibraryBatch() async {
    if (_batchRunning) return;
    setState(() {
      _batchRunning = true;
      _cancelBatchRequested = false;
      _batchProgress = 'Preparing media library scan…';
    });
    try {
      final result = await _queue.runLibraryBatch(
        shouldCancel: () => _cancelBatchRequested,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() => _batchProgress = total == 0
              ? 'No media to process.'
              : 'Processed $completed of $total items…');
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          result.cancelled
              ? 'Library batch stopped after ${result.processed} of ${result.total} items: ${result.succeeded} fingerprinted, ${result.failed} failed.'
              : 'Library batch finished: ${result.succeeded} fingerprinted, ${result.alreadyFingerprinted} already ready, ${result.failed} failed (total ${result.total}).',
        )),
      );
      await _refreshJobs();
      await _refreshDiagnostics();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Library batch failed: $error')),
      );
    } finally {
      if (mounted) setState(() {
        _batchRunning = false;
        _cancelBatchRequested = false;
        _batchProgress = null;
      });
    }
  }

  Future<void> _refreshDiagnostics() async {
    final next = _loadDiagnostics();
    setState(() => _diagnostics = next);
    await next;
  }

  Future<void> _refreshJobs() async {
    final next = _queue.jobs();
    setState(() => _jobs = next);
    await next;
  }

  Future<void> _runJobAction(
    Map<String, Object?> job, {
    required bool retry,
  }) async {
    final id = job['id'].toString();
    try {
      if (retry) {
        await _queue.retry(id);
      } else {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Cancel processing job?'),
            content: const Text(
              'The job will be marked as cancelled in Studio. This does not interrupt a native operation that is already executing.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep job'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Cancel job'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await _queue.cancel(id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(retry
              ? 'Retry attempt finished. Check the updated job status.'
              : 'Job marked as cancelled.'),
        ),
      );
      await _refreshJobs();
      await _refreshDiagnostics();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queue action failed: $error')),
      );
    }
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Color _statusColor(BuildContext context, String status) {
    final colors = Theme.of(context).colorScheme;
    switch (status) {
      case 'failed':
        return colors.error;
      case 'completed':
        return Colors.green;
      case 'running':
      case 'queued':
        return colors.primary;
      case 'cancelled':
        return colors.onSurfaceVariant;
      default:
        return colors.tertiary;
    }
  }

  Widget _metric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: colors.primary, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio Management'),
        actions: [
          IconButton(
            tooltip: 'Fingerprint entire media library',
            onPressed: _batchRunning ? null : _runLibraryBatch,
            icon: _batchRunning
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.library_add_check_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              _refreshDiagnostics();
              _refreshJobs();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'System'),
            Tab(text: 'Processing Queue'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_batchProgress != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Row(children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_batchProgress!)),
                ]),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _systemTab(),
                _queueTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemTab() {
    return FutureBuilder<_Diagnostics>(
      future: _diagnostics,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _errorState('Diagnostics failed: ${snapshot.error}',
              onRetry: _refreshDiagnostics);
        }
        final data = snapshot.data!;
        final report = data.summary;
        final health = data.health;
        return RefreshIndicator(
          onRefresh: _refreshDiagnostics,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Text('System health',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 9),
              _metric(context, 'Studio database',
                  'Connected',
                  Icons.storage_rounded),
              const SizedBox(height: 8),
              _metric(context, 'Database schema', 'Fresh V1',
                  Icons.data_object_rounded),
              const SizedBox(height: 8),
              _metric(context, 'Managed storage', _size(health.totalManagedBytes),
                  Icons.folder_open_rounded),
              const SizedBox(height: 8),
              _metric(context, 'Media records',
                  health.registeredMediaCount.toString(),
                  Icons.perm_media_outlined),
              const SizedBox(height: 8),
              _metric(context, 'Healthy media',
                  health.healthyMediaCount.toString(),
                  Icons.verified_outlined),
              const SizedBox(height: 8),
              _metric(context, 'Missing media files',
                  health.missingMediaIds.length.toString(),
                  Icons.link_off_rounded),
              if (health.unavailableMediaIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                _metric(context, 'Unavailable media records',
                    health.unavailableMediaIds.length.toString(),
                    Icons.warning_amber_rounded),
              ],
              if (health.missingMediaIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Missing media IDs: ${health.missingMediaIds.take(10).join(', ')}${health.missingMediaIds.length > 10 ? '…' : ''}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text('Studio activity',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 9),
              _metric(context, 'Total media', report.media.toString(),
                  Icons.perm_media_rounded),
              const SizedBox(height: 8),
              _metric(context, 'Fingerprints', report.fingerprints.toString(),
                  Icons.fingerprint_rounded),
              const SizedBox(height: 8),
              _metric(context, 'Catalogue tracks', report.tracks.toString(),
                  Icons.library_music_rounded),
              const SizedBox(height: 8),
              _metric(context, 'Rights claims & licences',
                  '${report.licenses} licences',
                  Icons.gavel_rounded),
              const SizedBox(height: 8),
              _metric(context, 'Active processing jobs',
                  report.pendingJobs.toString(),
                  Icons.pending_actions_rounded),
              const SizedBox(height: 8),
              _metric(context, 'Failed processing jobs',
                  report.failedJobs.toString(),
                  Icons.error_outline_rounded),
            ],
          ),
        );
      },
    );
  }

  Widget _queueTab() {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: _jobs,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _errorState('Queue could not be loaded: ${snapshot.error}',
              onRetry: _refreshJobs);
        }
        final jobs = snapshot.data ?? const [];
        if (jobs.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refreshJobs,
            child: ListView(
              children: const [
                SizedBox(height: 130),
                Icon(Icons.task_alt_rounded, size: 48),
                SizedBox(height: 12),
                Center(child: Text('No processing jobs yet')),
                SizedBox(height: 5),
                Center(child: Text('Studio processing activity will appear here.')),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refreshJobs,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: jobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final job = jobs[index];
              final status = job['status'].toString();
              final progress = (job['progress'] as num?)?.toDouble() ?? 0;
              final canRetry = status == 'failed';
              final canCancel = {'pending', 'queued', 'running'}.contains(status);
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              job['job_type'].toString().replaceAll('_', ' '),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          PopupMenuButton<String>(
                            enabled: canRetry || canCancel,
                            onSelected: (value) => _runJobAction(job,
                                retry: value == 'retry'),
                            itemBuilder: (_) => [
                              if (canRetry)
                                const PopupMenuItem(
                                  value: 'retry',
                                  child: Text('Return to queue'),
                                ),
                              if (canCancel)
                                const PopupMenuItem(
                                  value: 'cancel',
                                  child: Text('Mark cancelled'),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        '${job['target_type'] ?? 'Task'}: ${job['target_id'] ?? job['id']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(context, status)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                color: _statusColor(context, status),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text('Attempt ${job['attempts'] ?? 0}',
                              style: Theme.of(context).textTheme.bodySmall),
                          const Spacer(),
                          Text('${progress.toStringAsFixed(0)}%',
                              style: Theme.of(context).textTheme.labelMedium),
                        ],
                      ),
                      if (status == 'running' || progress > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress / 100),
                      ],
                      if ((job['error_message'] as String?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Text(
                          job['error_message'].toString(),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        'Updated: ${job['updated_at']}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _errorState(String message, {required Future<void> Function() onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Diagnostics {
  const _Diagnostics(this.summary, this.health);

  final StudioReportSummary summary;
  final StudioStorageHealthReport health;
}
