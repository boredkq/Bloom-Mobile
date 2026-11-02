/// Transparency: glass formulas, persistence, the overlay gate and the
/// surfaces.
///
/// I check what breaks quietly. Glass brightness must stay on its formula,
/// since the same number has to give the same glass after a sync. The overlays
/// toggle is a sub-mode: with transparency off there must be no glass anywhere.
/// And the settings slider shows the transparency level, the inverse of what's
/// stored.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/settings/transparency_store.dart';
import 'package:bloom/shared/ui/bloom_sheet.dart';
import 'package:bloom/shared/ui/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// A screen with one glass plate.
Future<void> _pumpBox(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: const Scaffold(
          body: GlassGroup(
            child: GlassBox(child: SizedBox(width: 100, height: 40)),
          ),
        ),
      ),
    ),
  );
}

/// A screen with a button that opens a sheet with no cover.
Future<void> _pumpSheet(
  WidgetTester tester,
  ProviderContainer container,
) async {
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
              onPressed: () => showBloomSheetChild<void>(
                context: context,
                child: const SizedBox(height: 80),
              ),
              child: const Text('открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('открыть'));
  await tester.pumpAndSettle();
}

/// The plate's fill: `GlassBox` paints it with a material.
Color _fillOf(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(
        of: find.byType(GlassBox),
        matching: find.byType(Material),
      ),
    )
    .color!;

void main() {
  group('formulas', () {
    test('glass brightness: the three expected points', () {
      // 0 → 0.4 (dark), 50 → 1.0 (neutral), 100 → 1.8 (light).
      expect(const Transparency(glassStr: 0).brightness, closeTo(0.4, 1e-9));
      expect(const Transparency(glassStr: 25).brightness, closeTo(0.7, 1e-9));
      expect(const Transparency(glassStr: 50).brightness, closeTo(1, 1e-9));
      expect(const Transparency(glassStr: 75).brightness, closeTo(1.4, 1e-9));
      expect(const Transparency(glassStr: 100).brightness, closeTo(1.8, 1e-9));
    });

    test('the transparency level is the inverse of opacity', () {
      expect(const Transparency(blockOpacity: 60).transparencyPercent, 40);
      expect(const Transparency(blockOpacity: 100).transparencyPercent, 0);
      expect(const Transparency(blockOpacity: 0).transparencyPercent, 100);
    });

    test("overlays don't turn on without the main transparency", () {
      const off = Transparency(overlayGlass: true);
      expect(off.overlaysOn, isFalse);
      expect(off.copyWith(on: true).overlaysOn, isTrue);
    });
  });

  group('store', () {
    test('defaults: off, 60/50/12', () {
      final tr = _container(JsonStore.memory()).read(transparencyProvider);
      expect(tr.on, isFalse);
      expect(tr.overlayGlass, isFalse);
      expect(tr.blockOpacity, kTrOpacityDefault);
      expect(tr.glassStr, kTrBrightnessDefault);
      expect(tr.glassBlur, kTrBlurDefault);
    });

    test('the level slider writes opacity to the store', () {
      final store = JsonStore.memory();
      _container(store).read(transparencyProvider.notifier)
        ..setOn(true)
        ..setTransparencyPercent(40);

      final tr = _container(store).read(transparencyProvider);
      expect(tr.on, isTrue);
      expect(tr.blockOpacity, 60);
      expect(tr.transparencyPercent, 40);
    });

    test('values survive a restart', () {
      final store = JsonStore.memory();
      _container(store).read(transparencyProvider.notifier)
        ..setOn(true)
        ..setOverlayGlass(true)
        ..setGlassStr(70)
        ..setGlassBlur(20);

      final tr = _container(store).read(transparencyProvider);
      expect(tr.overlayGlass, isTrue);
      expect(tr.glassStr, 70);
      expect(tr.glassBlur, 20);
    });

    test(
      'a broken entry reads as the default, a too large one gets trimmed',
      () {
        final store = JsonStore.memory({
          'transparency': {
            'on': 'ага',
            'blockOpacity': 'много',
            'glassStr': 500,
            'glassBlur': 999,
          },
        });
        final tr = _container(store).read(transparencyProvider);
        expect(tr.on, isFalse);
        expect(tr.blockOpacity, kTrOpacityDefault);
        expect(tr.glassStr, 100);
        expect(tr.glassBlur, kTrBlurMax);
      },
    );
  });

  group('glass', () {
    test('off: no glass on blocks or overlays', () {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier).setOverlayGlass(true);
      expect(c.read(glassProvider), isNull);
      expect(c.read(overlayGlassProvider), isNull);
    });

    test('on: blocks are glass, overlays wait for their switch', () {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier).setOn(true);
      expect(c.read(glassProvider), isNotNull);
      expect(c.read(overlayGlassProvider), isNull);
      c.read(transparencyProvider.notifier).setOverlayGlass(true);
      expect(c.read(overlayGlassProvider), isNotNull);
    });

    test('neutral glass with no blur needs no filter', () {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier)
        ..setOn(true)
        ..setGlassBlur(0)
        ..setGlassStr(50);
      // Nothing to blur or brighten, so no extra layer.
      expect(c.read(glassProvider)!.filter, isNull);
      c.read(transparencyProvider.notifier).setGlassStr(70);
      expect(c.read(glassProvider)!.filter, isNotNull);
    });
  });

  group('GlassBox', () {
    testWidgets('off: a solid plate with no filter', (tester) async {
      final c = _container(JsonStore.memory());
      await _pumpBox(tester, c);

      expect(_fillOf(tester), BloomThemes.dark.pill);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('on: the fill thins and a filter appears', (tester) async {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier)
        ..setOn(true)
        ..setTransparencyPercent(40);
      await _pumpBox(tester, c);
      await tester.pump();

      expect(_fillOf(tester).a, closeTo(0.6, 0.01));
      expect(find.byType(BackdropFilter), findsOneWidget);
      // `JsonStore` delays its write by 400 ms, and without this the test ends
      // with a pending timer.
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('zero blur and neutral brightness: no filter', (tester) async {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier)
        ..setOn(true)
        ..setGlassBlur(0);
      await _pumpBox(tester, c);
      await tester.pump();

      // The fill stays translucent: glass with no blur is a film.
      expect(_fillOf(tester).a, lessThan(1));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('sheets', () {
    testWidgets('overlay glass reaches both the sheet and the dimming', (
      tester,
    ) async {
      final c = _container(JsonStore.memory());
      c.read(transparencyProvider.notifier)
        ..setOn(true)
        ..setOverlayGlass(true);
      await _pumpSheet(tester, c);

      // Two filters: the sheet's surface and its dimming.
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('without the overlays switch a sheet stays solid', (
      tester,
    ) async {
      final c = _container(JsonStore.memory());
      // Block transparency is on and overlays' is off, which doesn't touch the
      // sheet.
      c.read(transparencyProvider.notifier).setOn(true);
      await _pumpSheet(tester, c);

      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
