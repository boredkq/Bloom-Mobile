/// The home shelves "For you" and "Similar to": seeds from the journal, picking
/// the unfamiliar, dropping reuploads, mixing tracks and artists. Platforms are
/// fake, no network.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/play_log.dart';
import 'package:bloom/core/store/play_stats.dart';
import 'package:bloom/features/home/for_you.dart';
import 'package:bloom/features/home/similar_to.dart';
import 'package:bloom/features/wave/wave_seeds.dart';
import 'package:bloom/shared/util/taste.dart';
import 'package:bloom/shared/util/track_dedup.dart';
import 'package:flutter_test/flutter_test.dart';

const int _day = 24 * 3600 * 1000;

Track _t(
  String id, {
  String? name,
  String? artist,
  int seconds = 180,
  String? artistId,
}) => Track(
  id: id,
  name: name ?? id,
  artist: artist ?? 'Artist $id',
  duration: Duration(seconds: seconds),
  source: MusicSource.fromId(id),
  artistId: artistId,
);

/// A platform that answers with similar tracks from a dictionary; all its
/// tracks have a radio.
class _Fake extends MusicProvider {
  _Fake({
    this.source = MusicSource.soundcloud,
    this.similar = const {},
    this.pages = const {},
  });

  @override
  final MusicSource source;
  final Map<String, List<Track>> similar;
  final Map<String, ArtistPageData> pages;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<List<Track>?> getSimilarTracks(String seedId) async =>
      similar[seedId] ?? const [];

  @override
  String trackStation(Track track) =>
      track.source == source ? 'track:${track.id}' : '';

  @override
  Future<ArtistPageData?> getArtist(String id) async => pages[id];
}

/// The shelves' input: [plays] is id to play count (within [daysAgo]), [heard]
/// is heard but not saved. A played track that's in neither [tracks] nor
/// [heard] gets its own snapshot, each with its own artist.
RecsInput _input({
  required List<_Fake> providers,
  Map<String, int> plays = const {},
  Map<String, int> daysAgo = const {},
  List<Track> tracks = const [],
  List<Track> heard = const [],
  Set<String> favs = const {},
  Set<String> disliked = const {},
  DateTime? now,
}) {
  final at = (now ?? DateTime(2026, 9, 13)).millisecondsSinceEpoch;
  final events = <PlayEvent>[
    for (final e in plays.entries)
      for (var i = 0; i < e.value; i++)
        PlayEvent(at - (daysAgo[e.key] ?? 1) * _day + i, e.key),
  ]..sort((a, b) => a.ts.compareTo(b.ts));
  final snapshots = {
    for (final id in plays.keys) id: _t(id),
    for (final t in [...tracks, ...heard]) t.id: t,
  };
  final registry = ProviderRegistry();
  for (final p in providers) {
    registry.register(p);
  }
  return RecsInput(
    registry: registry,
    stats: PlayStats.build(PlayLog(events: events, tracks: snapshots)),
    lib: LibraryState(
      tracks: {for (final t in tracks) t.id: t},
      // The last in [favs] is the freshest like and goes on top.
      libIds: [
        for (final t in tracks.reversed)
          if (favs.contains(t.id)) t.id,
      ],
      inLib: {
        for (final (i, t) in tracks.indexed)
          if (favs.contains(t.id)) t.id: i,
      },
      favIds: favs.toList().reversed.toList(),
      favs: {for (final (i, id) in favs.indexed) id: i},
    ),
    disliked: disliked,
    now: now ?? DateTime(2026, 9, 13),
  );
}

List<String> _ids(SimilarTo res) => [
  for (final it in res.items)
    switch (it) {
      SimilarTrackItem(:final track) => track.id,
      SimilarArtistItem(:final artist) => artist.id,
    },
];

