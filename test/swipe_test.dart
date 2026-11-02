/// Swipes: the setting (what's assigned and that it survives a restart), the
/// "Play next" math and the row itself: gesture, threshold and plate.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/settings/swipe_store.dart';
import 'package:bloom/shared/ui/swipe_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
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

/// The row's width in gesture checks: the threshold comes from it.
const double _rowWidth = 400;

const Key _rowKey = Key('row');

/// A row with swipes in the tree. [log] is written by the plates' handlers.
Future<void> _pumpRow(
  WidgetTester tester,
  List<String> log, {
  SwipePanel? left,
  SwipePanel? right,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildBloomTheme(BloomThemes.dark),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _rowWidth,
          child: SwipeRow(
            left: left,
            right: right,
            child: Container(
              key: _rowKey,
              height: 64,
              color: const Color(0xFF202020),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  group('настройка', () {
    test('умолчания — те, что на скриншотах', () {
      final c = _container(JsonStore.memory());
      final s = c.read(swipeProvider);

      expect(s.of(SwipeZone.library).left, SwipeAction.delete);
      expect(s.of(SwipeZone.library).right, SwipeAction.queue);
      expect(s.of(SwipeZone.queue).left, SwipeAction.delete);
      expect(s.of(SwipeZone.queue).right, SwipeAction.delete);
      expect(s.of(SwipeZone.mini).left, SwipeAction.next);
      expect(s.of(SwipeZone.mini).right, SwipeAction.prev);
      expect(s.of(SwipeZone.player).left, SwipeAction.next);
      expect(s.of(SwipeZone.player).right, SwipeAction.prev);
    });

    test('выбор переживает перезапуск, соседнее место не трогается', () {
      final store = JsonStore.memory();
      _container(store)
          .read(swipeProvider.notifier)
          .setAction(SwipeZone.library, isLeft: true, action: SwipeAction.like);

      // A new container means a new launch with the same file.
      final fresh = _container(store).read(swipeProvider);
      expect(fresh.of(SwipeZone.library).left, SwipeAction.like);
      expect(fresh.of(SwipeZone.library).right, SwipeAction.queue);
      expect(fresh.of(SwipeZone.queue).left, SwipeAction.delete);
    });

    test('битая запись в файле откатывается к умолчанию', () {
      final store = JsonStore.memory();
      store.write('swipes', {
        'library': {'left': 'выдумка', 'right': 'like'},
        'queue': 'мусор',
      });

      final s = _container(store).read(swipeProvider);
      expect(s.of(SwipeZone.library).left, SwipeAction.delete);
      expect(s.of(SwipeZone.library).right, SwipeAction.like);
      expect(s.of(SwipeZone.queue).left, SwipeAction.delete);
    });
  });

  group('«Следующим»', () {
    test('новый трек встаёт сразу за играющим', () {
      final queue = [_track('a'), _track('b'), _track('c')];
      final (next, index) = queueWithNext(queue, 0, _track('x'));

      expect(next.map((t) => t.id).toList(), ['a', 'x', 'b', 'c']);
      expect(next[index].id, 'a');
    });

    test('трек из хвоста переезжает, а не дублируется', () {
      final queue = [_track('a'), _track('b'), _track('c')];
      final (next, index) = queueWithNext(queue, 0, _track('c'));

      expect(next.map((t) => t.id).toList(), ['a', 'c', 'b']);
      expect(next[index].id, 'a');
    });

    test('трек сверху уносит номер играющего вверх', () {
      final queue = [_track('a'), _track('b'), _track('c')];
      final (next, index) = queueWithNext(queue, 2, _track('a'));

      expect(next.map((t) => t.id).toList(), ['b', 'c', 'a']);
      // "c" still plays, it's just second now.
      expect(next[index].id, 'c');
    });

    test('играющий сам себе следующим — очередь не трогается', () {
      final queue = [_track('a'), _track('b')];
      final (next, index) = queueWithNext(queue, 1, _track('b'));

      expect(next.map((t) => t.id).toList(), ['a', 'b']);
      expect(index, 1);
    });
  });

  group('«Играть следующими» пачкой', () {
    test('пачка встаёт за играющим в своём порядке', () {
      final queue = [_track('a'), _track('b')];
      final (next, index) = queueWithNextAll(queue, 0, [
        _track('x'),
        _track('y'),
      ]);

      expect(next.map((t) => t.id).toList(), ['a', 'x', 'y', 'b']);
      expect(next[index].id, 'a');
    });

    test('повторы внутри пачки и в очереди не задваиваются', () {
      final queue = [_track('a'), _track('b'), _track('c')];
      final (next, index) = queueWithNextAll(queue, 0, [
        _track('c'),
        _track('c'),
        _track('x'),
      ]);

      expect(next.map((t) => t.id).toList(), ['a', 'c', 'x', 'b']);
      expect(next[index].id, 'a');
    });

    test('играющий из пачки выпадает, остальные встают за ним', () {
      final queue = [_track('a'), _track('b'), _track('c')];
      final (next, index) = queueWithNextAll(queue, 1, [
        _track('b'),
        _track('c'),
      ]);

      // "b" plays and stays, "c" moves right next to it.
      expect(next.map((t) => t.id).toList(), ['a', 'b', 'c']);
      expect(next[index].id, 'b');
    });

    test('пачка из одного играющего ничего не меняет', () {
      final queue = [_track('a'), _track('b')];
      final (next, index) = queueWithNextAll(queue, 1, [_track('b')]);

      expect(identical(next, queue), isTrue);
      expect(index, 1);
    });

    test('пачка сверху уносит номер играющего вверх', () {
      final queue = [_track('a'), _track('b'), _track('c'), _track('d')];
      final (next, index) = queueWithNextAll(queue, 3, [
        _track('a'),
        _track('b'),
      ]);

      expect(next.map((t) => t.id).toList(), ['c', 'd', 'a', 'b']);
      expect(next[index].id, 'd');
    });
  });

  group('строка', () {
    testWidgets('короткий свайп ничего не делает и возвращает строку', (
      tester,
    ) async {
      final log = <String>[];
      await _pumpRow(
        tester,
        log,
        right: SwipePanel(
          icon: Bi.trashBinTrash,
          onFire: () => log.add('fire'),
        ),
      );

      await tester.drag(find.byKey(_rowKey), const Offset(-40, 0));
      await tester.pumpAndSettle();

      expect(log, isEmpty);
      expect(tester.getCenter(find.byKey(_rowKey)).dx, 400);
    });

    testWidgets('за порогом действие срабатывает', (tester) async {
      final log = <String>[];
      await _pumpRow(
        tester,
        log,
        right: SwipePanel(
          icon: Bi.trashBinTrash,
          onFire: () => log.add('fire'),
        ),
      );

      await tester.drag(
        find.byKey(_rowKey),
        const Offset(-_rowWidth * (kSwipeThreshold + 0.1), 0),
      );
      await tester.pumpAndSettle();

      expect(log, ['fire']);
    });

    testWidgets('не удаляющее действие возвращает строку на место', (
      tester,
    ) async {
      final log = <String>[];
      await _pumpRow(
        tester,
        log,
        left: SwipePanel(icon: Bi.add, onFire: () => log.add('queue')),
      );

      await tester.drag(find.byKey(_rowKey), const Offset(_rowWidth * 0.5, 0));
      await tester.pumpAndSettle();

      expect(log, ['queue']);
      expect(tester.getCenter(find.byKey(_rowKey)).dx, 400);
    });

    testWidgets('в сторону без действия строка не двигается', (tester) async {
      final log = <String>[];
      await _pumpRow(
        tester,
        log,
        right: SwipePanel(
          icon: Bi.trashBinTrash,
          onFire: () => log.add('fire'),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_rowKey)),
      );
      await gesture.moveBy(const Offset(150, 0));
      await tester.pump();

      expect(tester.getCenter(find.byKey(_rowKey)).dx, 400);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(log, isEmpty);
    });

    testWidgets('плашка растёт ровно на столько, на сколько утянули', (
      tester,
    ) async {
      final log = <String>[];
      await _pumpRow(
        tester,
        log,
        right: SwipePanel(
          icon: Bi.trashBinTrash,
          danger: true,
          onFire: () => log.add('fire'),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_rowKey)),
      );
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();

      // The row moved by the same 120, and the plate took the freed space.
      expect(tester.getCenter(find.byKey(_rowKey)).dx, 280);
      final panel = tester.getSize(
        find.byWidgetPredicate((w) => w is ClipRRect && w.child is ColoredBox),
      );
      expect(panel.width, 120);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
