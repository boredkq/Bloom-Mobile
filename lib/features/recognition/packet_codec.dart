import 'dart:typed_data';

enum FrequencyBand {
  low(0),
  midLow(1),
  midHigh(2),
  high(3);

  const FrequencyBand(this.wireId);
  final int wireId;
}

class SpectralPeak {
  const SpectralPeak({
    required this.frameIndex,
    required this.magnitude,
    required this.correctedBin,
  });

  final int frameIndex;
  final int magnitude;
  final int correctedBin;
}

/// Standard IEEE 802.3 CRC32 calculation.
class Crc32 {
  static final List<int> _table = () {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var j = 0; j < 8; j++) {
        if ((c & 1) != 0) {
          c = 0xEDB88320 ^ (c >>> 1);
        } else {
          c = c >>> 1;
        }
      }
      table[i] = c;
    }
    return table;
  }();

  static int compute(List<int> bytes, [int offset = 0, int? length]) {
    var c = 0xFFFFFFFF;
    final end = offset + (length ?? (bytes.length - offset));
    for (var i = offset; i < end; i++) {
      c = _table[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

/// Codec that serializes spectral peaks into Shazam's binary packet format.
class FingerprintPacketCodec {
  static const int magicA = 0xCAFE2580;
  static const int magicB = 0x94119C00;
  static const int headerSize = 48;
  static const int bodyTag = 0x40000000;
  static const int bandTagBase = 0x60030040;
  static const int absoluteFrameEscape = 0xFF;
  static const int sampleRateId16Khz = 3;
  static const double samplePaddingSeconds = 0.24;

  static Uint8List encode({
    required int sampleRateHz,
    required int sampleCount,
    required Map<FrequencyBand, List<SpectralPeak>> peaksByBand,
  }) {
    final bandBytes = BytesBuilder();
    final sortedBands = peaksByBand.keys.toList()
      ..sort((a, b) => a.wireId.compareTo(b.wireId));

    for (final band in sortedBands) {
      final peaks = peaksByBand[band];
      if (peaks == null || peaks.isEmpty) continue;
      final peakPayload = _encodePeaks(peaks);
      _writeLittleInt(bandBytes, bandTagBase + band.wireId);
      _writeLittleInt(bandBytes, peakPayload.length);
      bandBytes.add(peakPayload);
      final pad = (-peakPayload.length) % 4;
      final padCount = pad < 0 ? pad + 4 : pad;
      for (var i = 0; i < padCount; i++) {
        bandBytes.addByte(0);
      }
    }

    final encodedBands = bandBytes.takeBytes();
    final sizeMinusHeader = encodedBands.length + 8;

    final headerData = ByteData(headerSize);
    headerData.setUint32(0, magicA, Endian.little);
    headerData.setUint32(4, 0, Endian.little); // CRC placeholder
    headerData.setUint32(8, sizeMinusHeader, Endian.little);
    headerData.setUint32(12, magicB, Endian.little);
    headerData.setUint32(16, 0, Endian.little);
    headerData.setUint32(20, 0, Endian.little);
    headerData.setUint32(24, 0, Endian.little);
    headerData.setUint32(28, sampleRateId16Khz << 27, Endian.little);
    headerData.setUint32(32, 0, Endian.little);
    headerData.setUint32(36, 0, Endian.little);
    headerData.setUint32(
      40,
      (sampleCount + sampleRateHz * samplePaddingSeconds).toInt(),
      Endian.little,
    );
    headerData.setUint32(44, (15 << 19) + 0x40000, Endian.little);

    final packet = BytesBuilder();
    packet.add(headerData.buffer.asUint8List());
    _writeLittleInt(packet, bodyTag);
    _writeLittleInt(packet, sizeMinusHeader);
    packet.add(encodedBands);

    final bytes = packet.takeBytes();
    final crc = Crc32.compute(bytes, 8, bytes.length - 8);
    final view = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    view.setUint32(4, crc, Endian.little);
    return bytes;
  }

  static Uint8List _encodePeaks(List<SpectralPeak> peaks) {
    final sorted = List<SpectralPeak>.from(peaks)
      ..sort((a, b) => a.frameIndex.compareTo(b.frameIndex));
    final out = BytesBuilder();
    var previousFrame = 0;

    for (final peak in sorted) {
      var delta = peak.frameIndex - previousFrame;
      if (delta >= absoluteFrameEscape) {
        out.addByte(absoluteFrameEscape);
        _writeLittleInt(out, peak.frameIndex);
        previousFrame = peak.frameIndex;
        delta = 0;
      }
      out.addByte(delta.clamp(0, absoluteFrameEscape - 1));
      _writeLittleShort(out, peak.magnitude);
      _writeLittleShort(out, peak.correctedBin);
      previousFrame = peak.frameIndex;
    }

    return out.takeBytes();
  }

  static void _writeLittleInt(BytesBuilder b, int val) {
    b.addByte(val & 0xFF);
    b.addByte((val >>> 8) & 0xFF);
    b.addByte((val >>> 16) & 0xFF);
    b.addByte((val >>> 24) & 0xFF);
  }

  static void _writeLittleShort(BytesBuilder b, int val) {
    b.addByte(val & 0xFF);
    b.addByte((val >>> 8) & 0xFF);
  }
}
