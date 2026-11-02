/// Similar to X on home: one seed from the top plays and what's like it, tracks
/// and artists mixed.
///
/// A seed lives a day, like For you, and alternates type: an even day is an
/// artist, an odd day a track. Within a type seeds go round the top, so several
/// anchors get shown.
///
/// A track seed gives tracks like it, not by its artists, and artists like its
/// first artist, from that artist's page. An artist seed gives similar artists
/// from its page, and tracks like its most played, without its own (or the
/// shelf becomes its discography).
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/providers/artist_lookup.dart';
import '../../core/providers/music_provider.dart';
import '../../shared/util/artists.dart';
import '../../shared/util/taste.dart';
import 'daily_showcase.dart';
import 'for_you.dart';

/// How many top positions the seed rotates through.
const int _seedPool = 5;

/// Seeds tried in a row if the first gave nothing similar.
const int _seedTries = 2;
const int _tracksMax = 14;
const int _artistsMax = 6;

/// Below this many TRACKS the shelf turns into a list of names: another seed or
/// type.
const int _minTracks = 4;

/// This many artists with pictures is enough to skip faceless ones.
const int _minFaced = 4;

/// For you cards seen with no scrolling: Similar to always stays clear of them,
/// and of the rest while it has enough of its own.
const int _forYouNear = 6;

sealed class SimilarSeed {
  const SimilarSeed();

  String get name;
  String? get cover;

  Map<String, dynamic> toJson();

  static SimilarSeed? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['kind'] == 'artist') {
      final artist = Artist.fromJson(json['artist']);
      return artist == null ? null : SimilarArtistSeed(artist);
    }
    final id = json['id'];
    if (id is! String) return null;
    return SimilarTrackSeed(
      id: id,
      name: json['name'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      cover: json['cover'] as String?,
      track: Track.fromJson(json['track']),
    );
  }
}

final class SimilarTrackSeed extends SimilarSeed {
  const SimilarTrackSeed({
    required this.id,
    required this.name,
    required this.artist,
    this.cover,
    this.track,
  });

  final String id;
  @override
  final String name;
  final String artist;
  @override
  final String? cover;

  /// The track itself, played by the seed tile. `null` if it can't come up (a
  /// local file not in the library), and the tile can't be pressed.
  final Track? track;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'track',
    'id': id,
    'name': name,
    'artist': artist,
    if (cover != null) 'cover': cover,
    if (track != null) 'track': track!.toJson(),
  };
}

final class SimilarArtistSeed extends SimilarSeed {
  const SimilarArtistSeed(this.artist);

  final Artist artist;

  @override
  String get name => artist.name;
  @override
  String? get cover => artist.avatar;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'artist',
    'artist': artist.toJson(),
  };
}

sealed class SimilarItem {
  const SimilarItem();

  Map<String, dynamic> toJson();

  static SimilarItem? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['kind'] == 'artist') {
      final artist = Artist.fromJson(json['artist']);
      return artist == null ? null : SimilarArtistItem(artist);
    }
    final track = Track.fromJson(json['track']);
    return track == null ? null : SimilarTrackItem(track);
  }
}

final class SimilarTrackItem extends SimilarItem {
  const SimilarTrackItem(this.track);
  final Track track;

  @override
  Map<String, dynamic> toJson() => {'kind': 'track', 'track': track.toJson()};
}

final class SimilarArtistItem extends SimilarItem {
  const SimilarArtistItem(this.artist);
  final Artist artist;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'artist',
    'artist': artist.toJson(),
  };
}

class SimilarTo {
  const SimilarTo(this.seed, this.items);

  final SimilarSeed seed;
  final List<SimilarItem> items;
}

/// Local day number, for the seed type's parity and its place in the round.
int recsDayNumber(DateTime now) =>
    DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

MusicProvider? _providerOf(RecsInput input, MusicSource source) {
  final p = input.registry.byId(source.id);
  return p != null && p.isEnabled ? p : null;
}

/// Artist [name] on the platform of track [via]: their page if known from the
/// track, else a search by name.
Future<Artist?> _resolveArtist(RecsInput input, String name, Track via) async {
  final link = firstArtistLink(via);
  if (link.name == name && link.id != null) {
    return Artist(
      id: link.id!,
      name: name,
      avatar: via.artistAvatar,
      source: via.source,
    );
  }
  final provider = _providerOf(input, via.source);
  if (provider == null) return null;
  try {
    return await findArtistCached(provider, name);
  } on Object {
    return null;
  }
}

