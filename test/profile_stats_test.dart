/// Profile stats, days, achievements and level. All of it comes from the play
/// journal and the days table, so the database is in memory here.
library;

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/db/track_store.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/days_store.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:bloom/features/profile/achievements.dart';
import 'package:bloom/features/profile/level.dart';
import 'package:bloom/features/profile/stats.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(
  String id, {
  String artist = 'Artist',
  int seconds = 100,
  MusicSource source = MusicSource.soundcloud,
}) => Track(
  id: id,
  name: 'Song $id',
  artist: artist,
  duration: Duration(seconds: seconds),
  source: source,
);

/// A container over database [db]. The clock moves a minute per call, so each
/// play has its own moment.
ProviderContainer _container([BloomDb? db]) {
  var now = DateTime(2026, 9, 1).millisecondsSinceEpoch;
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      dbProvider.overrideWithValue(db ?? BloomDb.memory()),
      playLogClockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(now += 60000),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Counts a play, as the player does.
void _listen(ProviderContainer c, Track track) =>
    c.read(playLogProvider.notifier).log(track);

/// [n] plays of one track.
void _listenMany(ProviderContainer c, int n) {
  for (var i = 0; i < n; i++) {
    _listen(c, _track('sc:1'));
  }
}

/// The day [daysAgo] days back, at local noon.
DateTime _ago(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo, 12);
}

/// A past play as a row right in the journal, as the player writes it.
void _seedPlays(BloomDb db, DateTime at, int n, [String id = 'sc:1']) {
  TrackStore(db).put([_track(id)]);
  for (var i = 0; i < n; i++) {
    db.exec('INSERT INTO plays (ts, track_id) VALUES (?, ?)', [
      at.millisecondsSinceEpoch + i,
      id,
    ]);
  }
}

