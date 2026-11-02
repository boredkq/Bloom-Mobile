/// Track row gestures: the cover drags, the rest of the row opens the menu.
///
/// I check the split of the two long presses: if both sat on the whole row
/// they'd fight in the arena, and holding the cover would open the menu every
/// other time.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/shared/ui/atoms.dart';
import 'package:bloom/shared/ui/entity_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

import 'package:bloom/core/l10n/l10n.dart';

const _track = Track(
  id: 'sc:1',
  name: 'sleep mode',
  artist: 'ONDA ANDAR',
  duration: Duration(minutes: 2, seconds: 53),
  source: MusicSource.soundcloud,
);

/// What happened to the row during the run.
final _log = <String>[];

/// The row's [dragIndex]: null is a plain list with nothing to move.
Future<void> _pumpRow(WidgetTester tester, {int? dragIndex}) async {
  _log.clear();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jsonStoreProvider.overrideWithValue(JsonStore.memory()),
        dbProvider.overrideWithValue(BloomDb.memory()),
      ],
      child: MaterialApp(
        // The language is pinned: otherwise text checks would depend on the
        // machine's locale.
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          // A real list: without one `ReorderableDelayedDragStartListener`
          // finds no owner and crashes on the press.
          body: ReorderableListView(
            buildDefaultDragHandles: false,
            onReorder: (from, to) => _log.add('reorder $from→$to'),
            children: [
              SizedBox(
                key: const ValueKey('row'),
                child: TrackRowShell(
                  track: _track,
                  active: false,
                  onTap: () => _log.add('tap'),
                  onMenu: () => _log.add('menu'),
                  dragIndex: dragIndex,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The row's cover: pressed to drag.
Finder get _cover => find.byType(Cover);

/// The track's title: pressed to open the menu.
Finder get _title => find.text('sleep mode');

void main() {
  testWidgets('зажатие обложки не открывает меню трека', (tester) async {
    await _pumpRow(tester, dragIndex: 0);

    await tester.longPress(_cover);
    await tester.pumpAndSettle();

    expect(_log, isEmpty);
  });

  testWidgets('меню открывается долгим тапом по остальной строке', (
    tester,
  ) async {
    await _pumpRow(tester, dragIndex: 0);

    await tester.longPress(_title);
    await tester.pumpAndSettle();

    expect(_log, ['menu']);
  });

  testWidgets('тап по обложке остаётся тапом строки', (tester) async {
    await _pumpRow(tester, dragIndex: 0);

    await tester.tap(_cover);
    await tester.pumpAndSettle();

    expect(_log, ['tap']);
  });

  testWidgets('без тянучки меню открывается и с обложки', (tester) async {
    await _pumpRow(tester);

    await tester.longPress(_cover);
    await tester.pumpAndSettle();

    expect(_log, ['menu']);
  });
}
