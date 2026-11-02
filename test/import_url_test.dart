/// Importing by link from the "+" sheet: where tracks land and what counts as
/// added.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/library/import_url.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
  sourceData: const {'transcodings': []},
);

/// A platform where a link holds either a playlist or a single track.
class _FakeSoundCloud extends MusicProvider {
  _FakeSoundCloud({this.sets = const {}, this.singles = const {}});

  /// Link to playlist contents.
  final Map<String, List<Track>> sets;

  /// Links with a single track behind them, which can't be imported.
  final Map<String, Track> singles;

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  /// A collection's id is the path's last part: `https://sc/one?x` gives
  /// `sc:set:one`, so two different links lead to one collection.
  static String _idOf(String url) =>
      'sc:set:${Uri.parse(url).pathSegments.last}';

  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    final single = singles[url];
    if (single != null) return ResolvedTrack(single);
    final bare = url.split('?').first;
    if (!sets.containsKey(bare)) return null;
    return ResolvedSet(
      Playlist(
        id: _idOf(bare),
        title: 'Сет',
        ownerName: 'Владелец',
        sourceUrl: bare,
        source: MusicSource.soundcloud,
      ),
    );
  }

  @override
  Future<SetContent?> getPlaylist(String id) async => SetContent(
    playlist: Playlist(id: id, title: 'Сет', source: MusicSource.soundcloud),
    tracks: [
      for (final e in sets.entries)
        if (_idOf(e.key) == id) ...e.value,
    ],
  );
}

({ProviderContainer container, ProviderRegistry registry}) _setup(
  _FakeSoundCloud provider,
) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      dbProvider.overrideWithValue(BloomDb.memory()),
    ],
  );
  addTearDown(c.dispose);
  return (container: c, registry: ProviderRegistry()..register(provider));
}

Future<ImportResult> _import(
  ({ProviderContainer container, ProviderRegistry registry}) env,
  String url,
  ImportTarget target,
) => importUrlInto(
  env.registry,
  env.container.read(libraryProvider.notifier),
  () => env.container.read(libraryProvider),
  url,
  target,
);

void main() {
  test(
    'the Create target makes a playlist with a source and all tracks',
    () async {
      final env = _setup(
        _FakeSoundCloud(
          sets: {
            'https://sc/one': [_track('sc:1'), _track('sc:2')],
          },
        ),
      );

      final result = await _import(
        env,
        'https://sc/one',
        const ImportTarget.create(),
      );

      expect(result.added, 2);
      final playlist = env.container.read(libraryProvider).playlists.single;
      expect(playlist.id, result.createdId);
      expect(playlist.trackIds, ['sc:1', 'sc:2']);
      // The source is remembered, or the playlist would have nothing to refresh
      // from. The refresh goes by collection id on its platform.
      final source = playlist.sources.single;
      expect(source.toJson(), {
        'url': 'https://sc/one',
        'title': 'Сет',
        'owner': 'Владелец',
        'provider': 'sc',
        'id': 'sc:set:one',
        'kind': 'playlist',
        'cover': '',
      });
      expect(PlSourceRef.fromJson(source.toJson())?.toJson(), source.toJson());
    },
  );

  test("a source with no id or platform isn't read", () {
    expect(PlSourceRef.fromJson({'url': 'https://sc/one'}), isNull);
    expect(PlSourceRef.fromJson({'id': 'sc:set:1'}), isNull);
    expect(
      PlSourceRef.fromJson({'id': 'sc:set:1', 'provider': 'sc'})?.kind,
      'playlist',
    );
  });

  test(
    'the All tracks target makes no playlist and counts no duplicates',
    () async {
      final env = _setup(
        _FakeSoundCloud(
          sets: {
            'https://sc/one': [_track('sc:1'), _track('sc:2')],
          },
        ),
      );
      env.container.read(libraryProvider.notifier).addToLibrary([
        _track('sc:1'),
      ]);

      final result = await _import(
        env,
        'https://sc/one',
        const ImportTarget(ImportTargetKind.library),
      );

      expect(result.added, 1);
      expect(result.total, 2);
      expect(result.createdId, isNull);
      expect(env.container.read(libraryProvider).playlists, isEmpty);
      expect(env.container.read(libraryProvider).inLib.length, 2);
    },
  );

  test("the Favorites target likes only what isn't liked yet", () async {
    final env = _setup(
      _FakeSoundCloud(
        sets: {
          'https://sc/one': [_track('sc:1'), _track('sc:2')],
        },
      ),
    );
    env.container.read(libraryProvider.notifier).toggleFav(_track('sc:1'));

    final result = await _import(
      env,
      'https://sc/one',
      const ImportTarget(ImportTargetKind.favorites),
    );

    expect(result.added, 1);
    expect(env.container.read(libraryProvider).favs.length, 2);
  });

  test('importing into an existing playlist binds the source', () async {
    final env = _setup(
      _FakeSoundCloud(
        sets: {
          'https://sc/one': [_track('sc:1'), _track('sc:2')],
        },
      ),
    );
    final target = env.container
        .read(libraryProvider.notifier)
        .createPlaylist('Мой', tracks: [_track('sc:1')]);

    final result = await _import(
      env,
      'https://sc/one',
      ImportTarget(ImportTargetKind.playlist, playlistId: target.id),
    );

    expect(result.added, 1);
    final playlist = env.container.read(libraryProvider).playlists.single;
    expect(playlist.trackIds.toSet(), {'sc:1', 'sc:2'});
    // An imported collection becomes a source of an existing playlist too: a
    // refresh only mixes new tracks in on top, and what was added by hand stays
    // put.
    expect(playlist.sources.map((s) => s.id), ['sc:set:one']);

    // Another link to the same collection doesn't become a second source.
    await _import(
      env,
      'https://sc/one?utm=share',
      ImportTarget(ImportTargetKind.playlist, playlistId: target.id),
    );
    expect(
      env.container.read(libraryProvider).playlists.single.sources.length,
      1,
    );
  });

  test('a single track link is rejected', () async {
    final env = _setup(
      _FakeSoundCloud(singles: {'https://sc/track': _track('sc:1')}),
    );

    expect(
      () => _import(env, 'https://sc/track', const ImportTarget.create()),
      throwsA(isA<ImportException>()),
    );
  });

  test('an unknown link is rejected', () async {
    final env = _setup(_FakeSoundCloud());
    expect(
      () => _import(env, 'https://example.com/x', const ImportTarget.create()),
      throwsA(isA<ImportException>()),
    );
  });
}
