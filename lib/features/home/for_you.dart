/// For you on home: similar to what the user plays. Seeds are the most played
/// from the play log ([PlayStats]), then fresh likes and the newest in the
/// library: a track liked yesterday and not yet played says as much about
/// taste. First one per artist: five hits by one artist would make the strip
/// theirs.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/providers/registry.dart';
import '../../core/store/play_stats.dart';
import '../../shared/util/taste.dart';
import 'daily_showcase.dart';

/// Seeds to ask; each is a network request, so few.
const int _seedLimit = 5;

/// Cards in the strip.
const int kForYouMax = 20;

/// More than two tracks by one artist makes the strip theirs. Counted per each
/// name on a track.
const int kRecsPerArtistMax = 2;

/// Similar to a track on its platform, decided by the id prefix. With no method
/// or a network failure it's empty: one seed is no reason to bury the shelf.
Future<List<Track>> similarTracksFor(
  ProviderRegistry registry,
  String seedId,
) async {
  final provider = registry.byId(MusicSource.fromId(seedId).id);
  if (provider == null || !provider.isEnabled) return const [];
  try {
    return await provider.getSimilarTracks(seedId) ?? const [];
  } on Object {
    return const [];
  }
}

/// Seeds: most played, fresh likes, newest in the library; a first pass with
/// one per artist, a second to fill up.
List<String> pickForYouSeeds(RecsInput input, {int limit = _seedLimit}) {
  final all = [
    for (final r in recsTopPlayed(input, limit: limit * 3, minPlays: 2))
      ?input.trackOf(r.id),
    ...newestFirst(input.lib.favTracks, input.lib.favs),
    ...newestFirst(input.lib.allTracks, input.lib.inLib),
  ];
  final out = <String>[];
  final seen = <String>{};
  final artists = <String>{};
  for (final spread in [true, false]) {
    for (final t in all) {
      if (out.length >= limit) return out;
      final keys = artistKeys(t);
      if (seen.contains(t.id) ||
          (spread && keys.any(artists.contains)) ||
          input.disliked.contains(t.id) ||
          !recsAskable(input, t)) {
        continue;
      }
      seen.add(t.id);
      artists.addAll(keys);
      out.add(t.id);
    }
  }
  return out;
}

/// Builds the strip, round-robin with a track per seed per pass: otherwise the
/// first seed's long list fills it all.
Future<List<Track>> buildForYou(RecsInput input) async {
  final seeds = pickForYouSeeds(input);
  if (seeds.isEmpty) return const [];

  // In sequence: SoundCloud has a shared request queue, a fan-out would line up
  // anyway, and a parallel start gets in the way of the rest of home.
  final batches = <List<Track>>[];
  for (final seed in seeds) {
    final batch = await similarTracksFor(input.registry, seed);
    if (batch.isNotEmpty) batches.add(batch);
  }
  if (batches.isEmpty) return const [];

  final known = {...input.known, ...seeds};
  // The check isn't only by id: one track on two platforms has two ids, and
  // SoundCloud also has reuploads by different uploaders.
  final dup = input.knownDups();
  final cap = ArtistCap(kRecsPerArtistMax);

  final out = <Track>[];
  final maxLen = batches.map((b) => b.length).reduce(math.max);
  for (var i = 0; i < maxLen && out.length < kForYouMax; i++) {
    for (final batch in batches) {
      if (out.length >= kForYouMax) break;
      if (i >= batch.length) continue;
      final t = batch[i];
      if (known.contains(t.id) || input.disliked.contains(t.id)) continue;
      if (!cap.fits(t)) continue;
      // Most expensive check last, not to run it on those already out.
      if (!dup.accept(t)) continue;
      known.add(t.id);
      cap.take(t);
      out.add(t);
    }
  }
  return out;
}

final forYouProvider = NotifierProvider<ForYouController, List<Track>?>(
  ForYouController.new,
);

class ForYouController extends DailyShowcase<List<Track>> {
  @override
  String get storeKey => 'forYou';

  /// 3: seeds one per artist, YouTube Music as a seed too, the artist cap per
  /// each name.
  @override
  int get version => 3;

  @override
  Future<List<Track>?> fetch() async {
    final tracks = await buildForYou(recsInputOf(ref));
    return tracks.isEmpty ? null : tracks;
  }

  @override
  Object? encode(List<Track> value) => [for (final t in value) t.toJson()];

  @override
  List<Track>? decode(Object? raw) {
    if (raw is! List) return null;
    final tracks = [for (final t in raw) ?Track.fromJson(t)];
    return tracks.isEmpty ? null : tracks;
  }
}
