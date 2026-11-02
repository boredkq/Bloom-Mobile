/// The cover cache: what lands on the disk, what doesn't, and when it leaves.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bloom/core/store/cache_keep.dart';
import 'package:bloom/core/store/cover_cache.dart';
import 'package:bloom/core/store/cover_store.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final Uint8List _png = Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]);

/// True if the cover came and "decoded": a picture starts with its signature.
Future<bool> _load(String url) async {
  try {
    await CachedCover(url).loadWith((bytes) async {
      if (bytes.isEmpty || bytes.first != 0x89) {
        throw StateError('not a picture');
      }
    });
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late int fetched;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bloom_covers');
    setCoverCacheDirForTest(dir);
    fetched = 0;
    coverFetch = (_) async {
      fetched++;
      return _png;
    };
  });

  tearDown(() async {
    // A save may still be renaming its file.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    setCoverCacheDirForTest(null);
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a file; it's the system's temp folder.
    }
  });

  Future<void> waitForFiles(int n) async {
    for (var i = 0; i < 200; i++) {
      if ((await coverCacheStats()).count == n) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('expected $n files, got ${(await coverCacheStats()).count}');
  }

  test('a platform cover goes through the cache, a missing folder past it', () {
    expect(coverImage('https://x/a.jpg'), isA<CachedCover>());
    setCoverCacheDirForTest(null);
    expect(coverImage('https://x/a.jpg'), isA<NetworkImage>());
  });

  test('downloaded once, then read from the disk', () async {
    expect(await _load('https://x/a.jpg'), isTrue);
    await waitForFiles(1);
    expect(await _load('https://x/a.jpg'), isTrue);
    expect(fetched, 1);
    expect((await coverCacheStats()).bytes, _png.length);
  });

  test('what does not decode is not kept', () async {
    coverFetch = (_) async => Uint8List.fromList('<html>'.codeUnits);
    expect(await _load('https://x/bad.jpg'), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect((await coverCacheStats()).count, 0);
  });

  test('a broken file is taken again from the network', () async {
    await _load('https://x/a.jpg');
    await waitForFiles(1);
    final file = dir.listSync().whereType<File>().single;
    file.writeAsStringSync('broken');

    expect(await _load('https://x/a.jpg'), isTrue);
    expect(fetched, 2);
  });

  test('a time limit drops the old, "never" nothing', () async {
    await _load('https://x/old.jpg');
    await _load('https://x/new.jpg');
    await waitForFiles(2);
    dir.listSync().whereType<File>().first.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 2)),
    );

    expect(await purgeCoverCache(CacheKeep.never), 0);
    expect(await purgeCoverCache(CacheKeep.week), 0);
    expect(await purgeCoverCache(CacheKeep.day), 1);
    expect((await coverCacheStats()).count, 1);
  });

  test(
    '"until restart" empties at launch, clearing counts what went',
    () async {
      await _load('https://x/a.jpg');
      await waitForFiles(1);
      await startCoverCache(CacheKeep.never);
      expect((await coverCacheStats()).count, 1);
      await startCoverCache(CacheKeep.restart);
      expect((await coverCacheStats()).count, 0);

      await _load('https://x/b.jpg');
      await waitForFiles(1);
      expect(await clearCoverCache(), 1);
    },
  );

  test('over the limit the oldest go first', () async {
    // Sparse files: only the size matters here.
    for (final (name, ageDays) in [('old', 3), ('mid', 2), ('new', 1)]) {
      final f = File('${dir.path}/$name');
      final raf = f.openSync(mode: FileMode.write)
        ..truncateSync(120 << 20)
        ..closeSync();
      expect(raf, isNotNull);
      f.setLastModifiedSync(DateTime.now().subtract(Duration(days: ageDays)));
    }
    await startCoverCache(CacheKeep.never);
    final left = dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    expect(left, {'mid', 'new'});
  });

  test('the time limit is a setting that survives a restart', () async {
    final store = JsonStore.memory();
    final first = ProviderContainer(
      overrides: [jsonStoreProvider.overrideWithValue(store)],
    );
    addTearDown(first.dispose);
    expect(first.read(coverKeepProvider), CacheKeep.never);
    await first.read(coverKeepProvider.notifier).set(CacheKeep.week);

    final second = ProviderContainer(
      overrides: [jsonStoreProvider.overrideWithValue(store)],
    );
    addTearDown(second.dispose);
    expect(second.read(coverKeepProvider), CacheKeep.week);
  });
}
