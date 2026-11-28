import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/engines/audio_fingerprint/studio_audio_fingerprint_matcher.dart';

void main() {
  const matcher = StudioAudioFingerprintMatcher();

  test('finds a matching excerpt at a positive time offset', () {
    final reference = _artifact([
      for (var i = 0; i < 24; i++) (i, 20 + (i % 7)),
    ]);
    final query = _artifact([
      for (var i = 0; i < 16; i++) (i, 20 + (i % 7)),
    ]);

    final result = matcher.compare(query: query, reference: _shift(reference, 5));

    expect(result.isMatch, isTrue);
    expect(result.matchedLandmarks, greaterThanOrEqualTo(8));
    expect(result.offsetFrames, 5);
    expect(result.queryCoverage, 1);
    expect(result.matchedQueryTimestampsMs, hasLength(16));
    expect(result.matchedReferenceTimestampsMs, hasLength(16));
    expect(result.matchedQueryTimestampsMs.first, 0);
    expect(result.matchedReferenceTimestampsMs.first, result.offsetMs);
  });

  test('does not report a match for unrelated frequency landmarks', () {
    final a = _artifact([
      for (var i = 0; i < 20; i++) (i, 10 + (i % 4)),
    ]);
    final b = _artifact([
      for (var i = 0; i < 20; i++) (i, 100 + (i % 4)),
    ]);

    final result = matcher.compare(query: a, reference: b);

    expect(result.isMatch, isFalse);
    expect(result.confidence, 0);
  });

  test('rejects malformed fingerprint artifacts', () {
    expect(
      () => matcher.compare(
        query: Uint8List.fromList([1, 2, 3]),
        reference: Uint8List(8),
      ),
      throwsFormatException,
    );
  });

  test('empty artifacts return a non-match', () {
    final result = matcher.compare(
      query: Uint8List(0),
      reference: Uint8List(0),
    );
    expect(result.isMatch, isFalse);
    expect(result.confidence, 0);
  });
}

Uint8List _artifact(List<(int, int)> landmarks) {
  final bytes = Uint8List(landmarks.length * 8);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < landmarks.length; i++) {
    data.setUint32(i * 8, landmarks[i].$1, Endian.little);
    data.setUint16(i * 8 + 4, landmarks[i].$2, Endian.little);
    data.setUint16(i * 8 + 6, 1000, Endian.little);
  }
  return bytes;
}

Uint8List _shift(Uint8List source, int frames) {
  final shifted = Uint8List.fromList(source);
  final data = ByteData.sublistView(shifted);
  for (var offset = 0; offset < shifted.length; offset += 8) {
    data.setUint32(
      offset,
      data.getUint32(offset, Endian.little) + frames,
      Endian.little,
    );
  }
  return shifted;
}
