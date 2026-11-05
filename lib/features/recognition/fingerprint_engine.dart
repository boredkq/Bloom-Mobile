import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';
import 'models.dart';
import 'packet_codec.dart';

/// Configuration profile for fingerprint generation.
class FingerprintProfile {
  const FingerprintProfile({
    this.durationTargetSeconds = 3.1,
    this.peakTarget = 255,
    this.hardMaxDurationSeconds = 12.0,
    this.hardPeakLimit = 2048,
  });

  final double durationTargetSeconds;
  final int peakTarget;
  final double hardMaxDurationSeconds;
  final int hardPeakLimit;
}

/// Generates Shazam-compatible acoustic fingerprints from 16kHz mono PCM16 audio.
class AcousticFingerprintEngine {
  AcousticFingerprintEngine([this.profile = const FingerprintProfile()]);

  final FingerprintProfile profile;

  static const int sampleRateHz = 16000;
  static const int fftSize = 2048;
  static const int hopSize = 128;
  static const int spectrumBins = fftSize ~/ 2 + 1; // 1025
  static const int historyFrames = 256;
  static const int windowPeriod = 2050;
  static const int recognitionLag = 46;
  static const int spreadLag = 49;
  static const int minSearchBin = 10;
  static const int maxSearchBin = 1014;
  static const double magnitudeDivisor = 131072.0;
  static const double minMagnitude = 1e-10;
  static const double minPeakEnergy = 1.0 / 64.0;

  static const List<int> frequencyNeighbours = [
    -10,
    -7,
    -4,
    -3,
    1,
    2,
    5,
    8,
  ];
  static const List<int> timeNeighbours = [
    -53,
    -45,
    165,
    172,
    179,
    186,
    193,
    200,
    214,
    221,
    228,
    235,
    242,
    249,
  ];

  RecognitionSignature? fingerprint(Int16List pcm16Mono) {
    if (pcm16Mono.length < hopSize) return null;
    return _Session(profile).run(pcm16Mono);
  }
}

class _Session {
  _Session(this.profile);

  final FingerprintProfile profile;

  final Radix2Fft _fft = Radix2Fft(AcousticFingerprintEngine.fftSize);
  late final Float64List _window = () {
    final w = Float64List(AcousticFingerprintEngine.fftSize);
    for (var i = 0; i < AcousticFingerprintEngine.fftSize; i++) {
      w[i] =
          0.5 -
          0.5 *
              math.cos(
                2.0 *
                    math.pi *
                    (i + 1) /
                    (AcousticFingerprintEngine.windowPeriod - 1),
              );
    }
    return w;
  }();

  final Int32List _ring = Int32List(AcousticFingerprintEngine.fftSize);
  int _ringCursor = 0;

  final Float64List _real = Float64List(AcousticFingerprintEngine.fftSize);
  final Float64List _imaginary = Float64List(AcousticFingerprintEngine.fftSize);

  late final List<Float64List> _spectra = List.generate(
    AcousticFingerprintEngine.historyFrames,
    (_) => Float64List(AcousticFingerprintEngine.spectrumBins),
  );
  int _spectrumCursor = 0;

  late final List<Float64List> _spread = List.generate(
    AcousticFingerprintEngine.historyFrames,
    (_) => Float64List(AcousticFingerprintEngine.spectrumBins),
  );
  int _spreadCursor = 0;
  int _spreadFrames = 0;
  final Float64List _spreadScratch = Float64List(
    AcousticFingerprintEngine.spectrumBins,
  );

  final Map<FrequencyBand, List<SpectralPeak>> _peaks = {};
  int _processedSamples = 0;
  int _peakCount = 0;

  RecognitionSignature? run(Int16List samples) {
    final targetSamples =
        (profile.durationTargetSeconds *
                AcousticFingerprintEngine.sampleRateHz)
            .toInt();
    final hardMaxSamples =
        (profile.hardMaxDurationSeconds *
                AcousticFingerprintEngine.sampleRateHz)
            .toInt();

    var offset = 0;
    final totalSamples = samples.length;
    while (offset + AcousticFingerprintEngine.hopSize <= totalSamples &&
        _processedSamples < hardMaxSamples &&
        (_processedSamples < targetSamples ||
            _peakCount < profile.peakTarget)) {
      _appendFrame(samples, offset);
      offset += AcousticFingerprintEngine.hopSize;
      _processedSamples += AcousticFingerprintEngine.hopSize;
    }

    if (_peakCount == 0) return null;

    final bytes = FingerprintPacketCodec.encode(
      sampleRateHz: AcousticFingerprintEngine.sampleRateHz,
      sampleCount: _processedSamples,
      peaksByBand: _peaks,
    );

    return RecognitionSignature(
      payload: bytes,
      sampleDurationMs:
          _processedSamples * 1000 ~/ AcousticFingerprintEngine.sampleRateHz,
      peakCount: _peakCount,
    );
  }

  void _appendFrame(Int16List samples, int offset) {
    for (var i = 0; i < AcousticFingerprintEngine.hopSize; i++) {
      _ring[_ringCursor] = samples[offset + i];
      _ringCursor++;
      if (_ringCursor == AcousticFingerprintEngine.fftSize) _ringCursor = 0;
    }

    _calculateSpectrum();
    _spreadCurrentSpectrum();

    if (_spreadFrames >= AcousticFingerprintEngine.recognitionLag &&
        _peakCount < profile.hardPeakLimit) {
      _collectPeaks();
    }
  }

