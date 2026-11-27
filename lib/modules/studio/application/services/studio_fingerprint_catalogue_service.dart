import '../../domain/entities/studio_fingerprint.dart';
import '../../domain/entities/studio_media_file.dart';
import '../../domain/repositories/studio_fingerprint_repository.dart';
import '../../infrastructure/database/studio_database_manager.dart';
import '../../infrastructure/repositories/sqlite_studio_fingerprint_repository.dart';

/// Application boundary for fingerprint metadata and segment indexing.
///
/// This service does not decode media or calculate fingerprints. Dedicated
/// audio/video engines will produce artifacts and call this catalogue service.
class StudioFingerprintCatalogueService {
  StudioFingerprintCatalogueService({
    StudioFingerprintRepository? repository,
  }) : _repository = repository;

  final StudioFingerprintRepository? _repository;

  Future<StudioFingerprintRepository> get _readyRepository async {
    final supplied = _repository;
    if (supplied != null) return supplied;

    final database = await StudioDatabaseManager.instance.initialize();
    return SqliteStudioFingerprintRepository(database);
  }

  Future<void> register(StudioFingerprint fingerprint) async {
    if (fingerprint.id.trim().isEmpty ||
        fingerprint.mediaFileId.trim().isEmpty ||
        fingerprint.algorithmKey.trim().isEmpty ||
        fingerprint.algorithmVersion.trim().isEmpty ||
        fingerprint.fingerprintFormat.trim().isEmpty ||
        fingerprint.dataFilePath.trim().isEmpty) {
      throw ArgumentError('Fingerprint identity, algorithm and storage fields are required.');
    }
    if (fingerprint.frameCount < 0 ||
        (fingerprint.durationMs != null && fingerprint.durationMs! < 0) ||
        (fingerprint.sampleRate != null && fingerprint.sampleRate! <= 0) ||
        (fingerprint.channels != null && fingerprint.channels! <= 0)) {
      throw ArgumentError('Fingerprint technical values are invalid.');
    }

    final mediaLibrary = await StudioDatabaseManager.instance.initialize();
    final mediaRows = await mediaLibrary.query(
      'studio_media_files',
      columns: ['id', 'media_type'],
      where: 'id = ?',
      whereArgs: [fingerprint.mediaFileId],
      limit: 1,
    );
    if (mediaRows.isEmpty) {
      throw StateError('Source Studio media file not found: ${fingerprint.mediaFileId}');
    }
    final sourceType = StudioMediaType.fromDatabase(
      mediaRows.first['media_type'] as String,
    );
    if (sourceType != fingerprint.mediaType) {
      throw ArgumentError('Fingerprint media type must match its source media.');
    }

    await (await _readyRepository).register(fingerprint);
  }

  Future<StudioFingerprint?> getById(String id) async =>
      (await _readyRepository).getById(id);

  Future<StudioFingerprint?> getForMedia({
    required String mediaFileId,
    required String algorithmKey,
    required String algorithmVersion,
  }) async =>
      (await _readyRepository).getForMedia(
        mediaFileId: mediaFileId,
        algorithmKey: algorithmKey,
        algorithmVersion: algorithmVersion,
      );

  Future<List<StudioFingerprint>> getForMediaFile(String mediaFileId) async =>
      (await _readyRepository).getForMediaFile(mediaFileId);

  Future<void> replaceSegments(
    String fingerprintId,
    List<StudioFingerprintSegment> segments,
  ) async {
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.fingerprintId != fingerprintId ||
          segment.segmentIndex != i ||
          segment.startMs < 0 ||
          segment.endMs <= segment.startMs ||
          segment.dataOffsetBytes < 0 ||
          segment.dataLengthBytes <= 0) {
        throw ArgumentError('Fingerprint segments must be ordered and contain valid ranges.');
      }
      if (i > 0 && segment.startMs < segments[i - 1].startMs) {
        throw ArgumentError('Fingerprint segments must be sorted by start time.');
      }
    }
    await (await _readyRepository).replaceSegments(fingerprintId, segments);
  }

  Future<List<StudioFingerprintSegment>> getSegments(
    String fingerprintId,
  ) async =>
      (await _readyRepository).getSegments(fingerprintId);

  Future<void> updateStatus(
    String id,
    StudioFingerprintStatus status,
  ) async =>
      (await _readyRepository).updateStatus(id, status);
}
