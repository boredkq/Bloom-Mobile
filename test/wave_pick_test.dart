/// Picking the wave's batch (`pickBatch`): what decides which tracks get heard
/// and in what order.
library;

import 'dart:math';

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/features/wave/wave_engine.dart';
import 'package:bloom/features/wave/wave_types.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(
  String id, {
  String artist = 'Artist',
  String? name,
  int seconds = 100,
  MusicSource source = MusicSource.soundcloud,
}) => Track(
  id: id,
  name: name ?? 'Song $id',
  artist: artist,
  duration: Duration(seconds: seconds),
  source: source,
);

WaveRun _run({
  WaveMode mode = WaveMode.track,
  bool native = false,
  List<String>? played,
  Map<String, int>? bonus,
}) => WaveRun(
  mode: mode,
  seeds: const [WaveSeed('sc', 'track:1')],
  native: native,
  played: played,
  bonus: bonus,
);

WavePick _ctx({
  WaveRun? run,
  List<Track> queue = const [],
  String? currentId,
  List<Track> library = const [],
  Set<String> favs = const {},
  Set<String> disliked = const {},
  Set<String> recent = const {},
  Set<String> shown = const {},
}) {
  final inLib = {for (final t in library) t.id};
  return WavePick(
    run: run ?? _run(),
    queue: queue,
    currentId: currentId,
    library: library,
    inLibrary: inLib.contains,
    isFav: favs.contains,
    isDisliked: disliked.contains,
    playedWithin: (id, _) => recent.contains(id),
    shown: shown,
    // A seed quiets the random bonus: I compare contributions, not luck.
    random: Random(1),
  );
}

List<String> _ids(List<Track> l) => [for (final t in l) t.id];

/// Different artists, so the cap and "not in a row" don't get in the way of the
/// other checks.
List<Track> _page(int n, {int from = 0}) => [
  for (var i = from; i < from + n; i++) _t('sc:$i', artist: 'A$i'),
];