  void _calculateSpectrum() {
    var source = _ringCursor;
    for (var i = 0; i < AcousticFingerprintEngine.fftSize; i++) {
      _real[i] = _ring[source] * _window[i];
      _imaginary[i] = 0.0;
      source++;
      if (source == AcousticFingerprintEngine.fftSize) source = 0;
    }

    _fft.transform(_real, _imaginary);

    final output = _spectra[_spectrumCursor];
    for (var bin = 0; bin < AcousticFingerprintEngine.spectrumBins; bin++) {
      final r = _real[bin];
      final im = _imaginary[bin];
      final energy = (r * r + im * im) / AcousticFingerprintEngine.magnitudeDivisor;
      output[bin] =
          energy > AcousticFingerprintEngine.minMagnitude
              ? energy
              : AcousticFingerprintEngine.minMagnitude;
    }

    _spectrumCursor = _nextIndex(_spectrumCursor);
  }

  void _spreadCurrentSpectrum() {
    final source = _spectra[_historyIndex(_spectrumCursor, -1)];
    for (var bin = 0; bin < AcousticFingerprintEngine.spectrumBins - 3; bin++) {
      final b0 = source[bin];
      final b1 = source[bin + 1];
      final b2 = source[bin + 2];
      _spreadScratch[bin] = math.max(b0, math.max(b1, b2));
    }
    for (
      var bin = AcousticFingerprintEngine.spectrumBins - 3;
      bin < AcousticFingerprintEngine.spectrumBins;
      bin++
    ) {
      _spreadScratch[bin] = source[bin];
    }

    final oneBack = _spread[_historyIndex(_spreadCursor, -1)];
    final threeBack = _spread[_historyIndex(_spreadCursor, -3)];
    final sixBack = _spread[_historyIndex(_spreadCursor, -6)];

    for (var bin = 0; bin < AcousticFingerprintEngine.spectrumBins; bin++) {
      final first = math.max(_spreadScratch[bin], oneBack[bin]);
      oneBack[bin] = first;
      final second = math.max(first, threeBack[bin]);
      threeBack[bin] = second;
      sixBack[bin] = math.max(second, sixBack[bin]);
    }

    _spread[_spreadCursor].setAll(0, _spreadScratch);
    _spreadCursor = _nextIndex(_spreadCursor);
    _spreadFrames++;
  }

  void _collectPeaks() {
    final spectrum =
        _spectra[_historyIndex(
          _spectrumCursor,
          -AcousticFingerprintEngine.recognitionLag,
        )];
    final comparison =
        _spread[_historyIndex(
          _spreadCursor,
          -AcousticFingerprintEngine.spreadLag,
        )];

    for (
      var bin = AcousticFingerprintEngine.minSearchBin;
      bin <= AcousticFingerprintEngine.maxSearchBin;
      bin++
    ) {
      if (_peakCount >= profile.hardPeakLimit) return;

      final energy = spectrum[bin];
      if (energy < AcousticFingerprintEngine.minPeakEnergy ||
          energy < comparison[bin - 1]) {
        continue;
      }
      if (!_isFrequencyMaximum(energy, comparison, bin)) continue;
      if (!_isTimeMaximum(energy, bin)) continue;

      final magnitude = _encodedMagnitude(energy);
      final before = _encodedMagnitude(spectrum[bin - 1]);
      final after = _encodedMagnitude(spectrum[bin + 1]);
      final curvature = magnitude * 2.0 - before - after
          ;
      if (curvature <= 0.0) continue;

      final correction = (after - before) * 32.0 / curvature;
      final correctedBin = bin * 64.0 + correction;
      final frequencyHz =
          correctedBin *
          (AcousticFingerprintEngine.sampleRateHz / 2.0 / 1024.0 / 64.0);
      final band = _bandFor(frequencyHz);
      if (band == null) continue;

      _peaks.putIfAbsent(band, () => []).add(
        SpectralPeak(
          frameIndex:
              _spreadFrames - AcousticFingerprintEngine.recognitionLag,
          magnitude: magnitude.toInt(),
          correctedBin: correctedBin.toInt(),
        ),
      );
      _peakCount++;
    }
  }

  bool _isFrequencyMaximum(
    double energy,
    Float64List comparison,
    int bin,
  ) {
    var strongest = 0.0;
    for (final offset in AcousticFingerprintEngine.frequencyNeighbours) {
      strongest = math.max(strongest, comparison[bin + offset]);
    }
    return energy > strongest;
  }

  bool _isTimeMaximum(double energy, int bin) {
    var strongest = 0.0;
    for (final offset in AcousticFingerprintEngine.timeNeighbours) {
      final candidate = _spread[_historyIndex(_spreadCursor, offset)][bin - 1];
      strongest = math.max(strongest, candidate);
    }
    return energy > strongest;
  }

  double _encodedMagnitude(double energy) =>
      math.log(math.max(AcousticFingerprintEngine.minPeakEnergy, energy)) *
          1477.3 +
      6144.0;

  FrequencyBand? _bandFor(double frequencyHz) {
    if (frequencyHz > 250.0 && frequencyHz <= 520.0) return FrequencyBand.low;
    if (frequencyHz > 520.0 && frequencyHz <= 1450.0) {
      return FrequencyBand.midLow;
    }
    if (frequencyHz > 1450.0 && frequencyHz <= 3500.0) {
      return FrequencyBand.midHigh;
    }
    if (frequencyHz > 3500.0 && frequencyHz <= 5500.0) return FrequencyBand.high;
    return null;
  }

  int _nextIndex(int index) =>
      (index + 1 == AcousticFingerprintEngine.historyFrames) ? 0 : index + 1;

  int _historyIndex(int cursor, int offset) {
    final raw = (cursor + offset) % AcousticFingerprintEngine.historyFrames;
    return raw < 0 ? raw + AcousticFingerprintEngine.historyFrames : raw;
  }
}
