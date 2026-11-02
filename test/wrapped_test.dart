/// The reviews: periods, the count from the journal, the journal itself, what
/// shows when, and the sheet.
///
/// The clock is a stand-in everywhere, as the year's window hangs on the date.
/// No `pumpAndSettle` for the sheet: a slide runs its bar for 6 s and moves on,
/// so the tree settles only on the last one.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/wrapped/periods.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/features/wrapped/ui/wrapped_poster.dart';
import 'package:bloom/features/wrapped/ui/wrapped_sheet.dart';
import 'package:bloom/features/wrapped/wrapped_data.dart';
import 'package:bloom/features/wrapped/wrapped_format.dart';
import 'package:bloom/features/wrapped/wrapped_store.dart';
import 'package:bloom/shared/ui/atoms.dart' show BloomButton;
import 'package:bloom/shared/ui/bloom_sheet.dart' show SheetHandle;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'package:intl/date_symbol_data_local.dart';

/// August 3, 2026: the past month is July, the year window is closed.
final _now = DateTime(2026, 8, 3, 12);

ProviderContainer _container({
  DateTime? now,
  BloomDb? db,
  DateTime Function()? clock,
  bool force = false,
}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      dbProvider.overrideWithValue(db ?? BloomDb.memory()),
      playLogClockProvider.overrideWithValue(clock ?? () => now ?? _now),
      wrappedForceProvider.overrideWithValue(force),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Track _track(
  String id, {
  String name = 'Track',
  String artist = 'Artist',
  String? cover,
  int seconds = 180,
}) => Track(
  id: id,
  name: name,
  artist: artist,
  duration: Duration(seconds: seconds),
  source: MusicSource.fromId(id),
  cover: cover,
);

/// A journal right from events, so the math is checked with no player or
/// database.
PlayLog _log(List<(DateTime, Track)> events) {
  final tracks = <String, Track>{};
  final list = <PlayEvent>[];
  for (final (at, track) in events) {
    list.add(PlayEvent(at.millisecondsSinceEpoch, track.id));
    tracks[track.id] = track;
  }
  list.sort((a, b) => a.ts.compareTo(b.ts));
  return PlayLog(events: list, tracks: tracks);
}

void main() {
  // In the app `flutter_localizations` loads month names with the locale;
  // there's no tree here, so I init the dates myself.
  setUpAll(() => initializeDateFormatting('ru'));

  group('periods', () {
    test('the month is the last one whole', () {
      final r = periodRange(PeriodKind.month, _now);
      expect(r.from, DateTime(2026, 7, 1));
      expect(r.to, DateTime(2026, 8, 1));
    });

    test('always show takes the current month for the month', () {
      // Otherwise there'd be nothing to check: the journal starts collecting at
      // the update, and a past month often has zero events.
      final r = periodRange(PeriodKind.month, _now, true);
      expect(r.from, DateTime(2026, 8, 1));
      expect(r.to, _now);
    });

    test('the year runs from January 1 to now', () {
      final r = periodRange(PeriodKind.year, _now);
      expect(r.from, DateTime(2026, 1, 1));
      expect(r.to, _now);
    });

    test('the year window is December 21–31', () {
      expect(inYearWindow(_now), isFalse);
      expect(inYearWindow(DateTime(2026, 12, 20)), isFalse);
      expect(inYearWindow(DateTime(2026, 12, 22)), isTrue);
      expect(inYearWindow(DateTime(2026, 12, 31)), isTrue);
      // "Always show" opens the window on any day.
      expect(inYearWindow(_now, force: true), isTrue);
    });

    test('the hint week is the 1st to the 7th', () {
      expect(inMonthHintWindow(DateTime(2026, 8, 1)), isTrue);
      expect(inMonthHintWindow(DateTime(2026, 8, 7, 23)), isTrue);
      expect(inMonthHintWindow(DateTime(2026, 8, 8)), isFalse);
      expect(inMonthHintWindow(DateTime(2026, 8, 20), force: true), isTrue);
    });

    test('a reminder fits on the 1st and in the December window', () {
      expect(scheduledPeriods(_now), isEmpty);
      expect(scheduledPeriods(DateTime(2026, 8, 1)), [PeriodKind.month]);
      expect(scheduledPeriods(DateTime(2026, 12, 22)), [PeriodKind.year]);
      // On December 1 the year window is still closed, only the month.
      expect(scheduledPeriods(DateTime(2026, 12, 1)), [PeriodKind.month]);
      expect(scheduledPeriods(DateTime(2026, 12, 21)), [PeriodKind.year]);
      expect(scheduledPeriods(_now, force: true), [
        PeriodKind.year,
        PeriodKind.month,
      ]);
    });

    test('a period key is stable and tells kinds apart', () {
      expect(periodKey(periodRange(PeriodKind.year, _now)), '2026');
      expect(periodKey(periodRange(PeriodKind.month, _now)), '2026-07');
      // The same period asked at another hour gives the same key.
      expect(
        periodKey(periodRange(PeriodKind.month, DateTime(2026, 8, 3, 23))),
        periodKey(periodRange(PeriodKind.month, _now)),
      );
    });

    test('a period label: a capitalized month, a year as a number', () {
      expect(
        periodDatesLabel(periodRange(PeriodKind.month, _now), 'ru'),
        'Июль 2026',
      );
      expect(
        periodDatesLabel(periodRange(PeriodKind.year, _now), 'ru'),
        '2026',
      );
    });
  });

  group('calculation', () {
    final month = periodRange(PeriodKind.month, _now);

    test("counts only the period's events", () {
      final inside = _track('sc:1');
      final before = _track('sc:2');
      final after = _track('sc:3');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 6, 20), before), // before the period
          (DateTime(2026, 7, 28, 10), inside),
          (DateTime(2026, 7, 28, 11), inside),
          (DateTime(2026, 8, 2), after), // after the period
        ]),
        month,
      );
      expect(data.plays, 2);
      expect(data.uniqueTracks, 1);
      expect(data.seconds, 360);
      expect(data.topTracks.single.track.id, 'sc:1');
    });

    test('the track top by play count', () {
      final one = _track('sc:1', name: 'Один');
      final two = _track('sc:2', name: 'Два');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), one),
          (DateTime(2026, 7, 28, 9), two),
          (DateTime(2026, 7, 29, 9), two),
        ]),
        month,
      );
      expect(data.topTracks.map((t) => t.track.name), ['Два', 'Один']);
      expect(data.topTracks.first.plays, 2);
    });

    test('artists group ignoring case and spaces', () {
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), _track('sc:1', artist: 'Boards')),
          (DateTime(2026, 7, 28, 9), _track('sc:2', artist: ' boards ')),
        ]),
        month,
      );
      expect(data.uniqueArtists, 1);
      expect(data.topArtists.single.plays, 2);
    });

    test('a multi-artist row counts for each participant', () {
      final duo = _track('sc:1', artist: 'reidenshi, Øneheart', cover: 'a.jpg');
      final solo = _track('sc:2', artist: 'Øneheart');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), duo),
          (DateTime(2026, 7, 28, 9), solo),
        ]),
        month,
      );
      expect(data.uniqueArtists, 2);
      // A shared track counts for both, along with the cover.
      expect(data.topArtists.map((a) => a.name), ['Øneheart', 'reidenshi']);
      expect(data.topArtists.map((a) => a.plays), [2, 1]);
      expect(data.topArtists.map((a) => a.cover), ['a.jpg', 'a.jpg']);
    });

    test("an artist's platform is where they were heard most", () {
      // The avatar and page come from that platform: an account with the same
      // name on another one belongs to someone else.
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), _track('sc:1', artist: 'Boards')),
          (DateTime(2026, 7, 28, 9), _track('ym:1', artist: 'Boards')),
          (DateTime(2026, 7, 29, 9), _track('ym:2', artist: 'Boards')),
        ]),
        month,
      );
      expect(data.topArtists.single.source, MusicSource.yandex);
    });

    test("own files don't take an artist's platform away", () {
      // A local artist has no page, and searching where they were heard at
      // least once is the only way to one.
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), _track('local_1', artist: 'Boards')),
          (DateTime(2026, 7, 28, 9), _track('local_2', artist: 'Boards')),
          (DateTime(2026, 7, 29, 9), _track('sc:1', artist: 'Boards')),
        ]),
        month,
      );
      expect(data.topArtists.single.source, MusicSource.soundcloud);
    });

    test('discoveries are only those absent before the period', () {
      final old = _track('sc:1', artist: 'Старый');
      final fresh = _track('sc:2', artist: 'Новый');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 6, 1), old), // heard earlier
          (DateTime(2026, 7, 28, 9), old),
          (DateTime(2026, 7, 28, 10), fresh),
        ]),
        month,
      );
      expect(data.newArtistsCount, 1);
      expect(data.newArtists.single.name, 'Новый');
      expect(data.newTracksCount, 1);
    });

    test('a shared track before the period closes the discovery for both', () {
      // The "before the period" row gets parsed too: otherwise both
      // participants would stay "discoveries" forever, since the joined name
      // can't identify them.
      final duo = _track('sc:1', artist: 'reidenshi, Øneheart');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 6, 1), duo), // heard earlier
          (DateTime(2026, 7, 28, 9), _track('sc:2', artist: 'Øneheart')),
          (DateTime(2026, 7, 28, 10), _track('sc:3', artist: 'reidenshi')),
        ]),
        month,
      );
      expect(data.uniqueArtists, 2);
      expect(data.newArtistsCount, 0);
      expect(data.newArtists, isEmpty);
    });

    test('platforms split by id prefix', () {
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), _track('sc:1')),
          (DateTime(2026, 7, 27, 10), _track('ym:1')),
          (DateTime(2026, 7, 27, 11), _track('ym:2')),
        ]),
        month,
      );
      expect(data.sources.first.source, MusicSource.yandex);
      expect(data.sources.first.plays, 2);
      expect(data.sources.last.source, MusicSource.soundcloud);
    });

    test("the day's record, the streak and active days", () {
      final t = _track('sc:1');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), t),
          (DateTime(2026, 7, 28, 9), t),
          (DateTime(2026, 7, 28, 10), t),
          (DateTime(2026, 7, 28, 11), t),
          // Skipping the 29th breaks the streak.
          (DateTime(2026, 7, 30, 9), t),
        ]),
        month,
      );
      expect(data.recordDay!.plays, 3);
      expect(data.recordDay!.date, DateTime(2026, 7, 28));
      expect(data.activeDays, 3);
      expect(data.streak, 2);
    });

    test("hours, the peak and the night's share", () {
      final t = _track('sc:1');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 2), t),
          (DateTime(2026, 7, 27, 2, 30), t),
          (DateTime(2026, 7, 27, 15), t),
        ]),
        month,
      );
      expect(data.hours[2], 2);
      expect(data.hours[15], 1);
      expect(data.peakHour, 2);
      expect(data.nightShare, closeTo(2 / 3, 0.001));
    });

    test('an empty period gives an empty recap', () {
      final data = buildWrapped(const PlayLog(), month);
      expect(data.isEmpty, isTrue);
      expect(data.recordDay, isNull);
      expect(data.nightShare, 0);
    });

    test('with equal plays the longer track ranks higher', () {
      final short = _track('sc:1', name: 'Короткий', seconds: 100);
      final long = _track('sc:2', name: 'Длинный', seconds: 300);
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), short),
          (DateTime(2026, 7, 28, 9), long),
        ]),
        month,
      );
      expect(data.topTracks.map((t) => t.track.name), ['Длинный', 'Короткий']);
    });

    test("an artist's best track knows their page only if it's alone", () {
      final solo = Track(
        id: 'sc:1',
        name: 'Соло',
        artist: 'Boards',
        duration: const Duration(seconds: 180),
        source: MusicSource.soundcloud,
        cover: 'a.jpg',
      );
      final duo = _track('sc:2', artist: 'Boards, Canada', cover: 'b.jpg');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 7, 27, 9), solo),
          (DateTime(2026, 7, 27, 10), solo),
          (DateTime(2026, 7, 28, 9), duo),
        ]),
        month,
      );
      final boards = data.topArtists.firstWhere((a) => a.name == 'Boards');
      final canada = data.topArtists.firstWhere((a) => a.name == 'Canada');
      expect(boards.track.id, 'sc:1');
      // A shared track says nothing about them: a placeholder with the name.
      expect(canada.track.id, '');
      expect(canada.track.artist, 'Canada');
      expect(canada.cover, 'b.jpg');
    });

    test('a streak goes by the calendar, not 24-hour days', () {
      final t = _track('sc:1');
      final data = buildWrapped(
        _log([
          (DateTime(2026, 3, 28, 12), t),
          (DateTime(2026, 3, 29, 12), t),
          (DateTime(2026, 3, 30, 12), t),
        ]),
        PeriodRange(PeriodKind.month, DateTime(2026, 3), DateTime(2026, 4)),
      );
      expect(data.streak, 3);
    });

    test('an event with no track snapshot counts but stays out of the top', () {
      final data = buildWrapped(
        PlayLog(
          events: [
            PlayEvent(DateTime(2026, 7, 28, 9).millisecondsSinceEpoch, 'ym:9'),
          ],
        ),
        month,
      );
      expect(data.plays, 1);
      expect(data.uniqueTracks, 1);
      expect(data.uniqueArtists, 0);
      expect(data.topTracks, isEmpty);
      expect(data.sources.single.source, MusicSource.yandex);
    });
  });

  group('journal', () {
    test('writes an event and a snapshot, reads back from the database', () {
      final db = BloomDb.memory();
      final c = _container(db: db);
      c
          .read(playLogProvider.notifier)
          .log(_track('sc:1', name: 'Песня', artist: 'Артист', seconds: 200));

      final again = _container(db: db);
      final log = again.read(playLogProvider);
      expect(log.events.single.id, 'sc:1');
      expect(log.events.single.ts, _now.millisecondsSinceEpoch);
      expect(log.tracks['sc:1']!.name, 'Песня');
      expect(log.tracks['sc:1']!.duration.inSeconds, 200);
    });

    test('events always ascend by time', () {
      final db = BloomDb.memory();
      var at = DateTime(2026, 7, 2);
      final c = _container(db: db, clock: () => at);
      c.read(playLogProvider.notifier).log(_track('sc:2'));
      at = DateTime(2026, 7, 1);
      c.read(playLogProvider.notifier).log(_track('sc:1'));

      final log = _container(db: db).read(playLogProvider);
      expect(log.events.map((e) => e.id), ['sc:1', 'sc:2']);
    });

    test('clearing zeroes the database too', () {
      final db = BloomDb.memory();
      final c = _container(db: db);
      c.read(playLogProvider.notifier)
        ..log(_track('sc:1'))
        ..clear();
      expect(c.read(playLogProvider).isEmpty, isTrue);
      expect(_container(db: db).read(playLogProvider).isEmpty, isTrue);
    });
  });

  group('what to show', () {
    ProviderContainer withPlays(
      List<(DateTime, Track)> events, {
      DateTime? now,
      BloomDb? db,
      bool force = false,
    }) {
      var clock = now ?? _now;
      final seed = _container(db: db, clock: () => clock, force: force);
      final log = seed.read(playLogProvider.notifier);
      for (final (at, track) in events) {
        clock = at;
        log.log(track);
      }
      clock = now ?? _now;
      return seed;
    }

    test('the month is always available, the year only in December', () {
      final c = withPlays([
        (DateTime(2026, 7, 28, 9), _track('sc:1')),
        (DateTime(2026, 7, 29, 9), _track('sc:2')),
      ]);
      final entries = c.read(wrappedEntriesProvider);
      expect(entries.month!.plays, 2);
      expect(entries.monthUnseen, isTrue);
      // On August 3 the year window is closed, so no plate, though there's data
      // for the year.
      expect(entries.year, isNull);
    });

    test('in the December window the year shows too', () {
      final c = withPlays([
        (DateTime(2026, 12, 5, 9), _track('sc:1')),
      ], now: DateTime(2026, 12, 22, 12));
      final entries = c.read(wrappedEntriesProvider);
      expect(entries.year, isNotNull);
      expect(entries.yearUnseen, isTrue);
      // November is empty, so no month recap exists.
      expect(entries.month, isNull);
    });

    test('an empty period has no entry', () {
      // Heard before July: nothing to recap for the month.
      final c = withPlays([(DateTime(2026, 6, 1, 9), _track('sc:1'))]);
      expect(c.read(wrappedEntriesProvider).month, isNull);
    });

    test('a test run opens the year and takes the current month', () {
      final events = [(DateTime(2026, 8, 2, 9), _track('sc:1'))];
      // An event in August: the past month (July) is empty, the year window is
      // closed.
      expect(withPlays(events).read(wrappedEntriesProvider).isEmpty, isTrue);

      final entries = withPlays(
        events,
        force: true,
      ).read(wrappedEntriesProvider);
      expect(entries.year, isNotNull);
      expect(entries.month!.range.from, DateTime(2026, 8, 1));
    });

    test("a test run's marks leave the real ones alone", () {
      final db = BloomDb.memory();
      final events = [(DateTime(2026, 8, 2, 9), _track('sc:1'))];
      final forced = withPlays(events, db: db, force: true);
      final range = forced.read(wrappedEntriesProvider).month!.range;
      forced.read(wrappedMarksProvider.notifier).markSeen(range);
      expect(db.getMap('wrapped.seen.force')['month'], '2026-08');
      expect(db.getMap('wrapped.seen'), isEmpty);
    });

    test('a period is reminded of once, after a restart too', () {
      final db = BloomDb.memory();
      final c = withPlays([(DateTime(2026, 7, 28, 9), _track('sc:1'))], db: db);
      final marks = c.read(wrappedMarksProvider.notifier);
      final range = c.read(wrappedEntriesProvider).month!.range;

      expect(marks.isNotified(range), isFalse);
      marks.markNotified(range);
      expect(marks.isNotified(range), isTrue);
      // The key and its form are shared with sync.
      expect(db.getMap('wrapped.notified'), {'month': '2026-07'});
      final again = _container(db: db);
      expect(
        again.read(wrappedMarksProvider.notifier).isNotified(range),
        isTrue,
      );
      // Viewing and the reminder are separate marks: one doesn't clear the
      // other.
      expect(again.read(wrappedEntriesProvider).monthUnseen, isTrue);
    });

    test('viewing removes the swap and survives a restart', () {
      final db = BloomDb.memory();
      final c = withPlays([(DateTime(2026, 7, 28, 9), _track('sc:1'))], db: db);
      final range = c.read(wrappedEntriesProvider).month!.range;
      c.read(wrappedMarksProvider.notifier).markSeen(range);
      expect(c.read(wrappedEntriesProvider).monthUnseen, isFalse);
      expect(
        _container(db: db).read(wrappedEntriesProvider).monthUnseen,
        isFalse,
      );
      expect(db.getMap('wrapped.seen'), {'month': '2026-07'});
    });

    test('the month recap hint: the first week and after viewing', () {
      final c = withPlays([(DateTime(2026, 7, 28, 9), _track('sc:1'))]);
      expect(c.read(wrappedEntriesProvider).monthHint, isTrue);
      final range = c.read(wrappedEntriesProvider).month!.range;
      c.read(wrappedMarksProvider.notifier).markSeen(range);
      expect(c.read(wrappedEntriesProvider).monthHint, isTrue);

      final later = withPlays([
        (DateTime(2026, 7, 28, 9), _track('sc:1')),
      ], now: DateTime(2026, 8, 8, 12));
      expect(later.read(wrappedEntriesProvider).monthHint, isFalse);
    });
  });

  group('format', () {
    testWidgets('listening time in Russian', (tester) async {
      late AppLocalizations l;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l = AppLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(fmtListenTime(l, 20), 'Меньше минуты');
      expect(fmtListenTime(l, 60 * 45), '45 минут');
      expect(fmtListenTime(l, 3600 * 2), '2 часа');
      expect(fmtListenTime(l, 3600 * 12 + 60 * 34), '12 часов 34 минуты');
      expect(fmtHourRange(l, 23), '23:00 — 00:00');

      // The slide needs separate numbers with a label, not a ready string.
      expect(splitListenTime(l, 20), isEmpty);
      expect(splitListenTime(l, 3600 * 2), [(n: 2, word: 'часа')]);
      expect(splitListenTime(l, 3600 * 12 + 60 * 34), [
        (n: 12, word: 'часов'),
        (n: 34, word: 'минуты'),
      ]);
      expect(splitListenTime(l, 60 * 45), [(n: 45, word: 'минут')]);
    });
  });

  group('poster', () {
    testWidgets('a full top of five rows fits a 3:4 card', (tester) async {
      final month = periodRange(PeriodKind.month, _now);
      final data = buildWrapped(
        _log([
          for (var i = 0; i < 5; i++)
            for (var n = 0; n <= i; n++)
              (
                DateTime(2026, 7, 28, 9, i * 10 + n),
                _track(
                  'sc:$i',
                  name: 'Довольно длинное название трека номер $i',
                  artist: 'Исполнитель с длинным именем $i',
                ),
              ),
        ]),
        month,
      );
      expect(data.topTracks.length, 5);
      expect(data.topArtists.length, 5);

      final c = _container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildBloomTheme(BloomThemes.dark),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  height: 560,
                  child: WrappedPosterCard(data: data, width: 300),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.text('Поделиться'), findsOneWidget);
      expect(find.text('ТОП-ТРЕКИ'), findsOneWidget);
      expect(find.text('ТОП-АРТИСТЫ'), findsOneWidget);
    });
  });

  group('entries and the sheet', () {
    /// Month data from a couple of plays, enough for all the entries.
    WrappedData monthData() => buildWrapped(
      _log([
        (DateTime(2026, 7, 28, 9), _track('sc:1', name: 'Песня')),
        (DateTime(2026, 7, 29, 9), _track('sc:1', name: 'Песня')),
      ]),
      periodRange(PeriodKind.month, _now),
    );

    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(),
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildBloomTheme(BloomThemes.dark),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

    testWidgets('the sheet opens on its period and flips', (tester) async {
      late BuildContext ctx;
      await pump(
        tester,
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      );

      showWrappedSheet(ctx, monthData());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('ИЮЛЬ 2026'), findsOneWidget);
      expect(find.text('Далее'), findsOneWidget);
      // One button: "Close" takes its place on the last slide.
      expect(find.text('Закрыть'), findsNothing);
      // It spans the sheet's width and the sheet is big: the handle is above
      // the middle.
      final screen = tester.getSize(find.byType(MaterialApp));
      expect(
        tester.getSize(find.widgetWithText(BloomButton, 'Далее')).width,
        greaterThan(screen.width / 2),
      );
      final top = tester.getTopLeft(find.byType(SheetHandle)).dy;
      expect(top, lessThan(screen.height / 2));

      await tester.tap(find.text('Далее'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ты слушал музыку'), findsOneWidget);

      for (var i = 0; i < 20 && find.text('Далее').evaluate().isNotEmpty; i++) {
        await tester.tap(find.text('Далее'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }
      expect(find.text('Далее'), findsNothing);
      expect(find.text('Закрыть'), findsOneWidget);
      expect(find.byType(WrappedPosterCard), findsOneWidget);

      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
