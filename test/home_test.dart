/// Home's platform shelves: their cache and quiet retries.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/home/discover_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

Track _track(String id) => Track(
  id: 'sc:$id',
  name: id,
  artist: 'A',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

/// A platform that gives up the shelf only after a few tries.
class _FakeProvider extends MusicProvider {
  _FakeProvider({this.charts, this.releases, this.failFirst = 0});

  final List<Track>? charts;
  final NewReleases? releases;

  /// How many first answers to fail with an empty result.
  int failFirst;

  int chartCalls = 0;

  @override
  MusicSource get source => MusicSource.yandex;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<List<Track>?> getCharts() async {
    chartCalls++;
    if (failFirst > 0) {
      failFirst--;
      return const [];
    }
    return charts;
  }

  @override
  Future<NewReleases?> getNewReleases() async => releases;
}

ProviderContainer _container(MusicProvider provider) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      dbProvider.overrideWithValue(BloomDb.memory()),
      registryProvider.overrideWithValue(
        ProviderRegistry()..register(provider),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(resetDiscoverCache);

  group('витрина', () {
    test('чарт берётся у площадки и кешируется', () async {
      final provider = _FakeProvider(charts: [_track('a')]);
      final c = _container(provider);

      final first = await fetchDiscover(
        c.read(registryProvider),
        DiscoverMode.charts,
      );
      expect(first, isNotNull);
      expect(first!.source, MusicSource.yandex);
      expect((first.block as DiscoverTracks).tracks.single.id, 'sc:a');
      expect(provider.chartCalls, 1);

      // A second visit to home stays off the network.
      await fetchDiscover(c.read(registryProvider), DiscoverMode.charts);
      expect(provider.chartCalls, 1);
    });

    test('пустой ответ не кешируется, провайдер повторяет запрос', () async {
      final provider = _FakeProvider(charts: [_track('a')], failFirst: 1);
      final c = _container(provider);

      final result = await c.read(discoverProvider(DiscoverMode.charts).future);
      expect(result, isNotNull);
      expect((result!.block as DiscoverTracks).tracks.single.id, 'sc:a');
      // The first answer was empty, so it went twice.
      expect(provider.chartCalls, 2);
    });

    test('площадка молчит совсем — блока нет', () async {
      final provider = _FakeProvider(charts: [_track('a')], failFirst: 99);
      final c = _container(provider);
      expect(
        await c.read(discoverProvider(DiscoverMode.charts).future),
        isNull,
      );
      // Exactly as many calls as attempts: the first plus the retries.
      expect(provider.chartCalls, kDiscoverRetries.length + 1);
    });

    test('новинки альбомами разбираются как альбомы', () async {
      final album = Playlist(
        id: 'ym:1',
        title: 'Альбом',
        source: MusicSource.yandex,
        isAlbum: true,
      );
      final c = _container(_FakeProvider(releases: NewAlbums([album])));
      final result = await c.read(
        discoverProvider(DiscoverMode.newReleases).future,
      );
      expect((result!.block as DiscoverAlbums).albums.single.id, 'ym:1');
    });

    test('новинки треками разбираются как треки', () async {
      final c = _container(_FakeProvider(releases: NewTracks([_track('n')])));
      final result = await c.read(
        discoverProvider(DiscoverMode.newReleases).future,
      );
      expect((result!.block as DiscoverTracks).tracks.single.id, 'sc:n');
    });
  });
}
