/// System and Audio: the work log, moving playlists, comparing versions and
/// resetting settings.
///
/// No network and no file system: the log without `open()` lives in memory, the
/// update check goes through a swapped [releaseFetchProvider], and the store is
/// `JsonStore.memory`.
library;

import 'dart:io';

import 'dart:convert';

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/log/bloom_log.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/player/play_button_store.dart';
import 'package:bloom/features/player/player_bg_store.dart';
import 'package:bloom/features/settings/about_store.dart';
import 'package:bloom/features/settings/data_transfer.dart';
import 'package:bloom/features/settings/reset.dart';
import 'package:bloom/features/settings/update_notes_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

ProviderContainer _container(
  JsonStore store, {
  ReleaseFetch? fetch,
  NotesFetch? notes,
}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
      if (fetch != null) releaseFetchProvider.overrideWithValue(fetch),
      if (notes != null) notesFetchProvider.overrideWithValue(notes),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// The notes' manifest with a major version and a patch.
const String _manifest = '''
{
  "1.0.0": {
    "date": "2026-08-20",
    "image": "start.png",
    "summary": { "ru": "Первый релиз", "en": "First release" }
  },
  "1.0.1": {
    "date": "2026-08-21",
    "image": "ignored.png",
    "items": { "ru": ["раз", "два"], "en": ["one", "two"] }
  },
  "1.0.2": {
    "items": ["общий", { "ru": "только русский" }]
  }
}
''';

Track _track(String id, {String name = 'Song'}) => Track(
  id: id,
  name: name,
  artist: 'Artist',
  duration: const Duration(seconds: 200),
  source: MusicSource.soundcloud,
);

void main() {
  group('work log', () {
    setUp(() => BloomLog.instance.clear());

    test('a line builds and parses back', () {
      final entry = LogEntry(
        DateTime(2026, 8, 20, 14, 3, 11),
        LogLevel.error,
        'player',
        'нет провайдера',
      );
      final parsed = LogEntry.parse(entry.format());
      expect(parsed, isNotNull);
      expect(parsed!.level, LogLevel.error);
      expect(parsed.tag, 'player');
      expect(parsed.message, 'нет провайдера');
      expect(parsed.at, entry.at);
    });

    test('a foreign line is skipped, not a parsing crash', () {
      expect(LogEntry.parse(''), isNull);
      expect(LogEntry.parse('какой-то мусор из другого файла'), isNull);
    });

    test('multiline folds into one line', () {
      logError('dart', 'ошибка', 'кадр 1\n  кадр 2\n  кадр 3');
      final line = BloomLog.instance.entries.single.format();
      expect(line.contains('\n'), isFalse);
      expect(line, contains('кадр 3'));
    });

    test('old entries get pushed out, new ones stay', () {
      for (var i = 0; i < kLogMax + 20; i++) {
        logInfo('test', 'запись $i');
      }
      final entries = BloomLog.instance.entries;
      expect(entries.length, kLogMax);
      expect(entries.first.message, 'запись 20');
      expect(entries.last.message, 'запись ${kLogMax + 19}');
    });
  });

  group('moving playlists', () {
    Future<ImportResult> import(ProviderContainer c, String file) =>
        importPlaylistBundle(
          file,
          c.read(libraryProvider),
          c.read(libraryProvider.notifier),
        );

    test('only playlist tracks go into the file', () async {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      lib.addToLibrary([_track('sc:1'), _track('sc:2')]);
      lib.createPlaylist('Вечер', tracks: [_track('sc:1')]);

      final bundle = await buildExportAllBundle(c.read(libraryProvider));
      expect(bundle, contains('"sc:1"'));
      // The track is in the library but in no playlist: the file is about
      // playlists, not the whole library.
      expect(bundle, isNot(contains('"sc:2"')));
    });

    test('exporting one playlist takes only that one', () async {
      final c = _container(JsonStore.memory());
      final lib = c.read(libraryProvider.notifier);
      final mine = lib.createPlaylist('Вечер', tracks: [_track('sc:1')]);
      lib.createPlaylist('Утро', tracks: [_track('sc:2')]);

      final bundle = await buildExportBundle(mine, c.read(libraryProvider));
      expect(bundle, contains('Вечер'));
      expect(bundle, contains('"sc:1"'));
      expect(bundle, isNot(contains('Утро')));
      expect(bundle, isNot(contains('"sc:2"')));
    });

    test(
      'the file format: a mark, a version, a track as a database row',
      () async {
        final c = _container(JsonStore.memory());
        c
            .read(libraryProvider.notifier)
            .createPlaylist(
              'Вечер',
              tracks: [
                Track(
                  id: 'sc:5',
                  name: 'Song',
                  artist: 'A',
                  duration: const Duration(minutes: 3, seconds: 45),
                  source: MusicSource.soundcloud,
                  sourceData: const {
                    'transcodings': [
                      {'url': 'u'},
                    ],
                  },
                ),
              ],
            );

        final doc =
            jsonDecode(await buildExportAllBundle(c.read(libraryProvider)))
                as Map<String, dynamic>;
        expect(doc['bloom'], 'playlist');
        expect(doc['version'], 2);
        expect((doc['playlists'] as List).single['tracks'], ['sc:5']);
        final t = (doc['tracks'] as List).single as Map;
        expect(t['title'], 'Song');
        expect(t['duration'], 225);
        expect(t['provider'], 'sc');
        expect(t['extra']['scId'], 5);
        // Transcodings under the shared key: the stream resolves from them on the
        // other side.
        expect(t['extra']['media']['transcodings'], isNotEmpty);
      },
    );

    test(
      'a file from the computer is read: description, sources, order',
      () async {
        final c = _container(JsonStore.memory());
        final result = await import(c, '''
        {"bloom":"playlist","version":2,
         "playlists":[{"name":"С ПК","description":"вечером",
           "sources":[{"url":"https://soundcloud.com/x/sets/y","title":"Y","owner":"x",
             "provider":"sc","id":"sc:set:9","kind":"playlist","cover":""}],
           "tracks":["ym:7","sc:5"]}],
         "tracks":[
           {"id":"sc:5","title":"Song","artist":"A","album":"","cover":"","duration":225.5,
            "provider":"sc","extra":{"scId":5,"media":{"transcodings":[{"url":"u"}]}}},
           {"id":"ym:7","title":"Пес","artist":"Б","album":"","cover":"","duration":3723,
            "provider":"ym","extra":{"ymId":"7","available":false}}
         ]}
        ''');

        expect(result.playlists, 1);
        expect(result.tracks, 2);
        final pl = c.read(libraryProvider).playlists.single;
        expect(pl.name, 'С ПК');
        expect(pl.description, 'вечером');
        expect(pl.sources.single.url, 'https://soundcloud.com/x/sets/y');
        expect(pl.sources.single.id, 'sc:set:9');
        expect(pl.trackIds, ['ym:7', 'sc:5']);
        final tracks = c.read(libraryProvider).tracks;
        expect(tracks['sc:5']!.sourceData?['transcodings'], isNotEmpty);
        expect(tracks['sc:5']!.duration, const Duration(milliseconds: 225500));
        expect(tracks['ym:7']!.sourceData, {'available': false});
      },
    );

    test('a one-playlist file is read by the normal import', () async {
      final source = _container(JsonStore.memory());
      final mine = source
          .read(libraryProvider.notifier)
          .createPlaylist('Вечер', tracks: [_track('sc:1'), _track('sc:2')]);
      final file = await buildExportBundle(mine, source.read(libraryProvider));

      final c = _container(JsonStore.memory());
      final result = await import(c, file);

      expect(result.playlists, 1);
      expect(c.read(libraryProvider).playlists.single.trackIds, [
        'sc:1',
        'sc:2',
      ]);
    });

    test('the file name', () {
      expect(
        playlistFileName('AC/DC: лучшее?'),
        'AC_DC_ лучшее_.bloomplaylist',
      );
      // A nameless playlist must not give a file with no name.
      expect(playlistFileName('   '), 'playlist.bloomplaylist');
    });

    test(
      'the import sets up the playlist anew and brings tracks back',
      () async {
        final source = _container(JsonStore.memory());
        final lib = source.read(libraryProvider.notifier);
        lib.createPlaylist('Вечер', tracks: [_track('sc:1'), _track('sc:2')]);
        final file = await buildExportAllBundle(source.read(libraryProvider));

        final c = _container(JsonStore.memory());
        final result = await import(c, file);

        expect(result.playlists, 1);
        expect(result.tracks, 2);
        final pl = c.read(libraryProvider).playlists.single;
        expect(pl.name, 'Вечер');
        expect(pl.trackIds, ['sc:1', 'sc:2']);
      },
    );

    test(
      "a playlist id from a file doesn't take an existing one's place",
      () async {
        final c = _container(JsonStore.memory());
        final lib = c.read(libraryProvider.notifier);
        final mine = lib.createPlaylist('Мой', tracks: [_track('sc:9')]);
        final file = await buildExportAllBundle(c.read(libraryProvider));

        await import(c, file);
        final playlists = c.read(libraryProvider).playlists;
        expect(playlists.length, 2);
        expect(playlists.first.id, mine.id);
        expect(playlists.last.id, isNot(mine.id));
      },
    );

    test(
      'an old format, a foreign file and a newer file get a clear refusal',
      () async {
        final c = _container(JsonStore.memory());
        expect(
          (await import(c, '{"version":1,"playlists":[]}')).failure,
          ImportFailure.oldFormat,
        );
        expect((await import(c, 'не json')).failure, ImportFailure.bad);
        expect(
          (await import(c, '{"bloom":"playlist","version":3}')).failure,
          ImportFailure.newer,
        );
        expect(c.read(libraryProvider).playlists, isEmpty);
      },
    );

    test('an empty playlist list gives zeros', () async {
      final c = _container(JsonStore.memory());
      final empty = await import(
        c,
        '{"bloom":"playlist","version":2,"playlists":[]}',
      );
      expect(empty.failure, isNull);
      expect(empty.playlists, 0);
    });

    test('a track missing from the file stays out of the playlist', () async {
      final c = _container(JsonStore.memory());
      final result = await import(
        c,
        '{"bloom":"playlist","version":2,'
        '"playlists":[{"name":"Пусто","tracks":["sc:404"]}]}',
      );
      expect(result.playlists, 1);
      expect(result.tracks, 0);
      expect(c.read(libraryProvider).playlists.single.trackIds, isEmpty);
    });

    test(
      "a cover link survives the round, a picture doesn't crash the import",
      () async {
        final c = _container(JsonStore.memory());
        c
            .read(libraryProvider.notifier)
            .createPlaylist(
              'Вечер',
              tracks: [_track('sc:1')],
              cover: 'https://cdn/pl.jpg',
            );
        final file = await buildExportAllBundle(c.read(libraryProvider));
        expect(file, contains('https://cdn/pl.jpg'));

        // A computer's own cover arrives as a picture inside the file. Tests have
        // no covers folder to write it to, and the import must neither crash nor
        // lose the playlist.
        final other = _container(JsonStore.memory());
        final result = await import(
          other,
          '{"bloom":"playlist","version":2,"playlists":['
          '{"name":"Ссылкой","tracks":[],"cover":"https://cdn/a.jpg"},'
          '{"name":"Картинкой","tracks":[],"coverData":"iVBORw0="}'
          ']}',
        );

        expect(result.playlists, 2);
        final covers = {
          for (final p in other.read(libraryProvider).playlists)
            p.name: p.cover,
        };
        expect(covers['Ссылкой'], 'https://cdn/a.jpg');
        expect(covers['Картинкой'], isNull);
      },
    );
  });

  group('versions and updates', () {
    test('comparing by numeric parts', () {
      expect(compareVersions('1.2.3', '1.2.3'), 0);
      expect(compareVersions('1.3.0', '1.2.9'), 1);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.0', '1.10.0'), -1);
      expect(compareVersions('v2.0.0', '1.9.9'), 1);
      expect(compareVersions('1.2.3-beta', '1.2.3'), 0);
    });

    test('newer than installed: a version is available', () async {
      final c = _container(
        JsonStore.memory(),
        fetch: (_) async =>
            '{"tag_name":"v1.4.0","html_url":"https://example/1.4.0"}',
      );
      final about = c.read(aboutProvider.notifier);
      // The platform gives no version in tests, so I set it through a check
      // with a known installed one.
      about.state = const AboutState(version: '1.3.0');
      await about.check();
      expect(c.read(aboutProvider).phase, UpdatePhase.available);
      expect(c.read(aboutProvider).latest, '1.4.0');
      expect(c.read(aboutProvider).releaseUrl, 'https://example/1.4.0');
    });

    test('the same version: the latest is installed', () async {
      final c = _container(
        JsonStore.memory(),
        fetch: (_) async => '{"tag_name":"v1.3.0"}',
      );
      final about = c.read(aboutProvider.notifier);
      about.state = const AboutState(version: '1.3.0');
      await about.check();
      expect(c.read(aboutProvider).phase, UpdatePhase.uptodate);
    });

    test('the network dropped: an error, not a crash', () async {
      final c = _container(
        JsonStore.memory(),
        fetch: (_) async => throw Exception('нет сети'),
      );
      await c.read(aboutProvider.notifier).check();
      expect(c.read(aboutProvider).phase, UpdatePhase.error);
    });
  });

  group('version notes', () {
    test('a major version: summary and picture by language', () async {
      final c = _container(JsonStore.memory(), notes: (_) async => _manifest);
      final ru = await c.read(updateNotesProvider).note('1.0.0', 'ru');
      expect(ru!.summary, 'Первый релиз');
      expect(ru.date, '2026-08-20');
      expect(
        ru.image,
        'https://raw.githubusercontent.com/$kUpdateRepo/main/update-notes/assets/start.png',
      );
      final en = await c.read(updateNotesProvider).note('1.0.0', 'en');
      expect(en!.summary, 'First release');
    });

    test('a patch: items by language, no picture', () async {
      final c = _container(JsonStore.memory(), notes: (_) async => _manifest);
      final ru = await c.read(updateNotesProvider).note('1.0.1', 'ru');
      expect(ru!.items, ['раз', 'два']);
      expect(ru.image, isNull);
      final en = await c.read(updateNotesProvider).note('1.0.1', 'en');
      expect(en!.items, ['one', 'two']);
    });

    test('items as a list of texts fall back to the other language', () async {
      final c = _container(JsonStore.memory(), notes: (_) async => _manifest);
      final en = await c.read(updateNotesProvider).note('1.0.2', 'en');
      expect(en!.items, ['общий', 'только русский']);
    });

    test('versions go newest first', () async {
      final c = _container(JsonStore.memory(), notes: (_) async => _manifest);
      final history = await c.read(updateNotesProvider).history('ru');
      expect([for (final h in history) h.version], ['1.0.2', '1.0.1', '1.0.0']);
      expect(history[1].date, '2026-08-21');
    });

    test('the file in the repository parses and knows this version', () async {
      final file = File('update-notes/update-notes.json').readAsStringSync();
      final c = _container(JsonStore.memory(), notes: (_) async => file);
      final version = RegExp(
        r'^version: ([^+\s]+)',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())![1]!;
      final note = await c.read(updateNotesProvider).note(version, 'ru');
      expect(note?.hasContent, isTrue);
    });

    test('no such version in the manifest: no notes either', () async {
      final c = _container(JsonStore.memory(), notes: (_) async => _manifest);
      expect(await c.read(updateNotesProvider).note('9.9.9', 'ru'), isNull);
    });

    test("What's new stays silent on first launch and after", () async {
      final store = JsonStore.memory();
      final c = _container(store, notes: (_) async => _manifest);
      final notes = c.read(updateNotesProvider);
      // The first launch: no previous version recorded, so no sheet, but the
      // launch mark appears.
      expect(await notes.whatsNew('1.0.0', 'ru'), isNull);
      expect(notes.lastRun, '1.0.0');
      // A second launch of the same version: quiet too.
      expect(await notes.whatsNew('1.0.0', 'ru'), isNull);
    });

    test("after a version change What's new shows once", () async {
      final store = JsonStore.memory();
      final c = _container(store, notes: (_) async => _manifest);
      final notes = c.read(updateNotesProvider);
      await notes.whatsNew('1.0.0', 'ru');
      final shown = await notes.whatsNew('1.0.1', 'ru');
      expect(shown, isNotNull);
      expect(shown!.version, '1.0.1');
      expect(await notes.whatsNew('1.0.1', 'ru'), isNull);
    });

    test("the network dropped: takes the last download's cache", () async {
      final store = JsonStore.memory();
      final first = _container(store, notes: (_) async => _manifest);
      await first.read(updateNotesProvider).history('ru');

      final offline = _container(
        store,
        notes: (_) async => throw Exception('нет сети'),
      );
      final history = await offline.read(updateNotesProvider).history('ru');
      expect([for (final h in history) h.version], ['1.0.2', '1.0.1', '1.0.0']);
    });

    test('no cache and no network: an error, not an empty list', () async {
      final c = _container(
        JsonStore.memory(),
        notes: (_) async => throw Exception('нет сети'),
      );
      expect(c.read(updateNotesProvider).history('ru'), throwsException);
    });
  });

  group('launch and reset', () {
    test("autoplay doesn't turn restoring on", () {
      final c = _container(JsonStore.memory());
      final settings = c.read(settingsProvider.notifier);
      settings.setAutoplay(true);
      expect(c.read(settingsProvider).restoreQueue, isFalse);
      expect(c.read(settingsProvider).autoplay, isTrue);
    });

    test('restoring off turns autoplay off', () {
      final c = _container(JsonStore.memory());
      final settings = c.read(settingsProvider.notifier);
      settings.setRestoreQueue(true);
      settings.setAutoplay(true);
      settings.setRestoreQueue(false);
      expect(c.read(settingsProvider).autoplay, isFalse);
      expect(c.read(settingsProvider).restoreQueue, isFalse);
    });

    test('both flags survive a restart', () {
      final store = JsonStore.memory();
      final settings = _container(store).read(settingsProvider.notifier);
      settings.setRestoreQueue(true);
      settings.setAutoplay(true);
      final again = _container(store).read(settingsProvider);
      expect(again.autoplay, isTrue);
      expect(again.restoreQueue, isTrue);
    });

    test('Auto similar is off by default and survives a restart', () {
      final store = JsonStore.memory();
      expect(_container(store).read(settingsProvider).autoSimilar, isFalse);
      _container(store).read(settingsProvider.notifier).setAutoSimilar(true);
      expect(_container(store).read(settingsProvider).autoSimilar, isTrue);
    });

    test('resetting settings clears their keys and leaves the library', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(settingsProvider.notifier).setAutoplay(true);
      c.read(libraryProvider.notifier).addToLibrary([_track('sc:1')]);

      store.removeAll(kSettingsKeys);

      expect(store.read('settings'), isNull);
      // The library lives in the database, and a settings reset doesn't reach
      // it.
      expect(_container(store).read(libraryProvider).isInLib('sc:1'), isTrue);
      // A rebuilt store reads the now empty storage, which is what
      // `resetSettings` does through `ref.invalidate`.
      final fresh = _container(store).read(settingsProvider);
      expect(fresh.autoplay, isFalse);
      expect(fresh.themeId, 'dark');
    });

    test('no user data got into the settings key list', () {
      for (final key in ['profile', 'stats', 'follows', 'yandex', 'lastfm']) {
        expect(kSettingsKeys, isNot(contains(key)), reason: key);
      }
    });

    test(
      'a reset also brings back the player view: button, background and cover',
      () {
        final store = JsonStore.memory();
        final c = _container(store);
        c.read(playButtonShapeProvider.notifier).set(PlayButtonShape.square);
        c.read(playerBgProvider.notifier).set(PlayerBg.cover);
        c.read(coverBgFxProvider.notifier).set(CoverBgFx.original);

        store.removeAll(kSettingsKeys);

        final fresh = _container(store);
        expect(fresh.read(playButtonShapeProvider), PlayButtonShape.circle);
        expect(fresh.read(playerBgProvider), PlayerBg.none);
        expect(fresh.read(coverBgFxProvider), CoverBgFx.blur);
      },
    );
  });
}
