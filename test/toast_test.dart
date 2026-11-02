/// Toasts: the queue, undo, expiry, touch, and the live "work to result" toast.
///
/// I check behavior, not pixels: who gets `fn` and `onExpire` and when, how long
/// a toast stays when held, and that a job's toast changes in place rather than
/// being rebuilt.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:bloom/shared/ui/bloom_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

import 'package:bloom/core/l10n/l10n.dart';

import 'support/glyphs.dart';

/// A host screen with the toast layer over it.
///
/// The container is required: the toast card is a glass surface and reads
/// transparency settings (`GlassBox`), which live in the store.
Future<void> _pumpHost(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      dbProvider.overrideWithValue(BloomDb.memory()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        // The language is pinned: otherwise text checks would depend on the
        // machine's locale.
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        builder: (_, child) => ToastHost(child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  );
}

/// Lets the entrance play.
Future<void> _enter(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a plain toast shows its text and fades by itself', (
    tester,
  ) async {
    await _pumpHost(tester);
    toaster.show('Трек удалён');
    await _enter(tester);
    expect(find.text('Трек удалён'), findsOneWidget);

    // 2 s of life plus the exit animation.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Трек удалён'), findsNothing);
  });

  testWidgets('the toast sits at the top, under the status bar', (
    tester,
  ) async {
    await _pumpHost(tester);
    toaster.show('Трек удалён');
    await _enter(tester);

    final height = tester.getSize(find.byType(Scaffold)).height;
    expect(tester.getCenter(find.text('Трек удалён')).dy, lessThan(height / 4));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a long text stays on one line', (tester) async {
    await _pumpHost(tester);
    toaster.show('Очень длинное сообщение ' * 20);
    await _enter(tester);

    final text = tester.widget<Text>(find.textContaining('Очень длинное'));
    expect(text.maxLines, 1);
    expect(tester.takeException(), isNull, reason: 'no overflow');

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a tap takes it away at once', (tester) async {
    await _pumpHost(tester);
    toaster.show('Трек удалён');
    await _enter(tester);

    await tester.tap(find.text('Трек удалён'));
    await tester.pumpAndSettle();
    expect(find.text('Трек удалён'), findsNothing);
  });

  testWidgets('held, it stops running out', (tester) async {
    await _pumpHost(tester);
    toaster.show('Трек удалён');
    await _enter(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Трек удалён')),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Трек удалён'), findsOneWidget);

    await gesture.moveBy(const Offset(0, 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Трек удалён'), findsNothing);
  });

  testWidgets('swiped up it flies off; a short pull springs back', (
    tester,
  ) async {
    await _pumpHost(tester);
    toaster.show('Трек удалён');
    await _enter(tester);
    final y = tester.getCenter(find.text('Трек удалён')).dy;

    // A short, slow pull: back in place, still on screen.
    final pull = await tester.startGesture(
      tester.getCenter(find.text('Трек удалён')),
    );
    await pull.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 200));
    await pull.moveBy(const Offset(0, -4));
    await tester.pump(const Duration(milliseconds: 200));
    await pull.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getCenter(find.text('Трек удалён')).dy, closeTo(y, 0.5));

    await tester.fling(find.text('Трек удалён'), const Offset(0, -80), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Трек удалён'), findsNothing);
  });

  testWidgets('Undo calls fn and keeps onExpire from firing', (tester) async {
    await _pumpHost(tester);
    var undone = false;
    var expired = false;
    toaster.show(
      'Плейлист удалён',
      action: ToastAction(
        fn: () => undone = true,
        onExpire: () => expired = true,
      ),
    );
    await _enter(tester);

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();

    expect(undone, isTrue);
    expect(expired, isFalse, reason: 'undone, nothing left to delete');
    expect(find.text('Плейлист удалён'), findsNothing);
  });

  testWidgets('a toast with an action burned out: onExpire fires', (
    tester,
  ) async {
    await _pumpHost(tester);
    var undone = false;
    var expired = false;
    toaster.show(
      'Плейлист удалён',
      action: ToastAction(
        fn: () => undone = true,
        onExpire: () => expired = true,
      ),
    );
    await tester.pump();
    // With a button a toast lives 5 s, so I wait with a margin.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(expired, isTrue, reason: 'the decision stood');
    expect(undone, isFalse);
  });

  testWidgets('dismissed by a tap, a toast with an action still expires', (
    tester,
  ) async {
    await _pumpHost(tester);
    var expired = false;
    toaster.show(
      'Плейлист удалён',
      action: ToastAction(fn: () {}, onExpire: () => expired = true),
    );
    await _enter(tester);

    await tester.tap(find.text('Плейлист удалён'));
    await tester.pumpAndSettle();
    expect(expired, isTrue);
  });

  testWidgets('a job changes in place, not as a second toast', (tester) async {
    await _pumpHost(tester);
    final toast = toaster.busy('Сохранение для офлайна…');
    await _enter(tester);

    expect(find.text('Сохранение для офлайна…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    toast.finish('Доступно офлайн: Song');
    await _enter(tester);

    // The old text is gone: the card is the same, its contents changed.
    expect(find.text('Сохранение для офлайна…'), findsNothing);
    expect(find.text('Доступно офлайн: Song'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(findGlyph(Bi.check), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Доступно офлайн: Song'), findsNothing);
  });

  testWidgets('a running job stays put under a tap', (tester) async {
    await _pumpHost(tester);
    final toast = toaster.busy('Скачиваю…');
    await _enter(tester);

    await tester.tap(find.text('Скачиваю…'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Скачиваю…'), findsOneWidget);

    toast.finish('Готово');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a message comes over a job, and the job comes back', (
    tester,
  ) async {
    await _pumpHost(tester);
    final toast = toaster.busy('Скачиваю…');
    await _enter(tester);

    toaster.show('Добавлено');
    await _enter(tester);
    expect(find.text('Добавлено'), findsOneWidget);
    expect(find.text('Скачиваю…'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await _enter(tester);
    expect(find.text('Скачиваю…'), findsOneWidget);

    toast.finish('Готово');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('the job begun last is the one on top', (tester) async {
    await _pumpHost(tester);
    final first = toaster.busy('Первая');
    await _enter(tester);
    final second = toaster.busy('Вторая');
    await _enter(tester);
    expect(find.text('Вторая'), findsOneWidget);
    expect(find.text('Первая'), findsNothing);

    second.finish('Вторая готова');
    await _enter(tester);
    expect(find.text('Вторая готова'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await _enter(tester);
    expect(find.text('Первая'), findsOneWidget);

    first.finish('Готово');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a job that never ends doesn\'t stay for good', (tester) async {
    await _pumpHost(tester);
    toaster.busy('Упала');
    await _enter(tester);

    await tester.pump(const Duration(minutes: 31));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Упала'), findsNothing);
  });

  testWidgets('two toasts with Undo both get shown', (tester) async {
    await _pumpHost(tester);
    var first = false;
    var second = false;
    toaster.show('Удалён', action: ToastAction(fn: () => first = true));
    toaster.show('Удалён', action: ToastAction(fn: () => second = true));
    await _enter(tester);

    await tester.tap(find.text('Отменить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _enter(tester);
    expect(first, isTrue);

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(second, isTrue, reason: 'the second Undo undoes the second thing');
  });

  testWidgets('a long job shows its count, and its result stays longer', (
    tester,
  ) async {
    await _pumpHost(tester);
    var stopped = false;
    final toast = toaster.busy(
      'Сохранение',
      live: (_, _, view) => ToastView(
        text: view.text,
        share: 0.5,
        count: '3/5',
        onStop: () => stopped = true,
      ),
    );
    await _enter(tester);
    expect(find.text('3/5'), findsOneWidget);

    await tester.tap(findGlyph(Bi.close));
    await tester.pump();
    expect(stopped, isTrue);

    toast.finish('Скачано 5');
    await _enter(tester);
    expect(find.text('Скачано 5'), findsOneWidget);
    expect(find.text('3/5'), findsNothing);

    // A plain message would be gone by now.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Скачано 5'), findsOneWidget);

    // ✕ closes the result.
    await tester.tap(findGlyph(Bi.close));
    await tester.pumpAndSettle();
    expect(find.text('Скачано 5'), findsNothing);
  });

  testWidgets('toasts queue up rather than run over each other', (
    tester,
  ) async {
    await _pumpHost(tester);
    toaster.show('Первый');
    toaster.show('Второй');
    await _enter(tester);

    expect(find.text('Первый'), findsOneWidget);
    expect(find.text('Второй'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    await _enter(tester);
    expect(find.text('Второй'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('the same text twice in a row shows once', (tester) async {
    await _pumpHost(tester);
    toaster.show('Первый');
    toaster.show('Первый');
    await _enter(tester);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    await _enter(tester);
    expect(find.text('Первый'), findsNothing);
    await tester.pumpAndSettle();
  });
}
