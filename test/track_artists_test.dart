/// A track's artists: one opens at once, several in a sheet with avatars,
/// where only those with a page can be opened.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/detail/artists_sheet.dart';
import 'package:bloom/features/detail/ui/artist_screen.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/shared/ui/atoms.dart';
import 'package:bloom/shared/ui/bloom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/shared/ui/pressable.dart';
import 'package:bloom/shared/util/artists.dart';

Artist _artist(String name, {String? avatar}) => Artist(
  id: 'sc:artist:$name',
  name: name,
  avatar: avatar,
  source: MusicSource.soundcloud,
);

// No uploader's page: the line is split into names.
Track _track(String artist, {String? artistId}) => Track(
  id: 'sc:1',
  name: 'Песня',
  artist: artist,
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
  artistId: artistId,
);

class _FakeSoundCloud extends MusicProvider {
  _FakeSoundCloud(this.answers);

  /// What to answer for a name. A name missing from the map means the platform
  /// is silent.
  final Map<String, List<Artist>> answers;

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<List<Artist>> searchArtists(String query, {int limit = 3}) async =>
      answers[query] ?? const [];
}

/// A player with no sound: the artist page watches the queue for its Play/Pause
/// button, and the real controller reaches for `audioHandlerProvider`, which
/// tests don't have. Nothing plays, so the button stays on Play.
class _SilentPlayback extends PlaybackController {
  @override
  PlaybackState build() => const PlaybackState();
}

