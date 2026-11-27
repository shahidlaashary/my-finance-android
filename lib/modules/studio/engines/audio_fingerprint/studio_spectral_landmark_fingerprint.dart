import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'studio_audio_fingerprint_contracts.dart';

/// Deterministic spectral-peak fingerprint generator.
///
/// It stores compact time/frequency landmarks rather than audio samples.
/// Algorithm changes must use a new algorithmVersion.
class StudioSpectralLandmarkFingerprint
    implements StudioAudioFingerprintAlgorithm {
  const StudioSpectralLandmarkFingerprint({
    this.fftSize = 2048,
    this.hopSize = 1024,
    this.peaksPerFrame = 5,
    this.segmentDurationMs = 10000,
  })  : assert(fftSize >= 256),
        assert((fftSize & (fftSize - 1)) == 0),
        assert(hopSize > 0),
        assert(peaksPerFrame > 0),
        assert(segmentDurationMs > 0);

  final int fftSize;
  final int hopSize;
  final int peaksPerFrame;
  final int segmentDurationMs;

  @override
  String get algorithmKey => 'studio.audio.spectral-landmark';

  @override
  String get algorithmVersion => '1.1.0';

  @override
  String get fingerprintFormat => 'studio-audio-landmarks-v1';

  @override
  Future<StudioAudioFingerprintOutput> generate(
    StudioDecodedAudio audio,
  ) async {
    final mono = _toMono(audio);
    if (mono.length < fftSize) {
      throw ArgumentError('Audio is shorter than one fingerprint analysis frame.');
    }

    final recordBytes = <int>[];
    final segmentRecords = <int, List<int>>{};
    final real = List<double>.filled(fftSize, 0);
    final imaginary = List<double>.filled(fftSize, 0);
    final window = List<double>.generate(
      fftSize,
      (i) => 0.5 - 0.5 * math.cos(2 * math.pi * i / (fftSize - 1)),
      growable: false,
    );

    var frameIndex = 0;
    for (var start = 0; start + fftSize <= mono.length; start += hopSize) {
      for (var i = 0; i < fftSize; i++) {
        real[i] = mono[start + i] * window[i];
        imaginary[i] = 0;
      }
      _fft(real, imaginary);

      final magnitudes = List<double>.filled(fftSize ~/ 2, 0);
      for (var bin = 1; bin < magnitudes.length; bin++) {
        magnitudes[bin] = math.sqrt(
          real[bin] * real[bin] + imaginary[bin] * imaginary[bin],
        );
      }

      final candidates = <int>[];
      for (var bin = 4; bin < magnitudes.length - 1; bin++) {
        if (magnitudes[bin] > magnitudes[bin - 1] &&
            magnitudes[bin] >= magnitudes[bin + 1]) {
          candidates.add(bin);
        }
      }
      candidates.sort((a, b) => magnitudes[b].compareTo(magnitudes[a]));
      final selected = candidates.take(peaksPerFrame);
      final timeMs = ((start + fftSize ~/ 2) * 1000 / audio.sampleRate).round();
      final segmentIndex = timeMs ~/ segmentDurationMs;
      final segment = segmentRecords.putIfAbsent(segmentIndex, () => <int>[]);

      for (final bin in selected) {
        // Eight-byte record: frame index, FFT bin, and normalized peak strength.
        final strength = (math.log(1 + magnitudes[bin]) * 4096)
            .round()
            .clamp(0, 65535)
            .toInt();
        final record = Uint8List(8);
        final view = ByteData.sublistView(record);
        view.setUint32(0, frameIndex, Endian.little);
        view.setUint16(4, bin, Endian.little);
        view.setUint16(6, strength, Endian.little);
        segment.addAll(record);
      }
      frameIndex++;
    }

    final outputBytes = <int>[];
    final segments = <StudioAudioFingerprintSegmentData>[];
    var segmentIndex = 0;
    for (final entry in segmentRecords.entries) {
      final bytes = entry.value;
      final offset = outputBytes.length;
      outputBytes.addAll(bytes);
      final startMs = entry.key * segmentDurationMs;
      final endMs = math.min(
        audio.durationMs,
        startMs + segmentDurationMs,
      ).toInt();
      segments.add(
        StudioAudioFingerprintSegmentData(
          segmentIndex: segmentIndex++,
          startMs: startMs,
          endMs: endMs,
          dataOffsetBytes: offset,
          dataLengthBytes: bytes.length,
          signatureHash: sha256.convert(bytes).toString(),
        ),
      );
    }

    return StudioAudioFingerprintOutput(
      bytes: Uint8List.fromList(outputBytes),
      frameCount: frameIndex,
      segments: segments,
    );
  }

  List<double> _toMono(StudioDecodedAudio audio) {
    if (audio.channels == 1) return audio.samples;
    final mono = List<double>.filled(audio.frameCount, 0);
    for (var frame = 0; frame < audio.frameCount; frame++) {
      var sum = 0.0;
      for (var channel = 0; channel < audio.channels; channel++) {
        sum += audio.samples[frame * audio.channels + channel];
      }
      mono[frame] = sum / audio.channels;
    }
    return mono;
  }

  void _fft(List<double> real, List<double> imaginary) {
    final n = real.length;
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final realValue = real[i];
        real[i] = real[j];
        real[j] = realValue;
        final imaginaryValue = imaginary[i];
        imaginary[i] = imaginary[j];
        imaginary[j] = imaginaryValue;
      }
    }

    for (var length = 2; length <= n; length <<= 1) {
      final angle = -2 * math.pi / length;
      final wLengthReal = math.cos(angle);
      final wLengthImaginary = math.sin(angle);
      for (var start = 0; start < n; start += length) {
        var wReal = 1.0;
        var wImaginary = 0.0;
        for (var k = 0; k < length ~/ 2; k++) {
          final even = start + k;
          final odd = even + length ~/ 2;
          final oddReal =
              real[odd] * wReal - imaginary[odd] * wImaginary;
          final oddImaginary =
              real[odd] * wImaginary + imaginary[odd] * wReal;
          real[odd] = real[even] - oddReal;
          imaginary[odd] = imaginary[even] - oddImaginary;
          real[even] += oddReal;
          imaginary[even] += oddImaginary;

          final nextWReal = wReal * wLengthReal -
              wImaginary * wLengthImaginary;
          wImaginary = wReal * wLengthImaginary +
              wImaginary * wLengthReal;
          wReal = nextWReal;
        }
      }
    }
  }
}
