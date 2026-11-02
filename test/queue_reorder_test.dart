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

  test('перетащили сам играющий трек — номер идёт за ним', () {
    expect(indexAfterReorder(2, 2, 0), 0);
    expect(_after(queue, 2, 2, 0), 'c');
    expect(_after(queue, 2, 2, 4), 'c');
  });

  test('строку перенесли сверху вниз через играющий — он поднялся', () {
    expect(indexAfterReorder(2, 0, 4), 1);
    expect(_after(queue, 2, 0, 4), 'c');
  });

  test('строку перенесли снизу вверх через играющий — он опустился', () {
    expect(indexAfterReorder(2, 4, 0), 3);
    expect(_after(queue, 2, 4, 0), 'c');
  });

  test('перенос по одну сторону от играющего его не трогает', () {
    expect(indexAfterReorder(4, 0, 2), 4);
    expect(_after(queue, 4, 0, 2), 'e');
    expect(indexAfterReorder(0, 3, 1), 0);
    expect(_after(queue, 0, 3, 1), 'a');
  });

  test('пустой плеер: играющего нет — номер остаётся -1', () {
    expect(indexAfterReorder(-1, 1, 3), -1);
  });
}
