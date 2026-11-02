/// Last.fm: request signing, sign-in and the scrobble rule.
///
/// No network: [lastfmTransport] is swapped, and the tests also check what
/// exactly would go to Last.fm.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/lastfm/lastfm_api.dart';
import 'package:bloom/features/lastfm/lastfm_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

/// Requests that went "to the network" during a test.
late List<Map<String, String>> sent;

/// What the fake transport answers next.
late List<Map<String, dynamic>?> replies;

ProviderContainer _container(JsonStore store, {DateTime? now}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
      if (now != null) lfmClockProvider.overrideWithValue(() => now),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Track _track(
  String name, {
  String artist = 'Artist',
  String? album,
  Duration duration = const Duration(seconds: 300),
}) => Track(
  id: 'sc:1',
  name: name,
  artist: artist,
  album: album,
  duration: duration,
  source: MusicSource.soundcloud,
);

/// A store with a connected account and the switches on.
JsonStore _connected() => JsonStore.memory({
  'lastfm': {
    'sk': 'SESSION',
    'apiKey': 'KEY',
    'apiSecret': 'SECRET',
    'scrobble': true,
    'nowPlaying': true,
    'user': 'bxzlik',
  },
});

Iterable<Map<String, String>> _calls(String method) =>
    sent.where((r) => r['method'] == method);

Map<String, String>? _methodCall(String method) {
  for (final r in sent) {
    if (r['method'] == method) return r;
  }
  return null;
}

void main() {
  setUp(() {
    sent = [];
    replies = [];
    lastfmTransport = (form, {bool get = false}) async {
      sent.add(form);
      return replies.isEmpty ? null : replies.removeAt(0);
    };
    openLastfmPage = (url) async {
      sent.add({'method': '_open', 'url': url});
      return true;
    };
  });

  tearDown(() {
    lastfmTransport = defaultLastfmTransport;
    openLastfmPage = defaultOpenLastfmPage;
  });

  group('подпись', () {
    test('ключи сортируются, секрет в хвосте', () {
      expect(
        lastfmSign({'b': '2', 'a': '1'}, 'sec'),
        '35ba30f61c05c14be609e84509030ec5', // md5('a1b2sec')
      );
    });

    test('кириллица подписывается по UTF-8, а не по кодам символов', () {
      expect(
        lastfmSign({'method': 'track.scrobble', 'artist': 'Алиса'}, 'SECRET'),
        'a5565c8c8b4dad0ff8751db161a9e0a9',
      );
    });

    test(
      'запрос уезжает с подписью и форматом, но подпись считается без них',
      () {
        lastfmPost(
          {'method': 'track.love'},
          apiKey: 'KEY',
          apiSecret: 'SECRET',
        );
        final form = sent.single;
        expect(form['format'], 'json');
        expect(
          form['api_sig'],
          lastfmSign({'method': 'track.love', 'api_key': 'KEY'}, 'SECRET'),
        );
      },
    );

    test('без ключей приложения в сеть не ходим вовсе', () {
      lastfmPost({'method': 'track.scrobble'}, apiKey: '', apiSecret: '');
      expect(sent, isEmpty);
    });
  });

  group('вход', () {
    test('сохранённая сессия поднимается при старте', () {
      final c = _container(_connected());
      final s = c.read(lastfmProvider);
      expect(s.connected, isTrue);
      expect(s.user, 'bxzlik');
      expect(s.scrobbleEnabled, isTrue);
    });

    test('пустые ключи не сохраняются и объясняют причину', () {
      final store = JsonStore.memory();
      final c = _container(store);
      expect(c.read(lastfmProvider.notifier).saveKeys('KEY', '  '), isFalse);
      expect(c.read(lastfmProvider).note?.kind, LfmNoteKind.needKeys);
      expect(c.read(lastfmProvider).hasKeys, isFalse);
      expect(store.readMap('lastfm')['apiKey'], isNull);
    });

    test('вход без ключей не начинается', () async {
      final c = _container(JsonStore.memory());
      await c.read(lastfmProvider.notifier).startOAuth();
      expect(sent, isEmpty);
      expect(c.read(lastfmProvider).note?.kind, LfmNoteKind.needKeys);
    });

    test('getToken открывает браузер и включает «Готово»', () async {
      final c = _container(
        JsonStore.memory({
          'lastfm': {'apiKey': 'KEY', 'apiSecret': 'SECRET'},
        }),
      );
      replies.add({'token': 'TOKEN'});
      await c.read(lastfmProvider.notifier).startOAuth();

      expect(sent.first['method'], 'auth.getToken');
      expect(
        _methodCall('_open')?['url'],
        'https://www.last.fm/api/auth/?api_key=KEY&token=TOKEN',
      );
      final s = c.read(lastfmProvider);
      expect(s.oauthPending, isTrue);
      expect(s.busy, isFalse);
      expect(s.note?.kind, LfmNoteKind.confirmAccess);
    });

    test('getSession сохраняет ключ и включает оба тумблера', () async {
      final store = JsonStore.memory({
        'lastfm': {'apiKey': 'KEY', 'apiSecret': 'SECRET'},
      });
      final c = _container(store);
      replies.add({'token': 'TOKEN'});
      await c.read(lastfmProvider.notifier).startOAuth();
      replies.add({
        'session': {'key': 'SESSION', 'name': 'bxzlik'},
      });
      expect(await c.read(lastfmProvider.notifier).finishOAuth(), isTrue);

      final s = c.read(lastfmProvider);
      expect(s.connected, isTrue);
      expect(s.user, 'bxzlik');
      // No point connecting and not scrobbling.
      expect(s.scrobbleEnabled, isTrue);
      expect(s.nowPlayingEnabled, isTrue);
      expect(s.oauthPending, isFalse);
      expect(s.note, isNull);
      expect(store.readMap('lastfm')['sk'], 'SESSION');
    });

    test(
      'тихая проверка при возврате из браузера молчит о неподтверждённом',
      () async {
        final c = _container(
          JsonStore.memory({
            'lastfm': {'apiKey': 'KEY', 'apiSecret': 'SECRET'},
          }),
        );
        replies.add({'token': 'TOKEN'});
        await c.read(lastfmProvider.notifier).startOAuth();
        replies.add({'message': 'Unauthorized Token'});

        expect(
          await c.read(lastfmProvider.notifier).finishOAuth(silent: true),
          isFalse,
        );
        // The on-screen hint stays: the user hasn't pressed "Allow" yet.
        expect(c.read(lastfmProvider).note?.kind, LfmNoteKind.confirmAccess);
        expect(c.read(lastfmProvider).oauthPending, isTrue);

        // On the button press I tell it as it is.
        replies.add({'message': 'Unauthorized Token'});
        await c.read(lastfmProvider.notifier).finishOAuth();
        expect(c.read(lastfmProvider).note?.kind, LfmNoteKind.error);
      },
    );

    test('«Готово» без начатого входа объясняет, что делать', () async {
      final c = _container(_connected());
      expect(await c.read(lastfmProvider.notifier).finishOAuth(), isFalse);
      expect(c.read(lastfmProvider).note?.kind, LfmNoteKind.loginFirst);
    });

    test('выход стирает ключ сессии и ник, ключи приложения оставляет', () {
      final store = _connected();
      final c = _container(store);
      c.read(lastfmProvider.notifier).logout();

      expect(c.read(lastfmProvider).connected, isFalse);
      expect(c.read(lastfmProvider).user, '');
      expect(store.readMap('lastfm')['sk'], isNull);
      // App keys survive signing out: no need to enter them again.
      expect(store.readMap('lastfm')['apiKey'], 'KEY');
    });
  });

  group('скробблинг', () {
    test('старт трека шлёт «сейчас играет» с альбомом', () {
      final c = _container(_connected());
      c.read(lastfmProvider.notifier).onTrackStart(_track('Song', album: 'LP'));

      final form = _methodCall('track.updateNowPlaying');
      expect(form?['artist'], 'Artist');
      expect(form?['track'], 'Song');
      expect(form?['album'], 'LP');
      expect(form?['sk'], 'SESSION');
    });

    test('выключённый Now Playing молчит, но отсчёт для скроббла идёт', () {
      final store = _connected();
      store.write('lastfm', {...store.readMap('lastfm'), 'nowPlaying': false});
      final c = _container(store);
      final lfm = c.read(lastfmProvider.notifier);

      lfm.onTrackStart(_track('Song'));
      expect(_methodCall('track.updateNowPlaying'), isNull);

      lfm.onProgress(
        const Duration(seconds: 150),
        const Duration(seconds: 300),
      );
      expect(_methodCall('track.scrobble'), isNotNull);
    });

    test('порог зачёта: 30 секунд И (половина ИЛИ 240 секунд)', () {
      final c = _container(_connected());
      final lfm = c.read(lastfmProvider.notifier);

      lfm.onTrackStart(_track('Song'));
      lfm.onProgress(const Duration(seconds: 29), const Duration(seconds: 40));
      expect(_methodCall('track.scrobble'), isNull, reason: 'меньше 30 с');

      lfm.onProgress(
        const Duration(seconds: 100),
        const Duration(seconds: 300),
      );
      expect(_methodCall('track.scrobble'), isNull, reason: 'треть трека');

      lfm.onProgress(
        const Duration(seconds: 150),
        const Duration(seconds: 300),
      );
      expect(_methodCall('track.scrobble'), isNotNull, reason: 'половина');
    });

    test(
      'длинный трек засчитывается по 240 секундам, не дожидаясь половины',
      () {
        final c = _container(_connected());
        final lfm = c.read(lastfmProvider.notifier);

        lfm.onTrackStart(_track('Long', duration: const Duration(minutes: 30)));
        lfm.onProgress(
          const Duration(seconds: 239),
          const Duration(minutes: 30),
        );
        expect(_methodCall('track.scrobble'), isNull);

        lfm.onProgress(
          const Duration(seconds: 240),
          const Duration(minutes: 30),
        );
        expect(_methodCall('track.scrobble'), isNotNull);
      },
    );

    test('трек засчитывается один раз, следующий — заново', () async {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final c = _container(_connected(), now: now);
      final lfm = c.read(lastfmProvider.notifier);

      lfm.onTrackStart(_track('Song'));
      lfm.onProgress(
        const Duration(seconds: 150),
        const Duration(seconds: 300),
      );
      lfm.onProgress(
        const Duration(seconds: 200),
        const Duration(seconds: 300),
      );
      expect(
        sent.where((r) => r['method'] == 'track.scrobble'),
        hasLength(1),
        reason: 'второй тик того же трека',
      );
      // The timestamp is the track's start, as Last.fm requires.
      expect(_methodCall('track.scrobble')?['timestamp[0]'], '1700000000');

      await Future<void>.delayed(Duration.zero);
      lfm.onTrackStart(_track('Next'));
      lfm.onProgress(
        const Duration(seconds: 150),
        const Duration(seconds: 300),
      );
      expect(sent.where((r) => r['method'] == 'track.scrobble'), hasLength(2));
    });

    group('queue', () {
      Future<void> settle() => Future<void>.delayed(Duration.zero);

      // No "now playing": every answer here goes to the scrobbles.
      JsonStore quiet() {
        final store = _connected();
        store.write('lastfm', {
          ...store.readMap('lastfm'),
          'nowPlaying': false,
        });
        return store;
      }

      void hear(LastfmController lfm, String name) {
        lfm.onTrackStart(_track(name));
        lfm.onProgress(
          const Duration(seconds: 150),
          const Duration(seconds: 300),
        );
      }

      test(
        'without an answer a scrobble waits and survives a restart',
        () async {
          final store = quiet();
          final c = _container(store);
          hear(c.read(lastfmProvider.notifier), 'Song');
          await settle();
          expect(c.read(lastfmProvider).pending, 1);

          final again = ProviderContainer(
            overrides: [
              jsonStoreProvider.overrideWithValue(store),
              dbProvider.overrideWithValue(c.read(dbProvider)),
            ],
          );
          addTearDown(again.dispose);
          expect(again.read(lastfmProvider).pending, 1);
        },
      );

      test('an answer empties it and what waited goes with the next', () async {
        final c = _container(quiet());
        final lfm = c.read(lastfmProvider.notifier);
        hear(lfm, 'First');
        await settle();
        expect(c.read(lastfmProvider).pending, 1);

        replies.add({'scrobbles': {}});
        hear(lfm, 'Second');
        await settle();

        final last = _calls('track.scrobble').last;
        expect(last['track[0]'], 'First');
        expect(last['track[1]'], 'Second');
        expect(c.read(lastfmProvider).pending, 0);
      });

      test('a refused batch is done with, a transient error is not', () async {
        final c = _container(quiet());
        final lfm = c.read(lastfmProvider.notifier);
        replies.add({'error': 11, 'message': 'offline'});
        hear(lfm, 'Song');
        await settle();
        expect(c.read(lastfmProvider).pending, 1);

        replies.add({'error': 13, 'message': 'bad signature'});
        hear(lfm, 'Next');
        await settle();
        expect(c.read(lastfmProvider).pending, 0);
      });

      test(
        'a lost session signs out and keeps them for the next sign-in',
        () async {
          final c = _container(quiet());
          replies.add({'error': 9, 'message': 'invalid session'});
          hear(c.read(lastfmProvider.notifier), 'Song');
          await settle();

          final s = c.read(lastfmProvider);
          expect(s.connected, isFalse);
          expect(s.note?.kind, LfmNoteKind.sessionLost);
          expect(s.pending, 1);
        },
      );

      test('two weeks old are dropped, not sent', () async {
        final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
        final store = quiet();
        final c = _container(store, now: now);
        c.read(dbProvider).set('lastfm.pending', [
          const LfmScrobble(
            artist: 'A',
            track: 'Old',
            album: '',
            duration: 100,
            ts: 1700000000 - 15 * 24 * 3600,
          ).toJson(),
        ]);
        replies.add({'scrobbles': {}});
        hear(c.read(lastfmProvider.notifier), 'Song');
        await settle();

        final last = _calls('track.scrobble').last;
        expect(last['track[0]'], 'Song');
        expect(last.containsKey('track[1]'), isFalse);
      });
    });

    test('неизвестная длительность трек не засчитывает', () {
      final c = _container(_connected());
      final lfm = c.read(lastfmProvider.notifier);
      lfm.onTrackStart(_track('Song'));
      lfm.onProgress(const Duration(seconds: 300), null);
      expect(_methodCall('track.scrobble'), isNull);
    });

    test('без подключения не шлём ничего', () {
      final c = _container(
        JsonStore.memory({
          'lastfm': {'apiKey': 'KEY', 'apiSecret': 'SECRET', 'scrobble': true},
        }),
      );
      final lfm = c.read(lastfmProvider.notifier);
      lfm.onTrackStart(_track('Song'));
      lfm.onProgress(
        const Duration(seconds: 150),
        const Duration(seconds: 300),
      );
      expect(sent, isEmpty);
    });

    test('выключённый скробблинг не шлёт, но «сейчас играет» продолжает', () {
      final store = _connected();
      store.write('lastfm', {...store.readMap('lastfm'), 'scrobble': false});
      final c = _container(store);
      final lfm = c.read(lastfmProvider.notifier);

      lfm.onTrackStart(_track('Song'));
      lfm.onProgress(
        const Duration(seconds: 150),
        const Duration(seconds: 300),
      );
      expect(_methodCall('track.updateNowPlaying'), isNotNull);
      expect(_methodCall('track.scrobble'), isNull);
    });
  });
}
