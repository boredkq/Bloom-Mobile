/// The sleep timer: time, persistence and the sheet.
///
/// I check what breaks quietly: the deadline goes by the wall clock (`endsAt`),
/// "+5 minutes" counts from the deadline, not from now, the button's label
/// rounds seconds up, and only settings reach the disk: an active timer must
/// not survive a restart.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/sleep_timer_store.dart';
import 'package:bloom/features/player/ui/sleep_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

/// The test's clock: I won't really wait half an hour.
DateTime _now = DateTime(2026, 8, 15, 23, 30);

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
      sleepClockProvider.overrideWithValue(() => _now),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// A screen with a button that opens the timer sheet.
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
              onPressed: () => showSleepSheet(context),
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

SleepTimerController _ctrlOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(Scaffold).first),
).read(sleepTimerProvider.notifier);

SleepTimerState _stateOf(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(Scaffold).first),
).read(sleepTimerProvider);

/// A tap plus running time past the disk write (`JsonStore` delays it by 400
/// ms). `pumpAndSettle` won't do: a running timer ticks each second and redraws
/// the sheet, so it never settles.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Stops the timer at the end of a test, or its tick stays and `testWidgets`
/// fails on "A Timer is still pending".
void _stop(WidgetTester tester) => _ctrlOf(tester).cancel();

