/// What the wave starts from. Pure functions over a library snapshot
/// ([WaveLibrary]): what the listener played and liked decides it all, and
/// that's easier to check with lists. Plays are the listener's own, from the
/// log ([PlayStats]).
library;

import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';
import '../../shared/util/taste.dart';
import 'wave_engine.dart' show spreadSeeds;
import 'wave_types.dart';

/// Library snapshot as picks see it.
class WaveLibrary {
  WaveLibrary({
    required this.lib,
    required this.disliked,
    required this.seedOf,
    PlayStats? stats,
    Iterable<Track> extras = const [],
  }) : stats = stats ?? PlayStats.empty,
       _extras = {for (final t in extras) t.id: t};

  final LibraryState lib;

  /// The whole play log.
  final PlayStats stats;

  /// Disliked track ids, which never become seeds.
  final Set<String> disliked;

  /// A track's radio on its platform; `null` if none (a local file, Yandex with
  /// no login).
  final WaveSeed? Function(Track) seedOf;

  /// Tracks outside the library that can also be seeds: the queue, an artist
  /// page.
  final Map<String, Track> _extras;

  /// Library tracks minus disliked, in all tracks order.
  late final List<Track> tracks = [
    for (final t in lib.allTracks)
      if (!disliked.contains(t.id)) t,
  ];

  int playCount(String trackId) => stats.playCount(trackId);

  Track? byId(String trackId) => _extras[trackId] ?? lib.tracks[trackId];
}

/// Seeds from a list (queue, artist's tracks): one per radio, no disliked,
/// evenly along the list ([spreadSeeds]).
List<WaveSeed> queueSeeds(List<Track> tracks, WaveLibrary view) {
  final all = <WaveSeed>[];
  final seen = <WaveSeed>{};
  for (final t in tracks) {
    if (view.disliked.contains(t.id)) continue;
    final s = view.seedOf(t);
    if (s != null && seen.add(s)) all.add(s);
  }
  return spreadSeeds(all);
}

/// My wave from [provider] (a database code): the two most played, the two
/// freshest likes and one more of those. [rotation] shifts the pick with each
/// new wave, or it would stand forever on the same two from the top.
List<WaveSeed> personalSeeds(WaveLibrary view, String provider, int rotation) {
  bool usable(Track t) =>
      t.source.code == provider &&
      !view.disliked.contains(t.id) &&
      view.seedOf(t) != null;
  final lib = [
    for (final t in view.lib.allTracks)
      if (usable(t)) t,
  ];
  if (lib.isEmpty) return const [];

  final byPlays = _byPlays(view, lib);
  final favs = [
    for (final t in newestFirst(view.lib.favTracks, view.lib.favs))
      if (usable(t)) t,
  ];

  final picked = <Track>[];
  bool take(List<Track> from, int i) {
    if (from.isEmpty) return false;
    final t = from[i % from.length];
    if (picked.any((x) => x.id == t.id)) return false;
    picked.add(t);
    return true;
  }

  take(byPlays, rotation * 2);
  take(byPlays, rotation * 2 + 1);
  take(favs, rotation * 2);
  take(favs, rotation * 2 + 1);
  if (!take(byPlays, rotation * 2 + 2)) take(favs, rotation * 2 + 2);
  // Nothing played or liked: the freshest in the library.
  if (picked.isEmpty) picked.addAll(newestFirst(lib, view.lib.inLib).take(3));
  return [for (final t in picked) ?view.seedOf(t)];
}

/// Played ones, most played on top (on ties, as they came).
List<Track> _byPlays(WaveLibrary view, List<Track> lib) {
  final scored = [
    for (var i = 0; i < lib.length; i++)
      if (view.playCount(lib[i].id) case final n when n > 0) (lib[i], n, i),
  ]..sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3));
  return [for (final x in scored) x.$1];
}

/// What a wave started from an artist or a track is about: the pick that
/// started the wave on now is lit by it.
String waveAboutArtist(String name) => 'artist:${artistKey(name)}';
String waveAboutTrack(String trackId) => 'track:$trackId';

enum WaveOptionKind { artist, track, back, shake }

/// A wave to turn to from My Wave's stage.
class WaveOption {
  const WaveOption.artist(this.name, Track this.track)
    : kind = WaveOptionKind.artist;
  const WaveOption.track(Track this.track)
    : kind = WaveOptionKind.track,
      name = '';
  const WaveOption.action(this.kind) : name = '', track = null;

  final WaveOptionKind kind;
  final String name;

  /// The track's own for a track; for an artist, their own track (the
  /// platform to look them up on, the picture while there's no avatar).
  final Track? track;

  String get about => switch (kind) {
    WaveOptionKind.artist => waveAboutArtist(name),
    WaveOptionKind.track => waveAboutTrack(track!.id),
    _ => '',
  };
}

/// Waves to turn to, artist and track by turns:
/// the top artists, and tracks of others (two fresh likes, then the top). An
/// artist's own hit beside their name would say the same twice.
List<WaveOption> wavePicks(RecsInput input, {int each = 4}) {
  final artists = topArtists(input, each);
  final listed = {for (final a in artists) a.key};

  final tracks = <Track>[];
  final taken = <String>{};
  void take(Iterable<Track> from, int upTo) {
    for (final t in from) {
      if (tracks.length >= upTo) return;
      if (taken.contains(t.id) ||
          input.disliked.contains(t.id) ||
          !recsAskable(input, t) ||
          artistKeys(t).any(listed.contains)) {
        continue;
      }
      taken.add(t.id);
      tracks.add(t);
    }
  }

  take(newestFirst(input.lib.favTracks, input.lib.favs), 2);
  take([
    for (final r in recsTopPlayed(input, limit: 50)) ?input.trackOf(r.id),
  ], each);

  return [
    for (var i = 0; i < each; i++) ...[
      if (i < artists.length)
        WaveOption.artist(artists[i].name, artists[i].own),
      if (i < tracks.length) WaveOption.track(tracks[i]),
    ],
  ];
}
