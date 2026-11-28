import 'dart:io';
import 'dart:math';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../../application/services/studio_fingerprint_catalogue_service.dart';
import '../../application/services/studio_media_library_service.dart';
import '../../domain/entities/studio_fingerprint.dart';
import '../../domain/entities/studio_media_file.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';
import 'studio_audio_fingerprint_contracts.dart';

/// Coordinates decoding, algorithm execution, artifact storage and catalogue
/// registration. It does not prescribe a codec or a fingerprint algorithm.
class StudioAudioFingerprintEngine {
  StudioAudioFingerprintEngine({
    required StudioAudioDecoder decoder,
    required StudioAudioFingerprintAlgorithm algorithm,
    required StudioStorageManager storageManager,
    required StudioMediaLibraryService mediaLibrary,
    required StudioFingerprintCatalogueService fingerprintCatalogue,
  })  : _decoder = decoder,
        _algorithm = algorithm,
        _storageManager = storageManager,
        _mediaLibrary = mediaLibrary,
        _fingerprintCatalogue = fingerprintCatalogue;

  final StudioAudioDecoder _decoder;
  final StudioAudioFingerprintAlgorithm _algorithm;
  final StudioStorageManager _storageManager;
  final StudioMediaLibraryService _mediaLibrary;
  final StudioFingerprintCatalogueService _fingerprintCatalogue;
  final Random _random = Random.secure();

  String _newFingerprintId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final entropy = _random.nextInt(0x7fffffff).toRadixString(16);
    return 'fp_audio_${timestamp}_$entropy';
  }

  Future<StudioFingerprint> generateForMedia(String mediaFileId) async {
    final media = await _mediaLibrary.getById(mediaFileId);
    if (media == null) {
      throw StateError('Studio media file not found: $mediaFileId');
    }
    if (media.mediaType != StudioMediaType.audio) {
      throw ArgumentError('Audio fingerprinting only accepts audio media.');
    }
    if (!await File(media.storagePath).exists()) {
      await _mediaLibrary.markImportStatus(
        media.id,
        StudioMediaImportStatus.missing,
      );
      throw FileSystemException('The managed audio file is missing.', media.storagePath);
    }

    final existing = await _fingerprintCatalogue.getForMedia(
      mediaFileId: media.id,
      algorithmKey: _algorithm.algorithmKey,
      algorithmVersion: _algorithm.algorithmVersion,
    );
    if (existing != null) return existing;

    // Decoding (including native FFI work) and spectral analysis contain
    // long synchronous sections. Running them on the UI isolate can freeze
    // the whole Music ID route, including the AppBar back button.
    final decoder = _decoder;
    final algorithm = _algorithm;
    final computation = await Isolate.run(() async {
      final decodedAudio = await decoder.decode(media.storagePath);
      final fingerprintOutput = await algorithm.generate(decodedAudio);
      return (
        durationMs: decodedAudio.durationMs,
        sampleRate: decodedAudio.sampleRate,
        channels: decodedAudio.channels,
        output: fingerprintOutput,
      );
    });
    final output = computation.output;
    _validateOutput(output, computation.durationMs);

    final id = _newFingerprintId();
    final artifact = await _storageManager.allocateFingerprintFile(
      fingerprintId: id,
      extension: 'bin',
    );

    var catalogueRegistered = false;
    try {
      await artifact.writeAsBytes(output.bytes, flush: true);
      final checksum = await sha256.bind(artifact.openRead()).first;
      final now = DateTime.now().toUtc();
      final fingerprint = StudioFingerprint(
        id: id,
        mediaFileId: media.id,
        mediaType: StudioMediaType.audio,
        algorithmKey: _algorithm.algorithmKey,
        algorithmVersion: _algorithm.algorithmVersion,
        fingerprintFormat: _algorithm.fingerprintFormat,
        dataFilePath: artifact.path,
        checksumSha256: checksum.toString(),
        sampleRate: computation.sampleRate,
        channels: computation.channels,
        durationMs: computation.durationMs,
        frameCount: output.frameCount,
        status: StudioFingerprintStatus.generated,
        createdAt: now,
        updatedAt: now,
      );

      await _fingerprintCatalogue.register(fingerprint);
      catalogueRegistered = true;
      final segments = output.segments
          .map(
            (segment) => StudioFingerprintSegment(
              fingerprintId: id,
              segmentIndex: segment.segmentIndex,
              startMs: segment.startMs,
              endMs: segment.endMs,
              dataOffsetBytes: segment.dataOffsetBytes,
              dataLengthBytes: segment.dataLengthBytes,
              signatureHash: segment.signatureHash,
            ),
          )
          .toList(growable: false);
      await _fingerprintCatalogue.replaceSegments(id, segments);
      return fingerprint;
    } catch (_) {
      if (catalogueRegistered) {
        try {
          await _fingerprintCatalogue.remove(id);
        } catch (_) {
          // Preserve the original processing error if rollback also fails.
        }
      }
      if (await artifact.exists()) await artifact.delete();
      rethrow;
    }
  }

  void _validateOutput(
    StudioAudioFingerprintOutput output,
    int decodedDurationMs,
  ) {
    if (output.bytes.isEmpty || output.frameCount < 0) {
      throw StateError('Fingerprint algorithm returned an empty or invalid artifact.');
    }

    for (var i = 0; i < output.segments.length; i++) {
      final segment = output.segments[i];
      if (segment.segmentIndex != i ||
          segment.startMs < 0 ||
          segment.endMs <= segment.startMs ||
          segment.endMs > decodedDurationMs ||
          segment.dataOffsetBytes < 0 ||
          segment.dataLengthBytes <= 0 ||
          segment.dataOffsetBytes + segment.dataLengthBytes > output.bytes.length) {
        throw StateError('Fingerprint algorithm returned invalid segment metadata.');
      }
      if (i > 0 && segment.startMs < output.segments[i - 1].startMs) {
        throw StateError('Fingerprint segments must be ordered by start time.');
      }
    }
  }
}
