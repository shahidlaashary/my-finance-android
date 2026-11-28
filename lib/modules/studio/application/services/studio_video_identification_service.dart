import '../../domain/entities/studio_media_file.dart';
import '../../domain/entities/studio_fingerprint.dart';
import '../../domain/entities/studio_video_fingerprint_match.dart';
import '../../engines/video_fingerprint/studio_video_fingerprint_engine.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import 'studio_catalogue_rights_service.dart';
import 'studio_fingerprint_catalogue_service.dart';
import 'studio_media_library_service.dart';

/// Application-level entry point for Video ID workflows.
///
/// Keeps algorithm identity stable at the application boundary so UI and
/// application code do not need to reference engine implementation details.
class StudioVideoIdentificationService {
  static const algorithmKey = 'studio.video.frame-dhash';
  static const algorithmVersion = '1.0.0';

  StudioVideoIdentificationService({
    StudioMediaLibraryService? mediaLibrary,
    StudioFingerprintCatalogueService? catalogue,
    StudioStorageManager? storage,
    StudioCatalogueRightsService? catalogueRights,
  })  : mediaLibrary = mediaLibrary ?? StudioMediaLibraryService(),
        catalogue = catalogue ?? StudioFingerprintCatalogueService(),
        storage = storage ?? StudioStorageManager(),
        catalogueRights = catalogueRights ?? StudioCatalogueRightsService();

  final StudioMediaLibraryService mediaLibrary;
  final StudioFingerprintCatalogueService catalogue;
  final StudioStorageManager storage;
  final StudioCatalogueRightsService catalogueRights;

  StudioVideoFingerprintEngine get _engine => StudioVideoFingerprintEngine(
        storage: storage,
        media: mediaLibrary,
        catalogue: catalogue,
      );

  Future<List<StudioMediaFile>> videos() => mediaLibrary.browse(
        mediaType: StudioMediaType.video,
        limit: 500,
      );

  Future<StudioFingerprint> fingerprint(String id) => _engine.generate(id);

  Future<StudioVideoFingerprintMatch> compare(String first, String second) async {
    final result = await _engine.compare(first, second);
    await catalogueRights.saveComparison(
      leftId: first,
      rightId: second,
      score: result.confidence,
      matches: result.matches,
      offsetMs: result.offsetMs,
      algorithm: algorithmKey,
      version: algorithmVersion,
      result: {
        'queryFrames': result.queryFrames,
        'referenceFrames': result.referenceFrames,
      },
    );
    return result;
  }

  Future<List<Map<String, Object?>>> history() =>
      catalogueRights.comparisonHistory();
}
