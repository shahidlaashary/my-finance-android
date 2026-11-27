import 'dart:io';
import 'package:audio_decode/audio_decode.dart' as audio;
import 'studio_audio_fingerprint_contracts.dart';

/// Decodes supported audio containers and normalizes all fingerprint input
/// to mono 11,025 Hz PCM. This keeps time/frequency landmarks comparable
/// across MP3 bitrates, source sample rates and channel layouts.
class StudioAutoAudioDecoder implements StudioAudioDecoder {
  const StudioAutoAudioDecoder();

  static const int fingerprintSampleRate = 11025;

  @override
  Future<StudioDecodedAudio> decode(String managedMediaPath) async {
    final file = File(managedMediaPath);
    if (!await file.exists()) {
      throw FileSystemException('Audio source does not exist.', managedMediaPath);
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('Audio source is empty.');

    final decoded = audio.decodeAudio(bytes);
    if (decoded.frameCount <= 0 || decoded.sampleRate <= 0) {
      throw const FormatException('Audio source contains no decodable samples.');
    }

    // Mix stereo/multichannel sources consistently before resampling so
    // fingerprint frame indices and offsets use one canonical audio profile.
    final mono = decoded.toMono();
    final normalized = mono.sampleRate == fingerprintSampleRate
        ? mono
        : audio.resample(mono, fingerprintSampleRate);
    final samples = normalized.toFloat32();
    if (samples.isEmpty) {
      throw const FormatException('Audio decoding produced no PCM samples.');
    }

    return StudioDecodedAudio(
      samples: samples,
      sampleRate: fingerprintSampleRate,
      channels: 1,
    );
  }
}
