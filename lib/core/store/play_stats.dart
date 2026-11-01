/// Play stats: how many times and when last, folded from [PlayLog]. The one
/// source for all that relies on listening: history, profile stats and
/// achievements, wave and home seeds, sort by plays.
///
/// Recounted whole on every play: a hundred thousand events fold in
/// milliseconds, and hot paths (sort comparator, wave filter) need synchronous
/// answers.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entities/entities.dart';
import 'days_store.dart' show dayKey;
import 'play_log.dart';

const int _dayMs = 24 * 3600 * 1000;

/// A track in the play top.
@immutable
class TopPlayed {
  const TopPlayed(this.id, this.plays, this.lastTs, this.firstTs);

  final String id;
  final int plays;
  final int lastTs;

  /// First play, for the spread of days in stats.
  final int firstTs;
}

/// A History row.
@immutable
class HistoryRow {
  const HistoryRow(this.id, this.at, this.count);

  final String id;

  /// Last play.
  final int at;

  /// Play count.
  final int count;
}

/// Index of the first element `>= x`.
int _lowerBound(List<int> arr, int x) {
  var lo = 0;
  var hi = arr.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (arr[mid] < x) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

class PlayStats {
  PlayStats._(this._plays, this.tracks);

  factory PlayStats.build(PlayLog log) {
    final byTrack = <String, List<int>>{};
    // Log events are already ascending, so the arrays come out sorted.
    for (final e in log.events) {
      (byTrack[e.id] ??= []).add(e.ts);
    }
    return PlayStats._(byTrack, log.tracks);
  }

  static final PlayStats empty = PlayStats._(const {}, const {});

  /// Id to play times, ascending.
  final Map<String, List<int>> _plays;

  /// Snapshots of played tracks, which keep a history row alive after the track
  /// leaves the library.
  final Map<String, Track> tracks;

  /// How many times a track was played.
  int playCount(String id) => _plays[id]?.length ?? 0;

  /// When a track last played (0 if never).
  int lastPlayedAt(String id) => _plays[id]?.last ?? 0;

  /// Whether a track played in the last [days] days.
  bool recentlyPlayed(String id, int days, {DateTime? now}) {
    final last = lastPlayedAt(id);
    if (last <= 0) return false;
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return at - last < days * _dayMs;
  }

  /// All tracks ever played, with no sort or cutoffs, for profile totals that
  /// need the whole volume.
  List<TopPlayed> allPlayed() => [
    for (final e in _plays.entries)
      TopPlayed(e.key, e.value.length, e.value.last, e.value.first),
  ];

  /// Most played: more plays higher, newer on ties. [sinceDays] narrows the
  /// window: a three-month top reflects current taste.
  List<TopPlayed> topPlayed({
    int? sinceDays,
    int limit = 20,
    int minPlays = 1,
    DateTime? now,
  }) {
    final since = sinceDays == null
        ? 0
        : (now ?? DateTime.now()).millisecondsSinceEpoch - sinceDays * _dayMs;
    final rows = <TopPlayed>[
      for (final e in _plays.entries)
        if (e.value.length - _lowerBound(e.value, since) case final plays
            when plays >= minPlays)
          TopPlayed(e.key, plays, e.value.last, e.value.first),
    ]..sort(_byPlaysThenFresh);
    return rows.take(limit).toList();
  }

  /// History rows, newest first. Nothing is removed: it shows the whole log.
  List<HistoryRow> historyRows() => [
    for (final e in _plays.entries)
      HistoryRow(e.key, e.value.last, e.value.length),
  ]..sort((a, b) => b.at.compareTo(a.at));

  /// Plays per day (local date to count): activity chart, streaks, day record,
  /// days with music.
  late final Map<String, int> perDay = () {
    final out = <String, int>{};
    for (final list in _plays.values) {
      for (final ts in list) {
        final key = dayKey(DateTime.fromMillisecondsSinceEpoch(ts));
        out[key] = (out[key] ?? 0) + 1;
      }
    }
    return out;
  }();
}

int _byPlaysThenFresh(TopPlayed a, TopPlayed b) => a.plays != b.plays
    ? b.plays.compareTo(a.plays)
    : b.lastTs.compareTo(a.lastTs);

final playStatsProvider = Provider<PlayStats>(
  (ref) => PlayStats.build(ref.watch(playLogProvider)),
);
