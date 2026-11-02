/// The cover collage: what gets in from a track list and how many tiles come
/// out. The layout is shared by the library tile and the list header, so it's
/// tested apart from both.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/shared/ui/cover_collage.dart';
import 'package:flutter/material.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/glyphs.dart';

/// A section placeholder with an icon, which shows how many times it got drawn.
const Widget _fallback = BloomIcon(Bi.history);

Finder get _fallbacks => findGlyph(Bi.history);

Future<void> _pump(WidgetTester tester, List<String?> covers) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildBloomTheme(BloomThemes.dark),
        home: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: CoverCollage(covers: covers, fallback: _fallback),
          ),
        ),
      ),
    );

/// How many pictures the collage built. Pictures don't load in a test (no
/// network), but the `Image` widgets are in the tree, so I count those.
Future<int> _images(WidgetTester tester, List<String?> covers) async {
  await _pump(tester, covers);
  return tester.widgetList(find.byType(Image)).length;
}

void main() {
  group('pickCollageCovers', () {
    test('берёт первые четыре разных, пустые пропускает', () {
      expect(pickCollageCovers(['a', null, '', 'b', 'c', 'd', 'e']), [
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('повторы не считаются — у альбома одна обложка на все треки', () {
      expect(pickCollageCovers(['a', 'a', 'a', 'b']), ['a', 'b']);
    });

    test('обложек нет — пусто', () {
      expect(pickCollageCovers([null, '', null]), isEmpty);
    });
  });

  group('CoverCollage', () {
    testWidgets('одна обложка — одна картинка на всю площадь', (tester) async {
      expect(await _images(tester, ['a', 'a']), 1);
    });

    testWidgets('две, три, четыре — столько же плиток', (tester) async {
      expect(await _images(tester, ['a', 'b']), 2);
      expect(await _images(tester, ['a', 'b', 'c']), 3);
      expect(await _images(tester, ['a', 'b', 'c', 'd', 'e']), 4);
    });

    testWidgets('обложек нет — остаётся заглушка', (tester) async {
      expect(await _images(tester, [null, '']), 0);
      expect(_fallbacks, findsOneWidget);
    });

    // `local:` without a loaded covers folder gives no picture, like a network
    // one that failed. A section placeholder with its icon doesn't fit a cell:
    // four of them would make a grid of four icons instead of a collage.
    testWidgets('ячейка без картинки не повторяет заглушку раздела', (
      tester,
    ) async {
      expect(await _images(tester, ['local:a', 'local:b', 'local:c']), 0);
      expect(_fallbacks, findsNothing);
    });

    testWidgets('одна обложка не загрузилась — заглушка на всю площадь', (
      tester,
    ) async {
      expect(await _images(tester, ['local:a']), 0);
      expect(_fallbacks, findsOneWidget);
    });
  });
}
