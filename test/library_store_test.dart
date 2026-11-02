/// The library: likes, playlists and all of it surviving a restart. The store
/// is in memory, no file system.
library;

import 'package:bloom/core/db/track_store.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

Track _track(String id, {String name = 'Song'}) => Track(
  id: id,
  name: name,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
  sourceData: const {'transcodings': []},
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
  test("a like stores the whole track, removing it doesn't drop the track", () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final track = _track('sc:1');

    expect(c.read(libraryProvider).isFav('sc:1'), isFalse);
    lib.toggleFav(track);

    expect(c.read(libraryProvider).isFav('sc:1'), isTrue);
    // Without the track itself, favorites would hold a bare id: nothing to show
    // or play.
    expect(c.read(libraryProvider).favTracks.single.name, 'Song');

    lib.toggleFav(track);
    expect(c.read(libraryProvider).isFav('sc:1'), isFalse);
    // The track stays in the library: it may have come from a playlist too.
    expect(c.read(libraryProvider).tracks.containsKey('sc:1'), isTrue);
  });

  test('favorites are sorted freshest first', () async {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'Первый'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    lib.toggleFav(_track('sc:2', name: 'Второй'));

    expect(c.read(libraryProvider).favTracks.map((t) => t.name).toList(), [
      'Второй',
      'Первый',
    ]);
  });

  test(
    "tracks are added explicitly, freshest first, duplicates don't move the order",
    () {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);

      expect(lib.addToLibrary([_track('sc:1', name: 'A')]), 1);
      expect(lib.addToLibrary([_track('sc:2', name: 'B')]), 1);
      expect(lib.addToLibrary([_track('sc:1', name: 'A')]), 0);

      expect(c.read(libraryProvider).allTracks.map((t) => t.name).toList(), [
        'B',
        'A',
      ]);
    },
  );

  test('removing a track clears it everywhere', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final track = _track('sc:1');
    lib.toggleFav(track); // a like also adds to the library
    final pl = lib.createPlaylist('Мой', tracks: [track, _track('sc:2')]);

    lib.deleteTrack('sc:1');

    final after = c.read(libraryProvider);
    expect(after.isInLib('sc:1'), isFalse);
    expect(after.isFav('sc:1'), isFalse);
    // History keeps no track in the store: its row lives on the journal's
    // snapshot.
    expect(after.tracks.containsKey('sc:1'), isFalse);
    // A dangling id in a playlist would show a count with no row.
    expect(after.playlists.singleWhere((p) => p.id == pl.id).trackIds, [
      'sc:2',
    ]);
  });

  test('removing a track with no history takes it out of the store too', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.addToLibrary([_track('sc:1')]);

    lib.deleteTrack('sc:1');

    expect(c.read(libraryProvider).tracks.containsKey('sc:1'), isFalse);
  });

  test('switching platform moves all references to the new id', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final old = _track('sc:1', name: 'Ночь');
    lib.toggleFav(old);
    final pl = lib.createPlaylist('Мой', tracks: [_track('sc:9'), old]);
    final addedAt = c.read(libraryProvider).inLib['sc:1'];

    lib.replaceTrack(
      'sc:1',
      Track(
        id: 'ytm:1',
        name: 'Ночь',
        artist: 'Artist',
        duration: const Duration(seconds: 100),
        source: MusicSource.ytmusic,
      ),
    );

    final after = c.read(libraryProvider);
    expect(after.tracks.containsKey('sc:1'), isFalse);
    expect(after.isInLib('ytm:1'), isTrue);
    expect(after.isFav('ytm:1'), isTrue);
    // The playlist position stays: the platform changed, not the order.
    expect(after.playlists.singleWhere((p) => p.id == pl.id).trackIds, [
      'sc:9',
      'ytm:1',
    ]);
    // So does the added time, or the track would jump to the top of All tracks.
    expect(after.inLib['ytm:1'], addedAt);
  });

  test('replacing with the same id changes nothing', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'Ночь'));

    lib.replaceTrack('sc:1', _track('sc:1', name: 'Переписанное'));

    expect(c.read(libraryProvider).tracks['sc:1']?.name, 'Ночь');
  });

  test('dragging likes keeps the like time', () async {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'Первый'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    lib.toggleFav(_track('sc:2', name: 'Второй'));
    final at = Map.of(c.read(libraryProvider).favs);

    lib.setFavTracks(['sc:1', 'sc:2']);

    expect(c.read(libraryProvider).favTracks.map((t) => t.name), [
      'Первый',
      'Второй',
    ]);
    // Recent likes for the wave and "For you" still know when they were set.
    expect(c.read(libraryProvider).favs, at);
  });

  test("a platform doesn't overwrite a track fixed by hand", () {
    final c = _container(JsonStore.memory());
    final db = c.read(dbProvider);
    c.read(libraryProvider.notifier).addToLibrary([_track('sc:1', name: 'A')]);
    db.exec(
      "UPDATE tracks SET title = 'Своё', extra = json_set(extra, '\$.edited', json('true')) WHERE id = 'sc:1'",
    );

    c.read(libraryProvider.notifier).addToLibrary([
      _track('sc:1', name: 'С площадки'),
    ]);
    TrackStore(db).put([_track('sc:1', name: 'С площадки')]);

    expect(TrackStore(db).getOne('sc:1')?.name, 'Своё');
  });

  test('the track format round-trips without loss', () {
    final t = Track(
      id: 'sc:5',
      name: 'Песня',
      artist: 'Nick',
      duration: const Duration(milliseconds: 185500),
      source: MusicSource.soundcloud,
      url: 'https://soundcloud.com/nick/song',
      artistId: 'sc:artist:9',
      year: '2024',
      genres: const ['house'],
      sourceData: const {'transcodings': []},
    );
    final m = t.toJson();
    expect(m['title'], 'Песня');
    expect(m['duration'], 185.5);
    expect(m['provider'], 'sc');
    expect((m['extra'] as Map)['scId'], 5);
    expect((m['extra'] as Map)['artistId'], 9);

    final back = Track.fromJson(m)!;
    expect(back.artistId, 'sc:artist:9');
    expect(back.url, t.url);
    expect(back.duration, t.duration);
    expect(back.sourceData, t.sourceData);
  });

  test('playlist: a new track goes on top, duplicates are ignored', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Мой');

    lib.addTrackToPlaylist(pl.id, _track('sc:1', name: 'A'));
    lib.addTrackToPlaylist(pl.id, _track('sc:2', name: 'B'));
    lib.addTrackToPlaylist(pl.id, _track('sc:1', name: 'A'));

    final saved = c.read(libraryProvider).playlists.single;
    expect(saved.trackIds, ['sc:2', 'sc:1']);
    expect(
      c.read(libraryProvider).tracksOf(saved).map((t) => t.name).toList(),
      ['B', 'A'],
    );
  });

  test('editing a playlist: new contents and order at once', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist(
      'Мой',
      tracks: [
        _track('sc:1', name: 'A'),
        _track('sc:2', name: 'B'),
        _track('sc:3', name: 'C'),
      ],
    );

    lib.setPlaylistTracks(pl.id, ['sc:3', 'sc:1']);

    final saved = c.read(libraryProvider).playlists.single;
    expect(saved.trackIds, ['sc:3', 'sc:1']);
    // A track dropped from a playlist stays in the library: nobody removed it
    // from All tracks.
    expect(c.read(libraryProvider).isInLib('sc:2'), isTrue);
  });

  test(
    "editing All tracks: the order is kept, what's removed goes everywhere",
    () {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      final gone = _track('sc:2', name: 'B');
      lib.toggleFav(gone);
      final pl = lib.createPlaylist(
        'Мой',
        tracks: [
          _track('sc:1', name: 'A'),
          gone,
          _track('sc:3', name: 'C'),
        ],
      );

      lib.setLibraryTracks(['sc:3', 'sc:1']);

      final after = c.read(libraryProvider);
      expect(after.allTracks.map((t) => t.name).toList(), ['C', 'A']);
      // A track removed from the library must leave no like and no playlist row.
      expect(after.isFav('sc:2'), isFalse);
      expect(after.tracks.containsKey('sc:2'), isFalse);
      expect(after.playlists.singleWhere((p) => p.id == pl.id).trackIds, [
        'sc:1',
        'sc:3',
      ]);
    },
  );

  test('editing Favorites: a removed like keeps the track in the library', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'A'));
    lib.toggleFav(_track('sc:2', name: 'B'));

    lib.setFavTracks(['sc:2']);

    final after = c.read(libraryProvider);
    expect(after.favTracks.map((t) => t.name).toList(), ['B']);
    expect(after.isInLib('sc:1'), isTrue);
  });

  test('a batch into a playlist: inner order kept, duplicates skipped', () {
    final c = _container(JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Мой', tracks: [_track('sc:1', name: 'A')]);

    lib.addTracksToPlaylist(pl.id, [
      _track('sc:2', name: 'B'),
      _track('sc:1', name: 'A'),
      _track('sc:3', name: 'C'),
    ]);

    expect(c.read(libraryProvider).playlists.single.trackIds, [
      'sc:2',
      'sc:3',
      'sc:1',
    ]);
  });

  test("an empty playlist name doesn't create a nameless one", () {
    final c = _container(JsonStore.memory());
    final pl = c.read(libraryProvider.notifier).createPlaylist('   ');
    // With no widget tree there's no interface language, `globalL10n` is null,
    // and createPlaylist falls back to English.
    expect(pl.name, 'New playlist');
  });

  test('everything survives a restart', () {
    final store = JsonStore.memory();
    final first = _container(store);
    final lib = first.read(libraryProvider.notifier);
    lib.toggleFav(_track('sc:1', name: 'Любимая'));
    final pl = lib.createPlaylist('Импорт');
    lib.addTrackToPlaylist(pl.id, _track('sc:2', name: 'Вторая'));
    lib.toggleFollow(
      const Artist(
        id: 'sc:artist:9',
        name: 'Nick',
        source: MusicSource.soundcloud,
      ),
    );

    // A new container over the same store means an app restart.
    final second = _container(store);
    final restored = second.read(libraryProvider);

    expect(restored.isFav('sc:1'), isTrue);
    expect(restored.favTracks.single.name, 'Любимая');
    expect(restored.playlists.single.name, 'Импорт');
    expect(restored.tracksOf(restored.playlists.single).single.name, 'Вторая');
    expect(restored.isFollowing('sc:artist:9'), isTrue);
    // sourceData must survive serialization, or the track won't play.
    expect(restored.tracks['sc:2']?.sourceData, isNotNull);
  });
}