Future<ArtistPageData?> _artistPage(RecsInput input, Artist artist) async {
  final provider = _providerOf(input, artist.source);
  if (provider == null) return null;
  try {
    final page = await provider.getArtist(artist.id);
    // A listener's page lists their likes, not their music.
    return page?.likes == null ? page : null;
  } on Object {
    return null;
  }
}

/// Selects tracks: only new (not saved, heard or in the neighbouring For you),
/// no copies, at most two per artist (per each name), none by the seed's own
/// artists ([own]).
///
/// For you is built from the same top and already took the best, so the strict
/// pass often runs short: then I keep clear only of its first cards. A repeat
/// at its far end beats a row of just names.
List<Track> _pickTracks(
  RecsInput input,
  List<Track> batch,
  Set<String> skip,
  Set<String> own,
  List<Track> forYou,
) {
  List<Track> select(List<Track> avoid) {
    final known = {...input.known, for (final t in avoid) t.id, ...skip};
    final dup = input.knownDups();
    for (final t in avoid) {
      dup.add(t);
    }
    final cap = ArtistCap(kRecsPerArtistMax);
    final out = <Track>[];
    for (final t in batch) {
      if (out.length >= _tracksMax) break;
      if (known.contains(t.id) || input.disliked.contains(t.id)) continue;
      if (artistKeys(t).any(own.contains) || !cap.fits(t)) continue;
      if (!dup.accept(t)) continue;
      known.add(t.id);
      cap.take(t);
      out.add(t);
    }
    return out;
  }

  final strict = select(forYou);
  if (strict.length >= _minTracks || forYou.length <= _forYouNear) {
    return strict;
  }
  final soft = select(forYou.take(_forYouNear).toList());
  return soft.length > strict.length ? soft : strict;
}

/// Similar artists with none of the seed's ([own]) or repeats. A grey stand-in
/// circle looks broken, so faceless ones come only when there'd be almost no
/// artists otherwise.
List<Artist> _pickArtists(List<Artist> list, Set<String> own) {
  final seen = {...own};
  final uniq = [
    for (final a in list)
      if (a.name.isNotEmpty && seen.add(artistKey(a.name))) a,
  ];
  final withAvatar = [
    for (final a in uniq)
      if (a.avatar != null) a,
  ];
  return (withAvatar.length >= _minFaced ? withAvatar : uniq)
      .take(_artistsMax)
      .toList();
}

/// Mixes: an artist on every third position (T A T T A T T …), and no more
/// artists than half the tracks. A row of faces with a track or two reads as a
/// list of names.
List<SimilarItem> mixSimilar(List<Track> tracks, List<Artist> artists) {
  final few = artists.take((tracks.length + 1) ~/ 2).toList();
  final out = <SimilarItem>[];
  var ti = 0;
  var ai = 0;
  while (ti < tracks.length || ai < few.length) {
    final wantArtist = out.length % 3 == 1;
    if ((wantArtist && ai < few.length) || ti >= tracks.length) {
      out.add(SimilarArtistItem(few[ai++]));
    } else {
      out.add(SimilarTrackItem(tracks[ti++]));
    }
  }
  return out;
}

/// Similar to [seedId] that pass [_pickTracks]; a thin answer fills up with
/// those like the track [more] names (`null` as is).
Future<List<Track>> _likeTracks(
  RecsInput input,
  String seedId,
  Track? Function(List<Track> first) more,
  Set<String> skip,
  Set<String> own,
  List<Track> forYou,
) async {
  final b0 = await similarTracksFor(input.registry, seedId);
  final tracks = _pickTracks(input, b0, skip, own, forYou);
  final next = tracks.length < _tracksMax ? more(b0) : null;
  if (next == null) return tracks;
  final b1 = await similarTracksFor(input.registry, next.id);
  return _pickTracks(input, [...b0, ...b1], skip, own, forYou);
}

