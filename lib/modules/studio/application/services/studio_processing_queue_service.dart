import 'package:sqflite/sqflite.dart';

import '../../infrastructure/database/studio_database_manager.dart';
import 'studio_audio_match_service.dart';
import 'studio_visual_match_service.dart';

/// Read/write boundary for the Studio processing queue.
///
/// Executes the supported fingerprint jobs and persists their lifecycle.
class StudioProcessingQueueService {
  StudioProcessingQueueService({Database? database}) : _database = database;

  final Database? _database;

  Future<Database> get _db async =>
      _database ?? await StudioDatabaseManager.instance.initialize();

  Future<List<Map<String, Object?>>> jobs({String? status, int limit = 100}) async {
    final db = await _db;
    return db.query(
      'studio_processing_jobs',
      where: status == null ? null : 'status = ?',
      whereArgs: status == null ? null : [status],
      orderBy: "CASE status WHEN 'running' THEN 0 WHEN 'queued' THEN 1 WHEN 'pending' THEN 2 WHEN 'failed' THEN 3 ELSE 4 END, created_at DESC",
      limit: limit,
    );
  }

  Future<int> count({required List<String> statuses}) async {
    if (statuses.isEmpty) return 0;
    final db = await _db;
    final placeholders = List.filled(statuses.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM studio_processing_jobs WHERE status IN ($placeholders)',
      statuses,
    );
    return (rows.first['total'] as num).toInt();
  }

