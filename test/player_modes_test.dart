/// How the full player's repeat and shuffle buttons show their modes.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/ui/full_player.dart';
import 'package:bloom/l10n/app_localizations.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/glyphs.dart';

class _FakePlayback extends PlaybackController {
  _FakePlayback(this.initial);

  final PlaybackState initial;

  @override
  PlaybackState build() => initial;
}

const _track = Track(
  id: 'sc:1',
  name: 'Трек',
  artist: 'Артист',
  duration: Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

Future<void> _pump(
  WidgetTester tester, {
  PlayerRepeat repeat = PlayerRepeat.off,
  bool shuffle = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jsonStoreProvider.overrideWithValue(JsonStore.memory({})),
        dbProvider.overrideWithValue(BloomDb.memory()),
        playbackProvider.overrideWith(
          () => _FakePlayback(
            PlaybackState(
              queue: const [_track],
              index: 0,
              repeat: repeat,
              shuffle: shuffle,
            ),
          ),
        ),
        playingProvider.overrideWith((ref) => Stream.value(false)),
        playingNowProvider.overrideWithValue(false),
        playheadProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: MaterialApp(
        theme: buildBloomTheme(BloomThemes.dark),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FullPlayerBody(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// The last icon of this kind: the source pill above may show a small shuffle.
Color _colorOf(WidgetTester tester, BloomGlyph glyph) =>
    tester.widget<BloomIcon>(findGlyph(glyph).last).color!;

void main() {
  final t = BloomThemes.dark;
  final dimmed = t.iconFg.withValues(alpha: 0.5);

  testWidgets('both off: the plain icons at half brightness', (tester) async {
    await _pump(tester);
    expect(_colorOf(tester, Bi.repeat), dimmed);
    expect(_colorOf(tester, Bi.shuffle), dimmed);
    expect(findGlyph(Bi.repeatOne), findsNothing);
  });

  testWidgets('repeat all: the same loop, lit', (tester) async {
    await _pump(tester, repeat: PlayerRepeat.all);
    expect(_colorOf(tester, Bi.repeat), t.accent);
    expect(findGlyph(Bi.repeatOne), findsNothing);
  });

  testWidgets('repeat one: the loop with a 1 inside, lit', (tester) async {
    await _pump(tester, repeat: PlayerRepeat.one);
    expect(_colorOf(tester, Bi.repeatOne), t.accent);
    expect(findGlyph(Bi.repeat), findsNothing);
  });

  testWidgets('shuffle on: lit', (tester) async {
    await _pump(tester, shuffle: true);
    expect(_colorOf(tester, Bi.shuffle), t.accent);
  });
}
