/// Toasts: undo, expiry and the live "work to result" toast.
///
/// I check behavior, not pixels: who gets `fn` and `onExpire` and when, and
/// that a live toast changes in place rather than being rebuilt.
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

/// A host screen: a toast goes through the messenger, so it needs a Scaffold.
///
/// The container is required: the toast card is a glass surface and reads
/// transparency settings (`GlassBox`), which live in the store.
Future<ScaffoldMessengerState> _pumpHost(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      dbProvider.overrideWithValue(BloomDb.memory()),
    ],
  );
  addTearDown(container.dispose);

  late ScaffoldMessengerState messenger;
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
        home: Scaffold(
          body: Builder(
            builder: (context) {
              messenger = ScaffoldMessenger.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
  return messenger;
}

void main() {
  testWidgets('a plain toast shows its text and fades by itself', (
    tester,
  ) async {
    final messenger = await _pumpHost(tester);
    messenger.toast('Трек удалён');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Трек удалён'), findsOneWidget);

    // 2 s of life plus the exit animation.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Трек удалён'), findsNothing);
  });

  testWidgets('Undo calls fn and keeps onExpire from firing', (tester) async {
    final messenger = await _pumpHost(tester);
    var undone = false;
    var expired = false;
    messenger.toast(
      'Плейлист удалён',
      action: ToastAction(
        fn: () => undone = true,
        onExpire: () => expired = true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();

    expect(undone, isTrue);
    expect(expired, isFalse, reason: 'undone, nothing left to delete');
  });

  testWidgets('a toast with an action burned out: onExpire fires', (
    tester,
  ) async {
    final messenger = await _pumpHost(tester);
    var undone = false;
    var expired = false;
    messenger.toast(
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

  testWidgets('a live toast changes in place, not as a second toast', (
    tester,
  ) async {
    final messenger = await _pumpHost(tester);
    final toast = messenger.busyToast('Сохранение для офлайна…');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Сохранение для офлайна…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    toast.finish('Доступно офлайн: Song');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The old text is gone: the card is the same, its contents changed.
    expect(find.text('Сохранение для офлайна…'), findsNothing);
    expect(find.text('Доступно офлайн: Song'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(findGlyph(Bi.check), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Доступно офлайн: Song'), findsNothing);
  });

  testWidgets('toasts queue up rather than run over each other', (
    tester,
  ) async {
    final messenger = await _pumpHost(tester);
    messenger.toast('Первый');
    messenger.toast('Второй');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Первый'), findsOneWidget);
    expect(find.text('Второй'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Второй'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
