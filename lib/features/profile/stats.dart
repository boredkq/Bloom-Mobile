/// Расчёт статистики профиля — порт `Stats::details/recount` ПК.
///
/// Источники: журнал прослушиваний ([PlayStats] — сколько раз и когда слушали
/// каждый трек, по дням) и таблица дней ([DaysState] — время в приложении).
/// Ничего своего не персистится — всё считается на лету.
///
/// Разбивка по площадкам берётся из ПРЕФИКСА id, а не из поля трека: треки
/// площадок живут в памяти, и после перезапуска половина записей истории уже не
/// резолвится в объект — иначе в «где слушали чаще» остался бы один SoundCloud.
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

  /// Сколько треков в библиотеке — единственное число не из истории.
  final int libraryTracks;

  final int totalPlays;
  final int listenSec;
  final int uniqueTracks;
  final int uniqueArtists;

  /// Средняя длина прослушанного трека, секунды.
  final int avgSec;

  /// На сколько дней растянута история — знаменатель «в среднем за день».
  final int daySpan;

  final int recordDay;
  final DateTime? recordDate;

  /// Дней, в которые вообще что-то слушали.
  final int activeDays;

  /// Дней подряд с прослушиваниями, считая от сегодня.
  final int streak;

  /// Самая длинная серия дней с прослушиваниями за всё время — по ней
  /// достижение «Серия»: пропущенный день не отнимает взятую ступень (и её XP).
  final int longestStreak;

  final int appSec;

  final List<TrackPlays> topTracks;

  /// Обложка самого слушаемого трека (из тех, у кого она есть).
  final String? topCover;

  final List<ArtistPlays> topArtists;
  final List<SourcePlays> bySource;

  /// Прослушивания по дням — для графика и теплокарты.
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
      // Трек — из библиотеки, а если его там уже нет, его снимок из базы: иначе
      // всё, что человек слушал, но не сохранил, выпало бы из топов.
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

      // Дальше нужен сам трек: без него нечего показать в топах.
      if (track == null) continue;
      rows.add(TrackPlays(track, plays));
      // Обложка для «Авто» у баннера профиля: больше всех прослушиваний, при
      // равенстве — слушанный позже (тот же запрос, что на ПК).
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

/// Дни [keys] (`YYYY-MM-DD`) по возрастанию, без повторов.
List<DateTime> sortedDays(Iterable<String> keys) =>
    [for (final k in keys) ?DateTime.tryParse(k)]..sort();

/// Самая длинная серия дней подряд среди [keys].
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

/// Следующий календарный день — через конструктор, а не +24 ч: на переходе
/// на летнее время сутки бывают в 23 и 25 часов.
DateTime nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

/// Дней подряд с прослушиваниями. Отсчёт от сегодня, но если сегодня ещё не
/// слушали — от вчера: иначе стрик обнулялся бы каждое утро (десктопный грейс).
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

/// «Nч Nм» / «N мин» — десктопный `fmtDurLong`.
///
/// Берёт `BuildContext`, а не готовый `AppLocalizations`: зовут её из вёрстки
/// десятками мест, и лишний аргумент там был бы шумом.
String fmtDurLong(BuildContext context, int seconds) {
  final l = context.l;
  if (seconds <= 0) return l.statsZeroMinutes;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  return h > 0 ? l.statsHoursMinutes(h, m) : l.statsMinutes(m);
}

/// «м:сс» — средняя длина трека.
String fmtClock(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
