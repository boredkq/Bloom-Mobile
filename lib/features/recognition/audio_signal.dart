import 'dart:math' as math;
import 'dart:typed_data';

/// Analysis of raw 16-bit PCM audio samples to detect silence or clipping.
class AudioSignalQuality {
  const AudioSignalQuality({
    required this.sampleCount,
    required this.rms,
    required this.peakAmplitude,
    required this.nonZeroRatio,
    required this.clippingRatio,
  });

  final int sampleCount;
  final double rms;
  final int peakAmplitude;
  final double nonZeroRatio;
  final double clippingRatio;

  bool get isSilent => peakAmplitude == 0 || nonZeroRatio < 0.001;
  bool get isTooQuiet => !isSilent && rms < silenceRmsFloor;

  static const double silenceRmsFloor = 60.0;
  static const int clippingThreshold = 32000;

  static AudioSignalQuality analyze(Int16List pcm16Mono) {
    if (pcm16Mono.isEmpty) {
      return const AudioSignalQuality(
        sampleCount: 0,
        rms: 0.0,
        peakAmplitude: 0,
        nonZeroRatio: 0.0,
        clippingRatio: 0.0,
      );
    }

    var sumOfSquares = 0.0;
    var peak = 0;
    var nonZeroCount = 0;
    var clippingCount = 0;
    final count = pcm16Mono.length;

    for (var i = 0; i < count; i++) {
      final value = pcm16Mono[i];
      final magnitude = value.abs();
      sumOfSquares += value * value;
      if (magnitude > peak) peak = magnitude;
      if (value != 0) nonZeroCount++;
      if (magnitude >= clippingThreshold) clippingCount++;
    }

    return AudioSignalQuality(
      sampleCount: count,
      rms: math.sqrt(sumOfSquares / count),
      peakAmplitude: peak,
      nonZeroRatio: nonZeroCount / count,
      clippingRatio: clippingCount / count,
    );
  }
}
