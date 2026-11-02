/// The extended queue view: the setting, splitting into sections and
/// translating numbers.
///
/// I check what breaks quietly. A row has two numbers, in its section
/// (dragging) and in the queue (playing, menu, removing), and nothing stops
/// them being mixed up in the second section: the list looks right and actions
/// hit other rows. Plus the layout: the playing track must be pinned and no
/// section may be empty.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/player_view_store.dart';
import 'package:bloom/features/player/ui/queue_sheet.dart';
import 'package:bloom/l10n/app_localizations.dart';
import 'package:bloom/shared/ui/entity_tiles.dart';
import 'package:bloom/shared/ui/track_swipes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';
import 'package:just_audio/just_audio.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Трек $id',
  artist: 'Артист $id',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

/// A queue with no sound: the real controller reaches for
/// `audioHandlerProvider`, which tests don't have. It records a move instead of
/// making it, so I check which numbers reached it.
class _FakePlayback extends PlaybackController {
  _FakePlayback(this.initial);

  final PlaybackState initial;
  final List<(int, int)> reorders = [];

  @override
  PlaybackState build() => initial;

  @override
  void reorder(int from, int to) => reorders.add((from, to));
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
    test('по умолчанию вид обычный, как на ПК', () {
      final c = _container(JsonStore.memory());
      expect(c.read(queueViewProvider), QueueView.normal);
      expect(c.read(queueViewProvider).isExtended, isFalse);
    });

    test('выбранный вид читается с диска', () {
      final c = _container(
        JsonStore.memory({
          'playerView': {'queueView': 'extended'},
        }),
      );
      expect(c.read(queueViewProvider).isExtended, isTrue);
    });

    test('незнакомая запись — это обычный вид, а не падение', () {
      final c = _container(
        JsonStore.memory({
          'playerView': {'queueView': 'sections'},
        }),
      );
      expect(c.read(queueViewProvider), QueueView.normal);
    });

    test('выбор уезжает на диск и не сносит соседнюю настройку', () {
      final store = JsonStore.memory({
        'playerView': {'titleAlign': 'left'},
      });
      final c = _container(store);
      c.read(queueViewProvider.notifier).set(QueueView.extended);

      final saved = store.read('playerView')! as Map;
      expect(saved['queueView'], 'extended');
      expect(saved['titleAlign'], 'left');
      expect(c.read(titleAlignProvider), TitleAlign.left);
    });
  });

  group('промотка при открытии', () {
    test('обычный вид оставляет две строки запаса сверху', () {
      expect(queueScrollOffset(index: 2, extended: false), 0);
      expect(queueScrollOffset(index: 5, extended: false), 3 * kTrackRowHeight);
    });

    test('расширенный ставит наверх заголовок «Сейчас играет»', () {
      // Above it is the whole Played section, with its own header.
      expect(
        queueScrollOffset(index: 3, extended: true),
        3 * kTrackRowHeight + kQueueSectionLabel,
      );
    });

    test('играет первый — прокручивать нечего, заголовка «Прослушано» нет', () {
      expect(queueScrollOffset(index: 0, extended: true), 0);
    });
  });

  group('секции', () {
    /// A queue sheet with five tracks; [index] is the playing one.
    Future<_FakePlayback> pump(
      WidgetTester tester, {
      required bool extended,
      int index = 2,
      int length = 5,
    }) async {
      final playback = _FakePlayback(
        PlaybackState(
          queue: [
            for (var i = 0; i < length; i++)
              _track(String.fromCharCode(97 + i)),
          ],
          index: index,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jsonStoreProvider.overrideWithValue(
              JsonStore.memory({
                if (extended) 'playerView': {'queueView': 'extended'},
              }),
            ),
            dbProvider.overrideWithValue(BloomDb.memory()),
            playbackProvider.overrideWith(() => playback),
            // The playing row needs a play/pause stream (an equalizer instead
            // of the duration). There's no real sound in tests, so I give it a
            // silent player whose `playingStream` lives in the object itself.
            audioPlayerProvider.overrideWithValue(AudioPlayer()),
          ],
          child: MaterialApp(
            theme: buildBloomTheme(BloomThemes.dark),
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showQueueSheet(context),
                  child: const Text('открыть'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      // Not `pumpAndSettle`: the playing row has an equalizer that doesn't
      // freeze at once on pause, so I run frames myself.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return playback;
    }

    /// Pairs of queue number and section number for every row in the sheet.
    List<(int, int?)> rows(WidgetTester tester) => [
      for (final swipe in tester.widgetList<TrackSwipe>(
        find.byType(TrackSwipe),
      ))
        (swipe.queueIndex!, (swipe.child as dynamic).dragIndex as int?),
    ];

    testWidgets('обычный вид секций не рисует', (tester) async {
      await pump(tester, extended: false);
      expect(find.text('ПРОСЛУШАНО'), findsNothing);
      expect(find.text('СЕЙЧАС ИГРАЕТ'), findsNothing);
      expect(find.text('ДАЛЕЕ'), findsNothing);
      // A row's number in the list and in the queue is the same.
      expect(rows(tester), [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)]);
    });

    testWidgets('расширенный бьёт очередь на три секции', (tester) async {
      await pump(tester, extended: true);
      expect(find.text('ПРОСЛУШАНО'), findsOneWidget);
      expect(find.text('СЕЙЧАС ИГРАЕТ'), findsOneWidget);
      expect(find.text('ДАЛЕЕ'), findsOneWidget);
    });

    testWidgets('номер тянучки — свой в секции, номер очереди — общий', (
      tester,
    ) async {
      await pump(tester, extended: true);
      expect(rows(tester), [
        // Played starts at the queue's zero, so the numbers match.
        (0, 0),
        (1, 1),
        // The playing track is pinned: no drag handle at all.
        (2, null),
        // Up next starts at the queue's third track, and at zero inside itself.
        (3, 0),
        (4, 1),
      ]);
    });

    testWidgets('перестановка в «Далее» уходит номерами очереди', (
      tester,
    ) async {
      final playback = await pump(tester, extended: true);
      final lists = tester
          .widgetList<SliverReorderableList>(find.byType(SliverReorderableList))
          .toList();
      expect(lists, hasLength(2));
      // I drag Up next's first row (third in the queue) to the section's end.
      lists.last.onReorder(0, 2);
      expect(playback.reorders, [(3, 5)]);
    });

    testWidgets('играет первый — секции «Прослушано» нет', (tester) async {
      await pump(tester, extended: true, index: 0);
      expect(find.text('ПРОСЛУШАНО'), findsNothing);
      expect(find.text('СЕЙЧАС ИГРАЕТ'), findsOneWidget);
      expect(find.text('ДАЛЕЕ'), findsOneWidget);
      expect(rows(tester), [(0, null), (1, 0), (2, 1), (3, 2), (4, 3)]);
    });

    testWidgets('играет последний — секции «Далее» нет', (tester) async {
      await pump(tester, extended: true, index: 4);
      expect(find.text('ПРОСЛУШАНО'), findsOneWidget);
      expect(find.text('ДАЛЕЕ'), findsNothing);
    });

    testWidgets('один трек в очереди — только «Сейчас играет»', (tester) async {
      await pump(tester, extended: true, index: 0, length: 1);
      expect(find.text('ПРОСЛУШАНО'), findsNothing);
      expect(find.text('ДАЛЕЕ'), findsNothing);
      expect(find.text('СЕЙЧАС ИГРАЕТ'), findsOneWidget);
      expect(rows(tester), [(0, null)]);
    });
  });
}
