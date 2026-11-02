/// Moving rows in the queue: the playing track's number must move with it.
///
/// I check against a real list: move the items and see that the computed number
/// still holds the same element.
library;

import 'package:bloom/features/player/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// What's left at [indexAfterReorder] after the move.
String _after(List<String> queue, int current, int from, int target) {
  final q = [...queue];
  q.insert(target, q.removeAt(from));
  return q[indexAfterReorder(current, from, target)];
}

void main() {
  const queue = ['a', 'b', 'c', 'd', 'e'];

  test('dragged the playing track itself: the number follows it', () {
    expect(indexAfterReorder(2, 2, 0), 0);
    expect(_after(queue, 2, 2, 0), 'c');
    expect(_after(queue, 2, 2, 4), 'c');
  });

  test('a row moved top to bottom past the playing one: it went up', () {
    expect(indexAfterReorder(2, 0, 4), 1);
    expect(_after(queue, 2, 0, 4), 'c');
  });

  test('a row moved bottom to top past the playing one: it went down', () {
    expect(indexAfterReorder(2, 4, 0), 3);
    expect(_after(queue, 2, 4, 0), 'c');
  });

  test('a move on one side of the playing track leaves it alone', () {
    expect(indexAfterReorder(4, 0, 2), 4);
    expect(_after(queue, 4, 0, 2), 'e');
    expect(indexAfterReorder(0, 3, 1), 0);
    expect(_after(queue, 0, 3, 1), 'a');
  });

  test('an empty player: nothing playing, the number stays -1', () {
    expect(indexAfterReorder(-1, 1, 3), -1);
  });
}
