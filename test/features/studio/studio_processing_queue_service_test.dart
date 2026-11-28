import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_audio_match_service.dart';
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

  test('returns a clean result for an empty library batch', () async {
    final progress = <(int, int)>[];
    final result = await queue.runLibraryBatch(
      onProgress: (completed, total) => progress.add((completed, total)),
    );

    expect(result.total, 0);
    expect(result.succeeded, 0);
    expect(result.failed, 0);
    expect(result.processed, 0);
    expect(result.cancelled, isFalse);
    expect(progress, [(0, 0)]);
    expect(await queue.jobs(), isEmpty);
  });

  test('stops a library batch when cancellation is requested mid-batch', () async {
    final now = DateTime.utc(2026, 11, 28).toIso8601String();
    for (final id in ['media-1', 'media-2']) {
      await database.insert('studio_media_files', {
        'id': id,
        'media_type': 'audio',
        'original_name': '$id.wav',
        'storage_path': '/studio/audio/$id.wav',
        'mime_type': 'audio/wav',
        'file_extension': 'wav',
        'file_size_bytes': 100,
        'duration_ms': 1000,
        'checksum_sha256': 'checksum-$id',
        'import_status': 'imported',
        'created_at': now,
        'updated_at': now,
      });
      await database.insert('studio_fingerprints', {
        'id': 'fp-$id',
        'media_file_id': id,
        'media_type': 'audio',
        'algorithm_key': StudioAudioMatchService.algorithmKey,
        'algorithm_version': StudioAudioMatchService.algorithmVersion,
        'fingerprint_format': 'binary-v1',
        'data_file_path': '/studio/fingerprints/fp-$id.bin',
        'checksum_sha256': 'fingerprint-$id',
        'sample_rate': 11025,
        'channels': 1,
        'duration_ms': 1000,
        'frame_count': 10,
        'status': 'generated',
        'created_at': now,
        'updated_at': now,
      });
    }

    var cancelRequested = false;
    final progress = <(int, int)>[];
    final result = await queue.runLibraryBatch(
      shouldCancel: () => cancelRequested,
      onProgress: (completed, total) {
        progress.add((completed, total));
        if (completed == 1) cancelRequested = true;
      },
    );

    expect(result.total, 2);
    expect(result.processed, 1);
    expect(result.alreadyFingerprinted, 1);
    expect(result.succeeded, 0);
    expect(result.failed, 0);
    expect(result.cancelled, isTrue);
    expect(progress, [(0, 2), (1, 2)]);
  });

  test('rejects unsupported media types before creating a job', () async {
    await expectLater(
      queue.runFingerprintJob(mediaId: 'media-1', mediaType: 'image'),
      throwsArgumentError,
    );
    expect(await queue.jobs(), isEmpty);
  });
}
