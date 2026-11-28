import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_catalogue_rights_service.dart';
import 'package:my_finance/modules/studio/application/services/studio_media_library_service.dart';
import 'package:my_finance/modules/studio/application/services/studio_visual_match_service.dart';
import 'package:my_finance/modules/studio/domain/entities/studio_media_file.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:my_finance/modules/studio/infrastructure/repositories/sqlite_studio_media_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late StudioVisualMatchService service;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    service = StudioVisualMatchService(
      mediaLibrary: StudioMediaLibraryService(
        repository: SqliteStudioMediaRepository(database),
      ),
      catalogueRights: StudioCatalogueRightsService(
        databaseProvider: () async => database,
      ),
    );
  });

  tearDown(() async => database.close());

  StudioMediaFile media({
    required String id,
    required String name,
    required StudioMediaType type,
  }) {
    final now = DateTime.utc(2026, 11, 28);
    return StudioMediaFile(
      id: id,
      mediaType: type,
      originalName: name,
      storagePath: '/studio/media/$id',
      mimeType: type == StudioMediaType.video ? 'video/mp4' : 'audio/mpeg',
      fileExtension: type == StudioMediaType.video ? 'mp4' : 'mp3',
      fileSizeBytes: 100,
      importStatus: StudioMediaImportStatus.imported,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('returns only video media, excluding audio records', () async {
    final library = service.mediaLibrary;
    await library.register(media(
      id: 'video-1',
      name: 'clip.mp4',
      type: StudioMediaType.video,
    ));
    await library.register(media(
      id: 'audio-1',
      name: 'track.mp3',
      type: StudioMediaType.audio,
    ));

    final videos = await service.videos();

    expect(videos.map((item) => item.id), ['video-1']);
    expect(videos.every((item) => item.mediaType == StudioMediaType.video), isTrue);
  });

  test('returns video files in the media library ordering', () async {
    final library = service.mediaLibrary;
    await library.register(media(
      id: 'video-old',
      name: 'zeta.mp4',
      type: StudioMediaType.video,
    ));
    await library.register(media(
      id: 'video-new',
      name: 'alpha.mp4',
      type: StudioMediaType.video,
    ));

    final videos = await service.videos();

    expect(videos, hasLength(2));
    // Both records share the same timestamp, so the repository's stable
    // secondary ordering is ID ascending.
    expect(videos.map((item) => item.id), ['video-new', 'video-old']);
  });

  test('rejects scan IDs not present in the library', () async {
    expect(service.scanMatches('missing-video'), throwsArgumentError);
  });

  test('returns an empty list when no videos are registered', () async {
    expect(await service.videos(), isEmpty);
  });

  test('uses the injected catalogue-rights service for comparison history', () async {
    expect(await service.history(), isEmpty);
  });
}
