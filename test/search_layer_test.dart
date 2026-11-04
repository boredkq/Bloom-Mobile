/// Search as a layer: it opens over the page, keeps what it found between
/// openings, and hides the page only while results cover it.
library;

import 'dart:async';

import 'package:bloom/app/providers.dart';
import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/search/search_session.dart';
import 'package:bloom/features/search/ui/search_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_db.dart';

Track _track(String name) => Track(
  id: 'sc:$name',
  name: name,
  artist: 'A',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

class _SilentPlayback extends PlaybackController {
  @override
  PlaybackState build() => const PlaybackState();
}

/// Answers each query with a track named after it, or waits for [hold].
class _FakeProvider extends MusicProvider {
  Completer<void>? hold;

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    await hold?.future;
    return SearchResults(tracks: [_track('found $query')]);
  }
}

ProviderContainer _container() {
  final store = JsonStore.memory();
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
      playbackProvider.overrideWith(_SilentPlayback.new),
      registryProvider.overrideWithValue(
        ProviderRegistry()..register(_FakeProvider()),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// A page counting its builds and creations, under a navigator of its own.
class _Page extends StatefulWidget {
  const _Page();

  static int created = 0;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void initState() {
    super.initState();
    _Page.created++;
  }

  @override
  Widget build(BuildContext context) => const Text('page');
}

final _navigator = GlobalKey<NavigatorState>();

Future<ProviderContainer> _app(WidgetTester tester) async {
  _Page.created = 0;
  final c = _container();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: _navigator,
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: const Scaffold(body: _Page()),
      ),
    ),
  );
  return c;
}

Future<void> _open(WidgetTester tester) async {
  openSearchIn(_navigator.currentState!);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(EditableText), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

Finder get _page => find.text('page');

void main() {
  testWidgets('opens over the page, which stays as it was', (tester) async {
    await _app(tester);
    await _open(tester);

    expect(searchOpen.value, isTrue);
    expect(find.byType(EditableText), findsOneWidget);
    expect(_page, findsOneWidget);

    closeSearch();
    await tester.pumpAndSettle();

    expect(searchOpen.value, isFalse);
    expect(find.byType(EditableText), findsNothing);
    expect(_Page.created, 1);
  });

  testWidgets('results hide the page, an emptied field shows it again', (
    tester,
  ) async {
    await _app(tester);
    await _open(tester);
    await _submit(tester, 'q');

    expect(find.text('found q'), findsOneWidget);
    expect(_page, findsNothing);

    await tester.enterText(find.byType(EditableText), '');
    await tester.pumpAndSettle();

    expect(find.text('found q'), findsNothing);
    expect(_page, findsOneWidget);
    expect(_Page.created, 1);

    closeSearch();
    await tester.pumpAndSettle();
  });

  testWidgets('closing brings the page back; reopening, the results', (
    tester,
  ) async {
    await _app(tester);
    await _open(tester);
    await _submit(tester, 'q');

    closeSearch();
    await tester.pumpAndSettle();
    expect(_page, findsOneWidget);
    expect(find.text('found q'), findsNothing);

    await _open(tester);
    expect(find.text('found q'), findsOneWidget);
    final text = tester.widget<EditableText>(find.byType(EditableText));
    expect(text.controller.text, 'q');
    // Typing replaces the last query.
    expect(text.controller.selection.extentOffset, 1);
    expect(text.controller.selection.baseOffset, 0);
    expect(_Page.created, 1);

    closeSearch();
    await tester.pumpAndSettle();
  });

  testWidgets('a tap beside an empty field closes, beside text only blurs', (
    tester,
  ) async {
    await _app(tester);
    await _open(tester);

    await tester.enterText(find.byType(EditableText), 'draft');
    await tester.pump();
    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    expect(searchOpen.value, isTrue);

    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();
    await tester.tapAt(const Offset(200, 100));
    await tester.pumpAndSettle();
    expect(searchOpen.value, isFalse);
  });

  testWidgets('a page opened from search is under the same search', (
    tester,
  ) async {
    await _app(tester);
    await _open(tester);
    await _submit(tester, 'q');

    _navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('artist')),
    );
    await tester.pumpAndSettle();
    expect(find.text('artist'), findsOneWidget);
    expect(searchOpen.value, isTrue);
    expect(searchOnTop.value, isFalse);

    // The icon comes back to the results rather than closing search.
    toggleSearch();
    await tester.pumpAndSettle();
    expect(find.text('artist'), findsNothing);
    expect(find.text('found q'), findsOneWidget);
    expect(searchOnTop.value, isTrue);

    toggleSearch();
    await tester.pumpAndSettle();
    expect(searchOpen.value, isFalse);
    expect(_page, findsOneWidget);
  });

  testWidgets('the field goes up with the keyboard and comes back', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await _app(tester);
    await _open(tester);
    final field = find.byType(EditableText);
    final rest = tester.getBottomLeft(field).dy;

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    final keyboard = 900 / tester.view.devicePixelRatio;
    expect(tester.getBottomLeft(field).dy, closeTo(rest - keyboard, 1));

    tester.view.resetViewInsets();
    await tester.pump();
    expect(tester.getBottomLeft(field).dy, rest);

    closeSearch();
    await tester.pumpAndSettle();
  });

  testWidgets('Back closes search over the pages below', (tester) async {
    await _app(tester);
    await _open(tester);

    await _navigator.currentState!.maybePop();
    await tester.pumpAndSettle();

    expect(searchOpen.value, isFalse);
    expect(searchOnTop.value, isFalse);
    expect(_page, findsOneWidget);
  });

  test('an answer to a dropped search does not come back', () async {
    final provider = _FakeProvider()..hold = Completer<void>();
    final store = JsonStore.memory();
    final c = ProviderContainer(
      overrides: [
        jsonStoreProvider.overrideWithValue(store),
        dbProvider.overrideWithValue(testDb(store)),
        registryProvider.overrideWithValue(
          ProviderRegistry()..register(provider),
        ),
      ],
    );
    addTearDown(c.dispose);
    final session = c.read(searchSessionProvider);

    session.controller.text = 'q';
    final run = session.run();
    expect(session.showing, isTrue);

    session.clear();
    provider.hold!.complete();
    await run;

    expect(session.showing, isFalse);
    expect(session.results.isEmpty, isTrue);
  });
}
