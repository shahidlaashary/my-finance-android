import 'dart:typed_data';

import '../../domain/entities/studio_fingerprint.dart';

/// Decoded, normalized audio samples supplied to fingerprint algorithms.
/// Samples are interleaved when [channels] is greater than one.
class StudioDecodedAudio {
  StudioDecodedAudio({
    required this.samples,
    required this.sampleRate,
    required this.channels,
  }) {
    if (sampleRate <= 0 || channels <= 0 || samples.isEmpty ||
        samples.length % channels != 0) {
      throw ArgumentError('Decoded audio must contain valid PCM samples.');
    }
  }

  final Float32List samples;
  final int sampleRate;
  final int channels;

  int get frameCount => samples.length ~/ channels;

  int get durationMs =>
      ((frameCount / sampleRate) * 1000).round();
}

/// Decoder implementations can later use platform codecs or a bundled
/// decoder. The fingerprint engine is deliberately independent of codecs.
abstract interface class StudioAudioDecoder {
  Future<StudioDecodedAudio> decode(String managedMediaPath);
}

class StudioAudioFingerprintSegmentData {
  const StudioAudioFingerprintSegmentData({
    required this.segmentIndex,
    required this.startMs,
    required this.endMs,
    required this.dataOffsetBytes,
    required this.dataLengthBytes,
    this.signatureHash,
  });

  final int segmentIndex;
  final int startMs;
  final int endMs;
  final int dataOffsetBytes;
  final int dataLengthBytes;
  final String? signatureHash;
}

class StudioAudioFingerprintOutput {
  const StudioAudioFingerprintOutput({
    required this.bytes,
    required this.frameCount,
    required this.segments,
  });

  final Uint8List bytes;
  final int frameCount;
  final List<StudioAudioFingerprintSegmentData> segments;
}

/// Each algorithm declares a stable key and explicit version. A changed
/// algorithm must use a new version so old fingerprints are never mistaken
/// for compatible results.
abstract interface class StudioAudioFingerprintAlgorithm {
  String get algorithmKey;
  String get algorithmVersion;
  String get fingerprintFormat;

  Future<StudioAudioFingerprintOutput> generate(StudioDecodedAudio audio);
}
