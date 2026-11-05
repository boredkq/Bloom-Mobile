import 'dart:math' as math;
import 'dart:typed_data';

/// Fast Radix-2 Decimation-In-Time Fast Fourier Transform.
class Radix2Fft {
  Radix2Fft(this.size) {
    if (size <= 1 || (size & (size - 1)) != 0) {
      throw ArgumentError('FFT size must be a power of 2 greater than 1');
    }
    cosine = Float64List(size ~/ 2);
    sine = Float64List(size ~/ 2);
    for (var i = 0; i < size ~/ 2; i++) {
      cosine[i] = math.cos(2.0 * math.pi * i / size);
      sine[i] = math.sin(2.0 * math.pi * i / size);
    }
    final bits = (math.log(size) / math.ln2).round();
    bitReversed = Int32List(size);
    for (var i = 0; i < size; i++) {
      bitReversed[i] = _reverseBits(i, bits);
    }
  }

  final int size;
  late final Float64List cosine;
  late final Float64List sine;
  late final Int32List bitReversed;

  static int _reverseBits(int value, int bitCount) {
    var source = value;
    var target = 0;
    for (var i = 0; i < bitCount; i++) {
      target = (target << 1) | (source & 1);
      source >>= 1;
    }
    return target;
  }

  /// In-place in-order discrete Fourier transform of real and imaginary buffers.
  void transform(Float64List real, Float64List imaginary) {
    for (var index = 0; index < size; index++) {
      final mirror = bitReversed[index];
      if (mirror <= index) continue;
      final realVal = real[index];
      real[index] = real[mirror];
      real[mirror] = realVal;
      final imagVal = imaginary[index];
      imaginary[index] = imaginary[mirror];
      imaginary[mirror] = imagVal;
    }

    var width = 2;
    while (width <= size) {
      final halfWidth = width >> 1;
      final twiddleStep = size ~/ width;
      var blockStart = 0;
      while (blockStart < size) {
        var offset = 0;
        var twiddleIndex = 0;
        while (offset < halfWidth) {
          final low = blockStart + offset;
          final high = low + halfWidth;
          final highReal = real[high];
          final highImaginary = imaginary[high];
          final rotatedReal =
              highReal * cosine[twiddleIndex] +
              highImaginary * sine[twiddleIndex];
          final rotatedImaginary =
              -highReal * sine[twiddleIndex] +
              highImaginary * cosine[twiddleIndex];

          real[high] = real[low] - rotatedReal;
          imaginary[high] = imaginary[low] - rotatedImaginary;
          real[low] += rotatedReal;
          imaginary[low] += rotatedImaginary;

          offset++;
          twiddleIndex += twiddleStep;
        }
        blockStart += width;
      }
      width <<= 1;
    }
  }
}
