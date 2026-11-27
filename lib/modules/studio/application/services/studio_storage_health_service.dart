import '../../domain/entities/studio_media_file.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import 'studio_media_library_service.dart';

class StudioStorageHealthReport {
  const StudioStorageHealthReport({
    required this.totalManagedBytes,
    required this.registeredMediaCount,
    required this.missingMediaIds,
    required this.unavailableMediaIds,
  });

  final int totalManagedBytes;
  final int registeredMediaCount;
  final List<String> missingMediaIds;
  final List<String> unavailableMediaIds;

  int get healthyMediaCount =>
      registeredMediaCount - missingMediaIds.length - unavailableMediaIds.length;
}

/// Checks catalogue references against Studio's managed file storage.
class StudioStorageHealthService {
  const StudioStorageHealthService({
    required StudioStorageManager storageManager,
    required StudioMediaLibraryService mediaLibrary,
  })  : _storageManager = storageManager,
        _mediaLibrary = mediaLibrary;

  final StudioStorageManager _storageManager;
  final StudioMediaLibraryService _mediaLibrary;

  Future<StudioStorageHealthReport> inspect() async {
    final media = await _mediaLibrary.browse(limit: 100000);
    final missing = <String>[];
    final unavailable = <String>[];

    for (final item in media) {
      if (!await _storageManager.fileExists(item.storagePath)) {
        missing.add(item.id);
      } else if (item.importStatus != StudioMediaImportStatus.imported) {
        unavailable.add(item.id);
      }
    }

    return StudioStorageHealthReport(
      totalManagedBytes: await _storageManager.calculateTotalBytes(),
      registeredMediaCount: media.length,
      missingMediaIds: List.unmodifiable(missing),
      unavailableMediaIds: List.unmodifiable(unavailable),
    );
  }
}
