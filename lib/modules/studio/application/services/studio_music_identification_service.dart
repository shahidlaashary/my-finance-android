import 'dart:io';
import '../../domain/entities/studio_fingerprint.dart';
import '../../domain/entities/studio_media_file.dart';
import '../../engines/audio_fingerprint/studio_audio_fingerprint_engine.dart';
import '../../engines/audio_fingerprint/studio_audio_fingerprint_matcher.dart';
import '../../engines/audio_fingerprint/studio_auto_audio_decoder.dart';
import '../../engines/audio_fingerprint/studio_spectral_landmark_fingerprint.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import 'studio_media_library_service.dart';
import 'studio_fingerprint_catalogue_service.dart';
import 'studio_catalogue_rights_service.dart';

class StudioAudioCandidate {
  const StudioAudioCandidate({required this.media, required this.match});
  final StudioMediaFile media;
  final StudioAudioFingerprintMatch match;
}

class StudioAudioScanResult {
  const StudioAudioScanResult({
    required this.matches,
    required this.comparedCount,
    required this.skippedCount,
  });
  final List<StudioAudioCandidate> matches;
  final int comparedCount;
  final int skippedCount;
}

class StudioMusicIdentificationService {
  StudioMusicIdentificationService({
    StudioMediaLibraryService? mediaLibrary,
    StudioFingerprintCatalogueService? fingerprints,
    StudioStorageManager? storage,
  }) : mediaLibrary=mediaLibrary??StudioMediaLibraryService(),
       fingerprints=fingerprints??StudioFingerprintCatalogueService(),
       storage=storage??StudioStorageManager();
  final StudioMediaLibraryService mediaLibrary;
  final StudioFingerprintCatalogueService fingerprints;
  final StudioStorageManager storage;
  static const algorithmKey='studio.audio.spectral-landmark';
  static const algorithmVersion='1.1.0';
  StudioAudioFingerprintEngine get _engine=>StudioAudioFingerprintEngine(
    decoder:const StudioAutoAudioDecoder(),
    algorithm:const StudioSpectralLandmarkFingerprint(),
    storageManager:storage,
    mediaLibrary:mediaLibrary,
    fingerprintCatalogue:fingerprints,
  );
  static const int maxFilesPerScan = 100;
  Future<List<StudioMediaFile>> audioFiles()=>mediaLibrary.browse(mediaType:StudioMediaType.audio,limit:maxFilesPerScan);
  Future<StudioFingerprint?> fingerprintFor(String mediaId)=>fingerprints.getForMedia(mediaFileId:mediaId,algorithmKey:algorithmKey,algorithmVersion:algorithmVersion);
  Future<List<Map<String,Object?>>> comparisonHistory()=>StudioCatalogueRightsService().comparisonHistory();
  Future<StudioFingerprint> identify(String mediaId)=>_engine.generateForMedia(mediaId);

  Future<StudioAudioScanResult> scanMatches(String mediaId, {void Function(int completed, int total)? onProgress}) async {
    await identify(mediaId);
    final files=await audioFiles();
    final candidates=<StudioAudioCandidate>[];
    var skipped=0;
    var compared=0;
    final scanFiles = files.where((file) => file.id != mediaId).toList();
    var completed = 0;
    onProgress?.call(0, scanFiles.length);
    for(final file in scanFiles){
      try{
        final result=await compare(mediaId,file.id);
        compared++;
        if (result.isMatch) {
          candidates.add(StudioAudioCandidate(media:file,match:result));
        }
      } catch (_) {
        // Keep scanning other items, but surface skipped files in the result.
        skipped++;
      } finally {
        completed++;
        onProgress?.call(completed, scanFiles.length);
      }
    }
    candidates.sort((a,b)=>b.match.confidence.compareTo(a.match.confidence));
    return StudioAudioScanResult(matches:candidates,comparedCount:compared,skippedCount:skipped);
  }

  Future<List<StudioAudioCandidate>> identifyMatches(String mediaId) async =>
      (await scanMatches(mediaId)).matches;

  Future<StudioAudioFingerprintMatch> compare(String firstId,String secondId)async{
    final a=await fingerprintFor(firstId)??await identify(firstId);
    final b=await fingerprintFor(secondId)??await identify(secondId);
    if(a.algorithmKey!=b.algorithmKey||a.algorithmVersion!=b.algorithmVersion)throw StateError('Fingerprints use incompatible algorithms.');
    if(a.sampleRate!=StudioAutoAudioDecoder.fingerprintSampleRate||b.sampleRate!=StudioAutoAudioDecoder.fingerprintSampleRate) {
      throw StateError('Fingerprint audio profile is not normalized. Regenerate it with the current algorithm.');
    }
    final bytesA=await File(a.dataFilePath).readAsBytes(),bytesB=await File(b.dataFilePath).readAsBytes();
    final result=StudioAudioFingerprintMatcher(sampleRate:StudioAutoAudioDecoder.fingerprintSampleRate).compare(query:bytesA,reference:bytesB);
    await StudioCatalogueRightsService().saveComparison(leftId:firstId,rightId:secondId,score:result.confidence,matches:result.matchedLandmarks,offsetMs:result.offsetMs,algorithm:a.algorithmKey,version:a.algorithmVersion,result:{'queryCoverage':result.queryCoverage,'referenceCoverage':result.referenceCoverage,'queryLandmarks':result.queryLandmarks,'referenceLandmarks':result.referenceLandmarks});
    return result;
  }
}
