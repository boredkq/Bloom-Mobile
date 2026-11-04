import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/settings/storage_stats.dart';
import 'package:bloom/features/settings/ui/storage_screen.dart';
import 'package:bloom/shared/ui/atoms.dart';

const _mb = 1048576;

StorageStats _stats({
  int lyrics = 0,
  int covers = 0,
  int offline = 0,
  int custom = 0,
}) {
  CacheStat stat(CacheKind kind, int bytes) =>
      CacheStat(kind: kind, count: bytes > 0 ? 1 : 0, bytes: bytes);
  return StorageStats(
    caches: [
      stat(CacheKind.lyrics, lyrics),
      stat(CacheKind.covers, covers),
      stat(CacheKind.offline, offline),
      stat(CacheKind.custom, custom),
    ],
  );
}

void main() {
  group('the ring', () {
    test('nothing stored draws no arcs', () {
      expect(_stats().arcs, isEmpty);
    });

    test('arcs go end to end from the top in the order of the rows', () {
      final arcs = _stats(lyrics: 25, covers: 25, offline: 50).arcs;
      expect([for (final a in arcs) a.index], [0, 1, 2]);
      expect(arcs.first.start, -90);
      expect([for (final a in arcs) a.sweep], [90, 90, 180]);
      expect(arcs[1].start, 0);
      expect(arcs[2].start, 90);
    });

    test('a cache too small to see gets a sliver out of the others', () {
      final arcs = _stats(covers: 17 * _mb, custom: 100 * 1024).arcs;
      expect([for (final a in arcs) a.index], [1, 3]);
      expect(arcs[0].sweep, 357);
      expect(arcs[1].sweep, 3);
    });
  });

  group('the page', () {
    Future<void> pump(WidgetTester tester, StorageStats stats) async {
      // Tall enough for every row to clear the button at the bottom.
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = JsonStore.memory();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jsonStoreProvider.overrideWithValue(store),
            storageStatsProvider.overrideWith((ref) async => stats),
          ],
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildBloomTheme(BloomThemes.dark),
            home: const Scaffold(body: StorageSettingsScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('what comes back by itself starts ticked', (tester) async {
      await pump(tester, _stats(covers: 17 * _mb, offline: 3 * _mb));
      expect(find.text('Очистить 17.0 МБ'), findsOneWidget);
    });

    testWidgets('a tick adds its size to the button', (tester) async {
      await pump(tester, _stats(covers: 17 * _mb, offline: 3 * _mb));
      await tester.tap(find.text('Офлайн-кеш треков'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Очистить 20.0 МБ'), findsOneWidget);

      await tester.tap(find.text('Обложки'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Очистить 3.0 МБ'), findsOneWidget);
    });

    testWidgets('an empty cache has no tick to give', (tester) async {
      await pump(tester, _stats(covers: 17 * _mb));
      await tester.tap(find.text('Кастомизация'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Очистить 17.0 МБ'), findsOneWidget);
    });

    testWidgets('nothing to clear leaves the button dead', (tester) async {
      await pump(tester, _stats());
      final button = tester.widget<BloomButton>(find.byType(BloomButton));
      expect(button.label, 'Очистить');
      expect(button.onTap, isNull);
    });

    testWidgets('a keep row offers the periods in a sheet', (tester) async {
      await pump(tester, _stats());
      await tester.tap(find.text('Хранить обложки'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('До перезапуска'), findsOneWidget);
      expect(find.text('1 месяц'), findsOneWidget);

      await tester.tap(find.text('1 месяц'));
      await tester.pumpAndSettle();
      expect(find.text('До перезапуска'), findsNothing);
      expect(find.text('1 месяц'), findsOneWidget);
    });

    testWidgets('the first press only asks, a new tick asks again', (
      tester,
    ) async {
      await pump(tester, _stats(covers: 17 * _mb, offline: 3 * _mb));
      await tester.tap(find.text('Очистить 17.0 МБ'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Точно очистить?'), findsOneWidget);

      await tester.tap(find.text('Офлайн-кеш треков'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Точно очистить?'), findsNothing);
      expect(find.text('Очистить 20.0 МБ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
