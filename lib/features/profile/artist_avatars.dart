/// Artist avatars for the stats top. History keeps only a name, so a real
/// avatar has to be searched by name, but on the platform where they were
/// heard: elsewhere it finds someone else's account. Hence the cache key,
/// platform and name.
///
/// An answer (even empty, not found) caches for 30 days: otherwise each profile
/// opening hits the network for ten requests, and misses again and again.
///
/// Loading is background and optional: with no network or platform the top
/// keeps the artist's most played cover.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/artist_lookup.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../../shared/util/artists.dart';
import 'tally.dart';

/// Cache entry lifetime.
const Duration _ttl = Duration(days: 30);

/// Who to ask and on which platform.
typedef ArtistRef = ({String name, MusicSource source});

/// Key of the cache and avatar map. One function for writing and reading, or
/// the top would look at emptiness.
String artistAvatarKey(MusicSource source, String name) =>
    '${source.id}|${name.trim().toLowerCase()}';

/// What to show for an artist from the stats or a review: the avatar their best
/// track brings, else the one found, else that track's cover.
String? playedArtistAvatar(ArtistPlays a, Map<String, String> found) =>
    ownArtistAvatar(a.track) ??
    found[artistAvatarKey(a.source, a.name)] ??
    a.cover;

class _Cached {
  const _Cached(this.url, this.at);

  /// Empty string: looked and not found. Cached too.
  final String url;
  final int at;
}

final artistAvatarsProvider =
    NotifierProvider<ArtistAvatarsController, Map<String, String>>(
      ArtistAvatarsController.new,
    );

class ArtistAvatarsController extends Notifier<Map<String, String>> {
  final Map<String, _Cached> _cache = {};

  /// Who was already asked this run, so parallel list rebuilds don't send ten
  /// equal requests.
  final Set<String> _inFlight = {};

  /// Loading is asynchronous, and the store may be dropped before it ends.
  bool _disposed = false;

  @override
  Map<String, String> build() {
    ref.onDispose(() => _disposed = true);
    final raw = ref.read(jsonStoreProvider).readMap('artistAvatars');
    for (final e in raw.entries) {
      final v = e.value;
      if (v is! Map) continue;
      // Entries under a bare name have no platform, and can't say whose they
      // are. I drop them, and they get asked again on the right one.
      if (!e.key.contains('|')) continue;
      _cache[e.key] = _Cached(
        v['url'] as String? ?? '',
        (v['t'] as num?)?.toInt() ?? 0,
      );
    }
    return _visible();
  }

  Map<String, String> _visible() => {
    for (final e in _cache.entries)
      if (e.value.url.isNotEmpty) e.key: e.value.url,
  };

  void _save() {
    ref.read(jsonStoreProvider).write('artistAvatars', {
      for (final e in _cache.entries)
        e.key: {'url': e.value.url, 't': e.value.at},
    });
  }

  /// Loads missing avatars. Called from the UI when the top shows; extra calls
  /// are harmless, since a fresh cache requests nothing. Each artist is asked
  /// on THEIR platform; local files are skipped, with nowhere to search.
  Future<void> ensure(Iterable<ArtistRef> artists) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final todo = <ArtistRef>[];
    for (final artist in artists) {
      if (artist.name.trim().isEmpty) continue;
      if (artist.source == MusicSource.local) continue;
      final key = artistAvatarKey(artist.source, artist.name);
      if (_inFlight.contains(key)) continue;
      final cached = _cache[key];
      if (cached != null && now - cached.at < _ttl.inMilliseconds) continue;
      todo.add(artist);
      _inFlight.add(key);
    }
    if (todo.isEmpty) return;

    final registry = ref.read(registryProvider);
    var changed = false;
    for (final artist in todo) {
      final key = artistAvatarKey(artist.source, artist.name);
      final provider = registry.byId(artist.source.id);
      // The platform is off, so no miss is remembered: once on, I'll ask.
      if (provider == null) {
        _inFlight.remove(key);
        continue;
      }
      String url = '';
      try {
        url = (await findArtistByName(provider, artist.name))?.avatar ?? '';
      } catch (_) {
        // No network or a refusal: I remember the miss, so as not to hit it on
        // each profile opening.
      }
      _cache[key] = _Cached(url, DateTime.now().millisecondsSinceEpoch);
      _inFlight.remove(key);
      changed = true;
    }

    if (!changed || _disposed) return;
    _save();
    state = _visible();
  }
}
