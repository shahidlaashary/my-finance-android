import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_media_library_service.dart';
import 'package:my_finance/modules/studio/domain/entities/studio_media_file.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:my_finance/modules/studio/infrastructure/repositories/sqlite_studio_media_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late StudioMediaLibraryService service;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    service = StudioMediaLibraryService(
      repository: SqliteStudioMediaRepository(database),
    );
  });

  tearDown(() async {
    await database.close();
  });

  StudioMediaFile media({
    String id = 'media-1',
    StudioMediaType type = StudioMediaType.audio,
    String name = 'sample-track.wav',
  }) {
    final now = DateTime.utc(2026, 11, 28);
    return StudioMediaFile(
      id: id,
      mediaType: type,
      originalName: name,
      storagePath: '/studio/media/$id',
      mimeType: type == StudioMediaType.audio ? 'audio/wav' : 'video/mp4',
      fileExtension: type == StudioMediaType.audio ? 'wav' : 'mp4',
      fileSizeBytes: 1024,
      durationMs: 12000,
      checksumSha256: 'checksum-$id',
      importStatus: StudioMediaImportStatus.imported,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('registers and retrieves media metadata', () async {
    await service.register(media());

    final stored = await service.getById('media-1');

    expect(stored, isNotNull);
    expect(stored!.originalName, 'sample-track.wav');
    expect(stored.mediaType, StudioMediaType.audio);
    expect(stored.fileSizeBytes, 1024);
  });

  test('browses by media type and filename search', () async {
    await service.register(media());
    await service.register(
      media(
        id: 'media-2',
        type: StudioMediaType.video,
        name: 'sample-video.mp4',
      ),
    );

    final audio = await service.browse(mediaType: StudioMediaType.audio);
    final matchingName = await service.browse(search: 'video');

    expect(audio.map((item) => item.id), ['media-1']);
    expect(matchingName.map((item) => item.id), ['media-2']);
  });

  test('updates import status and removes only the catalogue record', () async {
    await service.register(media());

    await service.markImportStatus(
      'media-1',
      StudioMediaImportStatus.missing,
    );
    expect(
      (await service.getById('media-1'))!.importStatus,
      StudioMediaImportStatus.missing,
    );

    await service.removeRecord('media-1');
    expect(await service.getById('media-1'), isNull);
  });

  test('rejects invalid pagination', () async {
    await expectLater(
      service.browse(limit: 0),
      throwsArgumentError,
    );
    await expectLater(
      service.browse(offset: -1),
      throwsArgumentError,
    );
  });
}