void main() {
  test('повторное прослушивание растит счётчик, а не плодит записи', () {
    final c = _container();
    final track = _track('sc:1');

    _listen(c, track);
    _listen(c, _track('sc:2'));
    _listen(c, track);

    final rows = c.read(playStatsProvider).historyRows();
    expect(rows.length, 2);
    // The track rose to the top and took its count along.
    expect(rows.first.id, 'sc:1');
    expect(rows.first.count, 2);
    expect(c.read(profileStatsProvider).totalPlays, 3);
  });

  test('время прослушивания и средняя длина считаются по счётчику', () {
    final c = _container();
    _listen(c, _track('sc:1', seconds: 200));
    _listen(c, _track('sc:1', seconds: 200));
    _listen(c, _track('sc:2', seconds: 100));

    final stats = c.read(profileStatsProvider);
    expect(stats.listenSec, 500);
    expect(stats.avgSec, 167); // 500 / 3
    expect(stats.uniqueTracks, 2);
  });

  test('трек, которого нет в библиотеке, в топе остаётся — по снимку', () {
    final c = _container();
    _listen(c, _track('sc:1', artist: 'A'));
    _listen(c, _track('sc:1', artist: 'A'));

    // The library is empty: the track was only heard, not saved.
    final stats = c.read(profileStatsProvider);
    expect(stats.topTracks.single.track.id, 'sc:1');
    expect(stats.topTracks.single.plays, 2);
    expect(stats.favArtist, 'A');
  });

  test('прослушивания раскладываются по площадкам', () {
    final c = _container();
    for (var i = 0; i < 3; i++) {
      _listen(c, _track('ytm:1', source: MusicSource.ytmusic));
    }
    _listen(c, _track('sc:1'));

    final stats = c.read(profileStatsProvider);
    expect(stats.totalPlays, 4);
    expect(stats.bySource.first.source, MusicSource.ytmusic);
    expect(stats.bySource.first.plays, 3);
    expect(stats.bySource.length, 2);
  });

  test('топ артистов сортируется по прослушиваниям, любимый — первый', () {
    final c = _container();
    _listen(c, _track('sc:1', artist: 'A'));
    _listen(c, _track('sc:2', artist: 'B'));
    _listen(c, _track('sc:2', artist: 'B'));

    final stats = c.read(profileStatsProvider);
    expect(stats.favArtist, 'B');
    expect(stats.topArtists.map((a) => a.plays), [2, 1]);
    expect(stats.uniqueArtists, 2);
  });

  test('мультиартистный трек идёт в зачёт каждому участнику', () {
    final c = _container();
    _listen(c, _track('sc:1', artist: 'reidenshi, Øneheart'));
    _listen(c, _track('sc:2', artist: 'Øneheart'));
    _listen(c, _track('sc:2', artist: 'Øneheart'));

    final stats = c.read(profileStatsProvider);
    // No joined name in the top: it would find neither an avatar nor an artist
    // page.
    expect(stats.topArtists.map((a) => a.name), ['Øneheart', 'reidenshi']);
    expect(stats.topArtists.map((a) => a.plays), [3, 1]);
    expect(stats.uniqueArtists, 2);
    expect(stats.favArtist, 'Øneheart');
    expect(stats.topArtists.last.source, MusicSource.soundcloud);
  });

  test('дни — из журнала: серия с грейсом со вчера, рекорд, дни с музыкой', () {
    final db = BloomDb.memory();
    _seedPlays(db, _ago(1), 4);
    _seedPlays(db, _ago(2), 2);
    _seedPlays(db, _ago(4), 9);
    db.exec('INSERT INTO days (day, app_ms) VALUES (?, ?)', [
      dayKey(_ago(1)),
      3600000,
    ]);
    final c = _container(db);

    final stats = c.read(profileStatsProvider);
    // Yesterday and the day before in a row, a gap on the third: a streak of 2.
    expect(stats.streak, 2);
    expect(stats.longestStreak, 2);
    expect(stats.recordDay, 9);
    expect(stats.activeDays, 3);
    expect(stats.activity[dayKey(_ago(4))], 9);
    expect(stats.appSec, 3600);
  });

  test('«На волне» берёт самую длинную серию: пропуск ступень не отнимает', () {
    final db = BloomDb.memory();
    for (final d in [10, 9, 8, 7]) {
      _seedPlays(db, _ago(d), 1);
    }
    _seedPlays(db, _ago(1), 1);
    final c = _container(db);

    final stats = c.read(profileStatsProvider);
    expect(stats.streak, 1);
    expect(stats.longestStreak, 4);
    final streak = c
        .read(achievementsProvider)
        .firstWhere((a) => a.def.id == 'streak');
    expect(streak.tier, AchTier.bronze); // 3 days
  });

  test('достижения: тиры, прогресс до следующего и максимум', () {
    final c = _container();
    _listenMany(c, 150);

    final list = c.read(achievementsProvider);
    final listener = list.firstWhere((a) => a.def.id == 'listener');
    // 150 plays: bronze (100) is taken, silver (1000) is far.
    expect(listener.tierReached, 1);
    expect(listener.tier, AchTier.bronze);
    expect(listener.nextTarget, 1000);
    expect(listener.ratio, closeTo((150 - 100) / (1000 - 100), 0.001));
    expect(listener.maxed, isFalse);

    // One day with music: six more to bronze.
    final devotee = list.firstWhere((a) => a.def.id == 'devotee');
    expect(devotee.unlocked, isFalse);
    expect(devotee.value, 1);
  });

  test('первый прогон засеивает молча, новые анлоки приходят потом', () {
    final db = BloomDb.memory();
    final c = _container(db);
    _listenMany(c, 150);
    final unlocked = c.read(unlockedAchievementsProvider.notifier);

    // The seed: bronze is already done, but there's no notification for it.
    expect(unlocked.sync(c.read(achievementsProvider)), isEmpty);
    expect(c.read(unlockedAchievementsProvider).seeded, isTrue);
    expect(
      c
          .read(unlockedAchievementsProvider)
          .at
          .containsKey(tierKey('listener', 0)),
      isTrue,
    );
    // The marks are in kv under the shared keys.
    expect(db.getMap('ach.at').containsKey('listener:0'), isTrue);
    expect(db.get('ach.seeded'), isTrue);

    // Reached silver: now that's news.
    final grown = [
      for (final a in c.read(achievementsProvider))
        if (a.def.id == 'listener')
          AchProgress(def: a.def, value: 1200, tierReached: 2, ratio: 1)
        else
          a,
    ];
    final fresh = unlocked.sync(grown);
    expect(fresh.single.ach.def.id, 'listener');
    expect(fresh.single.tier, AchTier.silver);
  });

  test('уровень: 10 за трек, 50 за день, 100/250/500 за ступени, 100·L', () {
    final c = _container();
    _listenMany(c, 150);

    final lv = c.read(levelProvider);
    expect(lv.plays, 1500);
    expect(lv.days, 50); // all 150 in one day
    // The bronze and all three tiers of the marathon one (150 in a day).
    expect(lv.ach, 100 + 100 + 250 + 500);
    expect(lv.xp, 2500);
    // 100 + 200 + … + 600 = 2100 to the seventh, 700 more to the eighth.
    expect(lv.level, 7);
    expect(lv.from, 2100);
    expect(lv.to, 2800);
  });

  test('уровень: дни подряд дают +10 за каждый предыдущий, до +50', () {
    final db = BloomDb.memory();
    // Opened seven days in a row, with nothing heard.
    for (var d = 6; d >= 0; d--) {
      db.exec('INSERT INTO days (day) VALUES (?)', [dayKey(_ago(d))]);
    }
    final c = _container(db);

    final lv = c.read(levelProvider);
    expect(lv.days, 50 + 60 + 70 + 80 + 90 + 100 + 100);
    expect(lv.xp, 550);
    expect(lv.level, 3); // 100 + 200 = 300 to the third, 600 to the fourth
    expect(lv.from, 300);
    expect(lv.to, 600);
  });

  test(
    'визит и время в приложении — в таблице дней, переживают перезапуск',
    () {
      final db = BloomDb.memory();
      final c = _container(db);
      c.read(daysProvider.notifier)
        ..visit()
        ..visit()
        ..addUsage(1500)
        ..addUsage(500);

      expect(c.read(daysProvider).visited.length, 1);
      expect(c.read(daysProvider).appMs, 2000);

      final again = _container(db);
      expect(again.read(daysProvider).appMs, 2000);
      expect(again.read(levelProvider).days, 50);
    },
  );

  test('очистка с уровнем: XP откладываются, журнал и отметки уходят', () {
    final db = BloomDb.memory();
    final c = _container(db);
    _listenMany(c, 150);
    c
        .read(unlockedAchievementsProvider.notifier)
        .sync(c.read(achievementsProvider));
    final before = c.read(levelProvider).xp;

    c.read(statsClearProvider.notifier).clear(keepLevel: true);

    final stats = c.read(profileStatsProvider);
    expect(stats.totalPlays, 0);
    expect(stats.activeDays, 0);
    expect(stats.appSec, 0);
    expect(c.read(unlockedAchievementsProvider).at, isEmpty);
    // The first run is done, so anything taken anew comes as a notification.
    expect(c.read(unlockedAchievementsProvider).seeded, isTrue);
    expect(db.get('level.banked'), before);
    // Today's visit stays: the app is open.
    expect(c.read(levelProvider).xp, before + 50);
  });

  test('очистка без уровня: остаётся только сегодняшний визит', () {
    final c = _container();
    _listenMany(c, 150);

    c.read(statsClearProvider.notifier).clear(keepLevel: false);

    final lv = c.read(levelProvider);
    expect(lv.banked, 0);
    expect(lv.xp, 50);
    expect(lv.level, 1);
  });
}
