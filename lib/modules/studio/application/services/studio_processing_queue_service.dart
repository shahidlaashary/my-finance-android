import 'package:sqflite/sqflite.dart';

import '../../infrastructure/database/studio_database_manager.dart';

/// Read/write boundary for the Studio processing queue.
///
/// Retrying a failed job returns it to the queued state. A worker must claim
/// queued jobs before doing work; this service never pretends that a retry has
/// already executed.
class StudioProcessingQueueService {
  Future<Database> get _db => StudioDatabaseManager.instance.initialize();

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
