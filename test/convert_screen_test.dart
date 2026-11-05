/// The transfer page: what it says while it looks and after, the tabs, a track's
/// choice in a sheet, and the copy it makes.
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
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/library/ui/convert_screen.dart';
import 'package:bloom/shared/ui/atoms.dart';
import 'package:bloom/shared/ui/bloom_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/test_db.dart';

Track _track(
  String id,
  String name, {
  int seconds = 200,
  MusicSource source = MusicSource.soundcloud,
}) => Track(
  id: id,
  name: name,
  artist: 'Один',
  duration: Duration(seconds: seconds),
  source: source,
);

/// Three kinds of track: found for sure, doubtful and missing.
final Map<String, List<Track>> _answers = {
  'Ночь Один': [
    _track('ytm:1', 'Ночь', seconds: 201, source: MusicSource.ytmusic),
  ],
  'Утро Один': [
    _track('ytm:2', 'Утро (Slowed)', seconds: 201, source: MusicSource.ytmusic),
  ],
};

class _FakeProvider extends MusicProvider {
  _FakeProvider({this.wait});

  final Future<void>? wait;

  @override
  MusicSource get source => MusicSource.ytmusic;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    await wait;
    return SearchResults(tracks: _answers[query] ?? const []);
  }
}

final _source = [
  _track('sc:1', 'Ночь'),
  _track('sc:2', 'Утро'),
  _track('sc:3', 'Вечер'),
];

class _Page {
  _Page(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  LibraryState get lib => container.read(libraryProvider);
}

Future<_Page> _open(
  WidgetTester tester, {
  String? cover,
  Future<void>? wait,
}) async {
  final store = JsonStore.memory();
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
      registryProvider.overrideWithValue(
        ProviderRegistry()..register(_FakeProvider(wait: wait)),
      ),
    ],
  );
  addTearDown(container.dispose);
  final playlist = container
      .read(libraryProvider.notifier)
      .createPlaylist('Вечеринка', tracks: _source, cover: cover ?? '');

  final router = GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(
        path: '/library',
        builder: (_, _) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ConvertScreen(
                    playlist: playlist,
                    tracks: _source,
                    target: MusicSource.ytmusic,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        routes: [
          GoRoute(
            path: 'list/:id',
            builder: (_, state) =>
                Scaffold(body: Text('list ${state.pathParameters['id']}')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        routerConfig: router,
        builder: (_, child) => ToastHost(child: child!),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return _Page(container, router);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

BloomButton _button(WidgetTester tester, String label) =>
    tester.widget<BloomButton>(
      find.ancestor(of: find.text(label), matching: find.byType(BloomButton)),
    );

void main() {
  testWidgets('while it looks: how far, and nothing to create yet', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _open(tester, wait: gate.future);

    expect(find.text('Вечеринка (YouTube Music)'), findsOneWidget);
    expect(find.text('Ищу треки · 0 из 3'), findsOneWidget);
    expect(find.text('Можно закрыть — перенос отменится'), findsOneWidget);
    expect(find.byType(BloomBar), findsOneWidget);
    expect(_button(tester, 'Создать плейлист').onTap, isNull);
    expect(_button(tester, 'Закрыть').onTap, isNotNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BloomBar), findsNothing);
    expect(_button(tester, 'Создать плейлист').onTap, isNotNull);
  });

  testWidgets('the unclear ones first, all of them a tab away', (tester) async {
    await _open(tester);

    expect(find.text('Перенесено 1 из 3 · 2 ждут выбора'), findsOneWidget);
    expect(find.text('Спорные'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Утро'), findsOneWidget);
    expect(find.text('Вечер'), findsOneWidget);
    expect(find.text('Ночь'), findsNothing);
    expect(find.text('Оригинал'), findsOneWidget);
    expect(find.text('Не найден'), findsOneWidget);

    await _tapText(tester, 'Все треки');
    expect(find.text('Ночь'), findsOneWidget);
    expect(find.text('Перенесён'), findsOneWidget);
  });

  testWidgets('a choice in a sheet: no percents, it says why there is none', (
    tester,
  ) async {
    await _open(tester);

    await _tapText(tester, 'Утро');
    expect(find.text('Утро (Slowed)'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.byType(BloomCheck), findsOneWidget);
    await _tapText(tester, 'Утро (Slowed)');
    expect(find.text('Перенесено 2 из 3 · 1 ждёт выбора'), findsOneWidget);
    expect(find.text('Перенесён'), findsOneWidget);

    await _tapText(tester, 'Вечер');
    expect(find.text('Не найден на площадке YouTube Music'), findsOneWidget);
    await _tapText(tester, 'Пропустить');
    expect(find.text('Перенесено 2 из 3 · 1 пропущен'), findsOneWidget);
    expect(find.text('Пропущен'), findsOneWidget);
  });

  testWidgets('Take the best goes once there is nothing to take', (
    tester,
  ) async {
    await _open(tester);

    await _tapText(tester, 'Взять лучшие');
    expect(find.text('Взять лучшие'), findsNothing);
    expect(find.text('Перенесено 2 из 3 · 1 ждёт выбора'), findsOneWidget);
  });

  testWidgets('an emptied name comes back when left', (tester) async {
    await _open(tester);
    final field = find.byType(TextField);

    await tester.enterText(field, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Вечеринка (YouTube Music)'), findsOneWidget);
  });

  testWidgets('the copy takes the name and the link; the toast undoes it', (
    tester,
  ) async {
    final page = await _open(tester, cover: 'https://example.com/a.jpg');
    await tester.enterText(find.byType(TextField), 'Копия');
    await tester.pump();

    // Not settling: a toast with Undo would live out its time meanwhile.
    await tester.tap(find.text('Создать плейлист'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final copy = page.lib.playlists.singleWhere((p) => p.name == 'Копия');
    expect(copy.cover, 'https://example.com/a.jpg');
    expect(copy.trackIds.toSet(), {'ytm:1', 'sc:2', 'sc:3'});
    expect(page.router.state.uri.path, '/library/list/${copy.id}');
    expect(find.text('Создан «Копия» (3 трека)'), findsOneWidget);

    await tester.tap(find.text('Отменить'));
    await tester.pump();
    expect(page.lib.playlists.map((p) => p.name), ['Вечеринка']);
    expect(page.router.state.uri.path, '/library');
    await tester.pumpAndSettle();
  });

  testWidgets('undoing the copy keeps what the library had', (tester) async {
    final page = await _open(tester);

    await tester.tap(find.text('Создать плейлист'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();

    expect(page.lib.isInLib('sc:1'), isTrue);
    // What it found stays in all tracks: a playlist's removal never takes
    // tracks with it.
    expect(page.lib.isInLib('ytm:1'), isTrue);
  });

  testWidgets('a source with no picture gives a copy with none', (
    tester,
  ) async {
    final page = await _open(tester);

    await _tapText(tester, 'Создать плейлист');

    final copy = page.lib.playlists.singleWhere(
      (p) => p.name == 'Вечеринка (YouTube Music)',
    );
    expect(copy.cover ?? '', isEmpty);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}
