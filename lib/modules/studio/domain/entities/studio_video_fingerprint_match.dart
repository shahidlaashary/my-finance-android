class StudioVideoFingerprintMatch {
  const StudioVideoFingerprintMatch({
    required this.matches,
    required this.queryFrames,
    required this.referenceFrames,
    required this.confidence,
    required this.offsetMs,
  });

  final int matches;
  final int queryFrames;
  final int referenceFrames;
  final int offsetMs;
  final double confidence;

  bool get isMatch => matches >= 3 && confidence >= 0.15;
}