void main() {
  group('реаплоады', () {
    test('имя автора, переехавшее в заголовок, не делает трек другим', () {
      final a = TrackFingerprint(name: 'целоваться', artist: 'lightprey');
      final b = TrackFingerprint(
        name: 'lightprey - целоваться',
        artist: 'クリソライト',
      );
      expect(sameTrack(a, b), isTrue);
    });

    test('разные треки одного артиста — не дубли', () {
      final a = TrackFingerprint(name: 'Ночь', artist: 'Artist', seconds: 200);
      final b = TrackFingerprint(name: 'День', artist: 'Artist', seconds: 202);
      expect(sameTrack(a, b), isFalse);
    });

    test('короткое общее название сверяется по длительности', () {
      TrackFingerprint fp(String artist, int sec) =>
          TrackFingerprint(name: 'sleep mode', artist: artist, seconds: sec);
      expect(sameTrack(fp('a', 180), fp('b', 195)), isTrue);
      expect(sameTrack(fp('a', 180), fp('b', 300)), isFalse);
    });

    test('накопитель пропускает повтор, а новое принимает', () {
      final guard = DupGuard()
        ..add(_t('sc:1', name: 'целоваться', artist: 'Artist'));
      expect(
        guard.accept(_t('sc:2', name: 'Artist - целоваться', artist: 'x')),
        isFalse,
      );
      expect(guard.accept(_t('sc:3', name: 'другое')), isTrue);
    });

    test('снимок из журнала ловит перезалив, как и трек', () {
      final guard = DupGuard()
        ..addPrint(TrackFingerprint(name: 'Ночь', artist: 'X', seconds: 200));
      expect(
        guard.accept(_t('sc:1', name: 'X - Ночь', artist: 'up', seconds: 203)),
        isFalse,
      );
      // There's a shared word, but it's another track (the duration is far
      // outside the tolerance), and the index mustn't mix them up.
      expect(
        guard.accept(_t('sc:2', name: 'Ночь', artist: 'Y', seconds: 260)),
        isTrue,
      );
    });
  });

  group('«Для вас»: сиды', () {
    test('самое слушаемое за окно — с площадок, где есть радио', () {
      final input = _input(
        // No Yandex (not signed in), and own files have nobody to ask.
        providers: [
          _Fake(),
          _Fake(source: MusicSource.ytmusic),
        ],
        plays: {'sc:1': 5, 'ym:2': 4, 'sc:3': 3, 'ytm:4': 9, 'lf:5': 9},
      );
      expect(pickForYouSeeds(input), ['ytm:4', 'sc:1', 'sc:3']);
    });

    test('сначала по одному на артиста, потом добор', () {
      final input = _input(
        providers: [_Fake()],
        plays: {'sc:1': 5, 'sc:2': 4, 'sc:3': 3},
        heard: [
          _t('sc:1', artist: 'A'),
          _t('sc:2', artist: 'A feat. B'),
          _t('sc:3', artist: 'C'),
        ],
      );
      expect(pickForYouSeeds(input), ['sc:1', 'sc:3', 'sc:2']);
    });

    test('за окном мало — считаем за всё время', () {
      final input = _input(
        providers: [_Fake()],
        plays: {'sc:old': 6, 'sc:new': 2},
        daysAgo: {'sc:old': 200},
      );
      // Only one track in 90 days, fewer than three, so I take all time.
      expect(pickForYouSeeds(input), ['sc:old', 'sc:new']);
    });

    test('дизлайкнутое сидом не становится, лайки добивают', () {
      final input = _input(
        providers: [_Fake()],
        plays: {'sc:1': 5, 'sc:2': 4},
        tracks: [_t('sc:9')],
        favs: {'sc:9'},
        disliked: {'sc:1'},
      );
      expect(pickForYouSeeds(input), ['sc:2', 'sc:9']);
    });
  });

  group('«Для вас»: полоса', () {
    test(
      'по кругу, без знакомого, не больше двух от артиста, без дублей',
      () async {
        final provider = _Fake(
          similar: {
            'sc:1': [
              _t('sc:10', artist: 'A'),
              _t('sc:11', artist: 'A'),
              _t('sc:12', artist: 'A'),
              _t('sc:2'), // already heard
            ],
            'sc:2': [
              _t('sc:20', name: 'Песня', artist: 'B'),
              _t('sc:21', name: 'B - Песня', artist: 'uploader'), // reupload
              _t('sc:22', artist: 'C'),
            ],
          },
        );
        final input = _input(
          providers: [provider],
          plays: {'sc:1': 3, 'sc:2': 2},
        );
        final out = await buildForYou(input);

        expect(out.map((t) => t.id), ['sc:10', 'sc:20', 'sc:11', 'sc:22']);
      },
    );

    test('потолок артиста — по каждому имени трека', () async {
      final provider = _Fake(
        similar: {
          'sc:1': [
            _t('sc:10', artist: 'A'),
            _t('sc:11', artist: 'B feat. A'),
            _t('sc:12', artist: 'A & C'),
            _t('sc:13', artist: 'C'),
          ],
        },
      );
      final input = _input(providers: [provider], plays: {'sc:1': 3});
      expect((await buildForYou(input)).map((t) => t.id), [
        'sc:10',
        'sc:11',
        'sc:13',
      ]);
    });

    test('перезалив слышанного, но не сохранённого, не встаёт', () async {
      final provider = _Fake(
        similar: {
          'sc:1': [
            _t('sc:30', name: 'lightprey - целоваться', artist: 'クリソライト'),
            _t('sc:31', name: 'Другое', artist: 'D'),
          ],
        },
      );
      final input = _input(
        providers: [provider],
        // Not a seed (no YouTube Music here), only heard.
        plays: {'sc:1': 3, 'ytm:9': 1},
        heard: [_t('ytm:9', name: 'целоваться', artist: 'lightprey')],
      );
      expect((await buildForYou(input)).map((t) => t.id), ['sc:31']);
    });

    test('площадка без похожих — полосы нет', () async {
      final input = _input(providers: [_Fake()], plays: {'sc:1': 3});
      expect(await buildForYou(input), isEmpty);
    });
  });

  group('«Похожие на»', () {
    test('смесь: артист на каждой третьей, артистов не больше половины', () {
      final tracks = [for (var i = 0; i < 3; i++) _t('sc:$i')];
      final artists = [
        for (var i = 0; i < 5; i++)
          Artist(
            id: 'sc:artist:$i',
            name: 'A$i',
            source: MusicSource.soundcloud,
          ),
      ];
      final kinds = [
        for (final it in mixSimilar(tracks, artists))
          it is SimilarTrackItem ? 'T' : 'A',
      ];
      expect(kinds.join(), 'TATTA');
    });

    DateTime dayWith({required bool even}) {
      var d = DateTime(2026, 9, 13);
      while (recsDayNumber(d).isEven != even) {
        d = d.add(const Duration(days: 1));
      }
      return d;
    }

    test('нечётный день — трек-сид с похожими треками', () async {
      final seed = _t('sc:1', name: 'Сид');
      final provider = _Fake(
        similar: {
          'sc:1': [for (var i = 0; i < 5; i++) _t('sc:1$i', artist: 'X$i')],
        },
      );
      final res = await buildSimilarTo(
        _input(
          providers: [provider],
          plays: {'sc:1': 4},
          tracks: [seed],
          now: dayWith(even: false),
        ),
      );

      expect(res?.seed, isA<SimilarTrackSeed>());
      expect(res!.seed.name, 'Сид');
      expect((res.seed as SimilarTrackSeed).track?.id, 'sc:1');
      expect(res.items.length, 5);
    });

    test(
      'трек-сид: свои артисты не лезут — и аккаунт целиком, и имена',
      () async {
        final seed = _t(
          'sc:1',
          name: 'Сид',
          artist: 'Simon & Garfunkel',
          artistId: 'sc:artist:7',
        );
        final provider = _Fake(
          similar: {
            'sc:1': [
              _t('sc:40', artist: 'Simon'),
              _t('sc:41', artist: 'X feat. Garfunkel'),
              _t('sc:42', artist: 'Simon & Garfunkel'),
              for (var i = 0; i < 4; i++) _t('sc:5$i', artist: 'Y$i'),
            ],
          },
        );
        final res = await buildSimilarTo(
          _input(
            providers: [provider],
            plays: {'sc:1': 4},
            tracks: [seed],
            now: dayWith(even: false),
          ),
        );
        expect(_ids(res!), ['sc:50', 'sc:51', 'sc:52', 'sc:53']);
      },
    );

    test(
      'треков меньше четырёх — витрины нет, сколько бы ни было артистов',
      () async {
        final seed = _t(
          'sc:1',
          name: 'Сид',
          artist: 'Сам',
          artistId: 'sc:artist:7',
        );
        final provider = _Fake(
          similar: {
            'sc:1': [for (var i = 0; i < 3; i++) _t('sc:5$i', artist: 'Y$i')],
          },
          pages: {
            'sc:artist:7': ArtistPageData(
              artist: const Artist(
                id: 'sc:artist:7',
                name: 'Сам',
                source: MusicSource.soundcloud,
              ),
              similarArtists: [
                for (var i = 0; i < 6; i++)
                  Artist(
                    id: 'sc:artist:8$i',
                    name: 'Сосед $i',
                    avatar: 'https://a/$i.jpg',
                    source: MusicSource.soundcloud,
                  ),
              ],
            ),
          },
        );
        final input = _input(
          providers: [provider],
          plays: {'sc:1': 4},
          tracks: [seed],
          now: dayWith(even: false),
        );
        expect(await buildSimilarTo(input), isNull);
      },
    );

    test(
      'жидкий ответ добирается похожими на лучший трек чужого артиста',
      () async {
        final seed = _t('sc:1', name: 'Сид', artist: 'Сам');
        final provider = _Fake(
          similar: {
            'sc:1': [
              _t('sc:2', artist: 'Сам'),
              _t('sc:3', artist: 'Друг'),
              _t('sc:4', artist: 'Ещё'),
            ],
            'sc:3': [for (var i = 0; i < 3; i++) _t('sc:6$i', artist: 'Z$i')],
          },
        );
        final res = await buildSimilarTo(
          _input(
            providers: [provider],
            plays: {'sc:1': 4},
            tracks: [seed],
            now: dayWith(even: false),
          ),
        );
        expect(_ids(res!), ['sc:3', 'sc:4', 'sc:60', 'sc:61', 'sc:62']);
      },
    );

    test('без перезаливов «Для вас» и слышанного', () async {
      final provider = _Fake(
        similar: {
          'sc:1': [
            _t('sc:40', name: 'X - Ночь', artist: 'uploader'),
            _t('sc:41', name: 'lightprey - целоваться', artist: 'クリソライト'),
            for (var i = 0; i < 5; i++) _t('sc:5$i', artist: 'Y$i'),
          ],
        },
      );
      final res = await buildSimilarTo(
        _input(
          providers: [provider],
          plays: {'sc:1': 4, 'ytm:9': 1},
          tracks: [_t('sc:1', name: 'Сид')],
          heard: [_t('ytm:9', name: 'целоваться', artist: 'lightprey')],
          now: dayWith(even: false),
        ),
        forYou: [_t('sc:70', name: 'Ночь', artist: 'X')],
      );

      final ids = _ids(res!);
      expect(ids, isNot(contains('sc:40')));
      expect(ids, isNot(contains('sc:41')));
      expect(ids, contains('sc:50'));
    });

    test('мало своих — держимся только от первых карточек «Для вас»', () async {
      final forYou = [for (var i = 0; i < 8; i++) _t('sc:8$i', artist: 'F$i')];
      final provider = _Fake(
        similar: {
          'sc:1': [
            forYou[6],
            forYou[7],
            forYou[0],
            for (var i = 0; i < 2; i++) _t('sc:5$i', artist: 'Y$i'),
          ],
        },
      );
      final res = await buildSimilarTo(
        _input(
          providers: [provider],
          plays: {'sc:1': 4},
          tracks: [_t('sc:1', name: 'Сид')],
          now: dayWith(even: false),
        ),
        forYou: forYou,
      );
      expect(_ids(res!), ['sc:86', 'sc:87', 'sc:50', 'sc:51']);
    });

    test('чётный день — артист-сид, его собственные треки не лезут', () async {
      final mine = _t('sc:1', artist: 'Хозяин', artistId: 'sc:artist:7');
      final provider = _Fake(
        similar: {
          'sc:1': [
            _t('sc:50', artist: 'Хозяин'),
            for (var i = 0; i < 4; i++) _t('sc:6$i', artist: 'Y$i'),
          ],
        },
        pages: {
          'sc:artist:7': ArtistPageData(
            artist: const Artist(
              id: 'sc:artist:7',
              name: 'Хозяин',
              avatar: 'https://a/ava.jpg',
              source: MusicSource.soundcloud,
            ),
            similarArtists: [
              for (var i = 0; i < 2; i++)
                Artist(
                  id: 'sc:artist:8$i',
                  name: 'Сосед $i',
                  avatar: 'https://a/$i.jpg',
                  source: MusicSource.soundcloud,
                ),
            ],
          ),
        },
      );
      final res = await buildSimilarTo(
        _input(
          providers: [provider],
          plays: {'sc:1': 4},
          tracks: [mine],
          now: dayWith(even: true),
        ),
      );

      expect(res?.seed, isA<SimilarArtistSeed>());
      expect(res!.seed.cover, 'https://a/ava.jpg');
      final ids = _ids(res);
      expect(ids, isNot(contains('sc:50')));
      expect(ids, containsAll(['sc:60', 'sc:artist:80']));
    });

    test('сид и элементы переживают кэш', () {
      const artist = Artist(
        id: 'sc:artist:1',
        name: 'A',
        avatar: 'https://a',
        source: MusicSource.soundcloud,
      );
      final seed = SimilarTrackSeed(
        id: 'sc:1',
        name: 'Сид',
        artist: 'A',
        track: _t('sc:1', name: 'Сид'),
      );
      final back = SimilarSeed.fromJson(seed.toJson());
      expect(back, isA<SimilarTrackSeed>());
      expect((back as SimilarTrackSeed).track?.name, 'Сид');

      final item = SimilarItem.fromJson(
        const SimilarArtistItem(artist).toJson(),
      );
      expect((item as SimilarArtistItem).artist.avatar, 'https://a');
    });
  });

  group('волны для ряда «Моей волны»', () {
    test('артист и трек по очереди, треки не тех же артистов', () {
      final input = _input(
        providers: [_Fake()],
        plays: {'sc:a1': 9, 'sc:a2': 8, 'sc:b1': 7, 'sc:c1': 2},
        tracks: [
          _t('sc:a1', artist: 'A'),
          _t('sc:a2', artist: 'A'),
          _t('sc:b1', artist: 'B'),
          _t('sc:c1', artist: 'C'),
          _t('sc:d1', artist: 'D'),
        ],
        favs: {'sc:d1'},
      );
      final picks = wavePicks(input, each: 2);

      expect(
        [for (final p in picks) p.kind],
        [
          WaveOptionKind.artist,
          WaveOptionKind.track,
          WaveOptionKind.artist,
          WaveOptionKind.track,
        ],
      );
      expect(picks[0].name, 'A');
      expect(picks[2].name, 'B');
      // The fresh like first, then the top past A's and B's own tracks.
      expect(picks[1].track!.id, 'sc:d1');
      expect(picks[3].track!.id, 'sc:c1');
      expect(picks[1].about, 'track:sc:d1');
      expect(picks[0].about, 'artist:a');
    });

    test('дизлайкнутое и то, о чём не спросить, в ряд не идёт', () {
      final input = _input(
        providers: [_Fake()],
        tracks: [
          _t('sc:1', artist: 'X'),
          _t('ym:2', artist: 'Y'),
        ],
        favs: {'sc:1', 'ym:2'},
        disliked: {'sc:1'},
      );
      expect(wavePicks(input), isEmpty);
    });
  });
}
