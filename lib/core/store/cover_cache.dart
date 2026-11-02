/// Platform covers on disk: a file per url, 300 MB at most, oldest out first.
/// How long they stay is the owner's choice; a cleared one just downloads again.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'cache_keep.dart';
import 'json_store.dart' show jsonStoreProvider;

const int _limit = 300 << 20;
const String _tmp = '.tmp';

Directory? _dir;

/// Runs before the first frame: [coverCacheReady] is asked while building.
Future<void> initCoverCache() async {
  try {
    final root = await getApplicationCacheDirectory();
    final dir = Directory('${root.path}/covers');
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
  } catch (_) {
    // No place to write: covers stay in memory only.
  }
}

@visibleForTesting
void setCoverCacheDirForTest(Directory? dir) => _dir = dir;

bool get coverCacheReady => _dir != null;

/// The network — swapped in tests.
Future<Uint8List> Function(String url) coverFetch = _fetch;

final http.Client _http = http.Client();

Future<Uint8List> _fetch(String url) async {
  final res = await _http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
    throw HttpException('cover: ${res.statusCode}', uri: Uri.parse(url));
  }
  return res.bodyBytes;
}

/// Several surfaces ask for one cover at once, in different sizes: one download.
final Map<String, Future<Uint8List>> _fetching = {};

Future<Uint8List> _once(String url) => _fetching.putIfAbsent(
  url,
  () => coverFetch(url).whenComplete(() {
    _fetching.remove(url);
  }),
);

File? _fileOf(String url) {
  final dir = _dir;
  if (dir == null) return null;
  return File('${dir.path}/${sha1.convert(url.codeUnits)}');
}

// Written beside and renamed, so a killed app leaves no half of a picture.
Future<void> _save(File file, Uint8List bytes) async {
  final tmp = File('${file.path}.${Random().nextInt(1 << 32)}$_tmp');
  try {
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  } catch (_) {
    try {
      await tmp.delete();
    } catch (_) {}
  }
}

/// A platform cover: from the disk if it's there, else downloaded and kept.
@immutable
class CachedCover extends ImageProvider<CachedCover> {
  const CachedCover(this.url);

  final String url;

  @override
  Future<CachedCover> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedCover>(this);

  @override
  ImageStreamCompleter loadImage(
    CachedCover key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: key.loadWith(
      (bytes) async => decode(await ui.ImmutableBuffer.fromUint8List(bytes)),
    ),
    scale: 1,
    debugLabel: url,
  );

  @visibleForTesting
  Future<T> loadWith<T>(Future<T> Function(Uint8List bytes) decode) async {
    try {
      final file = _fileOf(url);
      if (file != null && await file.exists()) {
        try {
          return await decode(await file.readAsBytes());
        } catch (_) {
          // Unreadable: I take it again from the network.
          await file.delete().catchError((_) => file);
        }
      }
      final bytes = await _once(url);
      final done = await decode(bytes);
      // Only what decoded goes to disk: an error page must not stay as a cover.
      if (file != null) unawaited(_save(file, bytes));
      return done;
    } catch (_) {
      // A failed one isn't remembered, the next look tries again.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is CachedCover && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

Future<List<File>> _files() async {
  final dir = _dir;
  if (dir == null || !await dir.exists()) return const [];
  return dir.listSync().whereType<File>().toList();
}

/// Files without the ones still being written.
Future<({int count, int bytes})> coverCacheStats() async {
  var count = 0;
  var bytes = 0;
  for (final file in await _files()) {
    if (file.path.endsWith(_tmp)) continue;
    try {
      bytes += await file.length();
      count++;
    } catch (_) {}
  }
  return (count: count, bytes: bytes);
}

Future<int> _dropBefore(DateTime before) async {
  var gone = 0;
  for (final file in await _files()) {
    try {
      if (file.lastModifiedSync().isBefore(before)) {
        await file.delete();
        gone++;
      }
    } catch (_) {}
  }
  return gone;
}

/// Returns how many were dropped.
Future<int> clearCoverCache() =>
    _dropBefore(DateTime.now().add(const Duration(seconds: 1)));

/// Drops the ones older than [keep] allows; returns how many.
Future<int> purgeCoverCache(CacheKeep keep) async {
  final days = keep.days;
  if (days == null) return 0;
  return _dropBefore(DateTime.now().subtract(Duration(days: days)));
}

Future<void> _trim() async {
  final found = <(File, DateTime, int)>[];
  for (final file in await _files()) {
    try {
      found.add((file, file.lastModifiedSync(), file.lengthSync()));
    } catch (_) {}
  }
  var total = found.fold(0, (sum, f) => sum + f.$3);
  if (total <= _limit) return;
  found.sort((a, b) => a.$2.compareTo(b.$2));
  for (final (file, _, size) in found) {
    if (total <= _limit) break;
    try {
      await file.delete();
      total -= size;
    } catch (_) {}
  }
}

/// At launch: "until restart" empties the folder, a time limit trims it, and
/// the size limit holds either way.
Future<void> startCoverCache(CacheKeep keep) async {
  if (keep == CacheKeep.restart) {
    await clearCoverCache();
  } else {
    await purgeCoverCache(keep);
  }
  await _trim();
}

final coverKeepProvider = NotifierProvider<CoverKeepController, CacheKeep>(
  CoverKeepController.new,
);

class CoverKeepController extends Notifier<CacheKeep> {
  static const _key = 'covers';

  @override
  CacheKeep build() =>
      CacheKeep.of(ref.read(jsonStoreProvider).readMap(_key)['keep']);

  /// A time limit applies at once; returns how many went out of date.
  Future<int> set(CacheKeep keep) {
    state = keep;
    ref.read(jsonStoreProvider).write(_key, {'keep': keep.id});
    return keep == CacheKeep.restart ? Future.value(0) : purgeCoverCache(keep);
  }
}
