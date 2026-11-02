/// Finding duplicates: grouping repeats and choosing which one to keep.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/features/library/dups.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(
  String id, {
  String name = 'Song',
  String artist = 'Artist',
  String? cover,
}) => Track(
  id: id,
  name: name,
  artist: artist,
  duration: const Duration(seconds: 200),
  source: MusicSource.soundcloud,
  cover: cover,
);

void main() {
  group('группировка', () {
    test('регистр и лишние пробелы не делают трек другим', () {
      final groups = dupGroups([
        _track('a', name: 'Song'),
        _track('b', name: '  SONG  '),
      ]);

      expect(groups.length, 1);
      expect(groups.single.length, 2);
    });

    test('разные артисты — разные треки', () {
      final groups = dupGroups([
        _track('a', artist: 'Один'),
        _track('b', artist: 'Другой'),
      ]);

      expect(groups, isEmpty);
    });

    test('одиночки в группы не попадают', () {
      final groups = dupGroups([
        _track('a', name: 'Первая'),
        _track('b', name: 'Вторая'),
        _track('c', name: 'Вторая'),
      ]);

      expect(groups.length, 1);
      expect(groups.single.map((t) => t.id), containsAll(['b', 'c']));
    });
  });

  group('кого оставить', () {
    test('копия с обложкой обходит копию без неё', () {
      final groups = dupGroups([
        _track('нет обложки'),
        _track('с обложкой', cover: 'cover.jpg'),
      ]);

      expect(groups.single.first.id, 'с обложкой');
    });

    test('при равных обложках выигрывает тот, кого чаще слушали сами', () {
      const plays = {'редкий': 2, 'частый': 40};
      final groups = dupGroups([
        _track('редкий', cover: 'a.jpg'),
        _track('частый', cover: 'b.jpg'),
      ], plays: (id) => plays[id] ?? 0);

      expect(groups.single.first.id, 'частый');
    });

    test('иначе остаётся добавленный раньше', () {
      final groups = dupGroups(
        [_track('поздний'), _track('ранний')],
        addedAt: {'поздний': 200, 'ранний': 100},
      );

      expect(groups.single.first.id, 'ранний');
    });
  });

  test('лишние — всё, кроме первого в каждой группе', () {
    final groups = dupGroups([
      _track('a', name: 'Первая', cover: 'a.jpg'),
      _track('b', name: 'Первая'),
      _track('c', name: 'Вторая', cover: 'c.jpg'),
      _track('d', name: 'Вторая'),
      _track('e', name: 'Вторая'),
    ]);

    expect(extraDups(groups).map((t) => t.id), ['b', 'd', 'e']);
  });
}
