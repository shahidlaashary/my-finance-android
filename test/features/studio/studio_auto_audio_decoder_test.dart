import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_auto_audio_decoder.dart';

void main() {
  late Directory directory;
  setUp(() async => directory = await Directory.systemTemp.createTemp('studio-auto-audio-'));
  tearDown(() async => directory.delete(recursive: true));

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

  test('rejects invalid encoded audio rather than creating an empty fingerprint', () async {
    final file = File('${directory.path}/broken.mp3');
    await file.writeAsBytes([0, 1, 2, 3, 4, 5, 6]);
    await expectLater(
      const StudioAutoAudioDecoder().decode(file.path),
      throwsA(anything),
    );
  });
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
