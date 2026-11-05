import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/library/ui/list_edit.dart';
import 'package:bloom/shared/ui/atoms.dart';

import 'support/test_db.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
  sourceData: const {'transcodings': []},
);

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = JsonStore.memory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jsonStoreProvider.overrideWithValue(store),
          dbProvider.overrideWithValue(testDb(store)),
        ],
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildBloomTheme(BloomThemes.dark),
          home: Scaffold(
            body: ListEditor(
              listId: 'all',
              title: 'Все треки',
              playlist: null,
              tracks: [_track('sc:1'), _track('sc:2')],
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  bool on(WidgetTester tester, int index) => tester
      .widgetList<BloomCheck>(find.byType(BloomCheck))
      .elementAt(index)
      .on;

  testWidgets('a row selects with a round tick', (tester) async {
    await pump(tester);
    final box =
        tester
                .widget<AnimatedContainer>(
                  find
                      .descendant(
                        of: find.byType(BloomCheck).first,
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(box.shape, BoxShape.circle);

    await tester.tap(find.text('Song sc:1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(on(tester, 0), isTrue);
    expect(on(tester, 1), isFalse);
  });

  testWidgets('the count presses along with the tick for all', (tester) async {
    await pump(tester);
    // The bar's tick is the last one: it stands after the rows.
    final all = find.byType(BloomCheck).last;
    expect(tester.widget<BloomCheck>(all).on, isFalse);

    await tester.tap(find.textContaining('/2', findRichText: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<BloomCheck>(all).on, isTrue);
    expect(on(tester, 0), isTrue);
    expect(on(tester, 1), isTrue);

    await tester.tap(all);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<BloomCheck>(all).on, isFalse);
    expect(on(tester, 0), isFalse);
  });
}