/// Track seed: the most played tracks, round-robin. What's like it from others,
/// and artists like its first. Own artists in neither: on SoundCloud the
/// account (the first link) and names in the line can differ, so both count.
Future<SimilarTo?> _fromTrack(
  RecsInput input,
  int turn,
  List<Track> forYou,
) async {
  final pool = recsTopPlayed(input, limit: _seedPool, minPlays: 2);
  for (var k = 0; k < math.min(_seedTries, pool.length); k++) {
    final id = pool[(turn + k) % pool.length].id;
    final seed = input.trackOf(id);
    if (seed == null || seed.name.isEmpty) continue;

    final first = firstArtistLink(seed).name;
    final own = {...artistKeys(seed), if (first.isNotEmpty) artistKey(first)};
    // Fills up from the best track in the answer by another artist.
    Track? more(List<Track> b0) =>
        b0.where((t) => !artistKeys(t).any(own.contains)).firstOrNull;
    final tracks = await _likeTracks(input, id, more, {id}, own, forYou);
    // Nothing to show anyway, so no trip for artists.
    if (tracks.length < _minTracks) continue;

    final artist = isRealArtist(first)
        ? await _resolveArtist(input, first, seed)
        : null;
    final artists = artist == null
        ? const <Artist>[]
        : _pickArtists(
            (await _artistPage(input, artist))?.similarArtists ?? const [],
            own,
          );
    return SimilarTo(
      SimilarTrackSeed(
        id: id,
        name: seed.name,
        artist: seed.artist,
        cover: seed.cover,
        track: seed,
      ),
      mixSimilar(tracks, artists),
    );
  }
  return null;
}

/// Artist seed: the most played artists, round-robin. Similar artists come from
/// their page; tracks like their most played, but not theirs (or it's their
/// discography).
Future<SimilarTo?> _fromArtist(
  RecsInput input,
  int turn,
  List<Track> forYou,
) async {
  final pool = topArtists(input, _seedPool);
  for (var k = 0; k < math.min(_seedTries, pool.length); k++) {
    final cand = pool[(turn + k) % pool.length];
    final artist = await _resolveArtist(input, cand.name, cand.own);
    if (artist == null) continue;

    final page = await _artistPage(input, artist);
    final found = page?.artist ?? artist;
    final name = found.name.isEmpty ? cand.name : found.name;
    final own = {cand.key, artistKey(name)};
    final artists = _pickArtists(page?.similarArtists ?? const [], own);
    // What's like one track minus their own can be thin, so it fills up from
    // the second by plays.
    final tracks = await _likeTracks(
      input,
      cand.theirs.first.id,
      (_) => cand.theirs.elementAtOrNull(1),
      {for (final t in cand.theirs) t.id},
      own,
      forYou,
    );
    if (tracks.length < _minTracks) continue;

    return SimilarTo(
      SimilarArtistSeed(
        Artist(
          id: found.id,
          name: name,
          avatar: found.avatar ?? artist.avatar ?? cand.own.cover,
          source: found.source,
        ),
      ),
      mixSimilar(tracks, artists),
    );
  }
  return null;
}

/// Builds the shelf. Seed type by day parity; failing that it tries the other,
/// so the shelf doesn't vanish every other day. [forYou] is the neighbouring
/// shelf: its tracks and their reuploads don't repeat here.
Future<SimilarTo?> buildSimilarTo(
  RecsInput input, {
  List<Track> forYou = const [],
}) async {
  final day = recsDayNumber(input.now);
  final turn = day ~/ 2;
  final artistFirst = day.isEven;
  for (final artist in [artistFirst, !artistFirst]) {
    final res = artist
        ? await _fromArtist(input, turn, forYou)
        : await _fromTrack(input, turn, forYou);
    if (res != null) return res;
  }
  return null;
}

final similarToProvider = NotifierProvider<SimilarToController, SimilarTo?>(
  SimilarToController.new,
);

class SimilarToController extends DailyShowcase<SimilarTo> {
  @override
  String get storeKey => 'similarTo';

  /// 3: from four tracks, artists at most half the tracks, none of a track
  /// seed's own artists, filling up from another track.
  @override
  int get version => 3;

  @override
  Future<SimilarTo?> fetch() async {
    // In the morning both shelves build at once, so I wait for the neighbour,
    // or there'd be nothing to check against.
    await ref.read(forYouProvider.notifier).settled();
    return buildSimilarTo(
      recsInputOf(ref),
      forYou: ref.read(forYouProvider) ?? const [],
    );
  }

  @override
  Object? encode(SimilarTo value) => {
    'seed': value.seed.toJson(),
    'items': [for (final it in value.items) it.toJson()],
  };

  @override
  SimilarTo? decode(Object? raw) {
    if (raw is! Map) return null;
    final seed = SimilarSeed.fromJson(raw['seed']);
    final items = [
      for (final it in (raw['items'] as List?) ?? const [])
        ?SimilarItem.fromJson(it),
    ];
    return seed == null || items.isEmpty ? null : SimilarTo(seed, items);
  }
}
