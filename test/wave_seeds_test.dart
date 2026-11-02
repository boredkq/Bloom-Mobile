/// What the wave starts from: what exactly it gets built on.
///
/// I check by list, not by ear: a mistake here is quiet, the wave plays, just
/// the wrong thing and always the same.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:bloom/features/wave/wave_seeds.dart';
import 'package:bloom/features/wave/wave_types.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(
  String id, {
  MusicSource source = MusicSource.soundcloud,
  String artist = 'Artist',
}) => Track(
  id: id,
  name: id,
  artist: artist,
  duration: const Duration(seconds: 100),
  source: source,
);

/// SoundCloud and YouTube Music have a radio; Yandex acts as if not signed in.
WaveSeed? _seedOf(Track t) => t.source == MusicSource.yandex
    ? null
    : WaveSeed(t.source.code, 'track:${t.id.split(':').last}');

WaveSeed _sc(int id) => WaveSeed('sc', 'track:$id');

/// A library of the listed tracks (freshest on top). [plays] are plays, [favs]
/// are likes in order, freshest first.
WaveLibrary _library(
  List<Track> tracks, {
  Map<String, int> plays = const {},
  List<String> favs = const [],
  Set<String> disliked = const {},
  List<Track> extras = const [],
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final events = [
    for (final e in plays.entries)
      for (var i = 0; i < e.value; i++) PlayEvent(now - 1000 + i, e.key),
  ]..sort((a, b) => a.ts.compareTo(b.ts));
  return WaveLibrary(
    lib: LibraryState(
      tracks: {for (final t in tracks) t.id: t},
      libIds: [for (final t in tracks) t.id],
      inLib: {for (var i = 0; i < tracks.length; i++) tracks[i].id: now - i},
      favIds: favs,
      favs: {for (var i = 0; i < favs.length; i++) favs[i]: now - i},
    ),
    disliked: disliked,
    seedOf: _seedOf,
    stats: PlayStats.build(PlayLog(events: events)),
    extras: extras,
  );
}

void main() {
  group('queueSeeds', () {
    test('a short queue goes into seeds whole', () {
      final tracks = [for (var i = 0; i < 5; i++) _track('sc:$i')];
      expect(queueSeeds(tracks, _library(tracks)), [
        for (var i = 0; i < 5; i++) _sc(i),
      ]);
    });

    test('a long one gives ten evenly by position', () {
      final tracks = [for (var i = 0; i < 20; i++) _track('sc:$i')];
      expect(queueSeeds(tracks, _library(tracks)), [
        for (var i = 0; i < 20; i += 2) _sc(i),
      ]);
    });

    test(
      'mixed platforms: each has its radio; no radio and dislikes drop out before positions are computed',
      () {
        final tracks = [
          _track('sc:1'),
          _track('ym:2', source: MusicSource.yandex),
          _track('ytm:abc', source: MusicSource.ytmusic),
          _track('sc:4'),
        ];
        expect(queueSeeds(tracks, _library(tracks, disliked: {'sc:4'})), [
          _sc(1),
          const WaveSeed('ytm', 'track:abc'),
        ]);
      },
    );

    test('one radio, one seed', () {
      final tracks = [_track('sc:1'), _track('sc:2'), _track('sc:1')];
      expect(queueSeeds(tracks, _library(tracks)), [_sc(1), _sc(2)]);
    });

    test('not enough seeds: empty', () {
      final ym = [_track('ym:1', source: MusicSource.yandex)];
      expect(queueSeeds(ym, _library(ym)), isEmpty);
      expect(queueSeeds(const [], _library(const [])), isEmpty);
    });
  });

  group('personalSeeds', () {
    test('the two most played, two fresh likes and one more', () {
      final tracks = [for (var i = 0; i < 12; i++) _track('sc:$i')];
      final view = _library(
        tracks,
        plays: {'sc:0': 10, 'sc:1': 8, 'sc:2': 5},
        favs: ['sc:7', 'sc:8'],
      );
      expect(personalSeeds(view, 'sc', 0), [
        _sc(0),
        _sc(1),
        _sc(7),
        _sc(8),
        _sc(2),
      ]);
    });

    test(
      'the next from the top is already taken: the next like goes fifth',
      () {
        final tracks = [for (var i = 0; i < 6; i++) _track('sc:$i')];
        final view = _library(
          tracks,
          // Only two tracks in the top: the "next" one around the circle is the
          // first again.
          plays: {'sc:0': 10, 'sc:1': 8},
          favs: ['sc:3', 'sc:4', 'sc:5'],
        );
        expect(personalSeeds(view, 'sc', 0), [
          _sc(0),
          _sc(1),
          _sc(3),
          _sc(4),
          _sc(5),
        ]);
      },
    );

    test('only tracks of the chosen platform', () {
      final tracks = [
        _track('ytm:a', source: MusicSource.ytmusic),
        _track('sc:1'),
        _track('ytm:b', source: MusicSource.ytmusic),
      ];
      final view = _library(tracks, plays: {'sc:1': 9, 'ytm:a': 2});
      expect(personalSeeds(view, 'ytm', 0), [const WaveSeed('ytm', 'track:a')]);
      expect(personalSeeds(view, 'sc', 0), [_sc(1)]);
    });

    test("the shift: a second wave doesn't start the same", () {
      final tracks = [for (var i = 0; i < 8; i++) _track('sc:$i')];
      final view = _library(
        tracks,
        plays: {'sc:0': 10, 'sc:1': 8, 'sc:2': 6, 'sc:3': 4},
      );
      expect(personalSeeds(view, 'sc', 1), [_sc(2), _sc(3), _sc(0)]);
    });

    test('nothing heard or liked: the three freshest', () {
      final tracks = [for (var i = 0; i < 4; i++) _track('sc:$i')];
      expect(personalSeeds(_library(tracks), 'sc', 0), [
        _sc(0),
        _sc(1),
        _sc(2),
      ]);
    });

    test('empty and disliked: no seeds', () {
      expect(personalSeeds(_library(const []), 'sc', 0), isEmpty);
      final tracks = [_track('sc:1'), _track('sc:2')];
      final view = _library(
        tracks,
        plays: {'sc:1': 10, 'sc:2': 5},
        disliked: {'sc:1'},
      );
      expect(personalSeeds(view, 'sc', 0), isNot(contains(_sc(1))));
    });
  });
}
