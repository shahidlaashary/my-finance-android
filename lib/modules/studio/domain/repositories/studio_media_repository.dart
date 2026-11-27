import '../entities/studio_media_file.dart';

abstract interface class StudioMediaRepository {
  Future<void> register(StudioMediaFile mediaFile);

  Future<StudioMediaFile?> getById(String id);

  Future<List<StudioMediaFile>> getAll({
    StudioMediaType? mediaType,
    String? search,
    int limit = 50,
    int offset = 0,
  });

  Future<void> updateImportStatus(
    String id,
    StudioMediaImportStatus status,
  );

  /// Removes the catalogue record only; it does not delete the physical file.
  Future<void> removeRecord(String id);
}
