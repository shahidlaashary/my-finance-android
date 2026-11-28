import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/engines/video_fingerprint/studio_video_fingerprint_matcher.dart';

const _queryHashes = <int>[
  2481040521166681822,
  4880369992648891948,
  3226200683373518969,
  3520017203409810661,
  9192217636921393138,
  4450634989933947153,
  5934398258710840539,
  4244764367355312216,
  7972171298250599964,
  2099648675662337713,
  15365003085712134,
  5757532099830372025,
];

const _unrelatedHashes = <int>[
  9020830910331916353,
  3391022212753878601,
  3132996626709895672,
  1939229251872872551,
  5314641426230746217,
  1841294784444903972,
  4736384707650493920,
  7556246360347617565,
  6285139964275825406,
  7359107394608352558,
  805665040042016606,
  8475418501836914779,
];

void main() {
  const matcher = StudioVideoFingerprintMatcher();

  test('detects a short clip inside a longer reference with sampling drift', () {
    final query = [
      for (var i = 0; i < _queryHashes.length; i++)
        StudioVideoFrameSignature(timeMs: i * 2000, hash: _queryHashes[i]),
    ];
    final reference = [
      for (var i = 0; i < 30; i++)
        StudioVideoFrameSignature(
          timeMs: i * 2050,
          hash: i >= 7 && i < 19
              ? _queryHashes[i - 7]
              : _unrelatedHashes[i % _unrelatedHashes.length],
        ),
    ];

    final result = matcher.compare(query: query, reference: reference);

    expect(result.isMatch, isTrue);
    expect(result.matches, 12);
    expect(result.confidence, 1);
    expect(result.offsetMs, closeTo(14625, 1000));
    expect(result.matchedQueryTimestampsMs, [for (var i = 0; i < 12; i++) i * 2000]);
    expect(result.matchedReferenceTimestampsMs, [for (var i = 7; i < 19; i++) i * 2050]);
  });

  test('rejects unrelated frame signatures', () {
    final query = [
      for (var i = 0; i < _queryHashes.length; i++)
        StudioVideoFrameSignature(timeMs: i * 2000, hash: _queryHashes[i]),
    ];
    final reference = [
      for (var i = 0; i < _unrelatedHashes.length; i++)
        StudioVideoFrameSignature(
          timeMs: i * 2000,
          hash: _unrelatedHashes[i],
        ),
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
