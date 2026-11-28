import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/studio_media_file.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import 'studio_fingerprint_catalogue_service.dart';
import 'studio_media_library_service.dart';

class StudioStorageHealthReport {
  const StudioStorageHealthReport({
    required this.totalManagedBytes,
    required this.registeredMediaCount,
    required this.missingMediaIds,
    required this.unavailableMediaIds,
    required this.registeredFingerprintCount,
    required this.missingFingerprintIds,
    required this.orphanedFingerprintArtifactPaths,
  });

  final int totalManagedBytes;
  final int registeredMediaCount;
  final List<String> missingMediaIds;
  final List<String> unavailableMediaIds;
  final int registeredFingerprintCount;
  final List<String> missingFingerprintIds;
  final List<String> orphanedFingerprintArtifactPaths;

  int get healthyMediaCount =>
      registeredMediaCount - missingMediaIds.length - unavailableMediaIds.length;

  int get healthyFingerprintCount =>
      registeredFingerprintCount - missingFingerprintIds.length;
}

/// Checks catalogue references against Studio's managed file storage.
class StudioStorageHealthService {
  const StudioStorageHealthService({
    required StudioStorageManager storageManager,
    required StudioMediaLibraryService mediaLibrary,
    StudioFingerprintCatalogueService? fingerprintCatalogue,
  })  : _storageManager = storageManager,
        _mediaLibrary = mediaLibrary,
        _fingerprintCatalogue = fingerprintCatalogue;

  final StudioStorageManager _storageManager;
  final StudioMediaLibraryService _mediaLibrary;
  final StudioFingerprintCatalogueService? _fingerprintCatalogue;

  Future<StudioStorageHealthReport> inspect() async {
    final media = await _mediaLibrary.browse(limit: 100000);
    final fingerprints = await (_fingerprintCatalogue ??
            StudioFingerprintCatalogueService())
        .getAll(limit: 100000);
    final missingMedia = <String>[];
    final unavailable = <String>[];
    final missingFingerprints = <String>[];

    for (final item in media) {
      if (!await _storageManager.fileExists(item.storagePath)) {
        missingMedia.add(item.id);
      } else if (item.importStatus != StudioMediaImportStatus.imported) {
        unavailable.add(item.id);
      }
    }

    final registeredArtifactPaths = <String>{};
    for (final fingerprint in fingerprints) {
      final artifactPath = p.normalize(p.absolute(fingerprint.dataFilePath));
      registeredArtifactPaths.add(artifactPath);
      if (!await _storageManager.fileExists(fingerprint.dataFilePath)) {
        missingFingerprints.add(fingerprint.id);
      }
    }

    // Only inspect Studio's own fingerprints directory. Never classify files
    // elsewhere on the device as orphaned Studio artifacts.
    final fingerprintDirectory =
        await _storageManager.directoryFor('fingerprints');
    final orphanedArtifacts = <String>[];
    await for (final entity
        in fingerprintDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final artifactPath = p.normalize(p.absolute(entity.path));
      if (!registeredArtifactPaths.contains(artifactPath)) {
        orphanedArtifacts.add(entity.path);
      }
    }
    orphanedArtifacts.sort();

    return StudioStorageHealthReport(
      totalManagedBytes: await _storageManager.calculateTotalBytes(),
      registeredMediaCount: media.length,
      missingMediaIds: List.unmodifiable(missingMedia),
      unavailableMediaIds: List.unmodifiable(unavailable),
      registeredFingerprintCount: fingerprints.length,
      missingFingerprintIds: List.unmodifiable(missingFingerprints),
      orphanedFingerprintArtifactPaths:
          List.unmodifiable(orphanedArtifacts),
    );
  }
}
