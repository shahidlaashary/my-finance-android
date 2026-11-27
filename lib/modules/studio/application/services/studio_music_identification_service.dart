import 'dart:io';
import '../../domain/entities/studio_fingerprint.dart';
import '../../domain/entities/studio_media_file.dart';
import '../../engines/audio_fingerprint/studio_audio_fingerprint_engine.dart';
import '../../engines/audio_fingerprint/studio_audio_fingerprint_matcher.dart';
import '../../engines/audio_fingerprint/studio_spectral_landmark_fingerprint.dart';
import '../../engines/audio_fingerprint/studio_wav_pcm16_decoder.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import 'studio_media_library_service.dart';
import 'studio_fingerprint_catalogue_service.dart';
import 'studio_catalogue_rights_service.dart';

class StudioAudioCandidate {
  const StudioAudioCandidate({required this.media, required this.match});
  final StudioMediaFile media;
  final StudioAudioFingerprintMatch match;
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
  StudioAudioFingerprintEngine get _engine=>StudioAudioFingerprintEngine(
    decoder:const StudioWavPcm16Decoder(),
    algorithm:const StudioSpectralLandmarkFingerprint(),
    storageManager:storage,
    mediaLibrary:mediaLibrary,
    fingerprintCatalogue:fingerprints,
  );
  Future<List<StudioMediaFile>> audioFiles()=>mediaLibrary.browse(mediaType:StudioMediaType.audio,limit:500);
  Future<StudioFingerprint?> fingerprintFor(String mediaId)=>fingerprints.getForMedia(mediaFileId:mediaId,algorithmKey:'studio.audio.spectral-landmark',algorithmVersion:'1.0.0');
  Future<List<Map<String,Object?>>> comparisonHistory()=>StudioCatalogueRightsService().comparisonHistory();
  Future<StudioFingerprint> identify(String mediaId)=>_engine.generateForMedia(mediaId);
  Future<List<StudioAudioCandidate>> identifyMatches(String mediaId)async{
    await identify(mediaId);
    final files=await audioFiles();
    final candidates=<StudioAudioCandidate>[];
    for(final file in files){
      if(file.id==mediaId)continue;
      try{final result=await compare(mediaId,file.id);candidates.add(StudioAudioCandidate(media:file,match:result));}
      catch(_){/* An unsupported or unreadable file should not stop the rest of the scan. */}
    }
    candidates.sort((a,b)=>b.match.confidence.compareTo(a.match.confidence));
    return candidates;
  }
  Future<StudioAudioFingerprintMatch> compare(String firstId,String secondId)async{
    final a=await fingerprintFor(firstId)??await identify(firstId);
    final b=await fingerprintFor(secondId)??await identify(secondId);
    if(a.algorithmKey!=b.algorithmKey||a.algorithmVersion!=b.algorithmVersion)throw StateError('Fingerprints use incompatible algorithms.');
    if(a.sampleRate!=b.sampleRate)throw StateError('Audio files use different sample rates. Resampling is not available yet.');
    final bytesA=await File(a.dataFilePath).readAsBytes(),bytesB=await File(b.dataFilePath).readAsBytes();
    final result=StudioAudioFingerprintMatcher(sampleRate:a.sampleRate??11025).compare(query:bytesA,reference:bytesB);
    await StudioCatalogueRightsService().saveComparison(leftId:firstId,rightId:secondId,score:result.confidence,matches:result.matchedLandmarks,offsetMs:result.offsetMs,algorithm:a.algorithmKey,version:a.algorithmVersion,result:{'queryCoverage':result.queryCoverage,'referenceCoverage':result.referenceCoverage,'queryLandmarks':result.queryLandmarks,'referenceLandmarks':result.referenceLandmarks});
    return result;
  }
}
