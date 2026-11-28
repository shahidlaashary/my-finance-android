import 'dart:math';

import '../../domain/entities/studio_video_fingerprint_match.dart';

/// Compares sampled video-frame signatures while allowing small sampling drift.
class StudioVideoFingerprintMatcher {
  const StudioVideoFingerprintMatcher({
    this.maxHammingDistance = 8,
    this.offsetToleranceMs = 1000,
  });

  final int maxHammingDistance;
  final int offsetToleranceMs;

  StudioVideoFingerprintMatch compare({
    required List<StudioVideoFrameSignature> query,
    required List<StudioVideoFrameSignature> reference,
  }) {
    if (query.isEmpty || reference.isEmpty) {
      return const StudioVideoFingerprintMatch(
        matches: 0, queryFrames: 0, referenceFrames: 0,
        confidence: 0, offsetMs: 0,
        matchedQueryTimestampsMs: const [],
        matchedReferenceTimestampsMs: const [],
      );
    }

    final queryFrequency = _frequencies(query);
    final referenceFrequency = _frequencies(reference);
    final queryCommonLimit = max(3, query.length ~/ 3);
    final referenceCommonLimit = max(3, reference.length ~/ 3);
    final buckets = <int, List<_FramePair>>{};

    for (var qi = 0; qi < query.length; qi++) {
      final q = query[qi];
      if ((queryFrequency[q.hash] ?? 0) > queryCommonLimit) continue;
      for (var ri = 0; ri < reference.length; ri++) {
        final r = reference[ri];
        if ((referenceFrequency[r.hash] ?? 0) > referenceCommonLimit) continue;
        final distance = _distance(q.hash, r.hash);
        if (distance > maxHammingDistance) continue;
        final offset = r.timeMs - q.timeMs;
        final bucket = (offset / offsetToleranceMs).round();
        buckets.putIfAbsent(bucket, () => <_FramePair>[]).add(
          _FramePair(qi, ri, offset, distance),
        );
      }
    }

    List<_FramePair> best = const [];
    var bestOffset = 0;
    for (final bucket in buckets.keys) {
      final centerOffset = bucket * offsetToleranceMs;
      final candidates = <_FramePair>[
        ...?buckets[bucket - 1],
        ...?buckets[bucket],
        ...?buckets[bucket + 1],
      ].where((pair) =>
          (pair.offsetMs - centerOffset).abs() <= offsetToleranceMs).toList();
      candidates.sort((a, b) => a.distance.compareTo(b.distance));
      final usedQuery = <int>{};
      final usedReference = <int>{};
      final selected = <_FramePair>[];
      for (final pair in candidates) {
        if (usedQuery.contains(pair.queryIndex) ||
            usedReference.contains(pair.referenceIndex)) {
          continue;
        }
        usedQuery.add(pair.queryIndex);
        usedReference.add(pair.referenceIndex);
        selected.add(pair);
      }
      final ordered = _longestOrderedSequence(selected);
      if (ordered.length > best.length) {
        best = ordered;
        if (ordered.isNotEmpty) {
          final offsets = ordered.map((p) => p.offsetMs).toList()..sort();
          bestOffset = offsets[offsets.length ~/ 2];
        }
      }
    }

    final denominator = min(query.length, reference.length);
    final confidence = denominator == 0 ? 0.0 : best.length / denominator;
    return StudioVideoFingerprintMatch(
      matches: best.length,
      queryFrames: query.length,
      referenceFrames: reference.length,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      offsetMs: bestOffset,
      matchedQueryTimestampsMs: best.map((pair) => query[pair.queryIndex].timeMs).toList(growable: false),
      matchedReferenceTimestampsMs: best.map((pair) => reference[pair.referenceIndex].timeMs).toList(growable: false),
    );
  }

  Map<int, int> _frequencies(List<StudioVideoFrameSignature> frames) {
    final result = <int, int>{};
    for (final frame in frames) {
      result.update(frame.hash, (count) => count + 1, ifAbsent: () => 1);
    }
    return result;
  }

  List<_FramePair> _longestOrderedSequence(List<_FramePair> pairs) {
    if (pairs.isEmpty) return const [];
    pairs.sort((a, b) => a.queryIndex.compareTo(b.queryIndex));
    final lengths = List<int>.filled(pairs.length, 1);
    final previous = List<int>.filled(pairs.length, -1);
    var bestIndex = 0;
    for (var i = 0; i < pairs.length; i++) {
      for (var j = 0; j < i; j++) {
        if (pairs[j].referenceIndex < pairs[i].referenceIndex &&
            lengths[j] + 1 > lengths[i]) {
          lengths[i] = lengths[j] + 1;
          previous[i] = j;
        }
      }
      if (lengths[i] > lengths[bestIndex]) bestIndex = i;
    }
    final result = <_FramePair>[];
    for (var index = bestIndex; index >= 0; index = previous[index]) {
      result.add(pairs[index]);
      if (previous[index] == -1) break;
    }
    return result.reversed.toList();
  }

  int _distance(int a, int b) {
    var value = a ^ b;
    var count = 0;
    while (value != 0) {
      value &= value - 1;
      count++;
    }
    return count;
  }
}

class StudioVideoFrameSignature {
  const StudioVideoFrameSignature({required this.timeMs, required this.hash});
  final int timeMs;
  final int hash;
}

class _FramePair {
  const _FramePair(this.queryIndex, this.referenceIndex, this.offsetMs, this.distance);
  final int queryIndex;
  final int referenceIndex;
  final int offsetMs;
  final int distance;
}
