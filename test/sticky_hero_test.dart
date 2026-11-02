/// The sticky header: buttons stay on top, the title and action row scroll
/// away.
///
/// I check geometry and taps, not the picture: where the button row stands
/// after scrolling, how far the header collapses, and that the faded action row
/// catches no taps, since it ends up right under the buttons.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/shared/ui/sticky_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom/core/l10n/l10n.dart';

/// The status bar: the header must keep its height clear of the buttons.
const double _top = 40;

/// The collapsed header: status bar, padding, button row, padding.
const double _collapsed = _top + 10 + 48 + 10;

/// Whether Play in the action row was pressed.
bool _played = false;

Future<void> _pumpList(WidgetTester tester) async {
  _played = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildBloomTheme(BloomThemes.dark),
      home: MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: _top)),
        child: CustomScrollView(
          slivers: [
            StickyHero(
              height: 400,
              background: const ColoredBox(color: Colors.blue),
              barHeight: 48,
              bar: const SizedBox(height: 48, child: Text('назад')),
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Название списка'),
                  GestureDetector(
                    onTap: () => _played = true,
                    child: const SizedBox(height: 46, child: Text('играть')),
                  ),
                ],
              ),
            ),
            SliverList.builder(
              itemCount: 40,
              itemBuilder: (context, i) =>
                  SizedBox(height: 60, child: Text('строка $i')),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The header's visible height: the outer clip of its rounded bottom.
double _headerHeight(WidgetTester tester) => tester
    .getSize(
      find
          .descendant(
            of: find.byType(StickyHero),
            matching: find.byType(ClipRRect),
          )
          .first,
    )
    .height;

Future<void> _scroll(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
  await tester.pump();
}

void main() {
  testWidgets('the header collapses, the button row stays on top', (
    tester,
  ) async {
    await _pumpList(tester);
    final bar = find.text('назад');
    expect(tester.getTopLeft(bar).dy, _top + 10);
    expect(_headerHeight(tester), 400);

    final titleBefore = tester.getTopLeft(find.text('Название списка')).dy;
    await _scroll(tester, -150);

    // The buttons stay, and the title left with the cover by exactly the
    // scroll.
    expect(tester.getTopLeft(bar).dy, _top + 10);
    expect(_headerHeight(tester), 250);
    expect(
      tester.getTopLeft(find.text('Название списка')).dy,
      titleBefore - 150,
    );
  });

  testWidgets('past the collapsed header scrolling leaves it alone', (
    tester,
  ) async {
    await _pumpList(tester);
    await _scroll(tester, -2000);

    expect(_headerHeight(tester), _collapsed);
    expect(tester.getTopLeft(find.text('назад')).dy, _top + 10);
    // The list went under the header: the first row is no longer first on
    // screen.
    expect(find.text('строка 0'), findsNothing);
  });

  testWidgets('the faded action row catches no taps under the buttons', (
    tester,
  ) async {
    await _pumpList(tester);
    await tester.tap(find.text('играть'));
    expect(_played, isTrue, reason: 'in the open header the button works');

    _played = false;
    await _scroll(tester, -2000);
    await tester.tap(find.text('играть'), warnIfMissed: false);
    expect(_played, isFalse);
  });
}
