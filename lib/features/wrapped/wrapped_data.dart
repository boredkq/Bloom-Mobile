/// A period's review, counted from the plays journal.
///
/// The time is an estimate: each play counts its track's whole length.
library;

import 'package:flutter/foundation.dart';

import '../../core/entities/entities.dart';
import '../../core/store/days_store.dart' show dayKey;
import '../../core/store/play_log.dart';
import '../../shared/util/artists.dart';
import '../../shared/util/taste.dart' show artistKey;
import '../profile/stats.dart';
import 'periods.dart';

const int _kTop = 5;

/// Plays before 6:00 are the night's.
const int _kNightTo = 6;

@immutable
class WrappedRecordDay {
  const WrappedRecordDay(this.date, this.plays);

  final DateTime date;
  final int plays;
}

@immutable
class WrappedData {
  const WrappedData({
    required this.range,
    required this.plays,
    required this.uniqueTracks,
    required this.uniqueArtists,
    required this.seconds,
    required this.topTracks,
    required this.topArtists,
    required this.sources,
    required this.newArtists,
    required this.newArtistsCount,
    required this.newTracksCount,
    required this.recordDay,
    required this.hours,
    required this.peakHour,
    required this.nightShare,
    required this.activeDays,
    required this.streak,
  });

  final PeriodRange range;
  final int plays;
  final int uniqueTracks;
  final int uniqueArtists;
  final int seconds;
  final List<TrackPlays> topTracks;
  final List<ArtistPlays> topArtists;
  final List<SourcePlays> sources;

  /// Heard for the first time in this period.
  final List<ArtistPlays> newArtists;
  final int newArtistsCount;
  final int newTracksCount;

  final WrappedRecordDay? recordDay;

  /// Plays by the hour of the day, local time.
  final List<int> hours;
  final int peakHour;
  final double nightShare;
  final int activeDays;

  /// The longest run of days in a row within the period.
  final int streak;

  bool get isEmpty => plays == 0;
}

WrappedData buildWrapped(PlayLog log, PeriodRange range) {
  // What played before the period: the rest is heard for the first time.
  final seenTracks = <String>{};
  final seenArtists = <String>{};
  final perTrack = <String, int>{};
  final perDay = <String, int>{};
  final hours = List<int>.filled(24, 0);
  var plays = 0;

  for (final e in log.events) {
    if (e.ts >= range.toMs) break;
    if (e.ts < range.fromMs) {
      if (!seenTracks.add(e.id)) continue;
      for (final name in parseArtists(log.tracks[e.id]?.artist)) {
        seenArtists.add(artistKey(name));
      }
      continue;
    }
    plays++;
    perTrack[e.id] = (perTrack[e.id] ?? 0) + 1;
    final at = DateTime.fromMillisecondsSinceEpoch(e.ts);
    final day = dayKey(at);
    perDay[day] = (perDay[day] ?? 0) + 1;
    hours[at.hour]++;
  }

  final artists = ArtistTally();
  final sources = <MusicSource, SourcePlays>{};
  final tracks = <TrackPlays>[];
  var seconds = 0;
  var newTracks = 0;
  for (final MapEntry(key: id, value: n) in perTrack.entries) {
    final t = log.tracks[id];
    final source = t?.source ?? MusicSource.fromId(id);
    final sec = (t?.duration.inSeconds ?? 0) * n;
    final was = sources[source];
    sources[source] = SourcePlays(
      source,
      (was?.plays ?? 0) + n,
      (was?.seconds ?? 0) + sec,
    );
    if (!seenTracks.contains(id)) newTracks++;
    // Nothing to show of it in the tops.
    if (t == null) continue;
    seconds += sec;
    tracks.add(TrackPlays(t, n));
    artists.add(t, n, source);
  }

  // A tie goes to the longer listen.
  tracks.sort((a, b) {
    final byPlays = b.plays.compareTo(a.plays);
    return byPlays != 0
        ? byPlays
        : b.track.duration.compareTo(a.track.duration);
  });

  final rank = artists.ranked();
  final fresh = [
    for (final a in rank)
      if (!seenArtists.contains(artistKey(a.name))) a,
  ];

  WrappedRecordDay? record;
  for (final MapEntry(key: day, value: n) in perDay.entries) {
    if (record == null || n > record.plays) {
      record = WrappedRecordDay(DateTime.parse(day), n);
    }
  }

  var peak = 0;
  for (var h = 1; h < 24; h++) {
    if (hours[h] > hours[peak]) peak = h;
  }
  final night = hours.take(_kNightTo).fold(0, (s, n) => s + n);

  return WrappedData(
    range: range,
    plays: plays,
    uniqueTracks: perTrack.length,
    uniqueArtists: artists.size,
    seconds: seconds,
    topTracks: tracks.take(_kTop).toList(),
    topArtists: rank.take(_kTop).toList(),
    sources: sources.values.toList()
      ..sort((a, b) => b.plays.compareTo(a.plays)),
    newArtists: fresh.take(_kTop).toList(),
    newArtistsCount: fresh.length,
    newTracksCount: newTracks,
    recordDay: record,
    hours: hours,
    peakHour: peak,
    nightShare: plays > 0 ? night / plays : 0,
    activeDays: perDay.length,
    streak: longestRun(perDay.keys),
  );
}
