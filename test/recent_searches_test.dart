/// Recent in search: queries and opened cards. Order, dedup, ceiling and
/// reading from disk.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/search/recent_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

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

Track _track(String id) => Track(
  id: id,
  name: 'Nightcall',
  artist: 'Kavinsky',
  duration: const Duration(seconds: 258),
  source: MusicSource.soundcloud,
  cover: 'https://cdn/nightcall.jpg',
  sourceData: const {'transcodings': []},
);

void main() {
  test('новый запрос встаёт наверх', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentSearchesProvider.notifier);
    notifier.push('daft punk');
    notifier.push('radiohead');
    expect(c.read(recentSearchesProvider), ['radiohead', 'daft punk']);
  });

  test('повтор не двоится и поднимается, оставляя последнее написание', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentSearchesProvider.notifier);
    notifier.push('daft punk');
    notifier.push('radiohead');
    notifier.push('  Daft Punk  ');
    expect(c.read(recentSearchesProvider), ['Daft Punk', 'radiohead']);
  });

  test('пустой запрос не запоминается', () {
    final c = _container(JsonStore.memory());
    c.read(recentSearchesProvider.notifier).push('   ');
    expect(c.read(recentSearchesProvider), isEmpty);
  });

  test('дальше потолка список не растёт, лишнее уходит снизу', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentSearchesProvider.notifier);
    for (var i = 0; i <= kRecentSearchMax; i++) {
      notifier.push('q$i');
    }
    final state = c.read(recentSearchesProvider);
    expect(state, hasLength(kRecentSearchMax));
    expect(state.first, 'q$kRecentSearchMax');
    expect(state, isNot(contains('q0')));
  });

  test('удаление и очистка', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentSearchesProvider.notifier);
    notifier.push('a');
    notifier.push('b');
    notifier.remove('a');
    expect(c.read(recentSearchesProvider), ['b']);
    notifier.clear();
    expect(c.read(recentSearchesProvider), isEmpty);
  });

  test('список переживает перезапуск: пишется и читается из хранилища', () {
    final store = JsonStore.memory();
    _container(store).read(recentSearchesProvider.notifier).push('kavinsky');
    // A second container means a new app launch with the same file.
    expect(_container(store).read(recentSearchesProvider), ['kavinsky']);
  });

  test('чужое содержимое ключа не роняет чтение', () {
    final store = JsonStore.memory({
      'recentSearches': ['ok', 42, null],
    });
    expect(_container(store).read(recentSearchesProvider), ['ok']);
  });

  test('открытое: наверх, без дублей по типу и id', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentItemsProvider.notifier);
    notifier.push(RecentTrack(_track('sc:1')));
    notifier.push(
      RecentArtist(
        const Artist(id: 'sc:9', name: 'Kavinsky', source: MusicSource.local),
      ),
    );
    notifier.push(RecentTrack(_track('sc:1')));

    final state = c.read(recentItemsProvider);
    expect(state, hasLength(2));
    expect(state.first, isA<RecentTrack>());
  });

  test('трек и сет с одинаковым id — разные записи', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentItemsProvider.notifier);
    notifier.push(RecentTrack(_track('sc:1')));
    notifier.push(
      RecentSet(
        const Playlist(id: 'sc:1', title: 'Outrun', source: MusicSource.local),
      ),
    );
    expect(c.read(recentItemsProvider), hasLength(2));
  });

  test('дальше потолка список открытых не растёт', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentItemsProvider.notifier);
    for (var i = 0; i <= kRecentItemMax; i++) {
      notifier.push(RecentTrack(_track('sc:$i')));
    }
    expect(c.read(recentItemsProvider), hasLength(kRecentItemMax));
  });

  test('открытое переживает перезапуск целой сущностью', () {
    final store = JsonStore.memory();
    _container(store).read(recentItemsProvider.notifier)
      ..push(RecentTrack(_track('sc:1')))
      ..push(
        RecentSet(
          const Playlist(
            id: 'ym:5',
            title: 'Outrun',
            source: MusicSource.local,
            isAlbum: true,
            ownerName: 'Kavinsky',
          ),
        ),
      );

    final restored = _container(store).read(recentItemsProvider);
    expect(restored, hasLength(2));
    // A set opens as the same entity that came in the results, and the track's
    // `sourceData` is there too, or the stream would need resolving again.
    expect(restored.first, isA<RecentSet>());
    final set = (restored.first as RecentSet).set;
    expect(set.isAlbum, isTrue);
    expect(set.ownerName, 'Kavinsky');
    expect(set.source, MusicSource.yandex); // the source is restored by id
    final track = (restored.last as RecentTrack).track;
    expect(track.sourceData, isNotNull);
    expect(track.cover, 'https://cdn/nightcall.jpg');
  });

  test('удаление и очистка открытых', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(recentItemsProvider.notifier);
    final track = RecentTrack(_track('sc:1'));
    notifier.push(track);
    notifier.push(RecentTrack(_track('sc:2')));
    // I remove by key, not by reference: the list holds an entry restored from
    // disk, which is no longer the same object.
    notifier.remove(RecentTrack(_track('sc:1')));
    expect(c.read(recentItemsProvider), hasLength(1));
    notifier.clear();
    expect(c.read(recentItemsProvider), isEmpty);
  });

  test('битая запись открытого пропускается, остальные читаются', () {
    final store = JsonStore.memory({
      'recentItems': [
        {'kind': 'track', 'data': null},
        {'kind': 'таких нет', 'data': <String, dynamic>{}},
        {
          'kind': 'artist',
          'data': {'id': 'sc:9', 'name': 'Kavinsky'},
        },
      ],
    });
    final state = _container(store).read(recentItemsProvider);
    expect(state, hasLength(1));
    expect((state.single as RecentArtist).artist.name, 'Kavinsky');
  });
}
