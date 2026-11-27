import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_media_import_service.dart';
import 'package:my_finance/modules/studio/application/services/studio_media_library_service.dart';
import 'package:my_finance/modules/studio/application/services/studio_storage_health_service.dart';
import 'package:my_finance/modules/studio/domain/entities/studio_media_file.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:my_finance/modules/studio/infrastructure/repositories/sqlite_studio_media_repository.dart';
import 'package:my_finance/modules/studio/infrastructure/storage/studio_storage_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late Directory temporaryDirectory;
  late StudioStorageManager storage;
  late StudioMediaLibraryService library;
  late StudioMediaImportService importer;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('studio_test_');
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    storage = StudioStorageManager(rootDirectory: temporaryDirectory);
    library = StudioMediaLibraryService(
      repository: SqliteStudioMediaRepository(database),
    );
    importer = StudioMediaImportService(
      storageManager: storage,
      mediaLibrary: library,
    );
  });

  tearDown(() async {
    await database.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('imports media into managed storage and registers SHA-256', () async {
    final source = File('${temporaryDirectory.path}/source-track.wav');
    await source.writeAsBytes([1, 2, 3, 4, 5]);

    final imported = await importer.importFile(
      sourcePath: source.path,
      mediaType: StudioMediaType.audio,
    );

    expect(imported.originalName, 'source-track.wav');
    expect(imported.fileSizeBytes, 5);
    expect(imported.checksumSha256, isNotEmpty);
    expect(await File(imported.storagePath).exists(), isTrue);
    expect(await library.getById(imported.id), isNotNull);
  });


  test('imports MP3 files as audio/mpeg managed media', () async {
    final source = File('${temporaryDirectory.path}/reference-track.mp3');
    await source.writeAsBytes([0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00]);
    final imported = await importer.importFile(
      sourcePath: source.path,
      mediaType: StudioMediaType.audio,
    );

    expect(imported.fileExtension, 'mp3');
    expect(imported.mimeType, 'audio/mpeg');
    expect(imported.mediaType, StudioMediaType.audio);
    expect(await File(imported.storagePath).exists(), isTrue);
  });

  test('rejects missing and empty source files', () async {
    await expectLater(
      importer.importFile(
        sourcePath: '${temporaryDirectory.path}/missing.mp4',
        mediaType: StudioMediaType.video,
      ),
      throwsA(isA<FileSystemException>()),
    );

    final empty = File('${temporaryDirectory.path}/empty.mp4');
    await empty.create();
    await expectLater(
      importer.importFile(
        sourcePath: empty.path,
        mediaType: StudioMediaType.video,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('storage health reports deleted managed media', () async {
    final source = File('${temporaryDirectory.path}/source.mp3');
    await source.writeAsBytes([9, 8, 7]);
    final imported = await importer.importFile(
      sourcePath: source.path,
      mediaType: StudioMediaType.audio,
    );

    await File(imported.storagePath).delete();
    final report = await StudioStorageHealthService(
      storageManager: storage,
      mediaLibrary: library,
    ).inspect();

    expect(report.registeredMediaCount, 1);
    expect(report.missingMediaIds, [imported.id]);
  });

  test('refuses to delete files outside Studio storage', () async {
    final outside = File('${temporaryDirectory.path}/outside.txt');
    await outside.writeAsString('keep');
    await expectLater(
      storage.deleteManagedFile(outside.path),
      throwsArgumentError,
    );
    expect(await outside.exists(), isTrue);
  });
}
