import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bloom/features/recognition/audio_signal.dart';
import 'package:bloom/features/recognition/fft.dart';
import 'package:bloom/features/recognition/fingerprint_engine.dart';
import 'package:bloom/features/recognition/models.dart';
import 'package:bloom/features/recognition/native_audio_recorder.dart';
import 'package:bloom/features/recognition/packet_codec.dart';
import 'package:bloom/features/recognition/recognition_controller.dart';
import 'package:bloom/features/recognition/shazam_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Radix2Fft', () {
    test('rejects non power-of-two size', () {
      expect(() => Radix2Fft(100), throwsArgumentError);
      expect(() => Radix2Fft(0), throwsArgumentError);
      expect(() => Radix2Fft(1), throwsArgumentError);
    });

    test('transforms impulse into flat spectrum', () {
      final fft = Radix2Fft(64);
      final real = Float64List(64);
      final imag = Float64List(64);
      real[0] = 1.0;

      fft.transform(real, imag);

      for (var i = 0; i < 64; i++) {
        expect(real[i], closeTo(1.0, 1e-9));
        expect(imag[i], closeTo(0.0, 1e-9));
      }
    });

    test('transforms single sine wave with energy in expected bin', () {
      const size = 128;
      final fft = Radix2Fft(size);
      final real = Float64List(size);
      final imag = Float64List(size);

      const targetBin = 8;
      for (var i = 0; i < size; i++) {
        real[i] = math.cos(2.0 * math.pi * targetBin * i / size);
      }

      fft.transform(real, imag);

      final mag = Float64List(size ~/ 2 + 1);
      for (var i = 0; i < mag.length; i++) {
        mag[i] = math.sqrt(real[i] * real[i] + imag[i] * imag[i]);
      }

      var maxBin = 0;
      var maxVal = 0.0;
      for (var i = 0; i < mag.length; i++) {
        if (mag[i] > maxVal) {
          maxVal = mag[i];
          maxBin = i;
        }
      }

      expect(maxBin, equals(targetBin));
      expect(maxVal, closeTo(size / 2.0, 1e-6));
    });
  });

  group('AudioSignalQuality', () {
    test('detects silent buffer', () {
      final silence = Int16List(16000);
      final quality = AudioSignalQuality.analyze(silence);
      expect(quality.isSilent, isTrue);
      expect(quality.rms, equals(0.0));
      expect(quality.peakAmplitude, equals(0));
    });

    test('analyzes active audio tone', () {
      final samples = Int16List(16000);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = (math.sin(2.0 * math.pi * 440.0 * i / 16000) * 10000).toInt();
      }
      final quality = AudioSignalQuality.analyze(samples);
      expect(quality.isSilent, isFalse);
      expect(quality.isTooQuiet, isFalse);
      expect(quality.rms, greaterThan(6000.0));
      expect(quality.peakAmplitude, greaterThan(9000));
    });
  });

  group('Crc32 & FingerprintPacketCodec', () {
    test('computes standard IEEE 802.3 CRC32', () {
      final data = utf8.encode('123456789');
      final crc = Crc32.compute(data);
      expect(crc, equals(0xCBF43926));
    });

    test('encodes peaks into Shazam binary packet with magic and valid CRC', () {
      final peaks = {
        FrequencyBand.low: [
          const SpectralPeak(frameIndex: 10, magnitude: 5000, correctedBin: 120),
        ],
        FrequencyBand.midLow: [
          const SpectralPeak(frameIndex: 25, magnitude: 6200, correctedBin: 300),
        ],
      };

      final packet = FingerprintPacketCodec.encode(
        sampleRateHz: 16000,
        sampleCount: 16000 * 3,
        peaksByBand: peaks,
      );

      expect(packet.length, greaterThan(48));

      final view = ByteData.view(packet.buffer);
      final magicA = view.getUint32(0, Endian.little);
      final storedCrc = view.getUint32(4, Endian.little);
      final magicB = view.getUint32(12, Endian.little);

      expect(magicA, equals(FingerprintPacketCodec.magicA));
      expect(magicB, equals(FingerprintPacketCodec.magicB));

      final calcCrc = Crc32.compute(packet, 8, packet.length - 8);
      expect(storedCrc, equals(calcCrc));
    });
  });

  group('AcousticFingerprintEngine', () {
    test('returns null for silent audio', () {
      final silence = Int16List(16000 * 4);
      final engine = AcousticFingerprintEngine();
      final sig = engine.fingerprint(silence);
      expect(sig, isNull);
    });

    test('generates deterministic fingerprint for composite tone', () {
      const sampleRate = 16000;
      final samples = Int16List(sampleRate * 4);
      for (var i = 0; i < samples.length; i++) {
        final t = i / sampleRate;
        final v = (math.sin(2.0 * math.pi * 440.0 * t) +
                math.sin(2.0 * math.pi * 880.0 * t) +
                0.5 * math.sin(2.0 * math.pi * 1760.0 * t)) *
            12000.0;
        samples[i] = v.toInt();
      }

      final engine = AcousticFingerprintEngine();
      final first = engine.fingerprint(samples);
      final second = engine.fingerprint(samples);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.peakCount, greaterThan(0));
      expect(first.sampleDurationMs, greaterThan(1000));
      expect(first.payload, equals(second!.payload));
      expect(first.toDataUri(), startsWith('data:audio/vnd.shazam.sig;base64,'));
    });
  });

  group('ShazamClient JSON Parsing', () {
    test('parses full track metadata', () {
      final json = {
        'title': 'Blinding Lights',
        'subtitle': 'The Weeknd',
        'isrc': 'USUM71920807',
        'url': 'https://www.shazam.com/track/505322127/blinding-lights',
        'images': {
          'coverart': 'https://is1-ssl.mzstatic.com/image/thumb/low.jpg',
          'coverarthq': 'https://is1-ssl.mzstatic.com/image/thumb/high.jpg',
        },
        'genres': {'primary': 'Pop'},
        'sections': [
          {
            'type': 'SONG',
            'metadata': [
              {'title': 'Album', 'text': 'After Hours'},
              {'title': 'Label', 'text': 'XO / Republic Records'},
              {'title': 'Released', 'text': '2020'},
            ],
          },
        ],
        'hub': {
          'options': [
            {
              'type': 'video',
              'actions': [
                {'uri': 'https://www.youtube.com/watch?v=4NRXx6U8ABQ'},
              ],
            },
          ],
        },
      };

      final result = ShazamClient.parseTrackJson(json);
      expect(result, isNotNull);
      expect(result!.title, equals('Blinding Lights'));
      expect(result.artist, equals('The Weeknd'));
      expect(result.album, equals('After Hours'));
      expect(result.year, equals('2020'));
      expect(result.genre, equals('Pop'));
      expect(result.label, equals('XO / Republic Records'));
      expect(result.coverUrl, equals('https://is1-ssl.mzstatic.com/image/thumb/high.jpg'));
      expect(result.isrc, equals('USUM71920807'));
      expect(result.youtubeVideoId, equals('4NRXx6U8ABQ'));
      expect(result.searchPhrase, equals('The Weeknd Blinding Lights'));
    });

    test('returns null when title or subtitle are missing', () {
      expect(ShazamClient.parseTrackJson({'title': ''}), isNull);
      expect(ShazamClient.parseTrackJson({'subtitle': 'Artist'}), isNull);
      expect(ShazamClient.parseTrackJson({}), isNull);
    });
  });

  group('RecognitionResult & HistoryEntry serialization', () {
    test('roundtrips JSON', () {
      const result = RecognitionResult(
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        coverUrl: 'https://img.com/art.jpg',
        year: '2024',
        genre: 'Electronic',
      );

      final entry = RecognitionHistoryEntry(
        id: '123',
        result: result,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final json = entry.toJson();
      final restored = RecognitionHistoryEntry.fromJson(json);

      expect(restored.id, equals('123'));
      expect(restored.result.title, equals('Song'));
      expect(restored.result.artist, equals('Artist'));
      expect(restored.result.album, equals('Album'));
      expect(restored.result.coverUrl, equals('https://img.com/art.jpg'));
      expect(restored.result.year, equals('2024'));
      expect(restored.result.genre, equals('Electronic'));
      expect(restored.timestamp.millisecondsSinceEpoch, equals(1700000000000));
    });
  });

  group('RecognitionController State Flow', () {
    test('transitions states when listening and matched', () async {
      final mockRecorder = _MockAudioRecorder();
      final mockClient = _MockShazamClient();
      RecognitionResult? capturedResult;

      final controller = RecognitionController(
        recorder: mockRecorder,
        shazamClient: mockClient,
        fingerprintEngine: AcousticFingerprintEngine(),
        onMatch: (r) => capturedResult = r,
      );

      expect(controller.state, isA<RecognitionIdle>());

      final future = controller.startListening(durationMs: 1000);
      expect(controller.state, isA<RecognitionListening>());

      await future;

      expect(controller.state, isA<RecognitionMatch>());
      final match = controller.state as RecognitionMatch;
      expect(match.result.title, equals('Test Song'));
      expect(match.result.artist, equals('Test Artist'));
      expect(capturedResult, equals(match.result));
    });
  });
}

class _MockAudioRecorder implements NativeAudioRecorder {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<Uint8List?> captureAudio({int durationMs = 6000}) async {
    const sampleRate = 16000;
    final samples = Int16List(sampleRate * 2);
    for (var i = 0; i < samples.length; i++) {
      final t = i / sampleRate;
      samples[i] = ((math.sin(2.0 * math.pi * 440.0 * t) +
                  math.sin(2.0 * math.pi * 880.0 * t)) *
              10000.0)
          .toInt();
    }
    return Uint8List.view(samples.buffer);
  }

  @override
  Future<void> cancelCapture() async {}
}

class _MockShazamClient implements ShazamClient {
  @override
  Future<RecognitionResult?> identify(
    RecognitionSignature signature, {
    String? timezone,
  }) async {
    return const RecognitionResult(
      title: 'Test Song',
      artist: 'Test Artist',
      album: 'Test Album',
      coverUrl: 'https://example.com/cover.jpg',
    );
  }
}
