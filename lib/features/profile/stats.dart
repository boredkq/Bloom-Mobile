/// Profile stats. Sources: the play log ([PlayStats], how many times and when
/// each track played, per day) and the days table ([DaysState], app time).
/// Nothing's stored; all is counted on the fly.
///
/// The platform breakdown comes from the id's PREFIX rather than a track's
/// field: after a restart half the history entries no longer resolve to an
/// object, and it would leave only SoundCloud.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';

import '../../core/entities/entities.dart';
import '../../core/store/history_store.dart';
import '../../core/store/library_store.dart';
import '../../core/store/days_store.dart';
import '../../core/store/play_stats.dart';
import 'tally.dart';

export 'tally.dart';

class ProfileStats {
  const ProfileStats({
    required this.libraryTracks,
    required this.totalPlays,
    required this.listenSec,
    required this.uniqueTracks,
    required this.uniqueArtists,
    required this.avgSec,
    required this.daySpan,
    required this.recordDay,
    required this.recordDate,
    required this.activeDays,
    required this.streak,
    required this.longestStreak,
    required this.appSec,
    required this.topTracks,
    this.topCover,
    required this.topArtists,
    required this.bySource,
    required this.activity,
  });

  /// Tracks in the library, the only number not from history.
  final int libraryTracks;

  final int totalPlays;
  final int listenSec;
  final int uniqueTracks;
  final int uniqueArtists;

  /// Average length of a played track, seconds.
  final int avgSec;

  /// Days history spans, the denominator of per day averages.
  final int daySpan;

  final int recordDay;
  final DateTime? recordDate;

  /// Days with any listening at all.
  final int activeDays;

  /// Days in a row with listening, counted from today.
  final int streak;

  /// The longest all-time run of listening days, for the Streak achievement: a
  /// missed day doesn't take a tier (or its XP) away.
  final int longestStreak;

  final int appSec;

  final List<TrackPlays> topTracks;

  /// Cover of the most played track that has one.
  final String? topCover;

  final List<ArtistPlays> topArtists;
  final List<SourcePlays> bySource;

  /// Plays per day.
  final Map<String, int> activity;

  String? get favArtist => topArtists.isEmpty ? null : topArtists.first.name;

  static ProfileStats build(
    LibraryState lib,
    DaysState days,
    PlayStats journal,
  ) {
    var totalPlays = 0;
    var listenSec = 0;
    final artists = ArtistTally();
    final sources = <MusicSource, ({int plays, int seconds})>{};
    final rows = <TrackPlays>[];
    String? topCover;
    var topPlays = 0, topTs = 0;

    var firstTs = DateTime.now().millisecondsSinceEpoch;
    var lastTs = firstTs;

    final played = journal.allPlayed();
    for (final entry in played) {
      final plays = entry.plays;
      totalPlays += plays;

      final source = MusicSource.fromId(entry.id);
      // A track from the library, or if it's gone its database snapshot:
      // otherwise everything heard but not saved drops from the tops.
      final track = resolveHistoryTrack(entry.id, lib, journal);
      final seconds = (track?.duration.inSeconds ?? 0) * plays;
      final was = sources[source] ?? (plays: 0, seconds: 0);
      sources[source] = (
        plays: was.plays + plays,
        seconds: was.seconds + seconds,
      );
      listenSec += seconds;

      if (entry.firstTs > 0 && entry.firstTs < firstTs) firstTs = entry.firstTs;
      if (entry.lastTs > lastTs) lastTs = entry.lastTs;

      // The track itself is needed from here: without it the tops have nothing
      // to show.
      if (track == null) continue;
      rows.add(TrackPlays(track, plays));
      // Cover for the profile banner's Auto: most plays, on ties the one played
      // later.
      final cover = track.cover;
      if (cover != null &&
          cover.isNotEmpty &&
          (plays > topPlays || plays == topPlays && entry.lastTs > topTs)) {
        topCover = cover;
        topPlays = plays;
        topTs = entry.lastTs;
      }

      artists.add(track, plays, source);
    }

    rows.sort((a, b) => b.plays.compareTo(a.plays));

    final topArtists = artists.ranked();

    final bySource =
        sources.entries
            .where((e) => e.value.plays > 0)
            .map((e) => SourcePlays(e.key, e.value.plays, e.value.seconds))
            .toList()
          ..sort((a, b) => b.plays.compareTo(a.plays));

    final perDay = journal.perDay;
    var recordDay = 0;
    String? recordKey;
    for (final e in perDay.entries) {
      if (e.value > recordDay) {
        recordDay = e.value;
        recordKey = e.key;
      }
    }

    final span = ((lastTs - firstTs) / 86400000).ceil();

    return ProfileStats(
      libraryTracks: lib.inLib.length,
      totalPlays: totalPlays,
      listenSec: listenSec,
      uniqueTracks: played.length,
      uniqueArtists: artists.size,
      avgSec: totalPlays > 0 ? (listenSec / totalPlays).round() : 0,
      daySpan: span < 1 ? 1 : span,
      recordDay: recordDay,
      recordDate: recordKey == null ? null : DateTime.tryParse(recordKey),
      activeDays: perDay.length,
      streak: _streak(perDay),
      longestStreak: longestRun(perDay.keys),
      appSec: days.appMs ~/ 1000,
      topTracks: rows.take(10).toList(),
      topCover: topCover,
      topArtists: topArtists.take(10).toList(),
      bySource: bySource,
      activity: perDay,
    );
  }
}

/// Days [keys] (`YYYY-MM-DD`), ascending with no repeats.
List<DateTime> sortedDays(Iterable<String> keys) =>
    [for (final k in keys) ?DateTime.tryParse(k)]..sort();

/// The longest run of consecutive days in [keys].
int longestRun(Iterable<String> keys) {
  var longest = 0, run = 0;
  DateTime? prev;
  for (final d in sortedDays(keys)) {
    run = prev != null && nextDay(prev) == d ? run + 1 : 1;
    prev = d;
    if (run > longest) longest = run;
  }
  return longest;
}

/// The next calendar day, through the constructor rather than +24 h: on clock
/// changes a day has 23 or 25 hours.
DateTime nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

/// Days in a row with listening. Counted from today, but from yesterday if
/// nothing's played yet today, or the streak would zero every morning.
int _streak(Map<String, int> log) {
  final now = DateTime.now();
  DateTime back(DateTime d) => DateTime(d.year, d.month, d.day - 1);
  var cursor = DateTime(now.year, now.month, now.day);
  if ((log[dayKey(cursor)] ?? 0) == 0) cursor = back(cursor);
  var streak = 0;
  while ((log[dayKey(cursor)] ?? 0) > 0) {
    streak++;
    cursor = back(cursor);
  }
  return streak;
}

final profileStatsProvider = Provider<ProfileStats>((ref) {
  return ProfileStats.build(
    ref.watch(libraryProvider),
    ref.watch(daysProvider),
    ref.watch(playStatsProvider),
  );
});

/// Long duration text. Takes a `BuildContext` rather than ready
/// `AppLocalizations`: it's called from dozens of layout spots, where an extra
/// argument would be noise.
String fmtDurLong(BuildContext context, int seconds) {
  final l = context.l;
  if (seconds <= 0) return l.statsZeroMinutes;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? l.statsHoursMinutes(h, m) : l.statsMinutes(m);
}

/// `m:ss`, average track length.
String fmtClock(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
