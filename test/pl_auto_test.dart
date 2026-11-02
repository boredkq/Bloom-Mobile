/// Playlist auto-refresh: which ones I visit, what counts as added, and what's
/// left of a playlist when the platform doesn't answer.
library;

import 'package:bloom/app/providers.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/library/pl_auto_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

Track _track(String id) => Track(
  id: id,
  name: id,
  artist: 'Artist',
  duration: const Duration(seconds: 100),
  source: MusicSource.soundcloud,
  sourceData: const {'transcodings': []},
);

/// A platform holding a playlist with given contents per collection id.
class _FakeSoundCloud extends MusicProvider {
  _FakeSoundCloud(this.byId);

  /// Collection id to tracks. `null` instead of a list means the platform
  /// fails.
  final Map<String, List<Track>?> byId;

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async => SearchResults.empty;

  @override
  Future<SetContent?> getPlaylist(String id) async {
    if (byId.containsKey(id) && byId[id] == null) throw StateError('нет сети');
    return SetContent(
      playlist: Playlist(id: id, title: 'Сет', source: MusicSource.soundcloud),
      tracks: byId[id] ?? const [],
    );
  }
}

/// A SoundCloud playlist binding: the refresh finds it by id.
PlSourceRef _src(String id) => PlSourceRef(id: id, provider: 'sc');

ProviderContainer _container(_FakeSoundCloud provider, JsonStore store) {
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
  return c;
}

