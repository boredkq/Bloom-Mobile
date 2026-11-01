/// Shared wave types.
library;

import '../../core/entities/entities.dart';

/// What fills the wave.
enum WaveMode {
  /// My wave: seeds from the library (most played and likes) plus own tracks.
  personal,

  /// Wave by one track.
  track,

  /// Similar to queue: seeds from the current queue.
  queue,

  /// Wave by artist: seeds from their tracks, or a Yandex station.
  artist,
}

/// Where the wave takes tracks: radio [station] of platform [provider] (a
/// database code: `sc`, `ytm`, `ym`).
class WaveSeed {
  const WaveSeed(this.provider, this.station);

  final String provider;
  final String station;

  /// Cursor key.
  String get key => '$provider|$station';

  @override
  bool operator ==(Object other) =>
      other is WaveSeed &&
      other.provider == provider &&
      other.station == station;

  @override
  int get hashCode => Object.hash(provider, station);
}

/// The running wave; survives a restart in kv `wave.session`.
class WaveRun {
  WaveRun({
    required this.mode,
    required this.seeds,
    this.about = '',
    this.native = false,
    List<String>? played,
    Map<String, int>? bonus,
  }) : played = played ?? [],
       bonus = bonus ?? {};

  final WaveMode mode;

  /// What it started from: `artist:<key>`, `track:<id>`; empty for My wave and
  /// the queue.
  final String about;

  /// One self-learning station (Yandex): its order stays untouched.
  final bool native;

  List<WaveSeed> seeds;

  /// What's been heard in this wave, oldest first.
  final List<String> played;

  /// Artist key to finished (+3) and skipped (−2) in this wave.
  final Map<String, int> bonus;

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'about': about,
    'native': native,
    'seeds': [
      for (final s in seeds) {'p': s.provider, 's': s.station},
    ],
    'played': played,
    'bonus': bonus,
  };

  static WaveRun? fromJson(Object? json) {
    if (json is! Map) return null;
    final mode = WaveMode.values
        .where((m) => m.name == json['mode'])
        .firstOrNull;
    final seeds = [
      for (final s in (json['seeds'] as List?) ?? const [])
        if (s is Map && s['p'] is String && s['s'] is String)
          WaveSeed(s['p'] as String, s['s'] as String),
    ];
    if (mode == null || seeds.isEmpty) return null;
    final bonus = json['bonus'];
    return WaveRun(
      mode: mode,
      seeds: seeds,
      about: json['about'] as String? ?? '',
      native: json['native'] == true,
      played: (json['played'] as List?)?.whereType<String>().toList(),
      bonus: bonus is Map
          ? {
              for (final e in bonus.entries)
                if (e.key is String && e.value is num)
                  e.key as String: (e.value as num).toInt(),
            }
          : null,
    );
  }
}

/// A batch candidate.
class WaveCandidate {
  WaveCandidate(this.track, this.rank, this.artists, {this.library = false});

  final Track track;

  /// Place in its station: 0 is the top … 20.
  final double rank;

  /// The track's artist keys (`artistKeys`).
  final Set<String> artists;

  /// An own library track mixed into My wave.
  final bool library;

  double score = 0;

  String get id => track.id;
}

/// Below this many seconds AND below a 0.3 share is skipped; from 0.85 is
/// finished. Both thresholds together: on a ten-minute track the first minute
/// isn't yet a verdict.
int completionStep(Duration played, Duration total) {
  if (total <= Duration.zero) return 0;
  final ratio = played.inMilliseconds / total.inMilliseconds;
  if (played.inMilliseconds < 20000 && ratio < 0.3) return -2;
  return ratio >= 0.85 ? 3 : 0;
}
