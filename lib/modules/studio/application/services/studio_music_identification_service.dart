import 'dart:io';
import 'package:flutter/foundation.dart';
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

class StudioMusicIdentificationService {
  StudioMusicIdentificationService({StudioMediaLibraryService? mediaLibrary, StudioFingerprintCatalogueService? fingerprints, StudioStorageManager? storage})
      : mediaLibrary=mediaLibrary??StudioMediaLibraryService(), fingerprints=fingerprints??StudioFingerprintCatalogueService(), storage=storage??StudioStorageManager();
  final StudioMediaLibraryService mediaLibrary;
  final StudioFingerprintCatalogueService fingerprints;
  final StudioStorageManager storage;
  StudioAudioFingerprintEngine get _engine=>StudioAudioFingerprintEngine(decoder:const StudioWavPcm16Decoder(),algorithm:const StudioSpectralLandmarkFingerprint(),storageManager:storage,mediaLibrary:mediaLibrary,fingerprintCatalogue:fingerprints);
  Future<List<StudioMediaFile>> audioFiles() => mediaLibrary.browse(mediaType:StudioMediaType.audio,limit:500);
  Future<StudioFingerprint?> fingerprintFor(String mediaId) => fingerprints.getForMedia(mediaFileId:mediaId,algorithmKey:'studio.audio.spectral-landmark',algorithmVersion:'1.0.0');
  Future<StudioFingerprint> identify(String mediaId) => _engine.generateForMedia(mediaId);
  Future<StudioAudioFingerprintMatch> compare(String firstId,String secondId) async {
    final a=await fingerprintFor(firstId)??await identify(firstId);
    final b=await fingerprintFor(secondId)??await identify(secondId);
    if(a.algorithmKey!=b.algorithmKey||a.algorithmVersion!=b.algorithmVersion)throw StateError('Fingerprints use incompatible algorithms.');
    final bytesA=await File(a.dataFilePath).readAsBytes();
    final bytesB=await File(b.dataFilePath).readAsBytes();
    return const StudioAudioFingerprintMatcher().compare(query:bytesA,reference:bytesB);
  }
}
