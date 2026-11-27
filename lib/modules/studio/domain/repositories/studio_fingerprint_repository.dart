import '../entities/studio_fingerprint.dart';

abstract interface class StudioFingerprintRepository {
  Future<void> register(StudioFingerprint fingerprint);

  Future<StudioFingerprint?> getById(String id);

  Future<StudioFingerprint?> getForMedia({
    required String mediaFileId,
    required String algorithmKey,
    required String algorithmVersion,
  });

  Future<List<StudioFingerprint>> getForMediaFile(String mediaFileId);

  Future<void> replaceSegments(
    String fingerprintId,
    List<StudioFingerprintSegment> segments,
  );

  Future<List<StudioFingerprintSegment>> getSegments(String fingerprintId);

  Future<void> updateStatus(String id, StudioFingerprintStatus status);
}
