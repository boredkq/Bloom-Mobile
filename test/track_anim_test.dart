/// The track change animation: the direction and the layers.
///
/// I check where it breaks unnoticed: that both surfaces go the same way (the
/// direction is computed once, in the player), that a change under the finger
/// draws no layers over the gesture, and that a gone layer is removed.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/features/player/track_swap_dir.dart';
import 'package:bloom/features/player/ui/track_swap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderClipRect;
import 'package:flutter_test/flutter_test.dart';

/// I recognize layers by text: each track has its own.
Future<void> _pumpSwap(
  WidgetTester tester,
  String id, {
  bool fade = false,
  bool animated = true,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildBloomTheme(BloomThemes.dark),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: TrackSwap(
            id: id,
            fade: fade,
            animated: animated,
            child: Text(id),
          ),
        ),
      ),
    ),
  ),
);

/// The shift of the layer with this text, as a share of the width.
double _shiftOf(WidgetTester tester, String text) {
  final translation = tester.widget<FractionalTranslation>(
    find
        .ancestor(
          of: find.text(text),
          matching: find.byType(FractionalTranslation),
        )
        .first,
  );
  return translation.translation.dx;
}

void main() {
  setUp(resetSwapDirForTest);

  group('направление перехода', () {
    test('дальше по очереди — вперёд, назад — назад', () {
      final queue = ['a', 'b', 'c'];
      commitSwapDir(queue, 0);
      commitSwapDir(queue, 1);
      expect(swapDir, 1);
      commitSwapDir(queue, 0);
      expect(swapDir, -1);
    });

    test('явное направление сильнее номеров: закольцовка', () {
      final queue = ['a', 'b', 'c'];
      commitSwapDir(queue, 2);
      // "Next" from last to first is "back" by numbers.
      markSwapDir(1);
      commitSwapDir(queue, 0);
      expect(swapDir, 1);
    });

    test('явное направление одноразовое', () {
      final queue = ['a', 'b', 'c'];
      commitSwapDir(queue, 2);
      markSwapDir(-1);
      commitSwapDir(queue, 1);
      expect(swapDir, -1);
      // The next switch goes by numbers again.
      commitSwapDir(queue, 2);
      expect(swapDir, 1);
    });

    test('другая очередь — всегда вперёд: номера несравнимы', () {
      commitSwapDir(['a', 'b', 'c'], 2);
      commitSwapDir(['x', 'y'], 0);
      expect(swapDir, 1);
    });

    test('«не анимировать» держится ровно до ближайшей смены', () {
      final queue = ['a', 'b'];
      commitSwapDir(queue, 0);
      markSwapSilent();
      commitSwapDir(queue, 1);
      expect(swapSilent, isTrue);
      commitSwapDir(queue, 0);
      expect(swapSilent, isFalse);
    });

    test('несостоявшийся жест флаг за собой убирает', () {
      final queue = ['a', 'b'];
      commitSwapDir(queue, 0);
      // "Back" mid-track rewinds it to the start instead of flipping.
      markSwapSilent();
      cancelSwapSilent();
      commitSwapDir(queue, 1);
      expect(swapSilent, isFalse);
    });
  });

  group('слои', () {
    testWidgets('первый трек за сессию не анимируется — уезжать нечему', (
      tester,
    ) async {
      await _pumpSwap(tester, 'первый');
      expect(find.text('первый'), findsOneWidget);
      expect(_shiftOf(tester, 'первый'), 0);
    });

    testWidgets('слайд: старый уезжает, новый приезжает и слой снимается', (
      tester,
    ) async {
      await _pumpSwap(tester, 'первый');
      await _pumpSwap(tester, 'второй');
      await tester.pump();

      // Both layers are in the tree and part the same way: the new one comes
      // from the right to zero, the old one leaves left.
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('первый'), findsOneWidget);
      expect(_shiftOf(tester, 'второй'), greaterThan(0));
      expect(_shiftOf(tester, 'первый'), lessThan(0));

      await tester.pumpAndSettle();
      expect(find.text('первый'), findsNothing);
      expect(_shiftOf(tester, 'второй'), 0);
    });

    testWidgets('назад — зеркально', (tester) async {
      await _pumpSwap(tester, 'первый');
      markSwapDir(-1);
      commitSwapDir(['первый', 'второй'], 0);
      await _pumpSwap(tester, 'второй');
      await tester.pump(const Duration(milliseconds: 60));

      expect(_shiftOf(tester, 'второй'), lessThan(0));
      expect(_shiftOf(tester, 'первый'), greaterThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets('уезжающий слой режется по своей коробке', (tester) async {
      await _pumpSwap(tester, 'первый');
      await _pumpSwap(tester, 'второй');
      await tester.pump(const Duration(milliseconds: 60));

      // The layers parted, and the clip must be there: `Stack` only counts
      // positioned children as overflow, and the shift happens at paint.
      // Without the clip the mini player's label runs over the cover.
      expect(_shiftOf(tester, 'первый'), isNot(0));
      final clip = tester.renderObject<RenderClipRect>(
        find
            .descendant(
              of: find.byType(TrackSwap),
              matching: find.byType(ClipRect),
            )
            .first,
      );
      expect(clip.clipBehavior, isNot(Clip.none));
      await tester.pumpAndSettle();
    });

    testWidgets('затухание не двигает слои', (tester) async {
      await _pumpSwap(tester, 'первый', fade: true);
      await _pumpSwap(tester, 'второй', fade: true);
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('первый'), findsOneWidget);
      expect(_shiftOf(tester, 'первый'), 0);
      expect(_shiftOf(tester, 'второй'), 0);
      await tester.pumpAndSettle();
    });

    testWidgets('сосед под пальцем меняется без второго слоя', (tester) async {
      await _pumpSwap(tester, 'первый', animated: false);
      await _pumpSwap(tester, 'второй', animated: false);
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('первый'), findsNothing);
      expect(find.text('второй'), findsOneWidget);
    });

    testWidgets('смену под пальцем слои не рисуют', (tester) async {
      await _pumpSwap(tester, 'первый');
      markSwapSilent();
      commitSwapDir(['первый', 'второй'], 1);
      await _pumpSwap(tester, 'второй');
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('первый'), findsNothing);
      expect(_shiftOf(tester, 'второй'), 0);
    });
  });
}
