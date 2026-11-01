/// SoundCloud api-v2. client_id: manual (from settings), then known ones, then
/// scraping soundcloud.com's assets. Each request races direct and a CORS
/// proxy: the proxy isn't for CORS but a fallback if SoundCloud is blocked for
/// the user; the first good answer wins.
///
/// Errors are dictionary codes (`sc.err.*`, `search.err.*`) in [ScException],
/// translated by the UI.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

const List<String> kKnownClientIds = [
  'O7atZypwLvuWSY9hWnnQ3vrLTHH7wqMe', // current as of 2026-07, from a scrape
  'iZIs9mchVcX5lhVRyQGGAYlNPa2Rp1jf',
  'a3e059563d7fd3372b49b37f00a00bcf',
  'fDoItMDbsbZz8dY16ZzARCZmzgHBPotA',
  'YUKXoArFcqrlQn9tfNHvvyfnDISj04zk',
];

const Duration _clientIdTtl = Duration(hours: 6);

// ============================ client_id state ============================

String? _manualId;
String? _autoId;

/// null when the auto cache is stale or absent, also after falling back to a
/// known id.
DateTime? _fetchedAt;

/// Manual client_id from settings. null or empty resets it, with the auto
/// cache.
void setManualClientId(String? id) {
  final v = id?.trim();
  final norm = (v == null || v.isEmpty) ? null : v;
  if (norm == null) {
    _autoId = null;
    _fetchedAt = null;
  }
  _manualId = norm;
}

String? activeClientId() => _manualId ?? _autoId;

/// Clears the auto cache, not the manual: before [checkConnection] and on an
/// invalid answer.
void _resetAutoCache() {
  if (_manualId == null) {
    _autoId = null;
    _fetchedAt = null;
  }
}

void _clearAuto() {
  _autoId = null;
  _fetchedAt = null;
}

// ── HTTP (direct and proxy race) ────────────────────────────────────────

final http.Client _http = http.Client();

List<String> _proxyUrls(String u) {
  final enc = Uri.encodeComponent(u);
  return [
    'https://corsproxy.io/?$enc',
    'https://api.allorigins.win/raw?url=$enc',
    'https://api.codetabs.com/v1/proxy?quest=$enc',
  ];
}

Future<(int, String)> _get(
  String url,
  Duration timeout, {
  required bool acceptAuthErr,
}) async {
  final r = await _http.get(Uri.parse(url)).timeout(timeout);
  final status = r.statusCode;
  final ok = status >= 200 && status < 300;
  if (ok || (acceptAuthErr && (status == 401 || status == 403))) {
    // I decode the body myself: with no charset in Content-Type http falls to
    // latin1 and breaks Cyrillic titles.
    return (status, utf8.decode(r.bodyBytes, allowMalformed: true));
  }
  throw const ScException('not ok');
}

/// Race of a direct request (8 s) and a proxy (12 s), the first good one wins.
/// [acceptAuthErr] accepts 401 or 403 from the direct one, for [apiFetch]'s
/// known client_id branch; from a proxy only 2xx.
Future<(int, String)> _raceFetch(String url, bool acceptAuthErr) {
  final attempts = <Future<(int, String)>>[
    _get(url, const Duration(seconds: 8), acceptAuthErr: acceptAuthErr),
    for (final p in _proxyUrls(url))
      _get(p, const Duration(seconds: 12), acceptAuthErr: false),
  ];

  final done = Completer<(int, String)>();
  var pending = attempts.length;
  for (final f in attempts) {
    unawaited(
      f.then(
        (v) {
          if (!done.isCompleted) done.complete(v);
        },
        onError: (_) {
          pending--;
          if (pending == 0 && !done.isCompleted) {
            done.completeError(const ScException('sc.err.unavailable'));
          }
        },
      ),
    );
  }
  return done.future;
}

// ============================ client_id ============================

final RegExp _assetRe = RegExp(
  r'src="(https://a-v2\.sndcdn\.com/assets/[^"]*\.js)"',
);
final RegExp _idRe = RegExp(r'client_id:"([a-zA-Z0-9]{20,})"');

