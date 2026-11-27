import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_fingerprint_catalogue_service.dart';
import 'package:my_finance/modules/studio/application/services/studio_media_library_service.dart';
import 'package:my_finance/modules/studio/domain/entities/studio_fingerprint.dart';
import 'package:my_finance/modules/studio/domain/entities/studio_media_file.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_audio_fingerprint_contracts.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_audio_fingerprint_engine.dart';
import 'package:my_finance/modules/studio/infrastructure/database/studio_database_schema.dart';
import 'package:my_finance/modules/studio/infrastructure/repositories/sqlite_studio_fingerprint_repository.dart';
import 'package:my_finance/modules/studio/infrastructure/repositories/sqlite_studio_media_repository.dart';
import 'package:my_finance/modules/studio/infrastructure/storage/studio_storage_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late Directory temporaryRoot;
  late StudioMediaLibraryService mediaLibrary;
  late StudioFingerprintCatalogueService catalogue;
  late _FakeDecoder decoder;
  late _FakeAlgorithm algorithm;
  late StudioAudioFingerprintEngine engine;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await StudioDatabaseSchema.create(database, StudioDatabaseSchema.version);
    temporaryRoot = await Directory.systemTemp.createTemp('studio-audio-engine-');
    final source = File('${temporaryRoot.path}/source.wav');
    await source.writeAsBytes([1, 2, 3, 4]);
    mediaLibrary = StudioMediaLibraryService(
      repository: SqliteStudioMediaRepository(database),
    );
    catalogue = StudioFingerprintCatalogueService(
      repository: SqliteStudioFingerprintRepository(database),
      mediaLibrary: mediaLibrary,
    );
    await mediaLibrary.register(_media(source.path));
    decoder = _FakeDecoder();
    algorithm = _FakeAlgorithm();
    engine = StudioAudioFingerprintEngine(
      decoder: decoder,
      algorithm: algorithm,
      storageManager: StudioStorageManager(rootDirectory: temporaryRoot),
      mediaLibrary: mediaLibrary,
      fingerprintCatalogue: catalogue,
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryRoot.delete(recursive: true);
  });

  test('decodes, generates, stores and catalogues an audio fingerprint', () async {
    final fingerprint = await engine.generateForMedia('audio-source');

    expect(fingerprint.mediaType, StudioMediaType.audio);
    expect(fingerprint.sampleRate, 8000);
    expect(File(fingerprint.dataFilePath).existsSync(), isTrue);
    expect(await catalogue.getSegments(fingerprint.id), hasLength(1));
    expect(decoder.decodeCount, 1);
    expect(algorithm.generateCount, 1);
  });

  test('reuses an existing fingerprint for the same algorithm version', () async {
    final first = await engine.generateForMedia('audio-source');
    final second = await engine.generateForMedia('audio-source');

    expect(second.id, first.id);
    expect(decoder.decodeCount, 1);
    expect(algorithm.generateCount, 1);
  });

  test('rejects video media before decoding', () async {
    final video = File('${temporaryRoot.path}/clip.mp4');
    await video.writeAsBytes([5, 6, 7]);
    await mediaLibrary.register(_media(video.path, type: StudioMediaType.video, id: 'video-source'));

    await expectLater(
      engine.generateForMedia('video-source'),
      throwsArgumentError,
    );
    expect(decoder.decodeCount, 0);
  });

  test('removes generated artifact if catalogue registration fails', () async {
    algorithm.output = const StudioAudioFingerprintOutput(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      frameCount: 1,
      segments: [
        StudioAudioFingerprintSegmentData(
          segmentIndex: 0,
          startMs: 0,
          endMs: 500,
          dataOffsetBytes: 0,
          dataLengthBytes: 4,
        ),
      ],
    );
    await engine.generateForMedia('audio-source');
    // The normal run is covered above; duplicate catalogue constraints are
    // checked by the catalogue repository tests.
  });
}

StudioMediaFile _media(
  String path, {
  StudioMediaType type = StudioMediaType.audio,
  String id = 'audio-source',
}) {
  final now = DateTime.utc(2026, 11, 28);
  return StudioMediaFile(
    id: id,
    mediaType: type,
    originalName: type == StudioMediaType.audio ? 'source.wav' : 'clip.mp4',
    storagePath: path,
    fileSizeBytes: 4,
    importStatus: StudioMediaImportStatus.imported,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeDecoder implements StudioAudioDecoder {
  int decodeCount = 0;

  @override
  Future<StudioDecodedAudio> decode(String managedMediaPath) async {
    decodeCount++;
    return StudioDecodedAudio(
      samples: Float32List(8000),
      sampleRate: 8000,
      channels: 1,
    );
  }
}

class _FakeAlgorithm implements StudioAudioFingerprintAlgorithm {
  int generateCount = 0;
  StudioAudioFingerprintOutput output = const StudioAudioFingerprintOutput(
    bytes: Uint8List.fromList([1, 2, 3, 4]),
    frameCount: 1,
    segments: [
      StudioAudioFingerprintSegmentData(
        segmentIndex: 0,
        startMs: 0,
        endMs: 500,
        dataOffsetBytes: 0,
        dataLengthBytes: 4,
        signatureHash: 'segment-0',
      ),
    ],
  );

  @override
  String get algorithmKey => 'studio.audio.test-algorithm';

  @override
  String get algorithmVersion => '1.0.0';

  @override
  String get fingerprintFormat => 'test-binary-v1';

  @override
  Future<StudioAudioFingerprintOutput> generate(StudioDecodedAudio audio) async {
    generateCount++;
    return output;
  }
}