  Future<void> runFingerprintJob({required String mediaId, required String mediaType}) async {
    if (mediaType != 'audio' && mediaType != 'video') {
      throw ArgumentError('Unsupported fingerprint media type.');
    }
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = 'job_${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('studio_processing_jobs', {
      'id': id,
      'job_type': mediaType == 'audio' ? 'audio_fingerprint' : 'video_fingerprint',
      'target_type': 'media',
      'target_id': mediaId,
      'status': 'queued',
      'progress': 0,
      'attempts': 0,
      'created_at': now,
      'updated_at': now,
    });
    await _execute(id);
    final rows = await db.query('studio_processing_jobs', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      throw StateError('Fingerprint job disappeared before completion.');
    }
    final finalStatus = rows.first['status']?.toString();
    if (finalStatus != 'completed') {
      if (finalStatus == 'failed') {
        throw StateError(
          rows.first['error_message']?.toString() ?? 'Fingerprint job failed.',
        );
      }
      throw StateError('Fingerprint job did not complete (status: $finalStatus).');
    }
  }

  /// Fingerprints every imported audio/video item in library order.
  /// Each item gets its own persisted job so failures remain independently
  /// retryable and the caller receives progress as work completes.
  Future<StudioLibraryBatchResult> runLibraryBatch({
    void Function(int completed, int total)? onProgress,
  }) async {
    final db = await _db;
    final media = await db.query(
      'studio_media_files',
      columns: ['id', 'media_type'],
      orderBy: 'created_at ASC',
    );
    var completed = 0;
    var succeeded = 0;
    var failed = 0;
    var alreadyFingerprinted = 0;
    onProgress?.call(0, media.length);
    for (final item in media) {
      final id = item['id']?.toString();
      final type = item['media_type']?.toString();
      try {
        if (id == null || id.isEmpty || (type != 'audio' && type != 'video')) {
          throw StateError('Library item has invalid media metadata.');
        }
        final algorithmKey = type == 'audio'
            ? StudioAudioMatchService.algorithmKey
            : StudioVisualMatchService.algorithmKey;
        final algorithmVersion = type == 'audio'
            ? StudioAudioMatchService.algorithmVersion
            : StudioVisualMatchService.algorithmVersion;
        final existing = await db.query(
          'studio_fingerprints',
          columns: ['id'],
          where: 'media_file_id = ? AND algorithm_key = ? AND algorithm_version = ? AND status IN (?, ?)',
          whereArgs: [id, algorithmKey, algorithmVersion, 'generated', 'indexed'],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          alreadyFingerprinted++;
        } else {
          await runFingerprintJob(mediaId: id, mediaType: type!);
          succeeded++;
        }
      } catch (_) {
        failed++;
      } finally {
        completed++;
        onProgress?.call(completed, media.length);
      }
    }
    return StudioLibraryBatchResult(
      total: media.length,
      succeeded: succeeded,
      failed: failed,
      alreadyFingerprinted: alreadyFingerprinted,
    );
  }

  Future<void> _execute(String id) async {
    final db = await _db;
    final rows = await db.query('studio_processing_jobs', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw ArgumentError('Processing job not found.');
    final job = rows.first;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update('studio_processing_jobs', {
      'status': 'running', 'progress': 5,
      'attempts': (job['attempts'] as num? ?? 0).toInt() + 1,
      'started_at': now, 'completed_at': null, 'error_message': null,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [id]);
    try {
      final targetId = job['target_id']?.toString();
      if (targetId == null || targetId.isEmpty) throw StateError('Job target is missing.');
      switch (job['job_type']) {
        case 'audio_fingerprint':
          await StudioAudioMatchService().identify(targetId);
          break;
        case 'video_fingerprint':
          await StudioVisualMatchService().fingerprint(targetId);
          break;
        default:
          throw StateError('No worker is registered for ${job['job_type']}.');
      }
      // Make the final transition atomic with cancellation. A cancel request
      // that commits first must never be overwritten by this completion write.
      await db.transaction((txn) async {
        final current = await txn.query(
          'studio_processing_jobs',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (current.isEmpty || current.first['status'] == 'cancelled') return;
        final finished = DateTime.now().toUtc().toIso8601String();
        await txn.update(
          'studio_processing_jobs',
          {
            'status': 'completed',
            'progress': 100,
            'completed_at': finished,
            'updated_at': finished,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    } catch (error) {
      final failed = DateTime.now().toUtc().toIso8601String();
      // A user may mark a running job as cancelled while the native decoder
      // is still executing. Preserve that explicit cancellation if the native
      // operation subsequently throws instead of overwriting it as "failed".
      await db.transaction((txn) async {
        final current = await txn.query(
          'studio_processing_jobs',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (current.isEmpty || current.first['status'] == 'cancelled') return;
        await txn.update(
          'studio_processing_jobs',
          {
            'status': 'failed',
            'error_message': error.toString(),
            'updated_at': failed,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    }
  }

  Future<void> retry(String id) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'studio_processing_jobs',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('Processing job not found.');
      if (rows.first['status'] != 'failed') {
        throw StateError('Only failed jobs can be retried.');
      }
      await txn.update(
        'studio_processing_jobs',
        {
          'status': 'queued',
          'progress': 0,
          'error_message': null,
          'started_at': null,
          'completed_at': null,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert('studio_activity_logs', {
        'event_type': 'processing_job_requeued',
        'entity_type': 'processing_job',
        'entity_id': id,
        'description': 'Failed processing job returned to the queue.',
        'created_at': now,
      });
    });
    await _execute(id);
  }

  /// Marks an unfinished job cancelled. This is a persisted queue-state
  /// transition; it does not interrupt a native operation already executing.
  Future<void> cancel(String id) async {
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'studio_processing_jobs',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw ArgumentError('Processing job not found.');
      final status = rows.first['status'] as String;
      if (!{'pending', 'queued', 'running'}.contains(status)) {
        throw StateError('Only unfinished jobs can be cancelled.');
      }
      await txn.update(
        'studio_processing_jobs',
        {'status': 'cancelled', 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.insert('studio_activity_logs', {
        'event_type': 'processing_job_cancelled',
        'entity_type': 'processing_job',
        'entity_id': id,
        'description': 'Processing job marked as cancelled.',
        'created_at': now,
      });
    });
  }
}

/// Outcome of a full-library fingerprint batch.
class StudioLibraryBatchResult {
  const StudioLibraryBatchResult({
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.alreadyFingerprinted,
  });

  final int total;
  final int succeeded;
  final int failed;
  final int alreadyFingerprinted;
}
