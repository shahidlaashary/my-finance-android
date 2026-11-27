import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_audio_fingerprint_contracts.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_spectral_landmark_fingerprint.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_wav_pcm16_decoder.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studio-wav-decoder-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('decodes PCM16 mono WAV into normalized samples', () async {
    final file = File('${directory.path}/tone.wav');
    await file.writeAsBytes(_wavPcm16(
      sampleRate: 11025,
      channels: 1,
      samples: _tone(11025, 440),
    ));

    final decoded = await const StudioWavPcm16Decoder().decode(file.path);

    expect(decoded.sampleRate, 11025);
    expect(decoded.channels, 1);
    expect(decoded.frameCount, 11025);
    expect(decoded.durationMs, 1000);
    expect(decoded.samples.first, closeTo(0, 0.0001));
    expect(decoded.samples.any((sample) => sample.abs() > 0.5), isTrue);
  });

  test('rejects unsupported non-WAV input', () async {
    final file = File('${directory.path}/not-a-wave.bin');
    await file.writeAsBytes([1, 2, 3, 4, 5]);

    await expectLater(
      const StudioWavPcm16Decoder().decode(file.path),
      throwsFormatException,
    );
  });

  test('generates deterministic spectral landmarks and time segments', () async {
    final decoder = const StudioWavPcm16Decoder();
    final file = File('${directory.path}/tone.wav');
    await file.writeAsBytes(_wavPcm16(
      sampleRate: 11025,
      channels: 1,
      samples: _tone(22050, 440),
    ));
    final decoded = await decoder.decode(file.path);
    const algorithm = StudioSpectralLandmarkFingerprint();

    final first = await algorithm.generate(decoded);
    final second = await algorithm.generate(decoded);

    expect(first.bytes, isNotEmpty);
    expect(first.frameCount, greaterThan(0));
    expect(first.bytes, orderedEquals(second.bytes));
    expect(first.segments, hasLength(2));
    expect(first.segments.first.startMs, 0);
    expect(first.segments.last.endMs, decoded.durationMs);
    expect(first.segments.every((segment) => segment.signatureHash != null), isTrue);
  });

  test('different tones produce different fingerprint artifacts', () async {
    final algorithm = const StudioSpectralLandmarkFingerprint();
    final a = StudioDecodedAudio(
      samples: Float32List.fromList(_tone(11025, 440)),
      sampleRate: 11025,
      channels: 1,
    );
    final b = StudioDecodedAudio(
      samples: Float32List.fromList(_tone(11025, 880)),
      sampleRate: 11025,
      channels: 1,
    );

    final first = await algorithm.generate(a);
    final second = await algorithm.generate(b);

    expect(first.bytes, isNot(orderedEquals(second.bytes)));
  });
}

List<double> _tone(int sampleCount, double frequency) {
  return List<double>.generate(
    sampleCount,
    (index) => 0.7 * math.sin(2 * math.pi * frequency * index / 11025),
  );
}

Uint8List _wavPcm16({
  required int sampleRate,
  required int channels,
  required List<double> samples,
}) {
  final dataLength = samples.length * 2;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  void putText(int offset, String value) {
    bytes.setRange(offset, offset + value.length, value.codeUnits);
  }

  putText(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  putText(8, 'WAVE');
  putText(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * 2, Endian.little);
  data.setUint16(32, channels * 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  putText(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final value = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    data.setInt16(44 + i * 2, value, Endian.little);
  }
  return bytes;
}
