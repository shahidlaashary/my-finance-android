import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/engines/video_fingerprint/studio_video_fingerprint_matcher.dart';

void main() {
  const matcher = StudioVideoFingerprintMatcher();

  test('detects a short clip inside a longer reference with sampling drift', () {
    final query = [
      for (var i = 0; i < 12; i++)
        StudioVideoFrameSignature(timeMs: i * 2000, hash: 1000 + i * 97),
    ];
    final reference = [
      for (var i = 0; i < 30; i++)
        StudioVideoFrameSignature(
          timeMs: i * 2050,
          hash: i >= 7 && i < 19 ? 1000 + (i - 7) * 97 : 50000 + i * 131,
        ),
    ];

    final result = matcher.compare(query: query, reference: reference);

    expect(result.isMatch, isTrue);
    expect(result.matches, 12);
    expect(result.confidence, 1);
    expect(result.offsetMs, closeTo(14350, 1000));
  });

  test('rejects unrelated frame signatures', () {
    final query = [
      for (var i = 0; i < 12; i++)
        StudioVideoFrameSignature(timeMs: i * 2000, hash: 1000 + i * 97),
    ];
    final reference = [
      for (var i = 0; i < 12; i++)
        StudioVideoFrameSignature(timeMs: i * 2000, hash: 50000 + i * 131),
    ];

    final result = matcher.compare(query: query, reference: reference);

    expect(result.isMatch, isFalse);
    expect(result.matches, 0);
  });

  test('ignores repeated static-frame hashes to reduce false positives', () {
    final query = [
      for (var i = 0; i < 20; i++)
        StudioVideoFrameSignature(timeMs: i * 2000, hash: 12345),
    ];
    final reference = [
      for (var i = 0; i < 20; i++)
        StudioVideoFrameSignature(timeMs: i * 2000, hash: 12345),
    ];

    final result = matcher.compare(query: query, reference: reference);

    expect(result.isMatch, isFalse);
    expect(result.matches, 0);
  });
}
