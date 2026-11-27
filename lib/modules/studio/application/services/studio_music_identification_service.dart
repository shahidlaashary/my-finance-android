import 'dart:io';
import '../../domain/entities/studio_fingerprint.dart';
import '../../domain/entities/studio_media_file.dart';
import '../../engines/audio_fingerprint/studio_audio_fingerprint_engine.dart';
import '../../engines/audio_fingerprint/studio_audio_fingerprint_matcher.dart';
import '../../engines/audio_fingerprint/studio_audio_fingerprint_contracts.dart';
import '../../engines/audio_fingerprint/studio_spectral_landmark_fingerprint.dart';
import '../../engines/audio_fingerprint/studio_wav_pcm16_decoder.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import 'studio_media_library_service.dart';
import 'studio_fingerprint_catalogue_service.dart';
import 'studio_catalogue_rights_service.dart';

class StudioAudioCandidate {\n  const StudioAudioCandidate({required this.media,required this.match});\n  final StudioMediaFile media;\n  final StudioAudioFingerprintMatch match;\n}\n\nclass StudioMusicIdentificationService {
  StudioMusicIdentificationService({StudioMediaLibraryService? mediaLibrary, StudioFingerprintCatalogueService? fingerprints, StudioStorageManager? storage})
      : mediaLibrary=mediaLibrary??StudioMediaLibraryService(), fingerprints=fingerprints??StudioFingerprintCatalogueService(), storage=storage??StudioStorageManager();
  final StudioMediaLibraryService mediaLibrary;
  final StudioFingerprintCatalogueService fingerprints;
  final StudioStorageManager storage;
  StudioAudioFingerprintEngine get _engine=>StudioAudioFingerprintEngine(decoder:const StudioWavPcm16Decoder(),algorithm:const StudioSpectralLandmarkFingerprint(),storageManager:storage,mediaLibrary:mediaLibrary,fingerprintCatalogue:fingerprints);
  Future<List<StudioMediaFile>> audioFiles() => mediaLibrary.browse(mediaType:StudioMediaType.audio,limit:500);
  Future<StudioFingerprint?> fingerprintFor(String mediaId) => fingerprints.getForMedia(mediaFileId:mediaId,algorithmKey:'studio.audio.spectral-landmark',algorithmVersion:'1.0.0');
  Future<List<Map<String,Object?>>> comparisonHistory() => StudioCatalogueRightsService().comparisonHistory();
  Future<StudioFingerprint> identify(String mediaId) => _engine.generateForMedia(mediaId);\n  Future<List<StudioAudioCandidate>> identifyMatches(String mediaId) async {\n    await identify(mediaId);\n    final files=await audioFiles();\n    final candidates=<StudioAudioCandidate>[];\n    for(final file in files){\n      if(file.id==mediaId)continue;\n      try{final match=await compare(mediaId,file.id);candidates.add(StudioAudioCandidate(media:file,match:match));}catch(_){/* Unsupported file/decoder failures do not block remaining candidates. */}\n    }\n    candidates.sort((a,b)=>b.match.confidence.compareTo(a.match.confidence));\n    return candidates;\n  }
  Future<StudioAudioFingerprintMatch> compare(String firstId,String secondId) async {
    final a=await fingerprintFor(firstId)??await identify(firstId);
    final b=await fingerprintFor(secondId)??await identify(secondId);
    if(a.algorithmKey!=b.algorithmKey||a.algorithmVersion!=b.algorithmVersion)throw StateError('Fingerprints use incompatible algorithms.');
    final bytesA=await File(a.dataFilePath).readAsBytes();
    final bytesB=await File(b.dataFilePath).readAsBytes();
    final match=const StudioAudioFingerprintMatcher().compare(query:bytesA,reference:bytesB);
    await StudioCatalogueRightsService().saveComparison(leftId:firstId,rightId:secondId,score:match.confidence,matches:match.matchedLandmarks,offsetMs:match.offsetMs,algorithm:a.algorithmKey,version:a.algorithmVersion,result:{'queryCoverage':match.queryCoverage,'referenceCoverage':match.referenceCoverage,'queryLandmarks':match.queryLandmarks,'referenceLandmarks':match.referenceLandmarks});
    return match;
  }
}
