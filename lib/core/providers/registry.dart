/// Registry of music providers. A platform registers once at launch and the UI
/// asks the registry. A level below lies stream resolving
/// (`MusicProvider.resolveStream`): how to get the sound, while this is how to
/// search and serve entities.
library;

import 'dart:async';

import '../entities/entities.dart';
import 'music_provider.dart';

/// Sentinel for all sources in the platform picker.
const String kAllProviders = 'all';

class ProviderRegistry {
  final List<MusicProvider> _providers = [];

  /// Registers, or replaces by id.
  void register(MusicProvider p) {
    final i = _providers.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      _providers[i] = p;
    } else {
      _providers.add(p);
    }
  }

  /// Enabled providers, in registration order.
  List<MusicProvider> get enabled =>
      _providers.where((p) => p.isEnabled).toList();

  /// All registered, disabled too, for the picker, which always shows them.
  List<MusicProvider> get all => List.unmodifiable(_providers);

  MusicProvider? byId(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Who to ask: one platform or all enabled. An explicitly picked one is
  /// honoured even if off: the picker shows all, and the provider returns a
  /// result or an error. Not found at all (a stale id from settings) falls back
  /// to enabled.
  List<MusicProvider> _pick(String? providerId) {
    final onlyId = (providerId != null && providerId != kAllProviders)
        ? providerId
        : null;
    final enabledNow = enabled;
    if (onlyId == null) return enabledNow;
    final picked = all.where((p) => p.id == onlyId).toList();
    return picked.isEmpty ? enabledNow : picked;
  }

  /// Searches all enabled platforms in parallel and merges results. A failed
  /// provider just adds nothing.
  ///
  /// Per-provider timeout: one slow platform (SoundCloud scraping client_id)
  /// shouldn't hold everything. A timeout contributes nothing, like an error.
  /// With one source there's nothing to wait for, so it gets longer.
  Future<SearchResults> searchAll(
    String query, {
    String? providerId,
    SearchSort sort = SearchSort.relevance,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return SearchResults.empty;

    final providers = _pick(providerId);
    final onlyOne = providers.length == 1;
    final timeout = Duration(seconds: onlyOne ? 30 : 12);

    final responses = await Future.wait(
      providers.map(
        (p) => p
            .search(q, sort: sort)
            .timeout(timeout)
            .then<SearchResults?>((v) => v, onError: (_) => null),
      ),
    );

    final artists = <Artist>[];
    final playlists = <Playlist>[];
    final albums = <Playlist>[];
    final tracks = <Track>[];
    var hasMore = false;
    for (final r in responses) {
      if (r == null) continue;
      artists.addAll(r.artists);
      playlists.addAll(r.playlists);
      albums.addAll(r.albums);
      tracks.addAll(r.tracks);
      if (r.tracksHasMore) hasMore = true;
    }
    return SearchResults(
      artists: artists,
      playlists: playlists,
      albums: albums,
      tracks: tracks,
      tracksHasMore: hasMore,
    );
  }

  /// Loads more tracks across all platforms or the picked one.
  Future<TrackPage> loadMoreTracksAll(
    String query,
    int offset, {
    String? providerId,
    SearchSort sort = SearchSort.relevance,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const TrackPage();

    final responses = await Future.wait(
      _pick(providerId).map(
        (p) => p
            .loadMoreTracks(q, offset, sort: sort)
            .then<TrackPage?>((v) => v, onError: (_) => null),
      ),
    );

    final tracks = <Track>[];
    var hasMore = false;
    for (final r in responses) {
      if (r == null) continue;
      tracks.addAll(r.tracks);
      if (r.hasMore) hasMore = true;
    }
    return TrackPage(tracks: tracks, hasMore: hasMore);
  }

  /// Resolves a pasted link: asks the platforms, the first non-empty answer
  /// wins.
  Future<({MusicProvider provider, ResolvedUrl resolved})?> resolveUrlAny(
    String url,
  ) async {
    for (final p in enabled) {
      try {
        final resolved = await p.resolveUrl(url);
        if (resolved != null) return (provider: p, resolved: resolved);
      } catch (_) {
        // try the next platform
      }
    }
    return null;
  }

  /// A platform of an entity by its global id prefix.
  MusicProvider? forEntity(String entityId) =>
      byId(MusicSource.fromId(entityId).id);
}
