/// What the caches take, for the Storage page. The sum of what the page lists,
/// not the whole folder, or clearing a row wouldn't shrink the ring. The
/// library and one's own covers aren't here: they were put together by hand,
/// "Clear all" must not touch them.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/cover_cache.dart';
import '../../core/store/cover_store.dart';
import '../customization/custom_store.dart';
import '../customization/media_store.dart';
import '../lyrics/lyrics_store.dart';
import '../offline/offline_store.dart';

/// In the page's order; the ring's arcs go the same way round.
enum CacheKind { lyrics, covers, offline, custom }

/// An arc of the ring, in degrees clockwise from the right.
typedef StorageArc = ({int index, double start, double sweep});

class CacheStat {
  const CacheStat({
    required this.kind,
    required this.count,
    required this.bytes,
  });

  final CacheKind kind;
  final int count;
  final int bytes;

  bool get isEmpty => count == 0;
}

class StorageStats {
  const StorageStats({required this.caches});

  final List<CacheStat> caches;

  CacheStat of(CacheKind kind) =>
      caches.firstWhere((c) => c.kind == kind, orElse: () => _empty(kind));

  int get bytes => caches.fold(0, (sum, c) => sum + c.bytes);
  int get count => caches.fold(0, (sum, c) => sum + c.count);

  /// End to end from the top. A cache too small to see still gets a sliver,
  /// taken from the others.
  List<StorageArc> get arcs {
    const sliver = 3.0;
    final total = bytes;
    final on = [
      for (final kind in CacheKind.values)
        if (of(kind).bytes > 0) of(kind),
    ];
    bool small(CacheStat c) => c.bytes / total * 360 < sliver;
    final big = on.where((c) => !small(c)).fold(0, (s, c) => s + c.bytes);
    final share = 360 - on.where(small).length * sliver;
    var at = -90.0;
    return [
      for (final c in on)
        () {
          final sweep = small(c) ? sliver : c.bytes / big * share;
          final arc = (index: c.kind.index, start: at, sweep: sweep);
          at += sweep;
          return arc;
        }(),
    ];
  }

  static CacheStat _empty(CacheKind kind) =>
      CacheStat(kind: kind, count: 0, bytes: 0);
}

/// `autoDispose`: only while the page is open, each check walks folders.
final storageStatsProvider = FutureProvider.autoDispose<StorageStats>((
  ref,
) async {
  // Downloads and pictures recount by themselves, their numbers live in
  // stores; the lyrics are recounted by the screen after a clear or a new
  // time limit.
  ref.watch(offlineProvider.select((s) => s.files.length));
  final media = ref.watch(mediaLibProvider);

  final offline = await ref.read(offlineProvider.notifier).stats();
  final lyrics = ref.read(lyricsCacheProvider).stats();
  final covers = await coverCacheStats();
  final custom = await _mediaStats(media);

  return StorageStats(
    caches: [
      CacheStat(
        kind: CacheKind.lyrics,
        count: lyrics.count,
        bytes: lyrics.bytes,
      ),
      CacheStat(
        kind: CacheKind.covers,
        count: covers.count,
        bytes: covers.bytes,
      ),
      CacheStat(
        kind: CacheKind.offline,
        count: offline.count,
        bytes: offline.bytes,
      ),
      CacheStat(
        kind: CacheKind.custom,
        count: custom.count,
        bytes: custom.bytes,
      ),
    ],
  );
});

/// Returns how many went; the toast shows it. Takes the container, not the
/// page's ref: the page may be closed before the files are gone.
Future<int> clearCache(ProviderContainer box, CacheKind kind) async {
  final deleted = switch (kind) {
    CacheKind.lyrics => box.read(lyricsCacheProvider).clear(),
    CacheKind.covers => await clearCoverCache(),
    CacheKind.offline => await box.read(offlineProvider.notifier).clearAll(),
    // One by one: a picture may be a background or a cover, and a link to a
    // gone file would leave its place empty.
    CacheKind.custom => _clearMedia(box),
  };
  box.invalidate(storageStatsProvider);
  return deleted;
}

int _clearMedia(ProviderContainer box) {
  final ids = [for (final item in box.read(mediaLibProvider)) item.id];
  for (final id in ids) {
    removeMedia(box.read, id);
  }
  return ids.length;
}

/// Only one's own files: a linked picture takes no room here.
Future<({int count, int bytes})> _mediaStats(List<MediaItem> items) async {
  var count = 0;
  var bytes = 0;
  for (final item in items) {
    final path = localCoverPath(item.src);
    if (path == null) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    count++;
    try {
      bytes += await file.length();
    } catch (_) {
      // Gone between the check and the read: it just doesn't count.
    }
  }
  return (count: count, bytes: bytes);
}
