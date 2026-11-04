/// The wave's interface: the stage atop the home screen and the dislikes sheet.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/wave/ui/wave_dislikes_sheet.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/ui/mini_player.dart';
import 'package:bloom/features/wave/ui/vibe.dart';
import 'package:bloom/features/wave/ui/wave_hero.dart';
import 'package:bloom/shared/ui/atoms.dart';
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
  group('the wave scene on home', () {
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
          children: [WaveHero(scroll: scroll)],
        ),
      );
    }

    testWidgets('an empty player: My Wave, no wave row with no data', (
      tester,
    ) async {
      await hero(tester, _container());
      await settle(tester);

      expect(find.text('Моя волна'), findsOneWidget);
      // An empty library: nothing for My Wave to start from, so no row.
      expect(find.text('Встряхнуть Мою волну'), findsNothing);
    });

    testWidgets('a long press on My Wave opens its setup', (tester) async {
      await hero(tester, _container());
      await settle(tester);

      await tester.longPress(find.text('Моя волна'));
      await settle(tester);

      expect(find.text('Дизлайки'), findsOneWidget);
      expect(find.text('SoundCloud'), findsOneWidget);
      expect(find.text('Яндекс.Музыка'), findsOneWidget);
    });

    testWidgets('something plays: artist and title instead of My Wave', (
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

    testWidgets('a track coming moves nothing on the stage', (tester) async {
      // The bars' inset grows by the mini player's room when a track comes.
      Future<(Offset, Rect)> stage(Track? playing, double inset) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await _pump(
          tester,
          _container(playing: playing),
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: EdgeInsets.only(bottom: inset)),
              child: CustomScrollView(
                controller: scroll,
                slivers: [SliverToBoxAdapter(child: WaveHero(scroll: scroll))],
              ),
            ),
          ),
        );
        await settle(tester);
        final vibe = find.byType(Vibe);
        return (tester.widget<Vibe>(vibe).center, tester.getRect(vibe));
      }

      const nav = 76.0;
      final empty = await stage(null, nav);
      final playing = await stage(
        _track('sc:1'),
        nav + kMiniCardHeight + kFloatGap,
      );
      expect(playing, empty);

      // Swapping the scope leaves a timer behind.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('dislikes sheet', () {
    testWidgets('an empty list explains itself', (tester) async {
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

    testWidgets('a row shows the track, the cross removes the mark', (
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
