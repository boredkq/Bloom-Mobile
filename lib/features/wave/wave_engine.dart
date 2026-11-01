/// A wave batch from what stations gave. A pure function over a snapshot
/// ([WavePick]): it decides what's heard, and should be checked with lists, not
/// by ear. Network and queueing are in the controller.
library;

import 'dart:math';

import '../../core/entities/entities.dart';
import '../../shared/util/taste.dart';
import '../../shared/util/track_dedup.dart';
import 'wave_types.dart';

/// Tracks in a batch.
const int kWaveBatch = 20;

/// With this many left ahead it's time to ask for more (4 for a Yandex
/// station).
const int kWaveRefillAt = 5;
const int kWaveRefillAtNative = 4;

/// At most this many tracks by one artist in a batch.
const int kWaveMaxPerArtist = 2;

/// Share of own tracks in My wave.
const double kWaveFamiliarShare = 0.2;

/// Played within this many days isn't offered again; shown within this many
/// neither.
const int kWaveRecentDays = 7;
const int kWaveShownDays = 14;

/// Snapshot a batch is built from.
class WavePick {
  WavePick({
    required this.run,
    required this.queue,
    required this.library,
    required this.inLibrary,
    required this.isFav,
    required this.isDisliked,
    required this.playedWithin,
    required this.shown,
    this.currentId,
    Random? random,
  }) : random = random ?? Random();

  final WaveRun? run;

  /// The player's queue: what's in it doesn't go in twice, by id or as a
  /// reupload.
  final List<Track> queue;
  final String? currentId;

  /// Library tracks, from which My wave mixes in own ones.
  final List<Track> library;
  final bool Function(String id) inLibrary;
  final bool Function(String id) isFav;
  final bool Function(String id) isDisliked;

  /// Whether a track played in the last N days.
  final bool Function(String id, int days) playedWithin;

  /// What the wave showed within [kWaveShownDays].
  final Set<String> shown;
  final Random random;
}

/// A batch from stations' portions, one per seed. A self-learning station keeps
/// its order, losing only what's queued or disliked. For others: nothing heard
/// in a week, shown in two or in the library (own come only as My wave's
/// share); then by place in the station, likes and what the wave learned; an
/// artist at most twice and never twice in a row.
List<Track> pickBatch(
  List<List<Track>> pages,
  WavePick ctx, {
  int take = kWaveBatch,
}) {
  final queued = {for (final t in ctx.queue) t.id, ?ctx.currentId};

  final cands = <WaveCandidate>[
    for (final page in pages)
      for (var i = 0; i < page.length; i++)
        WaveCandidate(
          page[i],
          20.0 * i / max(1, page.length),
          artistKeys(page[i]),
        ),
  ];

  final dup = DupGuard();
  for (final t in ctx.queue) {
    dup.add(t);
  }
  final out = <Track>[];
  void fill(Iterable<WaveCandidate> list) {
    for (final c in list) {
      if (out.length >= take) break;
      if (dup.accept(c.track)) out.add(c.track);
    }
  }

  final run = ctx.run;
  if (run != null && run.native) {
    fill(cands.where((c) => !queued.contains(c.id) && !ctx.isDisliked(c.id)));
    return out;
  }

  final personal = run?.mode == WaveMode.personal;
  final played = {...?run?.played};
  if (personal) {
    // Own share: not heard in the last three days.
    final lib = [
      for (final t in ctx.library)
        if (!queued.contains(t.id) &&
            !played.contains(t.id) &&
            !ctx.isDisliked(t.id) &&
            !ctx.playedWithin(t.id, 3))
          t,
    ]..shuffle(ctx.random);
    final familiar = max(1, (take * kWaveFamiliarShare).round()) * 2;
    for (var i = 0; i < familiar && i < lib.length; i++) {
      cands.add(
        WaveCandidate(lib[i], i.toDouble(), artistKeys(lib[i]), library: true),
      );
    }
  }

  bool passes(WaveCandidate c, {required bool relaxed}) {
    final id = c.id;
    if (queued.contains(id) || played.contains(id) || ctx.isDisliked(id)) {
      return false;
    }
    if (!c.library && ctx.inLibrary(id)) return false;
    return relaxed ||
        (!ctx.playedWithin(id, kWaveRecentDays) &&
            (c.library || !ctx.shown.contains(id)));
  }

  var kept = [
    for (final c in cands)
      if (passes(c, relaxed: false)) c,
  ];
  // All heard or shown recently: a repeat beats silence.
  if (kept.isEmpty) {
    kept = [
      for (final c in cands)
        if (passes(c, relaxed: true)) c,
    ];
  }

  for (final c in kept) {
    var s = 20 - c.rank;
    if (ctx.isFav(c.id)) s += 8;
    if (run != null) {
      var b = 0;
      for (final a in c.artists) {
        b += run.bonus[a] ?? 0;
      }
      s += min(b, 12);
    }
    if (!c.library) s += 1;
    c.score = s + ctx.random.nextDouble() * 2;
  }
  // A stable sort: Dart's `List.sort` isn't.
  kept = _stableSorted(kept, (a, b) => b.score.compareTo(a.score));

  // My wave: one own after every four new.
  if (personal) {
    final fresh = [
      for (final c in kept)
        if (!c.library) c,
    ];
    final own = [
      for (final c in kept)
        if (c.library) c,
    ];
    kept = [];
    var f = 0, o = 0;
    for (var step = 0; f < fresh.length || o < own.length; step++) {
      if ((step % 5 == 4 && o < own.length) || f >= fresh.length) {
        kept.add(own[o++]);
      } else {
        kept.add(fresh[f++]);
      }
    }
  }

  // Those over the cap wait at the end, in case of a short batch.
  final spaced = <WaveCandidate>[];
  final later = <WaveCandidate>[];
  final cap = ArtistCap(kWaveMaxPerArtist);
  var lastArtists = <String>{};
  for (final c in kept) {
    if (!cap.fits(c.track) || c.artists.any(lastArtists.contains)) {
      later.add(c);
      continue;
    }
    spaced.add(c);
    cap.take(c.track);
    lastArtists = c.artists;
  }
  fill([...spaced, ...later]);
  return out;
}

List<T> _stableSorted<T>(List<T> list, int Function(T, T) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])]
    ..sort((a, b) {
      final c = compare(a.$2, b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final x in indexed) x.$2];
}

/// Seeds evenly along the list: all of ≤8, 8 of ≤15, else 10. Each seed is a
/// request or two; more than ten start slowly and add little.
List<T> spreadSeeds<T>(List<T> all) {
  final n = all.length;
  final want = n <= 8
      ? n
      : n <= 15
      ? 8
      : 10;
  if (want >= n) return all;
  return [
    for (var i = 0; i < want; i++) all[min(n - 1, (i * n / want).round())],
  ];
}