void main() {
  setUp(() => _now = DateTime(2026, 8, 15, 23, 30));

  group('sleepLabel', () {
    test('mm:ss under an hour', () {
      expect(sleepLabel(const Duration(minutes: 23, seconds: 14)), '23:14');
      expect(sleepLabel(const Duration(minutes: 5)), '5:00');
      expect(sleepLabel(const Duration(seconds: 9)), '0:09');
    });

    test('h:mm from an hour on', () {
      expect(sleepLabel(const Duration(hours: 1)), '1:00');
      expect(sleepLabel(const Duration(minutes: 90)), '1:30');
      expect(sleepLabel(const Duration(minutes: 120)), '2:00');
      // This form shows no seconds and doesn't fudge the minute with them:
      // "1:05" stays for the whole fifth minute rather than flashing "1:06" for
      // its first half.
      expect(
        sleepLabel(const Duration(hours: 1, minutes: 5, seconds: 30)),
        '1:05',
      );
    });

    test("seconds round up: while sound plays there can't be a zero", () {
      expect(sleepLabel(const Duration(milliseconds: 200)), '0:01');
      expect(
        sleepLabel(const Duration(seconds: 44, milliseconds: 200)),
        '0:45',
      );
      expect(sleepLabel(Duration.zero), '0:00');
      expect(sleepLabel(const Duration(seconds: -5)), '0:00');
    });
  });

  group('store', () {
    test('the default: no timer, fade on', () {
      final sleep = _container(JsonStore.memory()).read(sleepTimerProvider);
      expect(sleep.mode, SleepMode.off);
      expect(sleep.active, isFalse);
      expect(sleep.expired, isFalse);
      expect(sleep.fade, isTrue);
      expect(sleep.choice, const Duration(minutes: 30));
    });

    test('start sets the deadline by the wall clock', () {
      final c = _container(JsonStore.memory());
      c.read(sleepTimerProvider.notifier).start(const Duration(minutes: 15));

      final sleep = c.read(sleepTimerProvider);
      expect(sleep.mode, SleepMode.timer);
      expect(sleep.endsAt, _now.add(const Duration(minutes: 15)));
      expect(sleep.remaining, const Duration(minutes: 15));
      expect(sleep.choice, const Duration(minutes: 15));
      c.read(sleepTimerProvider.notifier).cancel();
    });

    test('+5 minutes counts from the deadline, not from now', () {
      final c = _container(JsonStore.memory());
      final ctrl = c.read(sleepTimerProvider.notifier);
      final started = _now;
      ctrl.start(const Duration(minutes: 30));

      // 29 minutes passed, one to go.
      _now = started.add(const Duration(minutes: 29));
      ctrl.extend();

      expect(
        c.read(sleepTimerProvider).endsAt,
        started.add(const Duration(minutes: 35)),
      );
      // Not "5 minutes from now" but "one minute plus five".
      expect(c.read(sleepTimerProvider).remaining, const Duration(minutes: 6));
      ctrl.cancel();
    });

    test('+5 minutes with no timer does nothing', () {
      final c = _container(JsonStore.memory());
      c.read(sleepTimerProvider.notifier).extend();
      expect(c.read(sleepTimerProvider).mode, SleepMode.off);
      expect(c.read(sleepTimerProvider).endsAt, isNull);
    });

    test('until the track ends is a mode with no deadline', () {
      final c = _container(JsonStore.memory());
      final ctrl = c.read(sleepTimerProvider.notifier);
      ctrl.start(const Duration(minutes: 45));
      ctrl.untilTrackEnd();

      final sleep = c.read(sleepTimerProvider);
      expect(sleep.mode, SleepMode.endOfTrack);
      expect(sleep.active, isTrue);
      // No deadline, nothing to wait for, and `expired` mustn't fire: the
      // track's end does the pause.
      expect(sleep.endsAt, isNull);
      expect(sleep.expired, isFalse);
    });

    test('cancel removes both the mode and the deadline', () {
      final c = _container(JsonStore.memory());
      final ctrl = c.read(sleepTimerProvider.notifier);
      ctrl.start(const Duration(minutes: 15));
      ctrl.cancel();

      final sleep = c.read(sleepTimerProvider);
      expect(sleep.mode, SleepMode.off);
      expect(sleep.endsAt, isNull);
      expect(sleep.remaining, Duration.zero);
    });

    test("settings reach the disk, a running timer doesn't", () {
      final store = JsonStore.memory();
      final first = _container(store);
      first.read(sleepTimerProvider.notifier)
        ..setFade(false)
        ..start(const Duration(minutes: 45));
      first.read(sleepTimerProvider.notifier).cancel();

      final second = _container(store).read(sleepTimerProvider);
      expect(second.fade, isFalse);
      expect(second.choice, const Duration(minutes: 45));
      // A restart is silence: nobody to wake.
      expect(second.mode, SleepMode.off);
      expect(second.endsAt, isNull);
    });

    test(
      "a broken entry reads as defaults, the time within the bar's bounds",
      () {
        final broken = JsonStore.memory({
          'sleep': {'minutes': 'скоро', 'fade': 'ага'},
        });
        final sleep = _container(broken).read(sleepTimerProvider);
        expect(sleep.choice, const Duration(minutes: 30));
        expect(sleep.fade, isTrue);

        final huge = JsonStore.memory({
          'sleep': {'minutes': 9000},
        });
        expect(
          _container(huge).read(sleepTimerProvider).choice,
          const Duration(minutes: kSleepMaxMinutes),
        );
      },
    );
  });

  group('tick', () {
    testWidgets("what's left shrinks and stops at zero", (tester) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);

      await _tap(tester, find.text('15 мин').first);
      expect(_stateOf(tester).remaining, const Duration(minutes: 15));

      // I move the store's clock myself: a tick just recounts what's left from
      // it.
      _now = _now.add(const Duration(minutes: 14, seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(_stateOf(tester).remaining, const Duration(seconds: 30));
      expect(_stateOf(tester).expired, isFalse);

      _now = _now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      // Zero is the signal to the player to pause. The timer doesn't remove
      // itself.
      expect(_stateOf(tester).remaining, Duration.zero);
      expect(_stateOf(tester).expired, isTrue);

      _stop(tester);
    });
  });

  group('sheet', () {
    testWidgets('a preset starts the timer, a second tap removes it', (
      tester,
    ) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);

      await _tap(tester, find.text('30 мин').first);
      expect(_stateOf(tester).mode, SleepMode.timer);
      expect(_stateOf(tester).choice, const Duration(minutes: 30));

      await _tap(tester, find.text('30 мин').first);
      expect(_stateOf(tester).mode, SleepMode.off);
    });

    testWidgets('until the track ends toggles by a tap', (tester) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);

      await _tap(tester, find.text('До конца трека').last);
      expect(_stateOf(tester).mode, SleepMode.endOfTrack);

      await _tap(tester, find.text('До конца трека').last);
      expect(_stateOf(tester).mode, SleepMode.off);
    });

    testWidgets('+5 minutes and Turn off show only with a timer', (
      tester,
    ) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);
      expect(find.text('+5 минут'), findsNothing);
      expect(find.text('Выключить таймер'), findsNothing);

      await _tap(tester, find.text('45 мин').first);
      expect(find.text('+5 минут'), findsOneWidget);

      await _tap(tester, find.text('+5 минут'));
      expect(_stateOf(tester).remaining, const Duration(minutes: 50));

      await _tap(tester, find.text('Выключить таймер'));
      expect(_stateOf(tester).mode, SleepMode.off);

      // "Until the track ends" has nothing to extend, so no button.
      await _tap(tester, find.text('До конца трека').last);
      expect(find.text('+5 минут'), findsNothing);
      expect(find.text('Выключить таймер'), findsOneWidget);
      _stop(tester);
    });

    testWidgets("what's left shows in the header", (tester) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);

      await _tap(tester, find.text('60 мин').first);
      expect(find.text('Осталось 1:00'), findsOneWidget);
      _stop(tester);
    });

    testWidgets('the fade tile toggles by a tap', (tester) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);
      expect(_stateOf(tester).fade, isTrue);

      await _tap(tester, find.text('Плавное затухание'));
      expect(_stateOf(tester).fade, isFalse);

      await _tap(tester, find.text('Плавное затухание'));
      expect(_stateOf(tester).fade, isTrue);
    });

    testWidgets('the bar moves the deadline under the finger', (tester) async {
      final store = JsonStore.memory();
      await _pumpSheet(tester, store);

      // I tap the bar's left quarter: the exact value depends on the test
      // screen's width, so I check the step and the side, not the number.
      final slider = tester.getRect(find.byType(Slider));
      await tester.tapAt(
        Offset(slider.left + slider.width * 0.25, slider.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final sleep = _stateOf(tester);
      expect(sleep.mode, SleepMode.timer);
      expect(sleep.choice.inMinutes % kSleepStepMinutes, 0);
      expect(sleep.choice.inMinutes, lessThan(kSleepMaxMinutes ~/ 2));
      expect(sleep.choice.inMinutes, greaterThanOrEqualTo(kSleepMinMinutes));
      _stop(tester);
    });
  });
}
