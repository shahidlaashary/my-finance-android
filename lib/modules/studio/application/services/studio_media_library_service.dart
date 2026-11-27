import '../../domain/entities/studio_media_file.dart';
import '../../domain/repositories/studio_media_repository.dart';
import '../../infrastructure/database/studio_database_manager.dart';
import '../../infrastructure/repositories/sqlite_studio_media_repository.dart';

/// Application boundary for Studio's media catalogue.
///
/// UI code calls this service rather than querying the Studio database.
class StudioMediaLibraryService {
  StudioMediaLibraryService({
    StudioMediaRepository? repository,
  }) : _repository = repository;

  final StudioMediaRepository? _repository;

  Future<StudioMediaRepository> get _readyRepository async {
    final supplied = _repository;
    if (supplied != null) return supplied;

    final database = await StudioDatabaseManager.instance.initialize();
    return SqliteStudioMediaRepository(database);
  }

  Future<void> register(StudioMediaFile mediaFile) async {
    if (mediaFile.id.trim().isEmpty ||
        mediaFile.originalName.trim().isEmpty ||
        mediaFile.storagePath.trim().isEmpty) {
      throw ArgumentError('Media ID, original name and storage path are required.');
    }
    if (mediaFile.fileSizeBytes < 0 ||
        (mediaFile.durationMs != null && mediaFile.durationMs! < 0)) {
      throw ArgumentError('Media size and duration cannot be negative.');
    }
    await (await _readyRepository).register(mediaFile);
  }

  Future<StudioMediaFile?> getById(String id) async {
    return (await _readyRepository).getById(id);
  }

  Future<List<StudioMediaFile>> browse({
    StudioMediaType? mediaType,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    return (await _readyRepository).getAll(
      mediaType: mediaType,
      search: search,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> markImportStatus(
    String id,
    StudioMediaImportStatus status,
  ) async {
    await (await _readyRepository).updateImportStatus(id, status);
  }

  /// Removes only the database record. Physical-file cleanup belongs to the
  /// future managed-storage service and is intentionally not performed here.
  Future<void> removeRecord(String id) async {
    await (await _readyRepository).removeRecord(id);
  }
}