/// The active client_id: manual, fresh auto, a scrape of soundcloud.com's
/// assets, then the first known (with no timestamp, so it rechecks next time).
Future<String> _getClientId() async {
  final manual = _manualId;
  if (manual != null) return manual;
  final auto = _autoId;
  final at = _fetchedAt;
  if (auto != null &&
      at != null &&
      DateTime.now().difference(at) < _clientIdTtl) {
    return auto;
  }

  // Scans ALL assets: SoundCloud may put client_id at the list's tail.
  try {
    final (_, html) = await _raceFetch('https://soundcloud.com', false);
    for (final m in _assetRe.allMatches(html).take(16)) {
      try {
        final (_, js) = await _raceFetch(m.group(1)!, false);
        final c = _idRe.firstMatch(js);
        if (c != null) {
          final id = c.group(1)!;
          _autoId = id;
          _fetchedAt = DateTime.now();
          return id;
        }
      } catch (_) {
        // next asset
      }
    }
  } catch (_) {
    // fall through to a known id
  }

  final id = kKnownClientIds[0];
  _autoId = id;
  return id;
}

/// JS-style falsiness for answer fields.
bool _falsy(Object? v) {
  if (v == null) return true;
  if (v is bool) return !v;
  if (v is String) return v.isEmpty;
  if (v is num) return v == 0;
  return false;
}

/// Tries known client_ids; on a valid answer caches the id and returns it.
Future<Object?> _tryKnownIds(String url) async {
  for (final id in kKnownClientIds) {
    final sep = url.contains('?') ? '&' : '?';
    Object? data;
    try {
      final (_, body) = await _raceFetch('$url${sep}client_id=$id', false);
      data = jsonDecode(body);
    } catch (_) {
      continue; // unavailable or not JSON, so try the next id
    }
    if (data is! Map) continue;
    final hasPayload =
        data.containsKey('collection') ||
        data.containsKey('id') ||
        !_falsy(data['url']);
    if (_falsy(data['errors']) && _falsy(data['status']) && hasPayload) {
      _autoId = id;
      _fetchedAt = DateTime.now();
      return data;
    }
  }
  return null;
}

