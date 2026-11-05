/// Lyrics: reading LRC, the line for a position, the query cleanup and
/// scoring, the kept lyrics in the database and the store following the track.
///
/// The texts are synthetic ("line one"): real songs have no place here.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/lyrics/lrc.dart';
import 'package:bloom/features/lyrics/lyrics_api.dart';
import 'package:bloom/features/lyrics/lyrics_cache.dart';
import 'package:bloom/features/lyrics/lyrics_store.dart';
import 'package:bloom/features/lyrics/ui/lyrics_view.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = Track(
  id: 'sc:1',
  name: 'Song',
  artist: 'Band',
  duration: Duration(seconds: 180),
  source: MusicSource.soundcloud,
);

const _other = Track(
  id: 'sc:2',
  name: 'Other',
  artist: 'Band',
  duration: Duration(seconds: 60),
  source: MusicSource.soundcloud,
);

/// The playing track, moved by hand.
final _playing = StateProvider<Track?>((ref) => _track);

/// A container with LRCLIB swapped for [answer].
ProviderContainer _container({
  required Future<LyricsResult> Function(String title) answer,
  JsonStore? store,
  BloomDb? db,
  Duration position = Duration.zero,
  void Function()? onFetch,
}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store ?? JsonStore.memory()),
      dbProvider.overrideWithValue(db ?? BloomDb.memory()),
      lyricsTrackProvider.overrideWith((ref) => ref.watch(_playing)),
      lyricsFetcherProvider.overrideWithValue(({
        required artist,
        required title,
        durationSec,
        trackId,
        album,
      }) {
        onFetch?.call();
        return answer(title);
      }),
      playheadProvider.overrideWith(
        (ref) => Stream.value((
          position: position,
          total: const Duration(minutes: 3),
        )),
      ),
      playingProvider.overrideWith((ref) => Stream.value(false)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Lets the store pick the track up and the fake network answer.
Future<LyricsState> _settle(ProviderContainer c) async {
  c.read(lyricsProvider);
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(lyricsProvider);
}

void main() {
  group('parseLrc', () {
    test('reads the stamps and sorts by time', () {
      final lines = parseLrc('[00:12.50]second\n[00:03.00]first\n');
      expect(lines.map((l) => l.text), ['first', 'second']);
      expect(lines.first.time, 3.0);
      expect(lines.last.time, 12.5);
    });

    test('minutes become seconds', () {
      expect(parseLrc('[02:05.00]x').single.time, 125.0);
    });

    test('a line with several stamps stands at each', () {
      final lines = parseLrc('[00:01.00][00:20.00]chorus\n[00:10.00]verse');
      expect(lines.map((l) => l.text), ['chorus', 'verse', 'chorus']);
      expect(lines.map((l) => l.time), [1.0, 10.0, 20.0]);
    });

    test('a colon before the hundredths is read too', () {
      expect(parseLrc('[00:07:50]a').single.time, 7.5);
    });

    test('stamps without text are dropped', () {
      final lines = parseLrc('[00:01.00]a\n[00:02.00]\n[00:03.00]   \n');
      expect(lines.map((l) => l.text), ['a']);
    });

    test('rows without a stamp are ignored', () {
      expect(parseLrc('[ar:Band]\nplain row\n[00:01.00]a').length, 1);
    });

    test('the fraction is optional', () {
      expect(parseLrc('[00:07]a').single.time, 7.0);
    });

    test('equal times keep the row order', () {
      final lines = parseLrc('[00:05.00]b\n[00:05.00]a');
      expect(lines.map((l) => l.text), ['b', 'a']);
    });

    test('parses section markers and attaches to timed lines', () {
      final lines = parseLrc(
        '[Chorus]\n[00:15.00]We will rock you\n[Verse 1]\n[00:30.00]Buddy, you\'re a boy',
      );
      expect(lines.first.section, 'Chorus');
      expect(lines.first.text, 'We will rock you');
      expect(lines.last.section, 'Verse 1');
      expect(lines.last.text, "Buddy, you're a boy");
    });

    test('adds romanization to foreign scripts', () {
      final lines = parseLrc('[00:05.00]さくら\n[00:10.00]Привет');
      expect(lines.first.romanized, 'sakura');
      expect(lines.last.romanized, 'Privet');
    });

    test('parses enhanced LRC word timestamps', () {
      final lines = parseLrc(
        '[00:10.00] <00:10.00>Never <00:10.50>gonna <00:11.00>give',
      );
      expect(lines.single.time, 10.0);
      expect(lines.single.text, 'Never gonna give');
      expect(lines.single.words.length, 3);
      expect(lines.single.words[0].text, 'Never');
      expect(lines.single.words[0].start, 10.0);
      expect(lines.single.words[0].end, 10.5);
      expect(lines.single.words[1].text, 'gonna');
      expect(lines.single.words[2].text, 'give');
    });
  });

  test('stripLrc drops the stamps', () {
    expect(stripLrc('[00:01.00]a\n[00:02.50]b'), 'a\nb');
  });

  group('activeLineAt', () {
    final lines = parseLrc('[00:10.00]a\n[00:20.00]b\n[00:30.00]c');

    test('before the first line — the intro', () {
      expect(activeLineAt(lines, 0), -1);
      expect(activeLineAt(lines, 9.5), -1);
    });

    test('a line lights up a quarter of a second early', () {
      expect(activeLineAt(lines, 9.8), 0);
      expect(activeLineAt(lines, 19.9), 1);
    });

    test('after the last one the last stays', () {
      expect(activeLineAt(lines, 300), 2);
    });

    test('no lines — nothing to light', () {
      expect(activeLineAt(const [], 10), -1);
    });
  });

  group('normalizeForSearch', () {
    test('drops (feat. …) and any brackets', () {
      expect(normalizeForSearch('Song (feat. Someone)'), 'Song');
      expect(normalizeForSearch('Song [Remix]'), 'Song');
    });

    test('drops the video junk', () {
      expect(normalizeForSearch('Song Official Video'), 'Song');
      expect(normalizeForSearch('Song prod. by Someone'), 'Song');
    });

    test('a clean title stays', () {
      expect(normalizeForSearch('Song'), 'Song');
    });
  });

  test('primaryArtist takes the first of a line', () {
    expect(primaryArtist('A, B & C'), 'A');
    expect(primaryArtist('A feat. B'), 'A');
    expect(primaryArtist('Solo'), 'Solo');
  });

  group('scoreHit', () {
    test('the same title and artist — the most', () {
      expect(
        scoreHit(
          hitTitle: 'Song',
          hitArtist: 'Band',
          queryTitle: 'Song',
          queryArtist: 'Band',
        ),
        100,
      );
    });

    test('another song stays below the bar', () {
      expect(
        scoreHit(
          hitTitle: 'Totally Other',
          hitArtist: 'Someone Else',
          queryTitle: 'Song',
          queryArtist: 'Band',
        ),
        lessThan(kMinSearchScore),
      );
    });

    test('a title with junk is still recognised', () {
      expect(
        scoreHit(
          hitTitle: 'Song',
          hitArtist: 'Band',
          queryTitle: 'Song (Official Video)',
          queryArtist: 'Band',
        ),
        greaterThanOrEqualTo(kMinSearchScore),
      );
    });
  });

  group('LyricsCache', () {
    const found = LyricsResult(plain: 'x', source: 'lrclib');

    test('kept lyrics come back from the database', () {
      final cache = LyricsCache(BloomDb.memory());
      final key = LyricsCache.keyOf('Band', 'Song');
      cache.remember(key, found, keep: true);
      expect(cache.read(key)?.plain, 'x');
      expect(cache.read(LyricsCache.keyOf('BAND', 'song'))?.plain, 'x');
      expect(cache.stats().count, 1);
    });

    test('without "keep" nothing is written', () {
      final cache = LyricsCache(BloomDb.memory());
      final key = LyricsCache.keyOf('Band', 'Song');
      cache.remember(key, found, keep: false);
      expect(cache.read(key), isNull);
    });

    test('a miss is remembered in memory', () {
      final cache = LyricsCache(BloomDb.memory());
      final key = LyricsCache.keyOf('Band', 'Song');
      cache.remember(key, LyricsResult.none, keep: true);
      expect(cache.read(key)?.ok, isFalse);
      expect(cache.stats().count, 0);
    });

    test('a time limit drops the older ones, "until restart" all', () {
      final db = BloomDb.memory();
      final cache = LyricsCache(db);
      cache.remember('a::old', found, keep: true);
      cache.remember('a::new', found, keep: true);
      db.exec("UPDATE lyrics SET at = at - 2 * 86400000 WHERE key = 'a::old'");
      expect(cache.purge(CacheKeep.day), 1);
      expect(cache.read('a::new'), isNotNull);
      cache.start(CacheKeep.restart);
      expect(cache.stats().count, 0);
    });

    test('older than 30 days is not read', () {
      final db = BloomDb.memory();
      final cache = LyricsCache(db)..remember('a::b', found, keep: true);
      db.exec('UPDATE lyrics SET at = at - 31 * 86400000');
      expect(cache.read('a::b'), isNull);
    });
  });

  group('LyricsController', () {
    test('timed lyrics become lines, the plain text built from them', () async {
      final c = _container(
        answer: (_) async => const LyricsResult(synced: '[00:01.00]line one'),
      );
      final state = await _settle(c);
      expect(state.status, LyricsStatus.ready);
      expect(state.lines.single.text, 'line one');
      expect(state.plain, 'line one');
    });

    test('plain lyrics stay plain', () async {
      final c = _container(
        answer: (_) async => const LyricsResult(plain: 'line one'),
      );
      expect((await _settle(c)).lines, isEmpty);
    });

    test('nothing found — empty, and the open lyrics close', () async {
      final c = _container(answer: (_) async => LyricsResult.none);
      c.read(lyricsOpenProvider.notifier).state = true;
      expect((await _settle(c)).status, LyricsStatus.empty);
      expect(c.read(lyricsOpenProvider), isFalse);
    });

    test('follows the playing track', () async {
      final c = _container(answer: (title) async => LyricsResult(plain: title));
      expect((await _settle(c)).plain, 'Song');
      c.read(_playing.notifier).state = _other;
      final state = await _settle(c);
      expect(state.trackId, 'sc:2');
      expect(state.plain, 'Other');
    });

    test('a miss is not asked again for 5 minutes', () async {
      var calls = 0;
      final c = _container(
        answer: (_) async => LyricsResult.none,
        onFetch: () => calls++,
      );
      await _settle(c);
      c.read(_playing.notifier).state = _other;
      await _settle(c);
      c.read(_playing.notifier).state = _track;
      await _settle(c);
      expect(calls, 2);
    });

    test('kept only while "keep lyrics" is on', () async {
      final db = BloomDb.memory();
      final store = JsonStore.memory();
      final c = _container(
        answer: (_) async => const LyricsResult(plain: 'x', source: 'lrclib'),
        db: db,
        store: store,
      );
      await _settle(c);
      expect(c.read(lyricsCacheProvider).stats().count, 0);

      c.read(lyricsPrefsProvider.notifier).setCache(true);
      c.read(_playing.notifier).state = _other;
      await _settle(c);
      expect(c.read(lyricsCacheProvider).stats().count, 1);
    });

    test('an answer for a track left behind is dropped', () async {
      final c = _container(
        answer: (title) async {
          if (title == 'Song') {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          return LyricsResult(plain: title);
        },
      );
      c.read(lyricsProvider);
      await Future<void>.delayed(Duration.zero);
      c.read(_playing.notifier).state = _other;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.read(lyricsProvider).plain, 'Other');
      expect(c.read(lyricsProvider).trackId, 'sc:2');
    });

    test('no track — idle', () async {
      final c = _container(answer: (_) async => const LyricsResult(plain: 'x'));
      await _settle(c);
      c.read(_playing.notifier).state = null;
      final state = await _settle(c);
      expect(state.status, LyricsStatus.idle);
      expect(state.plain, isEmpty);
    });

    test('the sung line follows the position', () async {
      final c = _container(
        answer: (_) async =>
            const LyricsResult(synced: '[00:10.00]a\n[00:20.00]b'),
        position: const Duration(seconds: 21),
      );
      c.listen(playheadProvider, (_, _) {});
      await _settle(c);
      expect(c.read(lyricsLineProvider), 1);
    });
  });

  group('LyricsPrefs', () {
    test('defaults — over the cover, not kept', () {
      final c = _container(answer: (_) async => LyricsResult.none);
      final prefs = c.read(lyricsPrefsProvider);
      expect(prefs.mode, LyricsMode.overlay);
      expect(prefs.cache, isFalse);
      expect(prefs.keep, CacheKeep.never);
    });

    test('saved and read back; unknown values fall back', () {
      final store = JsonStore.memory();
      final first = _container(
        answer: (_) async => LyricsResult.none,
        store: store,
      );
      first.read(lyricsPrefsProvider.notifier)
        ..setMode(LyricsMode.replace)
        ..setKeep(CacheKeep.week);
      final second = _container(
        answer: (_) async => LyricsResult.none,
        store: store,
      );
      expect(second.read(lyricsPrefsProvider).mode, LyricsMode.replace);
      expect(second.read(lyricsPrefsProvider).keep, CacheKeep.week);

      final odd = _container(
        answer: (_) async => LyricsResult.none,
        store: JsonStore.memory({
          'lyrics': {'mode': 'nonsense', 'keep': '2y'},
        }),
      );
      expect(odd.read(lyricsPrefsProvider).mode, LyricsMode.overlay);
      expect(odd.read(lyricsPrefsProvider).keep, CacheKeep.never);
    });
  });

  group('LyricsView', () {
    Future<void> pump(
      WidgetTester tester, {
      required String synced,
      required Duration position,
    }) async {
      final c = _container(
        answer: (_) async => LyricsResult(synced: synced),
        position: position,
      );
      await tester.runAsync(() => _settle(c));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildBloomTheme(BloomThemes.dark),
            home: const Scaffold(body: LyricsView()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('the sung line is the one whose time has come', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        synced: '[00:10.00]line one\n[00:20.00]line two\n[00:30.00]line three',
        position: const Duration(seconds: 21),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('line two')),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('line one')),
        isSemantics(isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('none is sung before the first line', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        synced: '[00:10.00]line one\n[00:20.00]line two',
        position: Duration.zero,
      );
      for (final label in ['line one', 'line two']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isSelected: false),
        );
      }
      handle.dispose();
    });
  });
}
