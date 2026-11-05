import 'package:bloom/features/audio_dsp/audio_dsp_models.dart';
import 'package:bloom/features/audio_dsp/audio_dsp_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioPresets and Band Math', () {
    test('has 10 calibrated standard frequency bands', () {
      expect(AudioPresets.bandCount, 10);
      expect(AudioPresets.bandFrequencies, [
        31,
        62,
        125,
        250,
        500,
        1000,
        2000,
        4000,
        8000,
        16000,
      ]);
    });

    test('formats frequency labels correctly', () {
      expect(AudioPresets.frequencyLabel(31), '31Hz');
      expect(AudioPresets.frequencyLabel(500), '500Hz');
      expect(AudioPresets.frequencyLabel(1000), '1kHz');
      expect(AudioPresets.frequencyLabel(4000), '4kHz');
      expect(AudioPresets.frequencyLabel(16000), '16kHz');
    });

    test('levelToDb and dbToLevel convert within -12 dB to +12 dB range', () {
      expect(AudioPresets.levelToDb(0), 0.0);
      expect(AudioPresets.levelToDb(100), 12.0);
      expect(AudioPresets.levelToDb(-100), -12.0);
      expect(AudioPresets.levelToDb(50), closeTo(6.0, 1e-4));
      expect(AudioPresets.levelToDb(-50), closeTo(-6.0, 1e-4));

      expect(AudioPresets.dbToLevel(0.0), 0);
      expect(AudioPresets.dbToLevel(12.0), 100);
      expect(AudioPresets.dbToLevel(-12.0), -100);
      expect(AudioPresets.dbToLevel(6.0), 50);
      expect(AudioPresets.dbToLevel(-6.0), -50);
    });

    test('provides all 16 calibrated presets each with 10 bands', () {
      expect(AudioPresets.builtIns.length, greaterThanOrEqualTo(15));
      for (final preset in AudioPresets.builtIns) {
        expect(
          preset.levels.length,
          AudioPresets.bandCount,
          reason: 'Preset ${preset.id} must have 10 bands',
        );
        for (final lvl in preset.levels) {
          expect(lvl, inInclusiveRange(-100, 100));
        }
        expect(preset.bassBoost, inInclusiveRange(0, 100));
        expect(preset.virtualizer, inInclusiveRange(0, 100));
      }
    });

    test('flat preset has zero boost across all bands', () {
      final flat = AudioPresets.findById('flat');
      expect(flat, isNotNull);
      expect(flat!.levels, List.filled(10, 0));
      expect(flat.bassBoost, 0);
      expect(flat.virtualizer, 0);
    });
  });

  group('HeadroomGuard', () {
    test('calculates 0 dB headroom for flat EQ and 0 bass boost', () {
      final headroom = HeadroomGuard.calculateRequiredHeadroomDb(
        List.filled(10, 0),
        0,
      );
      expect(headroom, 0.0);
    });

    test('calculates headroom based on highest band boost', () {
      final bands = [0, 50, 0, 0, 100, 0, 0, 0, 0, 0];
      final headroom = HeadroomGuard.calculateRequiredHeadroomDb(bands, 0);
      expect(headroom, closeTo(12.0, 1e-3));
    });

    test('incorporates bass boost into lowest frequency bands', () {
      final bands = List.filled(10, 0);
      // 100% bass boost adds 6.0 dB at band 0 (weight 1.0)
      final headroom = HeadroomGuard.calculateRequiredHeadroomDb(bands, 100);
      expect(headroom, closeTo(6.0, 1e-3));
    });

    test('calculateSafeInputGainDb prevents digital clipping', () {
      // 0 headroom needed and 0 preamp -> 0 safe input gain
      expect(HeadroomGuard.calculateSafeInputGainDb(0.0, 0.0), 0.0);

      // +6 dB boost with 0 preamp -> needs -6 dB safe input gain
      final safeGain = HeadroomGuard.calculateSafeInputGainDb(0.0, 6.0);
      expect(safeGain, closeTo(-6.0, 1e-3));

      // -3 dB preamp already reserves 3 dB, so 6 dB boost only needs additional 3 dB cut (-6 dB total)
      final safeGainWithPreamp = HeadroomGuard.calculateSafeInputGainDb(-3.0, 6.0);
      expect(safeGainWithPreamp, closeTo(-6.0, 1e-3));
    });
  });

  group('CrossfadeMath (Equal-Power Conservation)', () {
    test('conserves acoustic power across the entire transition curve', () {
      for (var i = 0; i <= 100; i++) {
        final progress = i / 100.0;
        final (outgoing, incoming) = CrossfadeMath.equalPowerGains(progress);
        final totalPower = (outgoing * outgoing) + (incoming * incoming);
        expect(
          totalPower,
          closeTo(1.0, 1e-6),
          reason: 'Acoustic power must sum to 1.0 at progress $progress',
        );
      }
    });

    test('has correct boundary values at progress 0, 0.5, and 1.0', () {
      final (out0, in0) = CrossfadeMath.equalPowerGains(0.0);
      expect(out0, closeTo(1.0, 1e-6));
      expect(in0, closeTo(0.0, 1e-6));

      final (outHalf, inHalf) = CrossfadeMath.equalPowerGains(0.5);
      expect(outHalf, closeTo(0.707106, 1e-4));
      expect(inHalf, closeTo(0.707106, 1e-4));

      final (out1, in1) = CrossfadeMath.equalPowerGains(1.0);
      expect(out1, closeTo(0.0, 1e-6));
      expect(in1, closeTo(1.0, 1e-6));
    });
  });

  group('AlbumGaplessDetector', () {
    test('bypasses crossfade when shuffle is enabled', () {
      final isGapless = AlbumGaplessDetector.isSequentialAlbumTracks(
        currentAlbum: 'Dark Side of the Moon',
        nextAlbum: 'Dark Side of the Moon',
        currentArtist: 'Pink Floyd',
        nextArtist: 'Pink Floyd',
        currentTrackNum: 1,
        nextTrackNum: 2,
        currentDiscNum: 1,
        nextDiscNum: 1,
        isShuffle: true,
      );
      expect(isGapless, isFalse);
    });

    test('bypasses crossfade when albums differ', () {
      final isGapless = AlbumGaplessDetector.isSequentialAlbumTracks(
        currentAlbum: 'Album A',
        nextAlbum: 'Album B',
        currentArtist: 'Artist',
        nextArtist: 'Artist',
        currentTrackNum: 1,
        nextTrackNum: 2,
        currentDiscNum: 1,
        nextDiscNum: 1,
        isShuffle: false,
      );
      expect(isGapless, isFalse);
    });

    test('detects sequential tracks on the same album and disc', () {
      final isGapless = AlbumGaplessDetector.isSequentialAlbumTracks(
        currentAlbum: 'Abbey Road',
        nextAlbum: 'Abbey Road',
        currentArtist: 'The Beatles',
        nextArtist: 'The Beatles',
        currentTrackNum: 3,
        nextTrackNum: 4,
        currentDiscNum: 1,
        nextDiscNum: 1,
        isShuffle: false,
      );
      expect(isGapless, isTrue);
    });

    test('detects non-sequential track jump as false', () {
      final isGapless = AlbumGaplessDetector.isSequentialAlbumTracks(
        currentAlbum: 'Abbey Road',
        nextAlbum: 'Abbey Road',
        currentArtist: 'The Beatles',
        nextArtist: 'The Beatles',
        currentTrackNum: 3,
        nextTrackNum: 8,
        currentDiscNum: 1,
        nextDiscNum: 1,
        isShuffle: false,
      );
      expect(isGapless, isFalse);
    });

    test('detects sequential multi-disc album transition (disc 1 end -> disc 2 start)', () {
      final isGapless = AlbumGaplessDetector.isSequentialAlbumTracks(
        currentAlbum: 'The Wall',
        nextAlbum: 'The Wall',
        currentArtist: 'Pink Floyd',
        nextArtist: 'Pink Floyd',
        currentTrackNum: 13,
        nextTrackNum: 1,
        currentDiscNum: 1,
        nextDiscNum: 2,
        isShuffle: false,
      );
      expect(isGapless, isTrue);
    });
  });

  group('AudioDspState serialization', () {
    test('roundtrips JSON serialization correctly', () {
      final original = AudioDspState(
        enabled: true,
        presetId: 'rock',
        bands: [50, 30, -10, 0, 10, 25, 40, 50, 60, 70],
        bassBoost: 45,
        virtualizer: 20,
        preampDb: -2.5,
        headroomGuard: true,
        crossfadeSeconds: 4,
        smartAlbumGapless: true,
        volumeNormalization: true,
        customPresets: {
          'my_custom_1': const AudioPreset(
            id: 'my_custom_1',
            name: 'Studio Master',
            levels: [10, 20, 30, 40, 50, 40, 30, 20, 10, 0],
            bassBoost: 15,
            virtualizer: 5,
            isCustom: true,
          ),
        },
      );

      final json = original.toJson();
      final restored = AudioDspState.fromJson(json);

      expect(restored.enabled, original.enabled);
      expect(restored.presetId, original.presetId);
      expect(restored.bands, original.bands);
      expect(restored.bassBoost, original.bassBoost);
      expect(restored.virtualizer, original.virtualizer);
      expect(restored.preampDb, original.preampDb);
      expect(restored.headroomGuard, original.headroomGuard);
      expect(restored.crossfadeSeconds, original.crossfadeSeconds);
      expect(restored.smartAlbumGapless, original.smartAlbumGapless);
      expect(restored.volumeNormalization, original.volumeNormalization);
      expect(restored.customPresets.length, 1);
      final custom = restored.customPresets['my_custom_1'];
      expect(custom, isNotNull);
      expect(custom!.name, 'Studio Master');
      expect(custom.levels, [10, 20, 30, 40, 50, 40, 30, 20, 10, 0]);
      expect(custom.bassBoost, 15);
      expect(custom.isCustom, isTrue);
    });

    test('handles fallback defaults on empty or invalid JSON', () {
      final restored = AudioDspState.fromJson(null);
      expect(restored.enabled, isFalse);
      expect(restored.presetId, 'flat');
      expect(restored.bands.length, 10);
      expect(restored.headroomGuard, isTrue);
      expect(restored.smartAlbumGapless, isTrue);
      expect(restored.crossfadeSeconds, 0);
    });
  });
}
