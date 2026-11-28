class StudioVideoFingerprintMatch {
  const StudioVideoFingerprintMatch({
    required this.matches,
    required this.queryFrames,
    required this.referenceFrames,
    required this.confidence,
    required this.offsetMs,
    this.matchedQueryTimestampsMs = const [],
    this.matchedReferenceTimestampsMs = const [],
  });

  final int matches;
  final int queryFrames;
  final int referenceFrames;
  final int offsetMs;
  final double confidence;
  final List<int> matchedQueryTimestampsMs;
  final List<int> matchedReferenceTimestampsMs;

  bool get isMatch => matches >= 3 && confidence >= 0.15;
}
