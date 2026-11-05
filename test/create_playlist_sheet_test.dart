/// The library's plus sheet: Import lists where the tracks go at once, Convert
/// takes a playlist and a platform before it starts.
library;

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
import 'package:bloom/features/library/ui/create_playlist_sheet.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:bloom/shared/ui/bloom_sheet.dart';
import 'package:bloom/shared/ui/platform_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/glyphs.dart';
import 'support/test_db.dart';

class _FakeProvider extends MusicProvider {
  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;
}

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.yandex,
);

Future<ProviderContainer> _open(WidgetTester tester) async {
  final store = JsonStore.memory();
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
      registryProvider.overrideWithValue(
        ProviderRegistry()..register(_FakeProvider()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBloomTheme(BloomThemes.dark),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showCreatePlaylistSheet(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

SheetButton _runButton(WidgetTester tester) =>
    tester.widget<SheetButton>(find.byType(SheetButton));

void main() {
  testWidgets('Import shows where the tracks go without another tap', (
    tester,
  ) async {
    final c = await _open(tester);
    c.read(libraryProvider.notifier).createPlaylist('Вечер');
    await _tapText(tester, 'open');
    await _tapText(tester, 'Импорт');

    expect(find.text('Создать плейлист'), findsOneWidget);
    expect(find.text('Все треки'), findsOneWidget);
    expect(find.text('Любимые'), findsOneWidget);
    expect(find.text('Вечер'), findsOneWidget);
    expect(find.text('Из файла'), findsOneWidget);
    expect(find.byType(SheetTick), findsOneWidget);

    await _tapText(tester, 'Вечер');
    final row = find.ancestor(
      of: find.text('Вечер'),
      matching: find.byType(SheetRow),
    );
    expect(
      find.descendant(of: row, matching: find.byType(SheetTick)),
      findsOneWidget,
    );
    expect(find.byType(SheetTick), findsOneWidget);
  });

  testWidgets('Convert needs a playlist with tracks and a platform', (
    tester,
  ) async {
    final c = await _open(tester);
    final lib = c.read(libraryProvider.notifier);
    lib.createPlaylist('Вечер', tracks: [_track('ym:1')]);
    lib.createPlaylist('Пустой');
    await _tapText(tester, 'open');
    await _tapText(tester, 'Конвертировать плейлист');

    expect(find.text('Перенос треков на другую платформу'), findsOneWidget);
    expect(find.text('1 трек'), findsOneWidget);
    expect(find.text('Нет треков'), findsOneWidget);
    expect(_runButton(tester).onTap, isNull);

    await tester.tap(find.byType(PlatformLogo));
    await tester.pumpAndSettle();
    expect(_runButton(tester).onTap, isNull);

    await _tapText(tester, 'Пустой');
    expect(_runButton(tester).onTap, isNull);

    await _tapText(tester, 'Вечер');
    expect(_runButton(tester).onTap, isNotNull);

    await tester.tap(find.byType(SheetButton));
    await tester.pumpAndSettle();
    expect(find.byType(ConvertScreen), findsOneWidget);
    expect(find.byType(SheetButton), findsNothing);
    final screen = tester.widget<ConvertScreen>(find.byType(ConvertScreen));
    expect(screen.playlist.name, 'Вечер');
    expect(screen.target, MusicSource.soundcloud);
    expect(screen.tracks.map((t) => t.id), ['ym:1']);
  });

  testWidgets('a long list scrolls inside, the rest stays on screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _open(tester);
    final lib = c.read(libraryProvider.notifier);
    for (var i = 0; i < 30; i++) {
      lib.createPlaylist('Плейлист $i');
    }
    await _tapText(tester, 'open');
    await _tapText(tester, 'Конвертировать плейлист');

    final height = tester.view.physicalSize.height;
    expect(
      tester.getBottomLeft(find.byType(PlatformLogo)).dy,
      lessThan(height),
    );
    expect(tester.getBottomLeft(find.text('Назад')).dy, lessThan(height));
    expect(find.text('Плейлист 29'), findsNothing);

    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    await _tapText(tester, 'Импорт');
    expect(tester.getBottomLeft(find.text('Из файла')).dy, lessThan(height));
    expect(tester.getBottomLeft(find.text('Назад')).dy, lessThan(height));
  });

  testWidgets('the plus sheet has both rows, with their icons', (tester) async {
    await _open(tester);
    await _tapText(tester, 'open');

    expect(find.text('Импорт'), findsOneWidget);
    expect(find.text('Конвертировать плейлист'), findsOneWidget);
    expect(findGlyph(Bi.export), findsOneWidget);
    expect(findGlyph(Bi.shuffle), findsOneWidget);
  });
}