void main() {
  // The pass looks for the app's messenger to announce new tracks; it lives in
  // the widget tree, and without a binding the lookup crashes.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('candidates are only playlists with a source', () {
    final c = _container(_FakeSoundCloud(const {}), JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    lib.createPlaylist('Свой');
    lib.createPlaylist('Импортированный', source: _src('sc:set:1'));

    final names = c
        .read(plAutoProvider.notifier)
        .candidates()
        .map((p) => p.name)
        .toList();
    expect(names, ['Импортированный']);
  });

  test('a pass refreshes only marked ones and counts new tracks', () async {
    final sc = _FakeSoundCloud({
      'sc:set:1': [_track('sc:1'), _track('sc:2')],
      'sc:set:2': [_track('sc:9')],
    });
    final c = _container(sc, JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final one = lib.createPlaylist(
      'Первый',
      tracks: [_track('sc:1')],
      source: _src('sc:set:1'),
    );
    final two = lib.createPlaylist('Второй', source: _src('sc:set:2'));

    final auto = c.read(plAutoProvider.notifier);
    lib.setAutoRefresh([one.id], true);
    final result = await auto.runSweep(silent: true);

    // The first gained one track, the second isn't marked and wasn't touched.
    expect(result.added, 1);
    expect(result.changed, 1);
    expect(result.failed, 0);
    final playlists = c.read(libraryProvider).playlists;
    // The new track went on top and the old one stayed: a refresh mixes in, it
    // doesn't replace.
    expect(playlists.firstWhere((p) => p.id == one.id).trackIds, [
      'sc:2',
      'sc:1',
    ]);
    expect(playlists.firstWhere((p) => p.id == two.id).trackIds, isEmpty);

    // The pass's result is remembered for the label in the sheet.
    final state = c.read(plAutoProvider);
    expect(state.runs[one.id]?.added, 1);
    expect(state.lastRun, greaterThan(0));
    expect(state.busy, isNull);
  });

  test('several sources: new on top, what was added by hand stays', () async {
    final sc = _FakeSoundCloud({
      'sc:set:1': [_track('sc:1')],
      'sc:set:2': [_track('sc:9')],
    });
    final c = _container(sc, JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist(
      'Свой',
      tracks: [_track('sc:7')],
      source: _src('sc:set:1'),
    );
    lib.setPlaylistSources(pl.id, [_src('sc:set:1'), _src('sc:set:2')]);

    final auto = c.read(plAutoProvider.notifier);
    lib.setAutoRefresh([pl.id], true);
    final result = await auto.runSweep(silent: true);

    expect(result.added, 2);
    expect(c.read(libraryProvider).playlists.single.trackIds, [
      'sc:1',
      'sc:9',
      'sc:7',
    ]);
  });

  test("one failed source doesn't cancel the others", () async {
    final sc = _FakeSoundCloud({
      'sc:set:1': null,
      'sc:set:2': [_track('sc:9')],
    });
    final c = _container(sc, JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Свой', tracks: [_track('sc:7')]);
    lib.setPlaylistSources(pl.id, [_src('sc:set:1'), _src('sc:set:2')]);

    final auto = c.read(plAutoProvider.notifier);
    lib.setAutoRefresh([pl.id], true);
    final result = await auto.runSweep(silent: true);

    // A partial success is a success: the missing collection may have been
    // deleted.
    expect(result.added, 1);
    expect(result.failed, 0);
    expect(c.read(libraryProvider).playlists.single.trackIds, ['sc:9', 'sc:7']);
  });

  test("a failed source doesn't erase the playlist's contents", () async {
    final sc = _FakeSoundCloud({'sc:set:1': null});
    final c = _container(sc, JsonStore.memory());
    final lib = c.read(libraryProvider.notifier);
    final pl = lib.createPlaylist(
      'Первый',
      tracks: [_track('sc:1')],
      source: _src('sc:set:1'),
    );

    final auto = c.read(plAutoProvider.notifier);
    lib.setAutoRefresh([pl.id], true);
    final result = await auto.runSweep(silent: true);

    expect(result.failed, 1);
    expect(c.read(libraryProvider).playlists.single.trackIds, ['sc:1']);
    expect(c.read(plAutoProvider).runs[pl.id]?.failed, isTrue);
  });

  test('no marked playlists, no pass', () async {
    final c = _container(_FakeSoundCloud(const {}), JsonStore.memory());
    c
        .read(libraryProvider.notifier)
        .createPlaylist('Импортированный', source: _src('sc:set:1'));

    final result = await c.read(plAutoProvider.notifier).runSweep(silent: true);
    expect(result.skipped, isTrue);
    expect(c.read(plAutoProvider).lastRun, 0);
  });

  test('the schedule, marks and results survive a restart', () async {
    final store = JsonStore.memory();
    final first = _container(
      _FakeSoundCloud({
        'sc:set:1': [_track('sc:1')],
      }),
      store,
    );
    final lib = first.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Первый', source: _src('sc:set:1'));
    lib.setAutoRefresh([pl.id], true);
    first.read(plAutoProvider.notifier)
      ..setEnabled(true)
      ..setEveryMin(720)
      ..setOnStart(false);
    await first.read(plAutoProvider.notifier).runSweep(silent: true);

    final second = _container(_FakeSoundCloud(const {}), store);
    final state = second.read(plAutoProvider);
    expect(state.enabled, isTrue);
    expect(state.everyMin, 720);
    expect(state.onStart, isFalse);
    // The mark is on the playlist itself, results and time are in the
    // database's kv.
    expect(second.read(libraryProvider).playlists.single.autoRefresh, isTrue);
    expect(state.runs[pl.id]?.added, 1);
    expect(state.lastRun, greaterThan(0));
  });

  test("a deleted playlist's results are forgotten", () async {
    final store = JsonStore.memory();
    final first = _container(
      _FakeSoundCloud({
        'sc:set:1': [_track('sc:1')],
      }),
      store,
    );
    final lib = first.read(libraryProvider.notifier);
    final pl = lib.createPlaylist('Первый', source: _src('sc:set:1'));
    lib.setAutoRefresh([pl.id], true);
    await first.read(plAutoProvider.notifier).runSweep(silent: true);
    lib.deletePlaylist(pl.id);

    final second = _container(_FakeSoundCloud(const {}), store);
    expect(second.read(plAutoProvider).runs, isEmpty);
  });
}
