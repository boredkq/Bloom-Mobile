/// Charts and new releases on home. Platform-agnostic: a chart is always
/// tracks, new releases are albums (Yandex, YTM) or tracks (SoundCloud New &
/// Hot). The platform is the first that has the method, with no switch, just
/// its logo by the title.
///
/// An empty answer from Yandex is nearly always a transient failure, so empty
/// ISN'T cached and the request quietly retries. With no data the section
/// doesn't show: an empty place beats a blinking stand-in.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import '../../core/providers/registry.dart';

enum DiscoverMode { charts, newReleases }

/// Block content: tracks or albums.
sealed class DiscoverBlock {
  const DiscoverBlock();

  bool get isEmpty;
}

class DiscoverTracks extends DiscoverBlock {
  const DiscoverTracks(this.tracks);
  final List<Track> tracks;

  @override
  bool get isEmpty => tracks.isEmpty;
}

class DiscoverAlbums extends DiscoverBlock {
  const DiscoverAlbums(this.albums);
  final List<Playlist> albums;

  @override
  bool get isEmpty => albums.isEmpty;
}

/// A loaded block with its platform: the logo by the title comes from this, not
/// from whichever track is first.
class DiscoverResult {
  const DiscoverResult(this.source, this.block);

  final MusicSource source;
  final DiscoverBlock block;
}

/// Block cache lifetime. Charts and new releases change daily; half an hour
/// just avoids the network on each visit to home.
const Duration kDiscoverTtl = Duration(minutes: 30);

/// Pauses before quiet retries if an answer is empty or a request failed; after
/// the last the block stays hidden.
const List<Duration> kDiscoverRetries = [
  Duration(milliseconds: 1500),
  Duration(seconds: 4),
];

class _CacheEntry {
  _CacheEntry(this.result, this.at);
  final DiscoverResult result;
  final DateTime at;
}

/// The cache outlives the provider: leaving home and returning shouldn't hit
/// the network again.
final Map<DiscoverMode, _CacheEntry> _cache = {};

/// Clears the shelf cache (tests and a platform account change).
void resetDiscoverCache() => _cache.clear();

/// One network trip with no retries. An empty result isn't cached.
Future<DiscoverResult?> fetchDiscover(
  ProviderRegistry registry,
  DiscoverMode mode,
) async {
  final hit = _cache[mode];
  if (hit != null && DateTime.now().difference(hit.at) < kDiscoverTtl) {
    return hit.result;
  }
  for (final provider in registry.enabled) {
    final DiscoverBlock? block;
    if (mode == DiscoverMode.charts) {
      final tracks = await provider.getCharts();
      block = tracks == null ? null : DiscoverTracks(tracks);
    } else {
      final releases = await provider.getNewReleases();
      block = switch (releases) {
        null => null,
        NewAlbums(:final albums) => DiscoverAlbums(albums),
        NewTracks(:final tracks) => DiscoverTracks(tracks),
      };
    }
    // The platform has no method, so on to the next; an empty answer counts as
    // THIS platform's failure and also moves on.
    if (block == null || block.isEmpty) continue;
    final result = DiscoverResult(provider.source, block);
    _cache[mode] = _CacheEntry(result, DateTime.now());
    return result;
  }
  return null;
}

/// Shelf block with quiet retries. `null` in data means nothing to show.
final discoverProvider = FutureProvider.family<DiscoverResult?, DiscoverMode>((
  ref,
  mode,
) async {
  final registry = ref.read(registryProvider);
  for (var attempt = 0; ; attempt++) {
    try {
      final result = await fetchDiscover(registry, mode);
      if (result != null) return result;
    } on Object {
      // A platform failure doesn't break the section: it just won't appear.
    }
    if (attempt >= kDiscoverRetries.length) return null;
    await Future<void>.delayed(kDiscoverRetries[attempt]);
  }
});
