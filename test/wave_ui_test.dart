/// The wave's interface: the stage atop the home screen and the dislikes sheet.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/wave/ui/wave_dislikes_sheet.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/wave/ui/wave_hero.dart';
import 'package:bloom/features/wave/wave_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/glyphs.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';

Track _track(String id, {String? cover}) => Track(
  id: id,
  name: 'Song $id',
  artist: 'Artist $id',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
  cover: cover,
);

class _FakePlayback extends PlaybackController {
  _FakePlayback(this.initial);

  final PlaybackState initial;

  @override
  PlaybackState build() => initial;
}

ProviderContainer _container({JsonStore? store, Track? playing}) {
  final json = store ?? JsonStore.memory();
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(json),
      dbProvider.overrideWithValue(testDb(json)),
      playbackProvider.overrideWith(
        () => _FakePlayback(PlaybackState(queue: [?playing], index: 0)),
      ),
      playingNowProvider.overrideWithValue(false),
      playheadProvider.overrideWith(
        (ref) => Stream.value((position: Duration.zero, total: Duration.zero)),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildBloomTheme(BloomThemes.dark),
      home: Scaffold(body: child),
    ),
  ),
);

void main() {
  group('сцена волны на главной', () {
    // The circle runs on a ticker for good: no `pumpAndSettle`, frames by hand.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> hero(WidgetTester tester, ProviderContainer c) {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      return _pump(
        tester,
        c,
        ListView(
          controller: scroll,
          children: [WaveHero(header: const SizedBox(), scroll: scroll)],
        ),
      );
    }

    testWidgets('плеер пуст — «Моя волна», ряда волн без данных нет', (
      tester,
    ) async {
      await hero(tester, _container());
      await settle(tester);

      expect(find.text('Моя волна'), findsOneWidget);
      // An empty library: nothing for My Wave to start from, so no row.
      expect(find.text('Встряхнуть Мою волну'), findsNothing);
    });

    testWidgets('долгое нажатие по «Моей волне» открывает настройку', (
      tester,
    ) async {
      await hero(tester, _container());
      await settle(tester);

      await tester.longPress(find.text('Моя волна'));
      await settle(tester);

      expect(find.text('Дизлайки'), findsOneWidget);
      expect(find.text('SoundCloud'), findsOneWidget);
      expect(find.text('Яндекс.Музыка'), findsOneWidget);
    });

    testWidgets('что-то играет — артист и название вместо «Моей волны»', (
      tester,
    ) async {
      await hero(tester, _container(playing: _track('sc:1')));
      await settle(tester);

      expect(find.text('Моя волна'), findsNothing);
      expect(find.text('Artist sc:1'), findsOneWidget);
      expect(find.text('Song sc:1'), findsOneWidget);
      expect(findGlyph(Bi.dislike), findsOneWidget);
      expect(findGlyph(Bi.heart), findsOneWidget);
    });
  });

  group('шторка дизлайков', () {
    testWidgets('пустой список объясняет себя словами', (tester) async {
      final container = _container();
      await _pump(
        tester,
        container,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showWaveDislikesSheet(context),
            child: const Text('открыть'),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();

      expect(find.text('Дизлайков пока нет'), findsOneWidget);
    });

    testWidgets('строка показывает трек, крестик снимает метку', (
      tester,
    ) async {
      final container = _container();
      container.read(waveStoreProvider.notifier).toggleDislike(_track('sc:1'));

      await _pump(
        tester,
        container,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showWaveDislikesSheet(context),
            child: const Text('открыть'),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();

      expect(find.text('Song sc:1'), findsOneWidget);
      expect(find.text('Artist sc:1'), findsOneWidget);

      // The row's cross is the second round icon, after "clear all" in the
      // header.
      await tester.tap(findGlyph(Bi.close));
      await tester.pumpAndSettle();

      expect(container.read(waveStoreProvider).isDisliked('sc:1'), isFalse);
      expect(find.text('Дизлайков пока нет'), findsOneWidget);
      // The file write is delayed, so I wait for it, or the test ends with a
      // pending timer.
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