/// A screen with a button that opens the artist choice.
Future<void> _pump(
  WidgetTester tester,
  Track track,
  _FakeSoundCloud provider,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jsonStoreProvider.overrideWithValue(JsonStore.memory()),
        dbProvider.overrideWithValue(BloomDb.memory()),
        registryProvider.overrideWithValue(
          ProviderRegistry()..register(provider),
        ),
        playbackProvider.overrideWith(_SilentPlayback.new),
      ],
      child: MaterialApp(
        // The language is pinned: otherwise text checks would depend on the
        // machine's locale.
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => openTrackArtist(context, ref, track),
              child: const Text('артист'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Links of the avatars now on screen.
List<String?> _avatars(WidgetTester tester) => [
  for (final c in tester.widgetList<Cover>(find.byType(Cover)))
    if (c.circle) c.url,
];

/// Does the sheet's row respond to a press?
bool _enabled(WidgetTester tester, String name) {
  final row = find.ancestor(
    of: find.text(name),
    matching: find.byType(Pressable),
  );
  return tester.widget<Pressable>(row.first).onTap != null;
}

void main() {
  testWidgets('несколько артистов — шторка с аватарками', (tester) async {
    final sc = _FakeSoundCloud({
      'Kanye West': [_artist('Kanye West', avatar: 'https://cdn/ye.jpg')],
      'Ty Dolla Sign': [_artist('Ty Dolla Sign', avatar: 'https://cdn/ty.jpg')],
    });
    await _pump(tester, _track('Kanye West & Ty Dolla Sign'), sc);

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();

    // Both names are rows, not one link to whoever uploaded the track.
    expect(find.text('Kanye West'), findsOneWidget);
    expect(find.text('Ty Dolla Sign'), findsOneWidget);
    expect(
      _avatars(tester),
      containsAll(['https://cdn/ye.jpg', 'https://cdn/ty.jpg']),
    );
    // Bloom shows no platform followers: nothing under the name.
    expect(find.textContaining('подписч'), findsNothing);
  });

  testWidgets('к незнакомому площадке артисту ходить некуда', (tester) async {
    final sc = _FakeSoundCloud({
      'Boards of Canada': [_artist('Boards of Canada')],
    });
    await _pump(tester, _track('Boards of Canada, Кто-то ещё'), sc);

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();

    expect(find.text('Не нашли у площадки'), findsOneWidget);
    expect(_enabled(tester, 'Кто-то ещё'), isFalse);
    expect(_enabled(tester, 'Boards of Canada'), isTrue);
  });

  testWidgets('выбранный в шторке артист открывает свою страницу', (
    tester,
  ) async {
    final sc = _FakeSoundCloud({
      'Aphex Twin': [_artist('Aphex Twin')],
      'Squarepusher': [_artist('Squarepusher')],
    });
    await _pump(tester, _track('Aphex Twin vs. Squarepusher'), sc);

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Squarepusher'));
    await tester.pumpAndSettle();

    expect(find.byType(ArtistScreen), findsOneWidget);
  });

  testWidgets('один артист без точного id — тапать нечего', (tester) async {
    final sc = _FakeSoundCloud(const {});
    final track = Track(
      id: 'sc:2',
      name: 'Песня',
      artist: 'Onda',
      duration: const Duration(minutes: 3),
      source: MusicSource.soundcloud,
    );
    await _pump(tester, track, sc);

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();

    // No sheet and no jump: searching by name with nothing to choose from would
    // lead astray.
    expect(find.byType(SheetPanel), findsNothing);
    expect(find.byType(ArtistScreen), findsNothing);
  });

  testWidgets('a SoundCloud line with a page is one account', (tester) async {
    final sc = _FakeSoundCloud(const {});
    await _pump(
      tester,
      _track('Simon & Garfunkel', artistId: 'sc:artist:sg'),
      sc,
    );

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();

    expect(find.byType(SheetPanel), findsNothing);
    expect(find.byType(ArtistScreen), findsOneWidget);
  });

  testWidgets('known pages open without a search', (tester) async {
    final sc = _FakeSoundCloud(const {});
    final track = Track(
      id: 'ym:1',
      name: 'Песня',
      artist: 'Один, Другой',
      duration: const Duration(minutes: 3),
      source: MusicSource.yandex,
      artistId: 'ym:artist:1',
      artists: const [
        (name: 'Один', id: 'ym:artist:1'),
        (name: 'Другой', id: null),
      ],
    );
    await _pump(tester, track, sc);

    await tester.tap(find.text('артист'));
    await tester.pumpAndSettle();

    // No Yandex to ask: the one with a page still opens, the other doesn't.
    expect(_enabled(tester, 'Один'), isTrue);
    expect(_enabled(tester, 'Другой'), isFalse);
  });

  group('artistLinks', () {
    Track t({
      String artist = 'A, B',
      MusicSource source = MusicSource.yandex,
      String? artistId = 'ym:artist:1',
      List<ArtistLink> artists = const [
        (name: 'A', id: 'ym:artist:1'),
        (name: 'B', id: 'ym:artist:2'),
      ],
      bool edited = false,
    }) => Track(
      id: 'ym:9',
      name: 'x',
      artist: artist,
      duration: Duration.zero,
      source: source,
      artistId: artistId,
      artists: artists,
      edited: edited,
    );

    test("the platform's list gives every page", () {
      expect(artistLinks(t()).map((l) => l.id), ['ym:artist:1', 'ym:artist:2']);
    });

    test('a line edited away from the list falls back to names', () {
      expect(artistLinks(t(artist: 'A, C')), [
        (name: 'A', id: null),
        (name: 'C', id: null),
      ]);
    });

    test('hand-edited tags drop the ids', () {
      expect(artistLinks(t(edited: true)).map((l) => l.id), [null, null]);
      expect(artistLinks(t(artist: 'A', artists: const [], edited: true)), [
        (name: 'A', id: null),
      ]);
    });

    test('the unknown artist is no one', () {
      expect(artistLinks(t(artist: 'Неизвестен', artists: const [])), isEmpty);
    });

    test('the list survives the round trip', () {
      final back = Track.fromJson(t().toJson())!;
      expect(back.artists, t().artists);
      final m = t(edited: true).toJson();
      expect((m['extra'] as Map)['artists'], [
        {'id': '1', 'name': 'A'},
        {'id': '2', 'name': 'B'},
      ]);
      expect(Track.fromJson(m)!.edited, isTrue);
    });
  });
}
