import 'dart:math' as math;

/// Definition of an equalizer preset.
class AudioPreset {
  const AudioPreset({
    required this.id,
    required this.name,
    required this.levels,
    this.bassBoost = 0,
    this.virtualizer = 0,
    this.isCustom = false,
  });

  final String id;
  final String name;

  /// 10 levels from -100 to 100 (-12 dB to +12 dB).
  final List<int> levels;

  /// Bass boost percentage (0 to 100).
  final int bassBoost;

  /// Spatial audio / virtualizer percentage (0 to 100).
  final int virtualizer;

  /// Whether this preset was created by the user.
  final bool isCustom;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'levels': levels,
    'bassBoost': bassBoost,
    'virtualizer': virtualizer,
    'isCustom': isCustom,
  };

  factory AudioPreset.fromJson(Map<String, dynamic> json) => AudioPreset(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    levels: (json['levels'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        List.filled(AudioPresets.bandCount, 0),
    bassBoost: (json['bassBoost'] as num?)?.toInt() ?? 0,
    virtualizer: (json['virtualizer'] as num?)?.toInt() ?? 0,
    isCustom: json['isCustom'] as bool? ?? false,
  );
}

/// Catalog of studio equalizer presets ported and calibrated.
class AudioPresets {
  static const int bandCount = 10;
  static const double maxBandDb = 12.0;

  static const List<String> bandFrequencyLabels = [
    '31',
    '62',
    '125',
    '250',
    '500',
    '1k',
    '2k',
    '4k',
    '8k',
    '16k',
  ];

  static const List<int> bandFrequenciesHz = [
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
  ];

  static List<int> get bandFrequencies => bandFrequenciesHz;

  static String frequencyLabel(int hz) {
    if (hz >= 1000) {
      return '${hz ~/ 1000}kHz';
    }
    return '${hz}Hz';
  }

  static double levelToDb(int level) =>
      (level.clamp(-100, 100) / 100.0) * maxBandDb;

  static int dbToLevel(double db) =>
      ((db / maxBandDb) * 100.0).round().clamp(-100, 100);

  static const String flatId = 'flat';
  static const String customId = 'custom';

  static List<AudioPreset> get builtIns => builtIn;

  static AudioPreset? findById(String id) {
    for (final p in builtIn) {
      if (p.id == id) return p;
    }
    return null;
  }

  static const List<AudioPreset> builtIn = [
    AudioPreset(
      id: flatId,
      name: 'Flat',
      levels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ),
    AudioPreset(
      id: 'bass_boost',
      name: 'Bass Boost',
      levels: [72, 58, 38, 18, 4, 0, 8, 16, 22, 24],
      bassBoost: 75,
      virtualizer: 18,
    ),
    AudioPreset(
      id: 'vocal',
      name: 'Vocal',
      levels: [-20, -12, 0, 24, 48, 54, 42, 20, 8, 0],
      bassBoost: 8,
      virtualizer: 6,
    ),
    AudioPreset(
      id: 'rock',
      name: 'Rock',
      levels: [52, 38, 16, -8, -14, 0, 18, 32, 44, 50],
      bassBoost: 50,
      virtualizer: 15,
    ),
    AudioPreset(
      id: 'pop',
      name: 'Pop',
      levels: [-10, 24, 42, 36, 12, -8, -12, 14, 30, 22],
      bassBoost: 30,
      virtualizer: 10,
    ),
    AudioPreset(
      id: 'electronic',
      name: 'Electronic',
      levels: [68, 54, 28, 0, -16, 12, 24, 42, 58, 62],
      bassBoost: 65,
      virtualizer: 25,
    ),
    AudioPreset(
      id: 'jazz',
      name: 'Jazz',
      levels: [24, 16, 8, 12, -10, -10, 0, 14, 28, 34],
      bassBoost: 20,
      virtualizer: 10,
    ),
    AudioPreset(
      id: 'acoustic',
      name: 'Acoustic',
      levels: [28, 18, 10, 12, 18, 14, 22, 30, 26, 18],
      bassBoost: 15,
      virtualizer: 5,
    ),
    AudioPreset(
      id: 'classical',
      name: 'Classical',
      levels: [32, 24, 16, 8, -4, -4, 0, 16, 24, 28],
      bassBoost: 10,
      virtualizer: 15,
    ),
    AudioPreset(
      id: 'night',
      name: 'Night',
      levels: [-24, -18, -8, 4, 10, 12, 6, -2, -8, -16],
    ),
    AudioPreset(
      id: 'gym',
      name: 'Gym',
      levels: [76, 64, 42, 18, 4, 6, 22, 42, 56, 48],
      bassBoost: 80,
      virtualizer: 34,
    ),
    AudioPreset(
      id: 'car',
      name: 'Car',
      levels: [44, 38, 26, 10, 0, 8, 24, 34, 38, 32],
      bassBoost: 48,
      virtualizer: 22,
    ),
    AudioPreset(
      id: 'airpods_pro',
      name: 'AirPods Pro',
      levels: [-12, -6, 4, 8, 2, -4, 6, 12, 8, -4],
      bassBoost: 10,
      virtualizer: 10,
    ),
    AudioPreset(
      id: 'sony_xm4_xm5',
      name: 'Sony WH-1000XM4/5',
      levels: [-25, -16, -6, 3, 7, 5, 5, 13, 8, -7],
      bassBoost: 0,
      virtualizer: 10,
    ),
    AudioPreset(
      id: 'hd600',
      name: 'Sennheiser HD600',
      levels: [42, 32, 14, 2, -2, -4, 2, 8, 4, -12],
      bassBoost: 35,
      virtualizer: 5,
    ),
  ];

  static AudioPreset byId(String id, [Map<String, AudioPreset>? custom]) {
    if (custom != null && custom.containsKey(id)) {
      return custom[id]!;
    }
    return builtIn.firstWhere(
      (p) => p.id == id,
      orElse: () => builtIn.first,
    );
  }
}

/// Dynamic headroom guard preventing inter-sample clipping when EQ bands are boosted.
class HeadroomGuard {
  static const double maxBandDb = 12.0;
  static const double bassMaxDb = 6.0;
  static const List<double> bassWeights = [
    1.0,
    0.82,
    0.48,
    0.18,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
  ];

  /// Calculates highest program boost dB across all bands and bass boost.
  static double calculateRequiredHeadroomDb(
    List<int> bandLevels,
    int bassBoost,
  ) {
    var highestBoost = 0.0;
    final count = math.min(bandLevels.length, AudioPresets.bandCount);
    for (var i = 0; i < count; i++) {
      final userDb = (bandLevels[i].clamp(-100, 100) / 100.0) * maxBandDb;
      final bassDb =
          (bassBoost.clamp(0, 100) / 100.0) * bassMaxDb * bassWeights[i];
      final totalDb = userDb + bassDb;
      if (totalDb > highestBoost) highestBoost = totalDb;
    }
    return highestBoost;
  }

  /// Calculates safe linear input gain to eliminate clipping distortion.
  static double calculateSafeInputGainDb(
    double preampDb,
    double requiredHeadroomDb,
  ) {
    final clampedPreamp = preampDb.clamp(-12.0, 3.0);
    final reservedByPreamp =
        (-clampedPreamp).clamp(0.0, double.infinity).toDouble();
    final extraHeadroomNeeded =
        (requiredHeadroomDb - reservedByPreamp)
            .clamp(0.0, double.infinity)
            .toDouble();
    return clampedPreamp - extraHeadroomNeeded;
  }
}

/// Equal-power crossfade curve math preserving perceived acoustic loudness.
class CrossfadeMath {
  /// Returns (outgoingGain, incomingGain) for progress in [0.0, 1.0].
  /// Total acoustic power (g_out^2 + g_in^2) is constant 1.0 throughout.
  static (double outgoing, double incoming) equalPowerGains(double progress) {
    final t = progress.clamp(0.0, 1.0);
    final angle = t * (math.pi / 2.0);
    return (math.cos(angle), math.sin(angle));
  }
}

/// Smart detection for sequential album tracks to maintain bit-perfect gapless flow.
class AlbumGaplessDetector {
  static bool isSequentialAlbumTracks({
    required String? currentAlbum,
    required String? nextAlbum,
    required String? currentArtist,
    required String? nextArtist,
    required int? currentTrackNum,
    required int? nextTrackNum,
    required int? currentDiscNum,
    required int? nextDiscNum,
    required bool isShuffle,
  }) {
    if (isShuffle) return false;
    if (currentAlbum == null || nextAlbum == null) return false;
    if (currentAlbum.trim().isEmpty || nextAlbum.trim().isEmpty) return false;
    if (currentAlbum.trim().toLowerCase() != nextAlbum.trim().toLowerCase()) {
      return false;
    }
    if (currentArtist != null &&
        nextArtist != null &&
        currentArtist.trim().isNotEmpty &&
        nextArtist.trim().isNotEmpty &&
        currentArtist.trim().toLowerCase() !=
            nextArtist.trim().toLowerCase()) {
      return false;
    }

    if (currentTrackNum != null &&
        nextTrackNum != null &&
        currentTrackNum > 0 &&
        nextTrackNum > 0) {
      final curDisc = currentDiscNum ?? 1;
      final nxtDisc = nextDiscNum ?? 1;
      if (curDisc == nxtDisc && nextTrackNum == currentTrackNum + 1) return true;
      if (nxtDisc == curDisc + 1 && nextTrackNum == 1) return true;
      return false;
    }
    return true;
  }
}
