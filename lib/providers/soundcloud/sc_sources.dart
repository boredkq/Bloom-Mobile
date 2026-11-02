/// SoundCloud similar tracks with a queue and cache. Over [sc.stationTracks]
/// and [sc.relatedTracks] there are three things without which frequent
/// requests hit 429: a sequential queue with a pause between requests, a
/// session answer cache and one retry after a refusal. In the platform layer
/// rather than the wave: home shelves use the same sources, and their queue
/// must be shared.
///
/// An empty list instead of an exception on purpose: the wave and shelves poll
/// seeds in batches, and one failed request mustn't bring down the picks.
library;

import 'dart:async';

import 'models.dart';
import 'soundcloud.dart' as sc;

const Duration _stationTtl = Duration(minutes: 5);
const Duration _relatedTtl = Duration(minutes: 10);

/// Pause between outgoing api-v2 requests.
const Duration _minGap = Duration(milliseconds: 150);

/// Backoff before a retry after a too often answer.
const Duration _retryDelay = Duration(seconds: 2);

/// Similar tracks counted as enough, with no filling up from a station.
const int _similarEnough = 12;

class _CacheEntry {
  _CacheEntry(this.at, this.data);
  final DateTime at;
  final List<ScRawTrack> data;
}

final Map<String, _CacheEntry> _stationCache = {};
final Map<String, _CacheEntry> _relatedCache = {};

/// Tail of the request queue: each next waits for the previous.
Future<void> _queue = Future.value();
DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

/// Runs a request through the shared queue, keeping the pause from the last.
Future<List<ScRawTrack>> _enqueue(Future<List<ScRawTrack>> Function() fn) {
  final completer = Completer<List<ScRawTrack>>();
  _queue = _queue.then((_) async {
    final gap = _minGap - DateTime.now().difference(_lastRequestAt);
    if (gap > Duration.zero) await Future<void>.delayed(gap);
    _lastRequestAt = DateTime.now();
    try {
      completer.complete(await fn());
    } catch (e, st) {
      completer.completeError(e, st);
    }
  });
  // One request's error mustn't break the queue for the next.
  _queue = _queue.catchError((_) {});
  return completer.future;
}

Future<List<ScRawTrack>> _cached(
  Map<String, _CacheEntry> cache,
  String key,
  Duration ttl,
  Future<List<ScRawTrack>> Function() fetch,
) async {
  final hit = cache[key];
  if (hit != null && DateTime.now().difference(hit.at) < ttl) return hit.data;

  try {
    return _store(cache, key, await _enqueue(fetch));
  } catch (_) {
    // One retry with backoff: it's usually a rate refusal. On an ERROR, not
    // emptiness: an empty answer means the station ended, and two seconds for
    // the same answer is pointless.
    try {
      await Future<void>.delayed(_retryDelay);
      return _store(cache, key, await _enqueue(fetch));
    } catch (_) {
      return const [];
    }
  }
}

/// Remembers an answer. Only non-empty ones cache: emptiness would wait out the
/// whole term, though the station may have just blinked.
List<ScRawTrack> _store(
  Map<String, _CacheEntry> cache,
  String key,
  List<ScRawTrack> data,
) {
  if (data.isNotEmpty) cache[key] = _CacheEntry(DateTime.now(), data);
  return data;
}

/// A seed station's tracks at offset [offset].
Future<List<ScRawTrack>> waveStation(String scTrackId, {int offset = 0}) =>
    _cached(
      _stationCache,
      '$scTrackId@$offset',
      _stationTtl,
      () => sc.stationTracks(scTrackId, offset: offset),
    );

/// Similar to a seed.
Future<List<ScRawTrack>> waveRelated(String scTrackId) => _cached(
  _relatedCache,
  scTrackId,
  _relatedTtl,
  () => sc.relatedTracks(scTrackId),
);

/// Similar to a track for home shelves, on the wave's network with its caches
/// and pauses. The station mixes in only when related are few: related are
/// truly similar, while a station is closer to radio and dilutes the selection.
/// The seed and repeats are removed: the seed already tops its listener's
/// chart.
Future<List<ScRawTrack>> similarTracks(String scTrackId) async {
  final seed = int.tryParse(scTrackId) ?? 0;
  final seen = <int>{};
  final out = <ScRawTrack>[];
  void take(List<ScRawTrack> raw) {
    for (final t in raw) {
      if (t.id == 0 || t.id == seed || !seen.add(t.id)) continue;
      out.add(t);
    }
  }

  take(await waveRelated(scTrackId));
  if (out.length < _similarEnough) take(await waveStation(scTrackId));
  return out;
}

/// Clears the cache before a new wave, so it isn't built from the same answers
/// as the last.
void resetWaveSourceCache() {
  _stationCache.clear();
  _relatedCache.clear();
}
