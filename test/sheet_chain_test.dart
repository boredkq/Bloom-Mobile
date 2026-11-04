/// A sheet opened from a sheet takes its place: back returns, a pick closes all.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:bloom/shared/ui/bloom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db.dart';

Future<void> _open(
  WidgetTester tester,
  void Function(BuildContext context) open,
) async {
  final store = JsonStore.memory();
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _menu(
  BuildContext context, {
  required VoidCallback onNext,
  VoidCallback? onPlain,
}) => showBloomSheet(
  context: context,
  header: const SheetHero(cover: null, title: 'title'),
  groups: [
    [
      SheetAction(icon: Bi.plus, label: 'next', next: true, onTap: onNext),
      SheetAction(icon: Bi.plus, label: 'plain', onTap: onPlain ?? () {}),
    ],
  ],
);

Finder get _back => find.text('Назад');

void main() {
  testWidgets('typing goes to the field of the page on show', (tester) async {
    final first = TextEditingController();
    final second = TextEditingController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await _open(tester, (context) {
      showBloomSheetChild<void>(
        context: context,
        child: Builder(
          builder: (sheet) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: first, autofocus: true),
              TextButton(
                onPressed: () => openNextSheet(
                  sheet,
                  () => showBloomSheetChild<void>(
                    context: context,
                    child: TextField(controller: second, autofocus: true),
                  ),
                ),
                child: const Text('more'),
              ),
            ],
          ),
        ),
      );
    });
    await tester.showKeyboard(find.byType(TextField).first);
    tester.testTextInput.enterText('one');
    await tester.pump();
    expect(first.text, 'one');

    await tester.tap(find.text('more'));
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('two');
    await tester.pump();
    expect(second.text, 'two');
    expect(first.text, 'one');

    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('three');
    await tester.pump();
    expect(first.text, 'three');
  });

  testWidgets('back returns to the menu with no result', (tester) async {
    var finished = false;
    String? result = 'untouched';
    await _open(tester, (context) {
      _menu(
        context,
        onNext: () {
          showBloomSheetChild<String>(
            context: context,
            child: const Text('second'),
          ).then((value) {
            finished = true;
            result = value;
          });
        },
      );
    });
    expect(_back, findsNothing);

    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    expect(find.text('next'), findsNothing);

    await tester.tap(_back);
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);
    expect(find.text('second'), findsNothing);
    expect(_back, findsNothing);
    expect(finished, isTrue);
    expect(result, isNull);
  });

  testWidgets('the system back goes one step, then closes', (tester) async {
    await _open(tester, (context) {
      _menu(
        context,
        onNext: () => showBloomSheetChild<void>(
          context: context,
          child: const Text('second'),
        ),
      );
    });
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('next'), findsNothing);
  });

  testWidgets('a pick closes the whole sheet and delivers its result', (
    tester,
  ) async {
    String? result;
    var menuDone = false;
    await _open(tester, (context) {
      _menu(
        context,
        onNext: () async {
          result = await showBloomSheetChild<String>(
            context: context,
            child: Builder(
              builder: (sheet) => TextButton(
                onPressed: () => Navigator.of(sheet).pop('picked'),
                child: const Text('pick'),
              ),
            ),
          );
        },
      ).then((_) => menuDone = true);
    });
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    expect(result, 'picked');
    expect(menuDone, isTrue);
    expect(find.text('next'), findsNothing);
    expect(find.text('pick'), findsNothing);
  });

  testWidgets('a tap outside closes the whole sheet', (tester) async {
    await _open(tester, (context) {
      _menu(
        context,
        onNext: () => showBloomSheetChild<void>(
          context: context,
          child: const Text('second'),
        ),
      );
    });
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    expect(find.text('next'), findsNothing);
  });

  testWidgets('an item that opened nothing closes the sheet', (tester) async {
    await _open(tester, (context) {
      _menu(context, onNext: () {});
    });
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    expect(find.text('next'), findsNothing);
  });

  testWidgets('a plain item closes the sheet before it acts', (tester) async {
    var ran = false;
    await _open(tester, (context) {
      _menu(context, onNext: () {}, onPlain: () => ran = true);
    });
    await tester.tap(find.text('plain'));
    await tester.pumpAndSettle();
    expect(ran, isTrue);
    expect(find.text('plain'), findsNothing);
  });
}
