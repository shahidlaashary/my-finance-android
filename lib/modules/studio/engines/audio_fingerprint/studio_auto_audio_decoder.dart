import 'dart:io';
import 'package:audio_decode/audio_decode.dart' as audio;
import 'studio_audio_fingerprint_contracts.dart';

/// Decodes supported audio containers and normalizes fingerprint input to
/// mono 11,025 Hz PCM. Production decoding runs in a worker isolate from the
/// fingerprint engine so large imports do not block Flutter's UI isolate.
class StudioAutoAudioDecoder implements StudioAudioDecoder {
  const StudioAutoAudioDecoder();

  static const int fingerprintSampleRate = 11025;

  // audio_decode currently decodes a complete input buffer. Keep the
  // temporary 200 MB ceiling until bounded-memory streaming is implemented.
  static const int maxEncodedFileBytes = 200 * 1024 * 1024;
  static const Set<String> supportedExtensions = {'mp3', 'ogg', 'wav'};

  @override
  Future<StudioDecodedAudio> decode(String managedMediaPath) async {
    final file = File(managedMediaPath);
    if (!await file.exists()) {
      throw FileSystemException('Audio source does not exist.', managedMediaPath);
    }
    final extension = managedMediaPath.split('.').last.toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw FormatException(
        'Unsupported audio format: .$extension. Audio Match supports MP3, OGG and WAV.',
      );
    }
    final length = await file.length();
    if (length == 0) throw const FormatException('Audio source is empty.');
    if (length > maxEncodedFileBytes) {
      throw const FormatException(
        'Audio file exceeds the current 200 MB decoding limit. Import a smaller or segmented copy.',
      );
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('Audio source is empty.');
    _validateContainerHeader(bytes, extension);

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

  void _validateContainerHeader(List<int> bytes, String extension) {
    if (extension == 'wav') {
      if (bytes.length < 12 ||
          String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
        throw const FormatException('Invalid WAV file header.');
      }
    } else if (extension == 'ogg') {
      if (bytes.length < 4 ||
          String.fromCharCodes(bytes.sublist(0, 4)) != 'OggS') {
        throw const FormatException('Invalid OGG file header.');
      }
    } else {
      final hasId3 =
          bytes.length >= 3 && String.fromCharCodes(bytes.sublist(0, 3)) == 'ID3';
      final hasMpegSync =
          bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
      if (!hasId3 && !hasMpegSync) {
        throw const FormatException('Invalid MP3 file header.');
      }
    }
  }
}
