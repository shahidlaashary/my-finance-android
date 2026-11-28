import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_processing_queue_service.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late StudioProcessingQueueService queue;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    queue = StudioProcessingQueueService(database: database);
  });

  tearDown(() async => database.close());

  Future<void> addJob(String id, String status, {String type = 'audio_fingerprint'}) async {
    final now = DateTime.utc(2026, 11, 28).toIso8601String();
    await database.insert('studio_processing_jobs', {
      'id': id,
      'job_type': type,
      'target_type': 'media',
      'target_id': 'media-$id',
      'status': status,
      'progress': 0,
      'attempts': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<Map<String, Object?>> job(String id) async {
    final rows = await database.query(
      'studio_processing_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.single;
  }

  test('lists jobs by status and counts requested statuses', () async {
    await addJob('queued-1', 'queued');
    await addJob('failed-1', 'failed');
    await addJob('done-1', 'completed');

    expect((await queue.jobs(status: 'queued')).map((row) => row['id']), ['queued-1']);
    expect(await queue.count(statuses: ['queued', 'failed']), 2);
    expect(await queue.count(statuses: []), 0);
  });

  test('cancels an unfinished job and records an activity event', () async {
    await addJob('queued-1', 'queued');

    await queue.cancel('queued-1');

    expect((await job('queued-1'))['status'], 'cancelled');
    final events = await database.query(
      'studio_activity_logs',
      where: 'entity_id = ?',
      whereArgs: ['queued-1'],
    );
    expect(events, hasLength(1));
    expect(events.single['event_type'], 'processing_job_cancelled');
  });

  test('does not cancel a completed job', () async {
    await addJob('done-1', 'completed');

    await expectLater(queue.cancel('done-1'), throwsA(isA<StateError>()));
    expect((await job('done-1'))['status'], 'completed');
  });

  test('rejects cancellation for an unknown job', () async {
    await expectLater(queue.cancel('missing'), throwsArgumentError);
  });

  test('retry accepts only failed jobs', () async {
    await addJob('queued-1', 'queued');

    await expectLater(queue.retry('queued-1'), throwsA(isA<StateError>()));
    expect((await job('queued-1'))['status'], 'queued');
  });

  test('retry increments attempts and preserves a new worker failure', () async {
    await addJob('failed-1', 'failed', type: 'unregistered_worker');

    await queue.retry('failed-1');

    final saved = await job('failed-1');
    expect(saved['status'], 'failed');
    expect(saved['attempts'], 1);
    expect(saved['error_message'], contains('No worker is registered'));
    final events = await database.query(
      'studio_activity_logs',
      where: 'entity_id = ?',
      whereArgs: ['failed-1'],
    );
    expect(events, hasLength(1));
    expect(events.single['event_type'], 'processing_job_requeued');
  });

  test('rejects unsupported media types before creating a job', () async {
    await expectLater(
      queue.runFingerprintJob(mediaId: 'media-1', mediaType: 'image'),
      throwsArgumentError,
    );
    expect(await queue.jobs(), isEmpty);
  });
}