/// An api-v2 request with client_id and auto-recovery on an invalid key (401 or
/// 403, `errors[]`, `status: "4xx"`: clears the cache and tries known ids).
Future<Object?> apiFetch(String url, {bool noRetry = false}) async {
  final id = await _getClientId();
  final sep = url.contains('?') ? '&' : '?';
  final (status, body) = await _raceFetch('$url${sep}client_id=$id', true);

  if (status == 401 || status == 403) {
    if (noRetry) throw const ScException('sc.err.forbidden');
    _clearAuto();
    final d = await _tryKnownIds(url);
    if (d != null) return d;
    throw const ScException('sc.err.clientIdInvalid');
  }

  final Object? data;
  try {
    data = jsonDecode(body);
  } catch (_) {
    throw const ScException('sc.err.unavailable');
  }

  // List answers (`/tracks?ids=`) never have errors or status.
  if (data is! Map) return data;

  final errors = data['errors'];
  final hasErrors = errors is List && errors.isNotEmpty;
  if (hasErrors) {
    if (noRetry) {
      final first = errors[0];
      final msg =
          (first is Map &&
              first['error_message'] is String &&
              (first['error_message'] as String).isNotEmpty)
          ? first['error_message'] as String
          : 'SC API error';
      throw ScException(msg);
    }
    _clearAuto();
    final d = await _tryKnownIds(url);
    if (d != null) return d;
    throw const ScException('sc.err.clientIdExpired');
  }

  final st = data['status'];
  final status4 =
      st is String &&
      st.length >= 3 &&
      st[0] == '4' &&
      _isDigit(st[1]) &&
      _isDigit(st[2]);
  if (status4) {
    if (noRetry) throw ScException('SC: $st');
    _clearAuto();
    final d = await _tryKnownIds(url);
    if (d != null) return d;
    throw const ScException('sc.err.clientIdInvalid');
  }

  return data;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

// ── JSON helpers ────────────────────────────────────────────────────────

/// A field's non-empty string (empty counts as falsy and falls through).
String? _vstr(Object? v, String k) {
  if (v is! Map) return null;
  final x = v[k];
  return (x is String && x.isNotEmpty) ? x : null;
}

int? _vu64(Object? v, String k) {
  if (v is! Map) return null;
  final x = v[k];
  if (x is int) return x;
  if (x is num) return x.toInt();
  return null;
}

/// A field's truthiness.
bool _vbool(Object? v, String k) => v is Map ? !_falsy(v[k]) : false;

List<Object?> _varr(Object? v, String k) {
  if (v is! Map) return const [];
  final x = v[k];
  return x is List ? x : const [];
}

/// `-large` to `-t300x300` (a 300 px cover), null when empty.
String? _t300(String? raw) => _sized(raw, 't300x300');

/// The same URL at 500 px, for an artist header at screen width, where 300 px
/// is visibly soft. Lists and tiles don't need it.
String? _t500(String? raw) => _sized(raw, 't500x500');

String? _sized(String? raw, String size) {
  if (raw == null || raw.isEmpty) return null;
  return raw.replaceAll('-large', '-$size');
}

int _nowMillis() => DateTime.now().millisecondsSinceEpoch;

Object? _obj(Object? v, String k) {
  if (v is! Map) return null;
  final x = v[k];
  return x is Map ? x : null;
}

// ── Mapping ─────────────────────────────────────────────────────────────

ScRawTrack mapRawTrack(Object? t) {
  final user = _obj(t, 'user');
  final pm = _obj(t, 'publisher_metadata');
  final media = (t is Map && t['media'] is Map)
      ? Map<String, dynamic>.from(t['media'] as Map)
      : null;
  return ScRawTrack(
    id: _vu64(t, 'id') ?? 0,
    title: _vstr(t, 'title') ?? '',
    artist: user != null ? (_vstr(user, 'username') ?? '') : 'Unknown',
    artistScId: user == null ? null : _vu64(user, 'id'),
    artwork: _t300(_vstr(t, 'artwork_url')),
    duration: _vu64(t, 'duration') ?? 0,
    permalink: _vstr(t, 'permalink_url'),
    media: media,
    genre: _vstr(t, 'genre'),
    tags: (_vstr(t, 'tag_list') ?? '')
        .split(' ')
        .where((p) => p.isNotEmpty)
        .toList(),
    album: (pm == null ? null : _vstr(pm, 'album_title')) ?? '',
    publisher:
        _vstr(t, 'label_name') ??
        (pm == null ? null : _vstr(pm, 'publisher')) ??
        '',
    description: _vstr(t, 'description') ?? '',
    explicit: pm != null && _vbool(pm, 'explicit'),
    creditedArtist: (pm == null ? null : _vstr(pm, 'artist')) ?? '',
    artistAvatar: user == null ? null : _t300(_vstr(user, 'avatar_url')),
    artistPermalink: user == null ? null : _vstr(user, 'permalink_url'),
    artistVerified: user != null && _vbool(user, 'verified'),
    year: _year(_vstr(t, 'release_date') ?? _vstr(t, 'created_at')),
    releaseDate: _vstr(t, 'release_date') ?? _vstr(t, 'created_at') ?? '',
    policy: _vstr(t, 'policy'),
  );
}

String _year(String? d) =>
    d == null ? '' : (d.length <= 4 ? d : d.substring(0, 4));

ScRawArtist mapRawArtist(Object? u) => ScRawArtist(
  id: _vu64(u, 'id') ?? 0,
  title: _vstr(u, 'username') ?? '',
  artist: _vstr(u, 'full_name') ?? '',
  artwork: _t300(_vstr(u, 'avatar_url')),
  permalink: _vstr(u, 'permalink_url'),
  trackCount: _vu64(u, 'track_count'),
);

ScRawPlaylist mapRawPlaylist(Object? p) {
  final user = _obj(p, 'user');
  return ScRawPlaylist(
    id: _vu64(p, 'id') ?? 0,
    title: _vstr(p, 'title') ?? '',
    artist: user != null ? (_vstr(user, 'username') ?? '') : 'Unknown',
    artwork: _t300(
      _vstr(p, 'artwork_url') ?? _vstr(p, 'calculated_artwork_url'),
    ),
    artistAvatar: user == null ? null : _t300(_vstr(user, 'avatar_url')),
    trackCount: _vu64(p, 'track_count') ?? 0,
    duration: _vu64(p, 'duration') ?? 0,
    year: _playlistYear(p),
    releaseDate: _playlistDate(p),
    permalink: _vstr(p, 'permalink_url'),
    setType: _vstr(p, 'set_type') ?? '',
  );
}

/// Playlist or album date: `release_date` (albums), else `created_at`.
String _playlistDate(Object? p) =>
    _vstr(p, 'release_date') ?? _vstr(p, 'created_at') ?? '';

/// The year from that same date, so year and full date share a source.
String _playlistYear(Object? p) => _year(_playlistDate(p));

bool _hasId(Object? v) => _vu64(v, 'id') != null;

// ── Search ──────────────────────────────────────────────────────────────

Future<ScPage<ScRawTrack>> searchTracks(
  String query, {
  int limit = 20,
  int offset = 0,
  String sort = 'relevance',
}) async {
  final url =
      'https://api-v2.soundcloud.com/search/tracks'
      '?q=${Uri.encodeComponent(query)}&limit=$limit&offset=$offset'
      '${sort == 'new' ? '&sort=created_at' : ''}';
  final data = await apiFetch(url);
  if (data is! Map || _falsy(data['collection'])) {
    return const ScPage(items: [], hasMore: false);
  }
  return ScPage(
    items: _varr(data, 'collection').where(_hasId).map(mapRawTrack).toList(),
    hasMore: !_falsy(data['next_href']),
  );
}

Future<ScPage<ScRawArtist>> searchArtists(
  String query, {
  int limit = 20,
}) async {
  final url =
      'https://api-v2.soundcloud.com/search/users'
      '?q=${Uri.encodeComponent(query)}&limit=$limit';
  final data = await apiFetch(url);
  if (data is! Map || _falsy(data['collection'])) {
    return const ScPage(items: [], hasMore: false);
  }
  return ScPage(
    items: _varr(data, 'collection').where(_hasId).map(mapRawArtist).toList(),
    hasMore: !_falsy(data['next_href']),
  );
}

Future<ScPage<ScRawPlaylist>> _searchSets(String url) async {
  final data = await apiFetch(url);
  if (data is! Map || _falsy(data['collection'])) {
    return const ScPage(items: [], hasMore: false);
  }
  return ScPage(
    items: _varr(data, 'collection').where(_hasId).map(mapRawPlaylist).toList(),
    hasMore: !_falsy(data['next_href']),
  );
}

Future<ScPage<ScRawPlaylist>> searchPlaylists(String query, {int limit = 20}) =>
    _searchSets(
      'https://api-v2.soundcloud.com/search/playlists'
      '?q=${Uri.encodeComponent(query)}&limit=$limit',
    );

Future<ScPage<ScRawPlaylist>> searchAlbums(String query, {int limit = 20}) =>
    _searchSets(
      'https://api-v2.soundcloud.com/search/albums'
      '?q=${Uri.encodeComponent(query)}&limit=$limit',
    );

/// Connection check from settings: clears the auto cache, then a test search.
Future<ScCheckResult> checkConnection() async {
  _resetAutoCache();
  try {
    await searchTracks('test', limit: 1);
    return ScCheckResult(ok: true, clientId: activeClientId());
  } catch (e) {
    return ScCheckResult(
      ok: false,
      clientId: activeClientId(),
      error: e.toString(),
    );
  }
}

// ── Artist and profile ──────────────────────────────────────────────────

/// Numeric userId from an id string ("12345") or a permalink URL (through
/// /resolve).
Future<int> _resolveUserId(String idOrUrl) async {
  if (idOrUrl.isNotEmpty && idOrUrl.split('').every(_isDigit)) {
    return int.parse(idOrUrl);
  }
  if (idOrUrl.contains('soundcloud.com')) {
    final user = await apiFetch(
      'https://api-v2.soundcloud.com/resolve?url=${Uri.encodeComponent(idOrUrl)}',
    );
    final id = _vu64(user, 'id');
    if (id == null) throw const ScException('search.err.artistNotFound');
    return id;
  }
  throw const ScException('search.err.artistUndetermined');
}

/// A listener's playlists, albums aside; errors give none.
Future<List<ScRawPlaylist>> userPlaylists(String idOrUrl) async {
  try {
    final id = await _resolveUserId(idOrUrl);
    final d = await apiFetch(
      'https://api-v2.soundcloud.com/users/$id/playlists_without_albums'
      '?limit=20&linked_partitioning=1',
    );
    return _varr(d, 'collection').where(_hasId).map(mapRawPlaylist).toList();
  } catch (_) {
    return [];
  }
}

/// The first page of a listener's liked tracks. Track likes only: /likes mixes
/// playlists in, and a page of those would end the paging.
Future<ScTracksCursorPage> userTrackLikes(int userId) => listPage(
  'https://api-v2.soundcloud.com/users/$userId/track_likes'
  '?limit=50&linked_partitioning=1',
);

/// A user's liked tracks; errors give an empty list. Likes come in pages (with
/// playlists among them, skipped), so I follow `next_href` to the end; an error
/// midway returns what's gathered.
Future<List<ScRawTrack>> userLikes(String idOrUrl) async {
  final out = <ScRawTrack>[];
  final seen = <int>{};
  try {
    final id = await _resolveUserId(idOrUrl);
    var url =
        'https://api-v2.soundcloud.com/users/$id/likes?limit=200&linked_partitioning=1';
    // A cap of 25 pages (~5000 likes), insurance against a hanging cursor.
    for (var page = 0; page < 25; page++) {
      final Object? d;
      try {
        d = await apiFetch(url);
      } catch (_) {
        break;
      }
      final coll = _varr(d, 'collection');
      if (coll.isEmpty) break;
      for (final x in coll) {
        final t = _obj(x, 'track');
        if (t == null || !_hasId(t)) continue;
        final tr = mapRawTrack(t);
        if (seen.add(tr.id)) out.add(tr);
      }
      final next = _vstr(d, 'next_href');
      if (next == null) break;
      url = next;
    }
  } catch (_) {
    return out;
  }
  return out;
}

/// User data for an artist hero; null on error.
Future<ScRawUser?> getUser(String idOrUrl) async {
  try {
    final userId = await _resolveUserId(idOrUrl);
    final u = await apiFetch('https://api-v2.soundcloud.com/users/$userId');
    if (_vu64(u, 'id') == null) return null;
    final visuals = _varr(_obj(u, 'visuals'), 'visuals');
    final banner = visuals.isEmpty ? null : _vstr(visuals.first, 'visual_url');
    return ScRawUser(
      id: _vu64(u, 'id') ?? 0,
      username: _vstr(u, 'username') ?? '',
      fullName: _vstr(u, 'full_name') ?? '',
      avatar: _t500(_vstr(u, 'avatar_url')),
      banner: banner,
      trackCount: _vu64(u, 'track_count'),
      likesCount: _vu64(u, 'likes_count'),
      description: _vstr(u, 'description') ?? '',
      website: _vstr(u, 'website'),
      permalink: _vstr(u, 'permalink_url'),
    );
  } catch (_) {
    return null;
  }
}

/// An artist's popular tracks: /toptracks, /spotlight, /tracks, then a search
/// by name.
Future<List<ScRawTrack>> artistTopTracks(
  String idOrUrl, {
  String? artistName,
}) async {
  var userId = 0;
  try {
    userId = await _resolveUserId(idOrUrl);
  } catch (_) {
    userId = 0;
  }

  if (userId != 0) {
    // 1. /toptracks, the true popular ones.
    try {
      final tt = await apiFetch(
        'https://api-v2.soundcloud.com/users/$userId/toptracks'
        '?limit=20&linked_partitioning=1',
      );
      if (_varr(tt, 'collection').isNotEmpty) {
        return _varr(tt, 'collection').where(_hasId).map(mapRawTrack).toList();
      }
    } catch (_) {
      // silently on to the next fallback
    }
    // 2. /spotlight, pinned by the artist.
    try {
      final sp = await apiFetch(
        'https://api-v2.soundcloud.com/users/$userId/spotlight'
        '?limit=10&linked_partitioning=1',
      );
      final trs = _varr(sp, 'collection')
          .where((x) => _vstr(x, 'kind') == 'track' && _hasId(x))
          .map(mapRawTrack)
          .toList();
      if (trs.isNotEmpty) return trs;
    } catch (_) {
      // silently on to the next fallback
    }
    // 3. /tracks (may need a session).
    try {
      final d = await apiFetch(
        'https://api-v2.soundcloud.com/users/$userId/tracks'
        '?limit=50&linked_partitioning=1',
      );
      if (_varr(d, 'collection').isNotEmpty) {
        return _varr(d, 'collection').where(_hasId).map(mapRawTrack).toList();
      }
    } catch (_) {
      // silently on to the next fallback
    }
  }

  // 4. Fallback: a search by the artist's name (exact match, first 20).
  if (artistName != null && artistName.isNotEmpty) {
    try {
      final sr = await apiFetch(
        'https://api-v2.soundcloud.com/search/tracks'
        '?q=${Uri.encodeComponent(artistName)}&limit=30',
      );
      if (sr is Map && sr.containsKey('collection')) {
        final nl = artistName.toLowerCase();
        final coll = _varr(sr, 'collection');
        final matched = coll
            .where(
              (t) =>
                  _hasId(t) &&
                  (_vstr(_obj(t, 'user'), 'username') ?? '').toLowerCase() ==
                      nl,
            )
            .toList();
        if (matched.isNotEmpty) return matched.map(mapRawTrack).toList();
        return coll.where(_hasId).take(20).map(mapRawTrack).toList();
      }
    } catch (_) {
      // silently on to the next fallback
    }
  }
  return [];
}

/// An artist's tracks (first page and cursor) and albums; the fallback is a
/// search by name.
Future<ScArtistData> artistData(String idOrUrl, {String? artistName}) async {
  var userId = 0;
  try {
    userId = await _resolveUserId(idOrUrl);
  } catch (_) {
    userId = 0;
  }

  var tracks = <ScRawTrack>[];
  String? tracksNext;
  if (userId != 0) {
    try {
      final page = await listPage(
        'https://api-v2.soundcloud.com/users/$userId/tracks'
        '?limit=50&linked_partitioning=1',
      );
      tracks = page.tracks;
      tracksNext = page.next;
    } catch (_) {
      // I fall back to the search below.
    }
  }

  var albums = <ScRawPlaylist>[];
  if (userId != 0) {
    try {
      final ad = await apiFetch(
        'https://api-v2.soundcloud.com/users/$userId/albums'
        '?limit=20&linked_partitioning=1',
      );
      albums = _varr(
        ad,
        'collection',
      ).where(_hasId).map(mapRawPlaylist).toList();
    } catch (_) {
      // silently on to the next fallback
    }
  }

  // Fallback: empty, so search by name.
  if (tracks.isEmpty &&
      albums.isEmpty &&
      artistName != null &&
      artistName.isNotEmpty) {
    try {
      final sr = await apiFetch(
        'https://api-v2.soundcloud.com/search/tracks'
        '?q=${Uri.encodeComponent(artistName)}&limit=30',
      );
      final nl = artistName.toLowerCase();
      final coll = _varr(sr, 'collection');
      final matched = coll
          .where(
            (t) =>
                _hasId(t) &&
                (_vstr(_obj(t, 'user'), 'username') ?? '').toLowerCase() == nl,
          )
          .toList();
      tracks = matched.isNotEmpty
          ? matched.map(mapRawTrack).toList()
          : coll.where(_hasId).take(20).map(mapRawTrack).toList();
    } catch (_) {
      // silently on to the next fallback
    }
  }

  return ScArtistData(tracks: tracks, tracksNext: tracksNext, albums: albums);
}

/// Similar artists (`/users/{id}/relatedartists`), the artist page's section.
/// Little-known profiles get an empty collection; errors also become an empty
/// list, and the section just isn't drawn.
Future<List<ScRawArtist>> relatedArtists(String idOrUrl) async {
  try {
    final id = await _resolveUserId(idOrUrl);
    final d = await apiFetch(
      'https://api-v2.soundcloud.com/users/$id/relatedartists?limit=18',
    );
    return _varr(d, 'collection').where(_hasId).map(mapRawArtist).toList();
  } catch (_) {
    return [];
  }
}

/// A page of a user's list of tracks (their own, their likes) by its link.
/// SC filters these page by page (blocked in the region, taken down): a page
/// comes short, even empty, with more behind it. I skip a few empty ones in a
/// row; the list ends where next_href does. A failed page throws.
Future<ScTracksCursorPage> listPage(String url, {int hops = 0}) async {
  // next_href may carry an old client_id; apiFetch adds the current one.
  final uri = Uri.parse(url);
  final link = uri.queryParameters.containsKey('client_id')
      ? uri
            .replace(
              queryParameters: {...uri.queryParameters}..remove('client_id'),
            )
            .toString()
      : url;
  final d = await apiFetch(link);
  final coll = _varr(d, 'collection');
  final next = _vstr(d, 'next_href');
  if (coll.isEmpty && next != null && hops < 4) {
    return listPage(next, hops: hops + 1);
  }
  return ScTracksCursorPage(
    tracks: [
      for (final x in coll)
        // A like wraps its track.
        if (_hasId(x) ? x : _obj(x, 'track') case final o? when _hasId(o))
          mapRawTrack(o),
    ],
    next: coll.isEmpty ? null : next,
  );
}

// ── Playlists and tracks ────────────────────────────────────────────────

/// Tracks from playlist data: full ones, plus stubs (id only) loaded in batches
/// of 50.
Future<List<ScRawTrack>> _loadTracksFromPlaylistData(Object? data) async {
  final all = _varr(data, 'tracks');
  final full = all.where((t) => _vstr(t, 'title') != null).toList();
  final stubs = all
      .where((t) => _vstr(t, 'title') == null)
      .map((t) => _vu64(t, 'id'))
      .whereType<int>()
      .toList();

  final fetched = <Object?>[];
  for (var i = 0; i * 50 < stubs.length; i++) {
    final chunk = stubs.skip(i * 50).take(50);
    final ids = chunk.join(',');
    try {
      final batch = await apiFetch(
        'https://api-v2.soundcloud.com/tracks?ids=$ids',
      );
      if (batch is List) fetched.addAll(batch);
    } catch (_) {
      // silently on to the next fallback
    }
    if ((i + 1) * 50 < stubs.length) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  return [...full, ...fetched].where(_hasId).map(mapRawTrack).toList();
}

/// A playlist's or album's tracks by permalink URL. Errors pass through: import
/// must show them.
Future<List<ScRawTrack>> playlistTracks(String permalinkUrl) async {
  final data = await apiFetch(
    'https://api-v2.soundcloud.com/resolve?url=${Uri.encodeComponent(permalinkUrl)}',
  );
  return _loadTracksFromPlaylistData(data);
}

/// Full playlist data by numeric id, for opening from recents.
Future<ScPlaylistFull> playlistById(int id) async {
  final data = await apiFetch('https://api-v2.soundcloud.com/playlists/$id');
  final tracks = await _loadTracksFromPlaylistData(data);
  final user = _obj(data, 'user');
  final cover =
      _t300(
        _vstr(data, 'artwork_url') ?? _vstr(data, 'calculated_artwork_url'),
      ) ??
      _t300(_vstr(user, 'avatar_url'));
  return ScPlaylistFull(
    title: _vstr(data, 'title') ?? '',
    cover: cover,
    ownerName: _vstr(user, 'username') ?? '',
    ownerAvatar: _t300(_vstr(user, 'avatar_url')),
    ownerId: _vu64(user, 'id'),
    trackCount: _vu64(data, 'track_count') ?? tracks.length,
    year: _playlistYear(data),
    releaseDate: _playlistDate(data),
    tracks: tracks,
  );
}

/// One track by numeric id; null on error.
Future<ScRawTrack?> trackById(int id) async {
  try {
    final data = await apiFetch('https://api-v2.soundcloud.com/tracks/$id');
    if (!_hasId(data)) return null;
    return mapRawTrack(data);
  } catch (_) {
    return null;
  }
}

// ── Wave: similar tracks ────────────────────────────────────────────────

/// A track station's tracks (`stations/soundcloud:track-stations:<id>/tracks`),
/// the wave's main candidate source. Pages by offset: [offset] moves so each
/// new session doesn't start with the same twenty.
///
/// A failure passes through rather than turning empty: an empty answer means
/// the station ended and moves the cursor, and can't be confused with a broken
/// network. The layer above dampens errors and retries.
Future<List<ScRawTrack>> stationTracks(Object scTrackId, {int offset = 0}) =>
    _waveTracks(
      'https://api-v2.soundcloud.com/stations/'
      'soundcloud:track-stations:$scTrackId/tracks?limit=20&offset=$offset',
    );

/// Similar to a track (`tracks/<id>/related`). No paging, but for a one-track
/// wave it's the main source of taste.
Future<List<ScRawTrack>> relatedTracks(Object scTrackId) => _waveTracks(
  'https://api-v2.soundcloud.com/tracks/$scTrackId/related?limit=20',
);

/// Parses both answers: a collection item is either the track or a `{track:
/// {...}}` wrapper, as a station gives it.
Future<List<ScRawTrack>> _waveTracks(String url) async {
  final data = await apiFetch(url);
  final items = data is List ? data : _varr(data, 'collection');
  return [
    for (final it in items)
      if (_unwrapTrack(it) case final t?)
        if (_hasId(t) && (_vstr(t, 'title') ?? '').isNotEmpty) mapRawTrack(t),
  ];
}

Object? _unwrapTrack(Object? item) {
  if (item is! Map) return null;
  final inner = item['track'];
  return inner is Map ? inner : item;
}

// ── Resolving a link ────────────────────────────────────────────────────

/// A SoundCloud link to an entity (track, artist, playlist, album); null if
/// unrecognised.
Future<ScResolved?> resolveUrl(String url) async {
  var u = url.trim();
  if (!u.startsWith('http://') && !u.startsWith('https://')) {
    u = 'https://$u';
  }
  final data = await apiFetch(
    'https://api-v2.soundcloud.com/resolve?url=${Uri.encodeComponent(u)}',
  );
  final kind = _vstr(data, 'kind');
  switch (kind) {
    case 'track':
      return ScResolved(kind: 'track', track: mapRawTrack(data));
    case 'user':
      return ScResolved(kind: 'artist', artist: mapRawArtist(data));
    case 'playlist':
      final isAlbum =
          _vbool(data, 'is_album') || _vstr(data, 'set_type') == 'album';
      return ScResolved(
        kind: isAlbum ? 'album' : 'playlist',
        playlist: mapRawPlaylist(data),
      );
    default:
      return null;
  }
}

// ── Stream ──────────────────────────────────────────────────────────────

/// A playable signed CDN URL from `media.transcodings`: progressive (mp3), hls,
/// then any non-DRM; one retry after 500 ms.
///
/// [progressiveOnly] is for downloading: HLS is a playlist of chunks that can't
/// save as a file, and any non-DRM may be the same HLS under another name. Such
/// a track fails with `sc.err.hlsOnly`.
Future<ScStream> streamUrl(
  Map<String, dynamic>? media, {
  bool progressiveOnly = false,
}) async {
  final tcs = _varr(media, 'transcodings');
  if (tcs.isEmpty) throw const ScException('search.err.noStream');

  String proto(Object? tc) => _vstr(_obj(tc, 'format'), 'protocol') ?? '';
  bool isDrm(Object? tc) => proto(tc).toLowerCase().contains('encrypted');

  final prog = _firstWhere(tcs, (tc) => proto(tc) == 'progressive');
  final hls = _firstWhere(tcs, (tc) => proto(tc) == 'hls');
  final fallback = _firstWhere(
    tcs,
    (tc) => !isDrm(tc) && !identical(tc, prog) && !identical(tc, hls),
  );

  final order = <Object?>[];
  for (final tc in progressiveOnly ? [prog] : [prog, hls, fallback]) {
    if (tc == null) continue;
    if (!isDrm(tc) && !order.any((o) => identical(o, tc))) order.add(tc);
  }
  final hasDrm = tcs.any(isDrm);
  if (order.isEmpty) {
    if (progressiveOnly && !hasDrm) throw const ScException('sc.err.hlsOnly');
    throw ScException(hasDrm ? 'sc.err.drm' : 'sc.err.noStream');
  }

  Object? lastErr;
  for (var attempt = 0; attempt < 2; attempt++) {
    for (final tc in order) {
      final p = proto(tc);
      final isHls = p == 'hls' || p.contains('hls');
      final tcUrl = _vstr(tc, 'url');
      if (tcUrl == null) continue;
      final sep = tcUrl.contains('?') ? '&' : '?';
      try {
        final data = await apiFetch('$tcUrl${sep}_cb=${_nowMillis()}');
        final u = _vstr(data, 'url');
        if (u != null) return ScStream(url: u, isHls: isHls);
        lastErr = const ScException('no url');
      } catch (e) {
        lastErr = e;
      }
    }
    if (hasDrm) throw const ScException('search.err.drm');
    if (attempt == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  throw lastErr ?? const ScException('sc.err.noStream');
}

Object? _firstWhere(List<Object?> items, bool Function(Object?) pred) {
  for (final x in items) {
    if (pred(x)) return x;
  }
  return null;
}
