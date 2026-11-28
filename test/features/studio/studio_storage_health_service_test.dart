import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_fingerprint_catalogue_service.dart';
import 'package:my_finance/modules/studio/application/services/studio_media_library_service.dart';
import 'package:my_finance/modules/studio/application/services/studio_storage_health_service.dart';
import 'package:my_finance/modules/studio/domain/entities/studio_fingerprint.dart';
import 'package:my_finance/modules/studio/domain/entities/studio_media_file.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:my_finance/modules/studio/infrastructure/repositories/sqlite_studio_fingerprint_repository.dart';
import 'package:my_finance/modules/studio/infrastructure/repositories/sqlite_studio_media_repository.dart';
import 'package:my_finance/modules/studio/infrastructure/storage/studio_storage_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory sandbox;
  late Database database;
  late StudioStorageManager storage;
  late StudioMediaLibraryService mediaLibrary;
  late StudioFingerprintCatalogueService fingerprints;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('studio_storage_health_');
    storage = StudioStorageManager(rootDirectory: sandbox);
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    mediaLibrary = StudioMediaLibraryService(
      repository: SqliteStudioMediaRepository(database),
    );
    fingerprints = StudioFingerprintCatalogueService(
      repository: SqliteStudioFingerprintRepository(database),
      mediaLibrary: mediaLibrary,
    );
  });

  tearDown(() async {
    await database.close();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('reports missing media and fingerprint artifacts and orphan files', () async {
    final mediaFile = await storage.allocateMediaFile(id: 'media-1', extension: 'wav', isVideo: false);
    await mediaFile.writeAsBytes([1, 2, 3]);
    await mediaLibrary.register(_media(id: 'media-1', path: mediaFile.path));
    await mediaLibrary.register(_media(id: 'media-missing', path: '${sandbox.path}/studio/audio/missing.wav'));

    final existingArtifact = await storage.allocateFingerprintFile(fingerprintId: 'fp-existing', extension: 'bin');
    await existingArtifact.writeAsBytes([4, 5, 6]);
    final orphanArtifact = await storage.allocateFingerprintFile(fingerprintId: 'orphan-file', extension: 'bin');
    await orphanArtifact.writeAsBytes([7, 8, 9]);

    await fingerprints.register(_fingerprint(id: 'fp-existing', mediaId: 'media-1', path: existingArtifact.path));
    await fingerprints.register(_fingerprint(id: 'fp-missing', mediaId: 'media-1', path: '${sandbox.path}/studio/fingerprints/missing.bin', algorithmVersion: '2.0.0'));

    final report = await StudioStorageHealthService(storageManager: storage, mediaLibrary: mediaLibrary, fingerprintCatalogue: fingerprints).inspect();

    expect(report.registeredMediaCount, 2);
    expect(report.missingMediaIds, ['media-missing']);
    expect(report.registeredFingerprintCount, 2);
    expect(report.missingFingerprintIds, ['fp-missing']);
    expect(report.healthyFingerprintCount, 1);
    expect(report.orphanedFingerprintArtifactPaths, [orphanArtifact.path]);
  });

  test('reports a clean fingerprint store when every artifact is registered', () async {
    final mediaFile = await storage.allocateMediaFile(id: 'media-1', extension: 'wav', isVideo: false);
    await mediaFile.writeAsBytes([1]);
    await mediaLibrary.register(_media(id: 'media-1', path: mediaFile.path));
    final artifact = await storage.allocateFingerprintFile(fingerprintId: 'fp-1', extension: 'bin');
    await artifact.writeAsBytes([2]);
    await fingerprints.register(_fingerprint(id: 'fp-1', mediaId: 'media-1', path: artifact.path));

    final report = await StudioStorageHealthService(storageManager: storage, mediaLibrary: mediaLibrary, fingerprintCatalogue: fingerprints).inspect();

    expect(report.missingFingerprintIds, isEmpty);
    expect(report.orphanedFingerprintArtifactPaths, isEmpty);
    expect(report.healthyFingerprintCount, 1);
  });
}

StudioMediaFile _media({required String id, required String path}) {
  final now = DateTime.utc(2026, 11, 28);
  return StudioMediaFile(
    id: id,
    mediaType: StudioMediaType.audio,
    originalName: '$id.wav',
    storagePath: path,
    mimeType: 'audio/wav',
    fileExtension: 'wav',
    fileSizeBytes: 3,
    durationMs: 30000,
    checksumSha256: 'source-$id',
    importStatus: StudioMediaImportStatus.imported,
    createdAt: now,
    updatedAt: now,
  );
}

StudioFingerprint _fingerprint({required String id, required String mediaId, required String path, String algorithmVersion = '1.0.0'}) {
  final now = DateTime.utc(2026, 11, 28);
  return StudioFingerprint(
    id: id,
    mediaFileId: mediaId,
    mediaType: StudioMediaType.audio,
    algorithmKey: 'studio.audio.chromaprint-like',
    algorithmVersion: algorithmVersion,
    fingerprintFormat: 'binary-v1',
    dataFilePath: path,
    checksumSha256: 'fingerprint-$id',
    sampleRate: 11025,
    channels: 1,
    durationMs: 30000,
    frameCount: 420,
    status: StudioFingerprintStatus.generated,
    createdAt: now,
    updatedAt: now,
  );
}
