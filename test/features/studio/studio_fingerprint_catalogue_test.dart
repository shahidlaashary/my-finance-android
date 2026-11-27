import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_fingerprint_catalogue_service.dart';
import 'package:my_finance/modules/studio/application/services/studio_media_library_service.dart';
import 'package:my_finance/modules/studio/domain/entities/studio_fingerprint.dart';
import 'package:my_finance/modules/studio/domain/entities/studio_media_file.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:my_finance/modules/studio/infrastructure/repositories/sqlite_studio_fingerprint_repository.dart';
import 'package:my_finance/modules/studio/infrastructure/repositories/sqlite_studio_media_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late StudioMediaLibraryService mediaLibrary;
  late StudioFingerprintCatalogueService fingerprints;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    mediaLibrary = StudioMediaLibraryService(
      repository: SqliteStudioMediaRepository(database),
    );
    fingerprints = StudioFingerprintCatalogueService(
      repository: SqliteStudioFingerprintRepository(database),
      mediaLibrary: mediaLibrary,
    );
    await mediaLibrary.register(_media());
  });

  tearDown(() async {
    await database.close();
  });

  test('registers and retrieves a fingerprint artifact', () async {
    await fingerprints.register(_fingerprint());

    final stored = await fingerprints.getById('fp-audio-1');

    expect(stored, isNotNull);
    expect(stored!.mediaFileId, 'media-audio-1');
    expect(stored.algorithmKey, 'studio.audio.chromaprint-like');
    expect(stored.frameCount, 420);
  });

  test('prevents duplicate algorithm versions for one media file', () async {
    await fingerprints.register(_fingerprint());

    await expectLater(
      fingerprints.register(_fingerprint(id: 'fp-audio-duplicate')),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('stores ordered segment metadata and replaces it atomically', () async {
    await fingerprints.register(_fingerprint());
    final segments = [
      _segment(index: 0, start: 0, end: 10000, offset: 0),
      _segment(index: 1, start: 10000, end: 20000, offset: 512),
    ];

    await fingerprints.replaceSegments('fp-audio-1', segments);
    final stored = await fingerprints.getSegments('fp-audio-1');

    expect(stored, hasLength(2));
    expect(stored.map((item) => item.segmentIndex), [0, 1]);
    expect(stored.last.dataOffsetBytes, 512);
  });

  test('rejects unsorted or invalid segment metadata', () async {
    await fingerprints.register(_fingerprint());

    await expectLater(
      fingerprints.replaceSegments('fp-audio-1', [
        _segment(index: 0, start: 10000, end: 20000, offset: 0),
        _segment(index: 1, start: 0, end: 10000, offset: 512),
      ]),
      throwsArgumentError,
    );
  });

  test('requires the fingerprint media type to match its source', () async {
    await expectLater(
      fingerprints.register(_fingerprint(mediaType: StudioMediaType.video)),
      throwsArgumentError,
    );
  });

  test('updates fingerprint processing status', () async {
    await fingerprints.register(_fingerprint());
    await fingerprints.updateStatus('fp-audio-1', StudioFingerprintStatus.indexed);

    expect(
      (await fingerprints.getById('fp-audio-1'))!.status,
      StudioFingerprintStatus.indexed,
    );
  });
}

StudioMediaFile _media() {
  final now = DateTime.utc(2026, 11, 28);
  return StudioMediaFile(
    id: 'media-audio-1',
    mediaType: StudioMediaType.audio,
    originalName: 'reference.wav',
    storagePath: '/studio/audio/reference.wav',
    mimeType: 'audio/wav',
    fileExtension: 'wav',
    fileSizeBytes: 4096,
    durationMs: 30000,
    checksumSha256: 'source-checksum',
    importStatus: StudioMediaImportStatus.imported,
    createdAt: now,
    updatedAt: now,
  );
}

StudioFingerprint _fingerprint({
  String id = 'fp-audio-1',
  StudioMediaType mediaType = StudioMediaType.audio,
}) {
  final now = DateTime.utc(2026, 11, 28);
  return StudioFingerprint(
    id: id,
    mediaFileId: 'media-audio-1',
    mediaType: mediaType,
    algorithmKey: 'studio.audio.chromaprint-like',
    algorithmVersion: '1.0.0',
    fingerprintFormat: 'binary-v1',
    dataFilePath: '/studio/fingerprints/$id.bin',
    checksumSha256: 'fingerprint-checksum',
    sampleRate: mediaType == StudioMediaType.audio ? 11025 : null,
    channels: mediaType == StudioMediaType.audio ? 1 : null,
    durationMs: 30000,
    frameCount: 420,
    status: StudioFingerprintStatus.generated,
    createdAt: now,
    updatedAt: now,
  );
}

StudioFingerprintSegment _segment({
  required int index,
  required int start,
  required int end,
  required int offset,
}) {
  return StudioFingerprintSegment(
    fingerprintId: 'fp-audio-1',
    segmentIndex: index,
    startMs: start,
    endMs: end,
    dataOffsetBytes: offset,
    dataLengthBytes: 512,
    signatureHash: 'segment-$index',
  );
}
