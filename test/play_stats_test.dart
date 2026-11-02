/// Play stats and History over the journal in the database: the top's window,
/// track snapshots, restart, moving on a platform switch, clearing.
library;

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/history_store.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const int _min = 60000;

Track _track(
  String id, {
  String name = 'Song',
  MusicSource source = MusicSource.soundcloud,
}) => Track(
  id: id,
  name: name,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: source,
);

/// A container with a controlled clock: [clock] moves by hand.
class _Env {
  _Env([BloomDb? db]) : db = db ?? BloomDb.memory() {
    c = ProviderContainer(
      overrides: [
        jsonStoreProvider.overrideWithValue(JsonStore.memory()),
        dbProvider.overrideWithValue(this.db),
        playLogClockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(clock),
        ),
      ],
    );
    addTearDown(c.dispose);
  }

  final BloomDb db;
  late final ProviderContainer c;
  int clock = DateTime(2026, 9, 1).millisecondsSinceEpoch;

  void listen(Track track, {int after = _min}) {
    clock += after;
    c.read(playLogProvider.notifier).log(track);
  }

  PlayStats get stats => c.read(playStatsProvider);
  List<HistoryItem> get history => c.read(historyProvider);
}

void main() {
  test('топ за окно не берёт то, что слушали раньше окна', () {
    final now = DateTime(2026, 9, 1);
    final day = 24 * 60 * _min;
    final base = now.millisecondsSinceEpoch;
    final stats = PlayStats.build(
      PlayLog(
        events: [
          for (var i = 0; i < 5; i++) PlayEvent(base - 200 * day + i, 'sc:a'),
          PlayEvent(base - 2 * day, 'sc:b'),
          PlayEvent(base - day, 'sc:b'),
        ],
      ),
    );

    expect(stats.topPlayed(now: now).map((t) => t.id), ['sc:a', 'sc:b']);
    expect(stats.topPlayed(sinceDays: 90, now: now).map((t) => t.id), ['sc:b']);
  });

  group('«История»', () {
    test('лимита нет', () {
      final env = _Env();
      for (var i = 0; i < 250; i++) {
        env.listen(_track('sc:$i'));
      }
      expect(env.history.length, 250);
      expect(env.history.first.track.id, 'sc:249'); // freshest on top
    });

    test('прослушивание не кладёт трек в библиотеку, но строка есть', () {
      final env = _Env();
      env.listen(_track('sc:1', name: 'A'));

      expect(env.c.read(libraryProvider).allTracks, isEmpty);
      // The track is rebuilt from the snapshot in the database, so there's
      // something to show and play.
      final track = env.history.single.track;
      expect(track.name, 'A');
      expect(track.source, MusicSource.soundcloud);
    });

    test('свой файл в истории тоже виден — как на ПК', () {
      final env = _Env();
      env.listen(_track('lf:1', source: MusicSource.local));
      env.listen(_track('sc:1'));

      expect(env.history.map((h) => h.row.id), ['sc:1', 'lf:1']);
    });

    test('трек из библиотеки берётся целиком, а не из снимка', () {
      final env = _Env();
      final full = Track(
        id: 'sc:1',
        name: 'Полный',
        artist: 'Artist',
        duration: const Duration(seconds: 100),
        source: MusicSource.soundcloud,
        sourceData: const {'transcodings': []},
      );
      env.c.read(libraryProvider.notifier).addToLibrary([full]);
      env.listen(full);

      expect(env.history.single.track.sourceData, isNotNull);
    });

    test('строка живёт и после удаления трека из библиотеки', () {
      final env = _Env();
      final t = _track('sc:1', name: 'Ушедший');
      env.c.read(libraryProvider.notifier).addToLibrary([t]);
      env.listen(t);
      env.c.read(libraryProvider.notifier).deleteTrack('sc:1');

      expect(env.history.single.track.name, 'Ушедший');
    });
  });

  test('журнал переживает перезапуск', () {
    final first = _Env();
    first.listen(_track('sc:1'));
    first.listen(_track('sc:1'));

    final again = _Env(first.db);
    expect(again.stats.playCount('sc:1'), 2);
    expect(again.history.single.track.name, 'Song');
  });

  test('смена площадки переносит прослушивания на новый id', () {
    final env = _Env();
    final old = _track('sc:1', name: 'Ночь');
    env.c.read(libraryProvider.notifier).addToLibrary([old]);
    env.listen(old);
    env.listen(old);

    env.c
        .read(libraryProvider.notifier)
        .replaceTrack(
          'sc:1',
          _track('ytm:1', name: 'Ночь', source: MusicSource.ytmusic),
        );
    env.c.read(playLogProvider.notifier).reload();

    expect(env.stats.playCount('sc:1'), 0);
    expect(env.stats.playCount('ytm:1'), 2);
    expect(env.stats.tracks['ytm:1']?.name, 'Ночь');
  });

  test('очистка стирает журнал и снимки без ссылок', () {
    final env = _Env();
    env.listen(_track('sc:1'));
    env.c.read(playLogProvider.notifier).clear();

    expect(env.history, isEmpty);
    expect(env.db.value('SELECT count(*) FROM tracks'), 0);
  });
}
