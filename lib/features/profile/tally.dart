/// Who was played and how much: one count for the stats and the reviews.
library;

import '../../core/entities/entities.dart';
import '../../shared/util/artists.dart';
import '../../shared/util/taste.dart' show artistKey;

class TrackPlays {
  const TrackPlays(this.track, this.plays);

  final Track track;
  final int plays;
}

class ArtistPlays {
  const ArtistPlays(this.name, this.plays, this.cover, this.source, this.track);

  final String name;
  final int plays;

  /// Their most played track's cover, until the avatar comes.
  final String? cover;

  /// Where they were played most: their avatar and page are looked for there,
  /// as the same name on another platform is another person. Local means own
  /// files only: nowhere to look.
  final MusicSource source;

  /// That best track when it is theirs alone on that platform (it may know
  /// their page), otherwise a stand-in with just the name.
  final Track track;
}

class SourcePlays {
  const SourcePlays(this.source, this.plays, this.seconds);

  final MusicSource source;
  final int plays;
  final int seconds;
}

class _Sum {
  _Sum(this.name);

  final String name;
  int plays = 0;
  Track? best;
  int bestPlays = 0;
  final Map<MusicSource, int> where = {};
}

/// Each artist of a line counts on their own, a joint track for each of them.
class ArtistTally {
  final Map<String, _Sum> _sums = {};

  int get size => _sums.length;

  void add(Track t, int plays, MusicSource where) {
    final cover = t.cover;
    for (final name in parseArtists(t.artist)) {
      final a = _sums[artistKey(name)] ??= _Sum(name);
      a.plays += plays;
      a.where[where] = (a.where[where] ?? 0) + plays;
      if (cover != null && cover.isNotEmpty && plays > a.bestPlays) {
        a.best = t;
        a.bestPlays = plays;
      }
    }
  }

  List<ArtistPlays> ranked() =>
      [for (final a in _sums.values) _row(a)]
        ..sort((a, b) => b.plays.compareTo(a.plays));

  static ArtistPlays _row(_Sum a) {
    final where = _mostPlayedOn(a.where);
    final best = a.best;
    final own =
        best != null &&
        best.source == where &&
        parseArtists(best.artist).length == 1;
    return ArtistPlays(
      a.name,
      a.plays,
      best?.cover,
      where,
      own
          ? best
          : Track(
              id: '',
              name: '',
              artist: a.name,
              duration: Duration.zero,
              source: where,
            ),
    );
  }

  /// Own files don't count while there is any platform at all.
  static MusicSource _mostPlayedOn(Map<MusicSource, int> plays) {
    var top = MusicSource.local;
    var most = 0;
    for (final e in plays.entries) {
      if (e.key == MusicSource.local || e.value <= most) continue;
      top = e.key;
      most = e.value;
    }
    return top;
  }
}
