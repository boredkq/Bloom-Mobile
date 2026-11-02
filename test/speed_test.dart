/// Playback speed: rounding, the label, persistence and the sheet.
///
/// I check what breaks quietly: the slider's step in double leaves tails
/// (`1.3000000000000003` would reach the disk), pitch must follow tempo only
/// with nightcore on, and the value pill must reset to 1×.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/speed_store.dart';
import 'package:bloom/features/player/ui/speed_sheet.dart';
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

/// A screen with a button that opens the speed sheet.
Future<void> _pumpSheet(WidgetTester tester, JsonStore store) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container(store),
      child: MaterialApp(
        // The language is pinned: otherwise text checks would depend on the
        // machine's locale.
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSpeedSheet(context),
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

/// A tap plus running time past the disk write: `JsonStore` delays it by 400
/// ms, and without this the test ends with a pending timer.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The sheet's store: the container lives in the tree, so I get it through the
/// element.
SpeedSettings _speedOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(Scaffold).first),
).read(speedProvider);

void main() {
  group('clampRate', () {
    test('садится на шаг 0.05 и режет хвосты double', () {
      expect(clampRate(1.33), 1.35);
      expect(clampRate(1.32), 1.3);
      expect(clampRate(0.7 + 0.05), 0.75);
      // Exactly on a step: the result must be round, or it leaks into JSON.
      expect(clampRate(1.1500000000000001), 1.15);
    });

    test('держится в границах', () {
      expect(clampRate(0.1), kSpeedMin);
      expect(clampRate(5), kSpeedMax);
      expect(clampRate(kSpeedMin), kSpeedMin);
      expect(clampRate(kSpeedMax), kSpeedMax);
    });

    test('мусор — это 1×', () {
      expect(clampRate(double.nan), 1);
      expect(clampRate(double.infinity), 1);
      expect(clampRate(double.negativeInfinity), 1);
    });
  });

  group('speedLabel', () {
    test('без хвостовых нулей', () {
      expect(speedLabel(1), '1×');
      expect(speedLabel(2), '2×');
      expect(speedLabel(1.5), '1.5×');
      expect(speedLabel(0.75), '0.75×');
      expect(speedLabel(1.35), '1.35×');
    });
  });

  group('стор', () {
    test('умолчание — 1× без nightcore, питч не трогаем', () {
      final speed = _container(JsonStore.memory()).read(speedProvider);
      expect(speed.rate, 1);
      expect(speed.nightcore, isFalse);
      expect(speed.pitch, 1);
    });

    test('nightcore ведёт питч за темпом', () {
      const off = SpeedSettings(rate: 1.25);
      const on = SpeedSettings(rate: 1.25, nightcore: true);
      expect(off.pitch, 1);
      expect(on.pitch, 1.25);
    });

    test('значение переживает перезапуск', () {
      final store = JsonStore.memory();
      final first = _container(store);
      first.read(speedProvider.notifier)
        ..setRate(1.35)
        ..setNightcore(true);

      final second = _container(store).read(speedProvider);
      expect(second.rate, 1.35);
      expect(second.nightcore, isTrue);
    });

    test('битая запись читается как 1×', () {
      final store = JsonStore.memory({
        'speed': {'rate': 'быстро', 'nightcore': 'ага'},
      });
      final speed = _container(store).read(speedProvider);
      expect(speed.rate, 1);
      expect(speed.nightcore, isFalse);
    });

    test('запись за границами подрезается на чтении', () {
      final store = JsonStore.memory({
        'speed': {'rate': 9},
      });
      expect(_container(store).read(speedProvider).rate, kSpeedMax);
    });
  });

  group('шторка', () {
    testWidgets('пресет ставит скорость', (tester) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);

      await _tap(tester, find.text('1.25×'));
      expect(_speedOf(tester).rate, 1.25);
    });

    testWidgets('пилюля значения сбрасывает на 1×', (tester) async {
      final store = JsonStore.memory({
        'speed': {'rate': 1.35},
      });
      await _pumpSheet(tester, store);
      expect(_speedOf(tester).rate, 1.35);

      // The pill is the only place showing the full value: no preset has 1.35×.
      await _tap(tester, find.text('1.35×'));
      expect(_speedOf(tester).rate, 1);
    });

    testWidgets('тумблер nightcore переключается тапом по всей строке', (
      tester,
    ) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);

      await _tap(tester, find.text('1.25×'));
      await _tap(tester, find.text('Тон едет вместе со скоростью'));
      expect(_speedOf(tester).nightcore, isTrue);
      // With nightcore on, pitch follows tempo instead of staying at 1.
      expect(_speedOf(tester).pitch, 1.25);

      await _tap(tester, find.text('Nightcore'));
      expect(_speedOf(tester).nightcore, isFalse);
      expect(_speedOf(tester).pitch, 1);
    });

    testWidgets('полоса ставит своё значение, кратное шагу', (tester) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);

      // I tap the bar's right quarter: the exact value depends on the test
      // screen's width, so I check the step and the side, not the number.
      final track = tester.getRect(find.byType(Slider));
      await tester.tapAt(
        Offset(track.left + track.width * 0.75, track.center.dy),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));

      final rate = _speedOf(tester).rate;
      expect(rate, greaterThan(1));
      expect(rate, lessThanOrEqualTo(kSpeedMax));
      expect(clampRate(rate), rate);
    });
  });
}
