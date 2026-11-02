/// The wave's memory: dislikes, "already shown", station cursors, the seed
/// shift and the running wave. The store is in memory, no file system.
library;

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/wave/wave_engine.dart' show kWaveShownDays;
import 'package:bloom/features/wave/wave_store.dart';
import 'package:bloom/features/wave/wave_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Song',
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
);

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a dislike survives a restart along with the track', () {
    final store = JsonStore.memory();
    _container(
      store,
    ).read(waveStoreProvider.notifier).toggleDislike(_track('sc:1'));

    // A new container is the same as a new app launch.
    final state = _container(store).read(waveStoreProvider);
    expect(state.isDisliked('sc:1'), isTrue);
    // The dislikes list needs something to show: an id isn't enough.
    expect(state.dislikes.single.name, 'Song');
  });

  test('the dislikes list: new on top', () async {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);
    wave.toggleDislike(_track('sc:1'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    wave.toggleDislike(_track('sc:2'));
    expect(c.read(waveStoreProvider).dislikes.map((t) => t.id), [
      'sc:2',
      'sc:1',
    ]);
  });

  test("switching a track's platform carries the dislike along", () {
    final c = _container(JsonStore.memory());
    c.read(waveStoreProvider.notifier).toggleDislike(_track('sc:1'));
    c.read(libraryProvider.notifier).replaceTrack('sc:1', _track('ytm:a'));

    final state = c.read(waveStoreProvider);
    expect(state.isDisliked('sc:1'), isFalse);
    expect(state.isDisliked('ytm:a'), isTrue);
  });

  test('clearing and a repeat dislike remove marks', () {
    final c = _container(JsonStore.memory());
    final wave = c.read(waveStoreProvider.notifier);
    expect(wave.toggleDislike(_track('sc:1')), isTrue);
    expect(wave.toggleDislike(_track('sc:1')), isFalse);
    wave
      ..toggleDislike(_track('sc:1'))
      ..toggleDislike(_track('sc:2'))
      ..clearDislikes();
    expect(c.read(waveStoreProvider).dislikes, isEmpty);
  });

  test(
    'what the wave showed is remembered, older than two weeks is forgotten',
    () {
      final store = JsonStore.memory();
      final c = _container(store);
      final wave = c.read(waveStoreProvider.notifier);
      wave.markShown(['sc:1', 'sc:2']);
      expect(wave.shownIds(), {'sc:1', 'sc:2'});

      final db = c.read(dbProvider);
      db.exec('INSERT INTO wave_shown (track_id, at) VALUES (?, ?)', [
        'sc:3',
        BloomDb.now() - (kWaveShownDays + 1) * 24 * 3600 * 1000,
      ]);
      expect(wave.shownIds(), isNot(contains('sc:3')));
      _container(store).read(waveStoreProvider);
      expect(db.value('SELECT count(*) FROM wave_shown'), 2);
    },
  );

  test(
    "a station cursor is in the database's kv under its shared key and survives a restart",
    () {
      final store = JsonStore.memory();
      const seed = WaveSeed('sc', 'track:42');
      final c = _container(store);
      final wave = c.read(waveStoreProvider.notifier);
      expect(wave.cursorOf(seed), '');
      wave.saveCursors({seed: '20'});

      final cursors = c.read(dbProvider).getMap('wave.cursors');
      expect((cursors['sc|track:42'] as Map)['c'], '20');
      expect(
        _container(store).read(waveStoreProvider.notifier).cursorOf(seed),
        '20',
      );
    },
  );

  test('at most three hundred cursors, old ones go first', () async {
    final wave = _container(
      JsonStore.memory(),
    ).read(waveStoreProvider.notifier);
    wave.saveCursors({const WaveSeed('sc', 'track:old'): '20'});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    wave.saveCursors({
      for (var i = 0; i < kMaxCursors; i++) WaveSeed('sc', 'track:$i'): '20',
    });
    expect(wave.cursorOf(const WaveSeed('sc', 'track:old')), '');
    expect(wave.cursorOf(const WaveSeed('sc', 'track:0')), '20');
  });

  test('the seed shift grows with each My Wave', () {
    final store = JsonStore.memory();
    final wave = _container(store).read(waveStoreProvider.notifier);
    expect(wave.takeRotation(), 0);
    expect(wave.takeRotation(), 1);
    expect(_container(store).read(waveStoreProvider.notifier).rotation, 2);
  });

  test('a running wave returns after a restart, its end erases it', () {
    final store = JsonStore.memory();
    _container(store)
        .read(waveStoreProvider.notifier)
        .saveRun(
          WaveRun(
            mode: WaveMode.track,
            seeds: const [WaveSeed('sc', 'track:1')],
            played: ['sc:1', 'sc:2'],
            bonus: {'artist': 3},
          ),
        );

    final wave = _container(store).read(waveStoreProvider.notifier);
    final restored = wave.savedRun!;
    expect(restored.mode, WaveMode.track);
    expect(restored.seeds, const [WaveSeed('sc', 'track:1')]);
    expect(restored.played, ['sc:1', 'sc:2']);
    expect(restored.bonus['artist'], 3);

    wave.saveRun(null);
    expect(_container(store).read(waveStoreProvider.notifier).savedRun, isNull);
  });

  test(
    'the chosen platform is remembered by its shared code, YouTube Music too',
    () {
      final store = JsonStore.memory();
      expect(
        _container(store).read(waveStoreProvider).source,
        MusicSource.soundcloud,
      );
      _container(
        store,
      ).read(waveStoreProvider.notifier).setSource(MusicSource.ytmusic);
      expect(store.readMap(kWaveKey)['source'], 'ytm');
      expect(
        _container(store).read(waveStoreProvider).source,
        MusicSource.ytmusic,
      );
    },
  );

  test('Yandex is chosen but not signed in: the wave goes from SoundCloud', () {
    final c = _container(JsonStore.memory());
    c.read(waveStoreProvider.notifier).setSource(MusicSource.yandex);

    // The choice is kept: when sign-in comes back, so does the station.
    expect(c.read(waveStoreProvider).source, MusicSource.yandex);
    expect(c.read(effectiveWaveSourceProvider), MusicSource.soundcloud);
  });
}
