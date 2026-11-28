import '../../domain/entities/studio_media_file.dart';
import '../../domain/entities/studio_fingerprint.dart';
import '../../domain/entities/studio_video_fingerprint_match.dart';
import '../../engines/video_fingerprint/studio_video_fingerprint_engine.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import 'studio_catalogue_rights_service.dart';
import 'studio_fingerprint_catalogue_service.dart';
import 'studio_media_library_service.dart';

/// A video discovered during a Visual Match library scan.
class StudioVisualMatchCandidate {
  const StudioVisualMatchCandidate({required this.media, required this.match});
  final StudioMediaFile media;
  final StudioVideoFingerprintMatch match;
}
class StudioVisualMatchScanResult {
  const StudioVisualMatchScanResult({required this.matches, required this.comparedCount, required this.skippedCount});
  final List<StudioVisualMatchCandidate> matches;
  final int comparedCount;
  final int skippedCount;
}
/// Application-level entry point for Visual Match workflows.
///
/// Keeps algorithm identity stable at the application boundary so UI and
/// application code do not need to reference engine implementation details.
class StudioVisualMatchService {
  static const algorithmKey = 'studio.video.frame-dhash';
  static const algorithmVersion = '1.0.0';

  StudioVisualMatchService({
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

  Future<StudioVisualMatchScanResult> scanMatches(String queryId, {void Function(int completed, int total)? onProgress}) async {
    final library = await videos();
    if (!library.any((file) => file.id == queryId)) throw ArgumentError('Selected video is not in the Studio library.');
    final references = library.where((file) => file.id != queryId).toList();
    final matches = <StudioVisualMatchCandidate>[];
    var compared = 0, skipped = 0;
    onProgress?.call(0, references.length);
    for (final reference in references) {
      try {
        final result = await compare(queryId, reference.id);
        compared++;
        if (result.isMatch) matches.add(StudioVisualMatchCandidate(media: reference, match: result));
      } catch (_) {
        skipped++;
      } finally {
        onProgress?.call(compared + skipped, references.length);
      }
    }
    matches.sort((a, b) => b.match.confidence.compareTo(a.match.confidence));
    return StudioVisualMatchScanResult(matches: matches, comparedCount: compared, skippedCount: skipped);
  }

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

  Future<List<Map<String, Object?>>> history() async =>
      (await catalogueRights.comparisonHistory())
          .where((row) => row['algorithm_key'] == algorithmKey)
          .toList(growable: false);
}
