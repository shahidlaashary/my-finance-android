import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_auto_audio_decoder.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_audio_fingerprint_matcher.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_spectral_landmark_fingerprint.dart';

void main() {
  late Directory directory;
  setUp(() async => directory = await Directory.systemTemp.createTemp('studio-auto-audio-'));
  tearDown(() async => directory.delete(recursive: true));

  test('allows audio files larger than the former 100 MB ceiling', () {
    expect(
      StudioAutoAudioDecoder.maxEncodedFileBytes,
      greaterThan(100 * 1024 * 1024),
    );
    expect(
      StudioAutoAudioDecoder.maxEncodedFileBytes,
      200 * 1024 * 1024,
    );
  });

  test('normalizes WAV input to mono 11025 Hz fingerprint PCM', () async {
    final file = File('${directory.path}/source.wav');
    await file.writeAsBytes(_wav(sampleRate: 44100, channels: 2, durationSeconds: 1));
    final decoded = await const StudioAutoAudioDecoder().decode(file.path);
    expect(decoded.sampleRate, StudioAutoAudioDecoder.fingerprintSampleRate);
    expect(decoded.channels, 1);
    expect(decoded.frameCount, closeTo(11025, 2));
    expect(decoded.durationMs, closeTo(1000, 1));
    expect(decoded.samples.any((sample) => sample.abs() > 0.1), isTrue);
  });

  test('decodes a valid MPEG-1 Layer III silent MP3 stream', () async {
    final file = File('${directory.path}/valid-silent.mp3');
    await file.writeAsBytes(_silentMp3(frameCount: 48));
    final decoded = await const StudioAutoAudioDecoder().decode(file.path);

    expect(decoded.sampleRate, StudioAutoAudioDecoder.fingerprintSampleRate);
    expect(decoded.channels, 1);
    expect(decoded.frameCount, greaterThan(0));
    expect(decoded.durationMs, greaterThan(900));
  });

  test('runs decoded audio through fingerprint generation and matching', () async {
    final file = File('${directory.path}/reference.wav');
    await file.writeAsBytes(_wav(sampleRate: 44100, channels: 1, durationSeconds: 3));
    final decoder = const StudioAutoAudioDecoder();
    final algorithm = const StudioSpectralLandmarkFingerprint();
    final decodedReference = await decoder.decode(file.path);
    final decodedCandidate = await decoder.decode(file.path);
    final reference = await algorithm.generate(decodedReference);
    final candidate = await algorithm.generate(decodedCandidate);
    final result = const StudioAudioFingerprintMatcher().compare(
      query: candidate.bytes,
      reference: reference.bytes,
    );

    expect(reference.bytes, isNotEmpty);
    expect(candidate.bytes, isNotEmpty);
    expect(result.isMatch, isTrue);
    expect(result.offsetMs, 0);
    expect(result.confidence, greaterThanOrEqualTo(0.12));
  });

  test('rejects an OGG file with an invalid container signature', () async {
    final file = File('${directory.path}/broken.ogg');
    await file.writeAsBytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0]);
    await expectLater(
      const StudioAutoAudioDecoder().decode(file.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unsupported audio extensions before decoding', () async {
    final file = File('${directory.path}/unsupported.flac');
    await file.writeAsBytes([0, 1, 2, 3]);
    await expectLater(
      const StudioAutoAudioDecoder().decode(file.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects invalid encoded audio rather than creating an empty fingerprint', () async {
    final file = File('${directory.path}/broken.mp3');
    await file.writeAsBytes([0, 1, 2, 3, 4, 5, 6]);
    await expectLater(
      const StudioAutoAudioDecoder().decode(file.path),
      throwsA(anything),
    );
  });
}

Uint8List _silentMp3({required int frameCount}) {
  // MPEG-1 Layer III, 128 kbps, 44.1 kHz, stereo, no CRC.
  // Zeroed side information and main data encode silent granules.
  const frameLength = 417;
  final bytes = Uint8List(frameCount * frameLength);
  for (var frame = 0; frame < frameCount; frame++) {
    final offset = frame * frameLength;
    bytes[offset] = 0xff;
    bytes[offset + 1] = 0xfb;
    bytes[offset + 2] = 0x90;
    bytes[offset + 3] = 0x64;
  }
  return bytes;
}

Uint8List _wav({required int sampleRate, required int channels, required int durationSeconds}) {
  final frames = sampleRate * durationSeconds;
  final dataLength = frames * channels * 2;
  final bytes = Uint8List(44 + dataLength);
  final view = ByteData.sublistView(bytes);
  void text(int offset, String value) => bytes.setRange(offset, offset + value.length, value.codeUnits);
  text(0, 'RIFF');
  view.setUint32(4, 36 + dataLength, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * channels * 2, Endian.little);
  view.setUint16(32, channels * 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  text(36, 'data');
  view.setUint32(40, dataLength, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    final sample = (0.5 * math.sin(2 * math.pi * 440 * frame / sampleRate) * 32767).round();
    for (var channel = 0; channel < channels; channel++) {
      view.setInt16(44 + (frame * channels + channel) * 2, sample, Endian.little);
    }
  }
  return bytes;
}
