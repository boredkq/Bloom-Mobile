/// Shared rules of taste: how the wave, the home shelves
/// and the wave's picks tell a track's artists, keep them in measure and read
/// what the listener plays most.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';
import '../../features/wave/wave_store.dart';
import 'artists.dart';
import 'track_dedup.dart';

/// An artist's name as a key: case and edge spaces don't count.
String artistKey(String name) => name.trim().toLowerCase();

/// Keys of all the track's names: "A feat. B" is both A and B.
Set<String> artistKeys(Track t) => {
  for (final n in parseArtists(t.artist)) artistKey(n),
};

/// No more than [max] tracks an artist, by each of a track's names rather than
/// the whole line: "A feat. B" takes a place of both A and B.
class ArtistCap {
  ArtistCap(this.max);

  final int max;
  final Map<String, int> _count = {};

  bool fits(Track t) => artistKeys(t).every((k) => (_count[k] ?? 0) < max);

  void take(Track t) {
    for (final k in artistKeys(t)) {
      _count[k] = (_count[k] ?? 0) + 1;
    }
  }
}

/// The window of current taste: what one liked two years ago only gets in
/// the way.
const int kRecsWindowDays = 90;

/// Fewer than this over the window: count over all time (a fresh install).
const int _windowMinSeeds = 3;

/// All that picks are made from. A snapshot, not the live stores: a pick takes
/// seconds and has to be made of one state.
class RecsInput {
  RecsInput({
    required this.registry,
    required this.stats,
    required this.lib,
    this.disliked = const {},
    DateTime? now,
  }) : now = now ?? DateTime.now();

  final ProviderRegistry registry;
  final PlayStats stats;
  final LibraryState lib;

  /// The wave's dislikes: never a seed, never a card.
  final Set<String> disliked;
  final DateTime now;

  /// A track by id: from the library, else its snapshot from the log.
  Track? trackOf(String id) => lib.tracks[id] ?? stats.tracks[id];

  /// All the listener already knows: saved and ever heard.
  late final Set<String> known = {
    ...lib.tracks.keys,
    for (final r in stats.allPlayed()) r.id,
  };

  /// Reuploads out across everything known. [known] alone isn't enough: a
  /// copy from another uploader comes under its own id. What was heard but not
  /// saved is checked by its snapshot. New each time: the guard remembers
  /// what it let through.
  DupGuard knownDups() {
    final guard = DupGuard();
    for (final t in lib.tracks.values) {
      guard.add(t);
    }
    for (final e in stats.tracks.entries) {
      if (!lib.tracks.containsKey(e.key)) guard.add(e.value);
    }
    return guard;
  }
}

RecsInput recsInputOf(Ref ref) => RecsInput(
  registry: ref.read(registryProvider),
  stats: ref.read(playStatsProvider),
  lib: ref.read(libraryProvider),
  disliked: ref.read(waveStoreProvider).dislikedIds,
);

/// Whether similar ones can be asked for: the track's platform is on and has
/// a radio for it. One's own files have no one to ask.
bool recsAskable(RecsInput input, Track t) {
  final p = input.registry.byId(t.source.id);
  return p != null && p.isEnabled && p.trackStation(t).isNotEmpty;
}

bool _askableId(RecsInput input, String id) {
  final t = input.trackOf(id);
  return t != null && recsAskable(input, t);
}

/// The most played that can be asked about, no dislikes.
/// Over the window, and over all time while the window has too few.
List<TopPlayed> recsTopPlayed(
  RecsInput input, {
  required int limit,
  int minPlays = 1,
}) {
  List<TopPlayed> pick({int? sinceDays, required int minPlays}) => [
    for (final r in input.stats.topPlayed(
      sinceDays: sinceDays,
      limit: limit * 4,
      minPlays: minPlays,
      now: input.now,
    ))
      if (!input.disliked.contains(r.id) && _askableId(input, r.id)) r,
  ].take(limit).toList();
  final top = pick(sinceDays: kRecsWindowDays, minPlays: minPlays);
  return top.length >= _windowMinSeeds ? top : pick(minPlays: 1);
}

/// The list newest first by when each was added ([at]).
List<Track> newestFirst(List<Track> list, Map<String, int> at) {
  final rows = [for (var i = 0; i < list.length; i++) (list[i], i)]
    ..sort((a, b) {
      final c = (at[b.$1.id] ?? 0).compareTo(at[a.$1.id] ?? 0);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
  return [for (final x in rows) x.$1];
}

bool isRealArtist(String name) {
  final n = name.trim().toLowerCase();
  return n.isNotEmpty && n != '—' && n != 'unknown artist';
}

/// An artist of the top.
class TopArtist {
  TopArtist(this.name, this.key);

  final String name;
  final String key;
  int plays = 0;

  /// Their tracks from the top, the most played first.
  final List<Track> theirs = [];

  /// Their own track: one where they're alone (the track's avatar is theirs),
  /// else the most played.
  Track get own =>
      theirs.where((t) => parseArtists(t.artist).length == 1).firstOrNull ??
      theirs.first;
}

/// The top artists, folded from the top tracks: a joint track goes to each,
/// or the top would hold a glued name no platform can find.
List<TopArtist> topArtists(RecsInput input, int limit) {
  final map = <String, TopArtist>{};
  for (final r in recsTopPlayed(input, limit: 1000)) {
    final t = input.trackOf(r.id);
    if (t == null) continue;
    for (final name in parseArtists(t.artist)) {
      if (!isRealArtist(name)) continue;
      final key = artistKey(name);
      final a = map.putIfAbsent(key, () => TopArtist(name, key));
      a.plays += r.plays;
      a.theirs.add(t);
    }
  }
  final list = map.values.toList()..sort((a, b) => b.plays.compareTo(a.plays));
  return list.take(limit).toList();
}
