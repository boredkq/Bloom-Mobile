/// The artist avatar cache: exact name match, misses are remembered too, a
/// fresh cache stays off the network, and an artist is asked of the platform
/// they were heard on.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/profile/artist_avatars.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

Artist _artist(String name, String? avatar, [MusicSource? source]) => Artist(
  id: '${(source ?? MusicSource.soundcloud).prefix}$name',
  name: name,
  avatar: avatar,
  source: source ?? MusicSource.soundcloud,
);

class _FakeProvider extends MusicProvider {
  _FakeProvider(this.answers, [this.source = MusicSource.soundcloud]);

  /// What to answer for a name.
  final Map<String, List<Artist>> answers;

  final List<String> queries = [];

  @override
  final MusicSource source;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<List<Artist>> searchArtists(String query, {int limit = 3}) async {
    queries.add(query);
    final found = answers[query];
    if (found == null) throw StateError('нет сети');
    return found;
  }
}

ProviderContainer _container(
  List<_FakeProvider> providers, [
  Map<String, dynamic>? seed,
]) {
  final registry = ProviderRegistry();
  for (final p in providers) {
    registry.register(p);
  }
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory(seed)),
      dbProvider.overrideWithValue(BloomDb.memory()),
      registryProvider.overrideWithValue(registry),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// A SoundCloud artist reference.
ArtistRef _sc(String name) => (name: name, source: MusicSource.soundcloud);

String _key(String name, [MusicSource source = MusicSource.soundcloud]) =>
    artistAvatarKey(source, name);

void main() {
  test('takes the exact name match, not the first result', () async {
    final sc = _FakeProvider({
      'Onda': [
        _artist('Onda Fan Page', 'https://cdn/fan.jpg'),
        _artist('onda', 'https://cdn/real.jpg'),
      ],
    });
    final c = _container([sc]);

    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Onda')]);

    expect(c.read(artistAvatarsProvider)[_key('onda')], 'https://cdn/real.jpg');
  });

  test('a fresh cache stays off the network', () async {
    final sc = _FakeProvider({
      'Artist': [_artist('Artist', 'https://cdn/a.jpg')],
    });
    final c = _container([sc]);

    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Artist')]);
    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Artist')]);

    expect(sc.queries, ['Artist']);
  });

  test('a miss is remembered and not asked again', () async {
    // The provider fails every request: no network.
    final sc = _FakeProvider(const {});
    final c = _container([sc]);

    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Кто-то')]);
    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Кто-то')]);

    expect(sc.queries, ['Кто-то']);
    // An empty entry isn't exposed, so the UI keeps the track cover.
    expect(c.read(artistAvatarsProvider), isEmpty);
  });

  test('a stale entry is refetched, a live one is not', () async {
    final old = DateTime.now()
        .subtract(const Duration(days: 31))
        .millisecondsSinceEpoch;
    final fresh = DateTime.now().millisecondsSinceEpoch;
    final sc = _FakeProvider({
      'Stale': [_artist('Stale', 'https://cdn/new.jpg')],
      'Fresh': [_artist('Fresh', 'https://cdn/nope.jpg')],
    });
    final c = _container(
      [sc],
      {
        'artistAvatars': {
          _key('stale'): {'url': 'https://cdn/old.jpg', 't': old},
          _key('fresh'): {'url': 'https://cdn/keep.jpg', 't': fresh},
        },
      },
    );

    // The cache loaded from the file before any network.
    expect(
      c.read(artistAvatarsProvider)[_key('fresh')],
      'https://cdn/keep.jpg',
    );

    await c.read(artistAvatarsProvider.notifier).ensure([
      _sc('Stale'),
      _sc('Fresh'),
    ]);

    expect(sc.queries, ['Stale']);
    expect(c.read(artistAvatarsProvider)[_key('stale')], 'https://cdn/new.jpg');
  });

  test("asks the artist's own platform, not another", () async {
    final sc = _FakeProvider({
      'Тот же': [_artist('Тот же', 'https://cdn/sc.jpg')],
    });
    final ym = _FakeProvider({
      'Тот же': [_artist('Тот же', 'https://cdn/ym.jpg', MusicSource.yandex)],
    }, MusicSource.yandex);
    final c = _container([sc, ym]);

    await c.read(artistAvatarsProvider.notifier).ensure([
      (name: 'Тот же', source: MusicSource.yandex),
    ]);

    expect(sc.queries, isEmpty);
    expect(ym.queries, ['Тот же']);
    // Platforms don't mix: SoundCloud just has no entry.
    final avatars = c.read(artistAvatarsProvider);
    expect(avatars[_key('тот же', MusicSource.yandex)], 'https://cdn/ym.jpg');
    expect(avatars[_key('тот же')], isNull);
  });

  test('a local artist is asked of nobody', () async {
    final sc = _FakeProvider({
      'Свой файл': [_artist('Свой файл', 'https://cdn/nope.jpg')],
    });
    final c = _container([sc]);

    await c.read(artistAvatarsProvider.notifier).ensure([
      (name: 'Свой файл', source: MusicSource.local),
    ]);

    expect(sc.queries, isEmpty);
    expect(c.read(artistAvatarsProvider), isEmpty);
  });

  test('old cache entries without a platform are dropped', () async {
    final fresh = DateTime.now().millisecondsSinceEpoch;
    final sc = _FakeProvider({
      'Artist': [_artist('Artist', 'https://cdn/new.jpg')],
    });
    final c = _container(
      [sc],
      {
        'artistAvatars': {
          'artist': {'url': 'https://cdn/old.jpg', 't': fresh},
        },
      },
    );

    // There's no telling whose avatar it was, so it stays out of the map.
    expect(c.read(artistAvatarsProvider), isEmpty);

    await c.read(artistAvatarsProvider.notifier).ensure([_sc('Artist')]);

    expect(sc.queries, ['Artist']);
    expect(
      c.read(artistAvatarsProvider)[_key('artist')],
      'https://cdn/new.jpg',
    );
  });
}
