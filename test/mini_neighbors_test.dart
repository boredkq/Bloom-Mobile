/// Neighbor tracks, the mini player's carousel: the setting, the geometry and
/// the gesture.
///
/// I check what breaks quietly: a neighbor's strip must fit the screen's normal
/// margin (or the card just gets thinner for nothing), a carousel step must
/// replace the middle with the neighbor exactly, a neighbor row must show no
/// foreign progress and catch no taps, and a flip in the carousel mustn't slide
/// in from the other edge over the card that already arrived.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/mini_style_store.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/ui/mini_player.dart';
import 'package:bloom/features/player/ui/play_button.dart';
import 'package:bloom/l10n/app_localizations.dart';
import 'package:bloom/shared/ui/atoms.dart';
import 'package:bloom/shared/ui/track_flick.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Трек $id',
  artist: 'Артист $id',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

/// A queue with no sound: the real controller reaches for
/// `audioHandlerProvider`, which tests don't have, and the card's row only
/// needs the list.
class _FakePlayback extends PlaybackController {
  _FakePlayback(this.initial);

  final PlaybackState initial;

  @override
  PlaybackState build() => initial;
}

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

void main() {
  group('настройка', () {
    test('по умолчанию соседей нет', () {
      expect(
        _container(JsonStore.memory()).read(miniStyleProvider).neighbors,
        isFalse,
      );
    });

    test('включённые читаются с диска', () {
      final c = _container(
        JsonStore.memory({
          'miniStyle': {'neighbors': true},
        }),
      );
      expect(c.read(miniStyleProvider).neighbors, isTrue);
    });

    test('битая запись — это «выключено», а не падение', () {
      final c = _container(
        JsonStore.memory({
          'miniStyle': {'neighbors': 'yes'},
        }),
      );
      expect(c.read(miniStyleProvider).neighbors, isFalse);
    });

    test('выбор уезжает на диск и не сносит соседние настройки', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(miniStyleProvider.notifier).setRadius(MiniRadius.pill);
      c.read(miniStyleProvider.notifier).setNeighbors(true);

      final saved = store.read('miniStyle')! as Map;
      expect(saved['neighbors'], isTrue);
      expect(saved['radius'], 'pill');
    });
  });

  group('геометрия', () {
    const screen = Size(360, 800);

    Rect card({required bool neighbors}) =>
        miniCardRect(screen: screen, navInset: 58, neighbors: neighbors);

    test('без соседей карточка стоит как стояла — поля по 8', () {
      expect(card(neighbors: false).left, kFloatGap);
      expect(card(neighbors: false).width, screen.width - kFloatGap * 2);
    });

    test('полоска соседа упирается в край экрана', () {
      final rect = card(neighbors: true);
      // The left neighbor's right edge: it stands one step left of the card.
      // The neighbor layer starts at the screen's edge, so this is a screen
      // coordinate already, and also the visible strip's width.
      final edge = rect.left - miniStride(rect.width) + rect.width;
      expect(edge, kMiniPeek);
      // The gap to the card is the normal margin, not on top of it.
      expect(rect.left - edge, kFloatGap);
    });

    test('шаг карусели ставит соседа ровно на место карточки', () {
      final rect = card(neighbors: true);
      final stride = miniStride(rect.width);
      expect(rect.left - stride + stride, rect.left);
      // Between cards there's the same gap as at the screen's edges.
      expect(stride - rect.width, kFloatGap);
    });

    test('карточка ужимается ровно на две полоски', () {
      // The gap between the strip and the card comes from the normal margin, so
      // the card loses nothing beyond the strips themselves.
      expect(
        card(neighbors: false).width - card(neighbors: true).width,
        kMiniPeek * 2,
      );
    });
  });

  group('строка соседа', () {
    /// The playing row isn't built here at all: its indicators and play button
    /// reach for a live player tests don't have. That also keeps the
    /// no-foreign-progress check honest: a progress line, on by default, would
    /// crash the test on a neighbor.
    Future<void> pump(WidgetTester tester, {required bool neighbor}) async {
      final queue = [_track('a'), _track('b')];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jsonStoreProvider.overrideWithValue(
              JsonStore.memory({
                // The progress line is on by default, so I check on it that a
                // neighbor gets no foreign progress.
                'miniStyle': {'neighbors': true},
              }),
            ),
            dbProvider.overrideWithValue(BloomDb.memory()),
            playbackProvider.overrideWith(
              () => _FakePlayback(PlaybackState(queue: queue, index: 0)),
            ),
          ],
          child: MaterialApp(
            theme: buildBloomTheme(BloomThemes.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              // The card's width, not the whole screen's: at full test width
              // the labels drift apart and there's nothing to check.
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: MiniCardRow(neighbor: neighbor ? queue[1] : null),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('показывает СВОЙ трек, а не играющий', (tester) async {
      await pump(tester, neighbor: true);
      expect(find.text('Трек b'), findsOneWidget);
      expect(find.text('Трек a'), findsNothing);
    });

    testWidgets('кнопки стоят, но не нажимаются', (tester) async {
      await pump(tester, neighbor: true);
      // The default is the skip trio: a neighbor has the same layout, or the
      // label would jump on the way in. Play is a separate [PlayButton], skip
      // buttons are atom circles, so I count them apart.
      final buttons = tester
          .widgetList<CircleIconButton>(find.byType(CircleIconButton))
          .toList();
      expect(buttons, hasLength(2));
      expect(buttons.every((b) => b.onTap == null), isTrue);
      expect(find.byType(PlayButton), findsOneWidget);
      // A dead button has no press at all: no `InkWell` inside, so there's no
      // `onTap` to check.
      expect(
        find.descendant(
          of: find.byType(PlayButton),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });
  });

  group('жест карусели', () {
    Future<double> flick(
      WidgetTester tester, {
      required bool carousel,
      required double dx,
    }) async {
      final shift = ValueNotifier<double>(0);
      addTearDown(shift.dispose);
      var flips = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 64,
              child: TrackFlick(
                shift: shift,
                carousel: carousel,
                onLeft: () => flips++,
                builder: (context, value) => CarouselSlide(
                  shift: value,
                  stride: 308,
                  child: Container(color: const Color(0xFF101010)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(TrackFlick), Offset(dx, 0));
      await tester.pumpAndSettle();
      expect(flips, dx.abs() > 100 ? 1 : 0);
      return shift.value;
    }

    testWidgets('перелистнули — карточка стоит на месте, без въезда', (
      tester,
    ) async {
      // The neighbor already arrived in the middle: nothing to bring in from
      // the other edge, and the shift must be exactly zero.
      expect(await flick(tester, carousel: true, dx: -200), 0);
    });

    testWidgets('не дотянули — сдвиг возвращается', (tester) async {
      expect(await flick(tester, carousel: true, dx: -20), 0);
    });

    testWidgets('чужой сдвиг живёт дольше жеста', (tester) async {
      // The carousel moves its neighbors with it too: `TrackFlick` must not
      // dispose it, or the neighbor layer would listen to a dead
      // `ValueNotifier`.
      final shift = ValueNotifier<double>(0);
      addTearDown(shift.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TrackFlick(
            shift: shift,
            carousel: true,
            onLeft: () {},
            builder: (context, value) => const SizedBox(width: 300, height: 64),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => shift.value = 0.5, returnsNormally);
    });
  });
}
