/// The player session in the database: `session_tracks` rows, kv `session`, the
/// queue source as a map.
library;

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/player/play_source.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/session_store.dart';
import 'package:bloom/features/wave/wave_types.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db.dart';

Track _track(String id) => Track(
  id: 'sc:$id',
  name: id,
  artist: 'A',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

/// Two launches on one database: the second container reads what the first
/// wrote.
(ProviderContainer Function(), BloomDb) _app() {
  final store = JsonStore.memory();
  final db = testDb(store);
  ProviderContainer open() {
    final c = ProviderContainer(
      overrides: [
        jsonStoreProvider.overrideWithValue(store),
        dbProvider.overrideWithValue(db),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  return (open, db);
}

void _save(
  ProviderContainer c,
  List<Track> queue, {
  int index = 0,
  Duration position = Duration.zero,
  PlaySource? source,
  List<Track>? orig,
  List<Track>? full,
  bool shuffle = false,
  PlayerRepeat repeat = PlayerRepeat.off,
  bool ended = false,
}) {
  final s = c.read(sessionProvider.notifier);
  s.saveQueue(queue, orig, full);
  s.saveState(
    index: index,
    position: position,
    source: source,
    shuffle: shuffle,
    repeat: repeat,
    ended: ended,
    playing: false,
  );
}

void main() {
  test('the queue, the order before shuffle and modes survive a restart', () {
    final (open, _) = _app();
    final queue = [_track('c'), _track('a'), _track('b')];
    _save(
      open(),
      queue,
      index: 2,
      position: const Duration(milliseconds: 90440),
      orig: [_track('a'), _track('b'), _track('c')],
      shuffle: true,
      repeat: PlayerRepeat.one,
      source: const LibSource('fav'),
    );
    final back = open().read(sessionProvider)!;
    expect(back.queue.map((t) => t.id), ['sc:c', 'sc:a', 'sc:b']);
    expect(back.orig.map((t) => t.id), ['sc:a', 'sc:b', 'sc:c']);
    expect(back.track.id, 'sc:b');
    expect(back.position, const Duration(milliseconds: 90400));
    expect(back.shuffle, isTrue);
    expect(back.repeat, PlayerRepeat.one);
    expect(back.source?.id, 'fav');
    expect(back.cleared, isFalse);
  });

  test('kv session format', () {
    final (open, db) = _app();
    _save(
      open(),
      [_track('a')],
      position: const Duration(seconds: 5),
      repeat: PlayerRepeat.all,
      source: const LibSource('all'),
      ended: true,
    );
    final s = db.getMap(kSessionKey);
    expect(s['index'], 0);
    expect(s['id'], 'sc:a');
    expect(s['pos'], 5);
    expect(s['repeat'], 1);
    expect(s['ended'], isTrue);
    expect(s['playing'], isFalse);
    expect(s['source'], {'kind': 'playlist', 'id': 'lib', 'glyph': 'note'});
    expect(
      db
          .select('SELECT list, pos, track_id FROM session_tracks')
          .map((r) => '${r['list']}:${r['pos']}:${r['track_id']}'),
      ['queue:0:sc:a'],
    );
  });

  test('a long queue is written whole', () {
    final (open, _) = _app();
    _save(open(), [for (var i = 0; i < 500; i++) _track('t$i')], index: 400);
    final back = open().read(sessionProvider)!;
    expect(back.queue.length, 500);
    expect(back.track.id, 'sc:t400');
  });

  test(
    "a track is found by id; if gone its place stays, the position doesn't",
    () {
      final (open, db) = _app();
      _save(
        open(),
        [_track('a'), _track('b')],
        index: 1,
        position: const Duration(seconds: 30),
      );
      db.set(kSessionKey, {...db.getMap(kSessionKey), 'index': 0});
      expect(open().read(sessionProvider)!.track.id, 'sc:b');

      db.set(kSessionKey, {...db.getMap(kSessionKey), 'id': 'sc:gone'});
      final lost = open().read(sessionProvider)!;
      expect(lost.index, 0);
      expect(lost.position, Duration.zero);
    },
  );

  test('an empty queue leaves the rows alone; clearing marks the session', () {
    final (open, _) = _app();
    final c = open();
    _save(c, [_track('a'), _track('b')], index: 1);
    c.read(sessionProvider.notifier).saveQueue(const [], null, null);
    c.read(sessionProvider.notifier).markCleared();
    final back = open().read(sessionProvider)!;
    expect(back.cleared, isTrue);
    expect(back.queue.map((t) => t.id), ['sc:a', 'sc:b']);
  });

  test(
    'Continue brings the queue back to before the clear, on the same track',
    () {
      final (open, _) = _app();
      _save(
        open(),
        [_track('b')],
        position: const Duration(seconds: 30),
        full: [_track('a'), _track('b'), _track('c')],
        repeat: PlayerRepeat.all,
      );
      final data = open().read(sessionProvider)!;
      final cont = data.forContinue();
      expect(cont.queue.length, 3);
      expect(cont.track.id, 'sc:b');
      expect(cont.position, const Duration(seconds: 30));
      expect(cont.repeat, PlayerRepeat.all);
      expect(cont.full, isEmpty);

      final (open2, _) = _app();
      _save(open2(), [_track('a'), _track('b')], index: 1);
      final plain = open2().read(sessionProvider)!;
      expect(identical(plain.forContinue(), plain), isTrue);
    },
  );

  test('an own playlist is named in the map from its card', () {
    final (open, db) = _app();
    final c = open();
    final pl = c
        .read(libraryProvider.notifier)
        .createPlaylist('Вечер', tracks: [_track('a')]);
    _save(c, [_track('a')], source: LibSource(pl.id));
    final src = db.getMap(kSessionKey)['source'] as Map;
    expect(src['kind'], 'playlist');
    expect(src['id'], pl.id);
    expect(src['name'], 'Вечер');
  });

  group('the source is a map', () {
    PlaySource? back(PlaySource s) => PlaySource.fromJson(s.toJson());

    test('own kinds survive writing', () {
      expect((back(const LibSource('all')) as LibSource).listId, 'all');
      expect((back(const LibSource('history')) as LibSource).listId, 'history');
      final set =
          back(
                const SetSource(
                  Playlist(
                    id: 'sc:set:7',
                    title: 'Сет',
                    cover: 'c',
                    source: MusicSource.soundcloud,
                    isAlbum: true,
                  ),
                ),
              )
              as SetSource;
      expect(set.set.title, 'Сет');
      expect(set.set.isAlbum, isTrue);
      final artist =
          back(
                const ArtistSource(
                  Artist(
                    id: 'sc:artist:1',
                    name: 'X',
                    source: MusicSource.soundcloud,
                  ),
                ),
              )
              as ArtistSource;
      expect(artist.artist.name, 'X');
      final wave =
          back(const WaveSource(label: 'Волна', mode: WaveMode.artist))
              as WaveSource;
      expect(wave.mode, WaveMode.artist);
      expect(wave.label, 'Волна');
      final single = back(PlainSource.single(_track('a'))) as PlainSource;
      expect(single.kind, 'track');
      expect(single.label, 'a');
    });

    test('maps written by the computer are read', () {
      expect(
        (PlaySource.fromJson({'kind': 'playlist', 'id': 'lib'}) as LibSource)
            .listId,
        'all',
      );
      final album =
          PlaySource.fromJson({
                'kind': 'collection',
                'id': 'ym:album:5',
                'name': 'Альбом',
                'cover': '',
              })
              as SetSource;
      expect(album.set.isAlbum, isTrue);
      expect(album.set.cover, isNull);
      final search =
          PlaySource.fromJson({'kind': 'search', 'name': 'daft punk'})
              as PlainSource;
      expect(search.icon, PlainSourceIcon.search);
      expect(search.label, 'daft punk');
      final forYou =
          PlaySource.fromJson({'kind': 'forYou', 'name': 'Для вас'})
              as PlainSource;
      expect(forYou.icon, PlainSourceIcon.note);
      expect(PlaySource.fromJson({'kind': 'history'}), isA<LibSource>());
      expect(PlaySource.fromJson(<String, dynamic>{}), isNull);
    });
  });
}