void main() {
  group('что отсеивается', () {
    test('играющий, стоящий в очереди и уже услышанный в волне', () {
      final out = pickBatch(
        [_page(4)],
        _ctx(
          run: _run(played: ['sc:3']),
          currentId: 'sc:0',
          queue: [_t('sc:1', artist: 'A1')],
        ),
      );
      expect(_ids(out), ['sc:2']);
    });

    test('дизлайк — про сам трек, соседей того же артиста не трогает', () {
      final out = pickBatch([
        [
          _t('sc:1', artist: 'A'),
          _t('sc:2', artist: 'B'),
          _t('sc:3', artist: 'A'),
        ],
      ], _ctx(disliked: {'sc:1'}));
      expect(_ids(out), containsAll(['sc:2', 'sc:3']));
      expect(_ids(out), isNot(contains('sc:1')));
    });

    test('находка, которая уже в библиотеке, находкой не считается', () {
      final out = pickBatch([
        _page(3),
      ], _ctx(library: [_t('sc:1', artist: 'A1')]));
      expect(_ids(out), isNot(contains('sc:1')));
    });

    test('слушанное за неделю и показанное за две не повторяем', () {
      final out = pickBatch([
        _page(4),
      ], _ctx(recent: {'sc:0'}, shown: {'sc:1'}));
      expect(_ids(out)..sort(), ['sc:2', 'sc:3']);
    });

    test('отсеялось всё — лучше повтор, чем тишина, но не дизлайк', () {
      final out = pickBatch([
        _page(3),
      ], _ctx(recent: {'sc:0'}, shown: {'sc:1'}, disliked: {'sc:2'}));
      expect(_ids(out)..sort(), ['sc:0', 'sc:1']);
    });
  });

  group('порядок', () {
    test('верх станции идёт выше хвоста', () {
      final out = pickBatch([_page(10)], _ctx());
      expect(out.first.id, 'sc:0');
      expect(out.last.id, 'sc:9');
    });

    test('лайк поднимает', () {
      // Without a like the sixth (sc:5) stays sixth; +8 is four places.
      final out = pickBatch([_page(10)], _ctx(favs: {'sc:5'}));
      expect(_ids(out).indexOf('sc:5'), lessThan(3));
    });

    test('артист, которого дослушивали в этой волне, поднимается', () {
      // Ranks 0/5/10/15: the last, with +12, passes the second and third.
      final out = pickBatch([_page(4)], _ctx(run: _run(bonus: {'a3': 12})));
      expect(_ids(out).indexOf('sc:3'), 1);
    });

    test('бонус артиста не больше 12, а пролистанный уходит вниз', () {
      // Without a cap 100 points would pull the last one to first place.
      final up = pickBatch([_page(10)], _ctx(run: _run(bonus: {'a9': 100})));
      expect(_ids(up).indexOf('sc:9'), greaterThan(2));
      final down = pickBatch([_page(4)], _ctx(run: _run(bonus: {'a0': -12})));
      expect(down.first.id, isNot('sc:0'));
    });

    test('бонус считается по каждому имени трека', () {
      final page = [
        _t('sc:0', artist: 'X0'),
        _t('sc:9', artist: 'Other feat. Liked'),
      ];
      final out = pickBatch([page], _ctx(run: _run(bonus: {'liked': 12})));
      expect(out.first.id, 'sc:9');
    });
  });

  group('артисты в пачке', () {
    test('больше двух треков артиста — только в хвост короткой пачки', () {
      final page = [
        for (var i = 0; i < 4; i++) _t('sc:$i', artist: 'Same'),
        for (var i = 10; i < 14; i++) _t('sc:$i', artist: 'B$i'),
      ];
      final out = pickBatch([page], _ctx(), take: 6);
      expect(out.where((t) => t.artist == 'Same').length, 2);
      // If the batch runs short of tracks, it takes them past the cap too.
      final all = pickBatch([page], _ctx());
      expect(all.length, 8);
    });

    test('потолок — по каждому имени: «A feat. B» занимает место и A, и B', () {
      final page = [
        _t('sc:1', artist: 'A'),
        _t('sc:2', artist: 'C'),
        _t('sc:3', artist: 'A feat. B'),
        _t('sc:4', artist: 'D'),
        _t('sc:5', artist: 'B, A'),
        _t('sc:6', artist: 'E'),
      ];
      final out = pickBatch([page], _ctx(), take: 5);
      // A's third track didn't get in, though its line is its own.
      expect(_ids(out), isNot(contains('sc:5')));
    });

    test('один артист дважды подряд не стоит, даже среди соавторов', () {
      final page = [
        _t('sc:1', artist: 'A'),
        _t('sc:2', artist: 'A & B'),
        _t('sc:3', artist: 'C'),
        _t('sc:4', artist: 'D'),
      ];
      final out = pickBatch([page], _ctx());
      for (var i = 1; i < out.length; i++) {
        final a = out[i - 1].artist.contains('A');
        final b = out[i].artist.contains('A');
        expect(a && b, isFalse, reason: _ids(out).join(','));
      }
    });
  });

  group('«Моя волна»', () {
    test('свой трек — через каждые четыре новых', () {
      final lib = [for (var i = 100; i < 110; i++) _t('sc:$i', artist: 'L$i')];
      final out = pickBatch(
        [_page(16)],
        _ctx(
          run: _run(mode: WaveMode.personal),
          library: lib,
        ),
      );
      final own = {for (final t in lib) t.id};
      expect(own.contains(out[4].id), isTrue);
      expect(own.contains(out[9].id), isTrue);
      expect(out.take(4).any((t) => own.contains(t.id)), isFalse);
    });

    test('свои, слышанные на днях или с дизлайком, не подмешиваются', () {
      final lib = [
        _t('sc:100', artist: 'L0'),
        _t('sc:101', artist: 'L1'),
        _t('sc:102', artist: 'L2'),
      ];
      final out = pickBatch(
        [_page(8)],
        _ctx(
          run: _run(mode: WaveMode.personal),
          library: lib,
          recent: {'sc:100'},
          disliked: {'sc:101'},
        ),
      );
      expect(_ids(out), contains('sc:102'));
      expect(_ids(out), isNot(contains('sc:100')));
      expect(_ids(out), isNot(contains('sc:101')));
    });

    test('в других волнах своих треков нет', () {
      final out = pickBatch([
        _page(8),
      ], _ctx(library: [_t('sc:100', artist: 'L')]));
      expect(_ids(out), isNot(contains('sc:100')));
    });
  });

  test('станция Яндекса: свой порядок, уходит только очередь и дизлайки', () {
    final page = [
      _t('ym:1', artist: 'A', source: MusicSource.yandex),
      _t('ym:2', artist: 'A', source: MusicSource.yandex),
      _t('ym:3', artist: 'A', source: MusicSource.yandex),
      _t('ym:4', artist: 'B', source: MusicSource.yandex),
      _t('ym:5', artist: 'C', source: MusicSource.yandex),
    ];
    final out = pickBatch(
      [page],
      _ctx(
        run: _run(native: true),
        queue: [page[4]],
        disliked: {'ym:2'},
        // The station handles what's heard and own by itself.
        recent: {'ym:3'},
        library: [page[0]],
      ),
    );
    expect(_ids(out), ['ym:1', 'ym:3', 'ym:4']);
  });

  group('перезаливы', () {
    test('внутри пачки выпадает, остаётся тот, что выше', () {
      final out = pickBatch([
        [
          _t('sc:1', name: 'целоваться', artist: 'lightprey', seconds: 200),
          _t('sc:2', name: 'Другая песня', artist: 'Кто-то', seconds: 200),
          // The same track: the author moved to the title, the uploader is
          // someone else.
          _t(
            'sc:3',
            name: 'lightprey - целоваться',
            artist: 'クリソライト',
            seconds: 200,
          ),
        ],
      ], _ctx());
      expect(_ids(out), ['sc:1', 'sc:2']);
    });

    test('уже стоящий в очереди выпадает и под другим id', () {
      final out = pickBatch(
        [
          [
            _t(
              'sc:11',
              name: 'Artist - Ночь',
              artist: 'reupload',
              seconds: 200,
            ),
            _t('sc:12', name: 'День', artist: 'Artist', seconds: 240),
          ],
        ],
        _ctx(
          queue: [_t('sc:10', name: 'Ночь', artist: 'Artist', seconds: 200)],
        ),
      );
      expect(_ids(out), ['sc:12']);
    });
  });

  group('completionStep', () {
    const total = Duration(minutes: 3);

    test('ушёл в первые секунды — пролистнул', () {
      expect(completionStep(const Duration(seconds: 5), total), -2);
    });

    test('дослушал — понравилось', () {
      expect(completionStep(const Duration(seconds: 170), total), 3);
    });

    test('половина, минута длинного микса, нет длительности — сигнала нет', () {
      expect(completionStep(const Duration(seconds: 90), total), 0);
      expect(
        completionStep(
          const Duration(seconds: 60),
          const Duration(minutes: 30),
        ),
        0,
      );
      expect(completionStep(const Duration(seconds: 30), Duration.zero), 0);
    });
  });

  group('spreadSeeds', () {
    test('до восьми — все, длинный список — десять поровну', () {
      expect(spreadSeeds([1, 2, 3]), [1, 2, 3]);
      final twenty = [for (var i = 0; i < 20; i++) i];
      expect(spreadSeeds(twenty), [for (var i = 0; i < 20; i += 2) i]);
      expect(spreadSeeds([for (var i = 0; i < 12; i++) i]).length, 8);
    });
  });

  test('сеанс сохраняется видом ПК и читается обратно', () {
    final run = WaveRun(
      mode: WaveMode.artist,
      seeds: const [WaveSeed('ytm', 'track:abc')],
      about: 'artist:x',
      played: ['ytm:abc'],
      bonus: {'x': 3},
    );
    final json = run.toJson();
    expect(json['seeds'], [
      {'p': 'ytm', 's': 'track:abc'},
    ]);
    final back = WaveRun.fromJson(json)!;
    expect(back.mode, WaveMode.artist);
    expect(back.seeds.single, const WaveSeed('ytm', 'track:abc'));
    expect(back.about, 'artist:x');
    expect(back.played, ['ytm:abc']);
    expect(back.bonus, {'x': 3});
    // With no seeds the wave has nothing to continue from.
    expect(WaveRun.fromJson({'mode': 'track', 'seeds': []}), isNull);
  });
}
