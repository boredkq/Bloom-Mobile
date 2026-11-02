/// Shuffling rearranges the queue itself rather than throwing a random number
/// at each transition, so I check the contents and the list's head.
///
/// The randomness is fixed: `Random(seed)` gives the same order, so a failure
/// means broken logic, not bad luck.
library;

import 'dart:math';

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'a',
  duration: Duration.zero,
  source: MusicSource.soundcloud,
);

List<String> _ids(List<Track> tracks) => [for (final t in tracks) t.id];

void main() {
  final queue = [
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) _track(id),
  ];

  test('the playing track comes first, contents stay', () {
    final out = shuffledQueue(queue, 3, Random(7));
    expect(out.first.id, 'd');
    expect(out.length, queue.length);
    expect(_ids(out).toSet(), _ids(queue).toSet());
  });

  test('with nothing playing all get shuffled, not in the source order', () {
    final out = shuffledQueue(queue, -1, Random(7));
    expect(_ids(out).toSet(), _ids(queue).toSet());
    expect(_ids(out), isNot(_ids(queue)));
  });

  test('a number outside the queue acts as nothing playing', () {
    final out = shuffledQueue(queue, 99, Random(1));
    expect(_ids(out).toSet(), _ids(queue).toSet());
  });

  test('a one-track queue survives a shuffle', () {
    expect(_ids(shuffledQueue([_track('a')], 0, Random(1))), ['a']);
    expect(shuffledQueue(const [], -1, Random(1)), isEmpty);
  });

  test('the shuffle really shuffles: two seeds give different orders', () {
    final long = [for (var i = 0; i < 30; i++) _track('t$i')];
    final a = _ids(shuffledQueue(long, 0, Random(1)));
    final b = _ids(shuffledQueue(long, 0, Random(2)));
    expect(a, isNot(b));
    expect(a.first, 't0'); // but the head stays in both
    expect(b.first, 't0');
  });
}
