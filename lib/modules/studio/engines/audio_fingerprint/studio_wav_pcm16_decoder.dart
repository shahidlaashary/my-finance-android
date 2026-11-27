import 'dart:io';
import 'dart:typed_data';

import 'studio_audio_fingerprint_contracts.dart';

/// Decodes little-endian RIFF/WAVE PCM16 files into normalized float samples.
///
/// Initial supported codec: uncompressed PCM, 16-bit, mono or stereo.
class StudioWavPcm16Decoder implements StudioAudioDecoder {
  const StudioWavPcm16Decoder();

  @override
  Future<StudioDecodedAudio> decode(String managedMediaPath) async {
    final file = File(managedMediaPath);
    if (!await file.exists()) {
      throw FileSystemException('Audio source does not exist.', managedMediaPath);
    }
    final bytes = await file.readAsBytes();
    if (bytes.length < 44) {
      throw const FormatException('WAV file is too small.');
    }
    final data = ByteData.sublistView(bytes);
    String fourCc(int offset) =>
        String.fromCharCodes(bytes.sublist(offset, offset + 4));

    if (fourCc(0) != 'RIFF' || fourCc(8) != 'WAVE') {
      throw const FormatException('Only RIFF/WAVE audio is supported.');
    }

    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? audioFormat;
    int? dataOffset;
    int? dataLength;

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = fourCc(offset);
      final chunkLength = data.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      final chunkEnd = chunkStart + chunkLength;
      if (chunkEnd > bytes.length) {
        throw const FormatException('WAV chunk exceeds file boundaries.');
      }

      if (chunkId == 'fmt ') {
        if (chunkLength < 16) {
          throw const FormatException('Invalid WAV format chunk.');
        }
        audioFormat = data.getUint16(chunkStart, Endian.little);
        channels = data.getUint16(chunkStart + 2, Endian.little);
        sampleRate = data.getUint32(chunkStart + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkStart;
        dataLength = chunkLength;
      }

      offset = chunkEnd + (chunkLength.isOdd ? 1 : 0);
    }

    if (audioFormat != 1 ||
        (channels != 1 && channels != 2) ||
        bitsPerSample != 16 ||
        sampleRate == null ||
        sampleRate <= 0 ||
        dataOffset == null ||
        dataLength == null ||
        dataLength == 0 ||
        dataLength % (channels! * 2) != 0) {
      throw const FormatException(
        'Unsupported WAV format. Expected PCM16 mono or stereo.',
      );
    }

    final sampleCount = dataLength ~/ 2;
    final samples = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(dataOffset + i * 2, Endian.little) / 32768.0;
    }

    return StudioDecodedAudio(
      samples: samples,
      sampleRate: sampleRate,
      channels: channels,
    );
  }
}
