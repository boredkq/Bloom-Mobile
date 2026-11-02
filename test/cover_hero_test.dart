/// The cover flight: card to page header.
///
/// I check two places that are easy to get wrong without noticing: the flying
/// copy must change shape on the way (or the avatar's circle snaps to a
/// rectangle at the start), and it must count its progress the right way on
/// "back" (the navigator runs frames from 1 to 0).
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/shared/ui/cover_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom/core/l10n/l10n.dart';

/// Radii on the card and in the header are extreme values, so anything in
/// between is unmistakable.
const double _card = 50;
const double _page = 0;

/// The flying copy's radius: the only `ClipRRect` that matches neither end.
double? _flying(WidgetTester tester) {
  for (final clip in tester.widgetList<ClipRRect>(find.byType(ClipRRect))) {
    final shape = clip.borderRadius;
    if (shape is! BorderRadius) continue;
    final r = shape.topLeft.x;
    if (r > _page && r < _card) return r;
  }
  return null;
}

Widget _end({
  required Object tag,
  required double radius,
  required Size size,
}) => CoverHero(
  tag: tag,
  shape: BorderRadius.circular(radius),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: size.width,
      height: size.height,
      child: const ColoredBox(color: Color(0xFF00FF00)),
    ),
  ),
);

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // The language is pinned: otherwise text checks would depend on the
        // machine's locale.
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      body: Column(
                        children: [
                          _end(
                            tag: 'cover',
                            radius: _page,
                            size: const Size(360, 300),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Text('назад'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: _end(
                  tag: 'cover',
                  radius: _card,
                  size: const Size(100, 100),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('обложка летит и меняет форму по дороге', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      _flying(tester),
      isNotNull,
      reason: 'посреди перехода в оверлее должна быть копия своей формы',
    );

    await tester.pumpAndSettle();
    expect(_flying(tester), isNull, reason: 'копия убирается после посадки');
  });

  testWidgets('на «назад» форма идёт от шапки к карточке, а не наоборот', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byType(GestureDetector));
    await tester.pumpAndSettle();

    await tester.tap(find.text('назад'));
    await tester.pump();
    // A quarter of the way back: the copy is still almost the header's
    // rectangle. Counting progress without the direction would show the card's
    // circle here, the very snap at the start.
    await tester.pump(const Duration(milliseconds: 75));

    final radius = _flying(tester);
    expect(radius, isNotNull);
    expect(radius, lessThan(_card / 2));

    await tester.pumpAndSettle();
  });

  testWidgets('страница под перелётом не едет по горизонтали', (tester) async {
    const key = Key('страница');

    await tester.pumpWidget(
      MaterialApp(
        // The language is pinned: otherwise text checks would depend on the
        // machine's locale.
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: GestureDetector(
              onTap: () => Navigator.of(context).push(
                detailPageRoute<void>(
                  (_) => const Scaffold(
                    body: SizedBox.expand(child: Placeholder(key: key)),
                  ),
                ),
              ),
              child: const Text('открыть'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('открыть'));
    await tester.pump();
    // The app's shared transition would have moved the page sideways by a
    // quarter of its width on this frame, everything except the flying cover.
    await tester.pump(const Duration(milliseconds: 150));

    expect(tester.getTopLeft(find.byKey(key)).dx, 0);

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(key)).dx, 0);
  });
}
