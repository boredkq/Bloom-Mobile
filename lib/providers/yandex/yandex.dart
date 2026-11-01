/// Yandex Music, unofficial API (`api.music.yandex.net`). HTTP goes from the
/// app itself, directly, so the token goes nowhere; no proxy race, as with
/// SoundCloud, on purpose: a foreign proxy would carry the `Authorization`
/// header.
///
/// Auth is OAuth Device Flow. The direct mp3 link's signature and the endpoints
/// reproduce the unofficial API's behaviour.
///
/// Errors are [YmException] with a code (`ym.err.*`), translated by the UI.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

const String kApi = 'https://api.music.yandex.net';
const String kOauth = 'https://oauth.yandex.ru';

/// Public client constants of the Yandex Music app (widely known, not secret).
const String kClientId = '23cabbbdc6cd418abb4b39c32c41195d';
const String kClientSecret = '53bc75238f0c4d08a118e51fe9203300';

/// Salt for signing a direct mp3 link, stable for years in all clients.
const String kSignSalt = 'XGRlBW9FXlekgbPrRHuSiA';
const String kUserAgent = 'Yandex-Music-API';
const String kYmClient = 'YandexMusicAndroid/24023621';

final http.Client _http = http.Client();

Map<String, String> _authHeaders(String token) => {
  'User-Agent': kUserAgent,
  'Authorization': 'OAuth $token',
  'X-Yandex-Music-Client': kYmClient,
};

// ============================ token state ============================

String? _token;

/// Gives the provider a saved token, or clears it on logout. Called by the auth
/// store; module state, like SoundCloud's `setManualClientId`.
void setToken(String? token) {
  final v = token?.trim();
  _token = (v == null || v.isEmpty) ? null : v;
}

String? activeToken() => _token;

/// A token for the request; with none the API answers 401 to everything.
String _requireToken() {
  final t = _token;
  if (t == null) throw const YmException('ym.err.noToken');
  return t;
}

// ============================ Device Flow ============================

/// Step 1: gets a device code and confirmation link. The auth store keeps and
/// passes `deviceId`: Yandex doesn't validate it strictly, only stability
/// between launches matters.
Future<YmDeviceCode> authStart(String deviceId) async {
  final r = await _http.post(
    Uri.parse('$kOauth/device/code'),
    headers: {'User-Agent': kUserAgent},
    body: {
      'client_id': kClientId,
      'device_id': deviceId,
      'device_name': 'Bloom',
    },
  );
  final v = _decode(r.bodyBytes);
  if (r.statusCode < 200 || r.statusCode >= 300) {
    final desc = v?['error_description'];
    throw YmException(desc is String ? desc : 'ym.err.deviceCode');
  }
  return YmDeviceCode(
    deviceCode: v?['device_code'] as String? ?? '',
    userCode: v?['user_code'] as String? ?? '',
    verificationUrl:
        v?['verification_url'] as String? ?? 'https://ya.ru/device',
    interval: Duration(seconds: (v?['interval'] as num?)?.toInt() ?? 5),
    expiresIn: Duration(seconds: (v?['expires_in'] as num?)?.toInt() ?? 300),
  );
}

/// Step 2: one poll, exchanging `device_code` for a token. Not confirmed yet is
/// [YmPollOutcome.pending]; an exception is fatal (code expired or refused).
Future<YmPollOutcome> authPoll(String deviceCode) async {
  final r = await _http.post(
    Uri.parse('$kOauth/token'),
    headers: {'User-Agent': kUserAgent},
    body: {
      'grant_type': 'device_code',
      'code': deviceCode,
      'client_id': kClientId,
      'client_secret': kClientSecret,
    },
  );
  final v = _decode(r.bodyBytes);
  final token = v?['access_token'];
  if (token is String && token.isNotEmpty) return YmPollOutcome.token(token);
  final err = v?['error'];
  if (err == 'authorization_pending' || err == 'slow_down') {
    return const YmPollOutcome.pending();
  }
  throw YmException(err is String ? 'ym.err.authFailed:$err' : 'ym.err.oauth');
}

Map<String, dynamic>? _decode(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

// ============================ API ============================

const int _maxAttempts = 3;
const Duration _retryDelay = Duration(milliseconds: 600);
const Duration _timeout = Duration(seconds: 20);

/// GET to the API with auth and one way of handling 401 and JSON. A light retry
/// on transient failures (network, 5xx, 429): 3 tries, 600 ms backoff. 401 is
/// fatal, with no retry. Without this a single network blip brings down all
/// search. landing3 (charts, new releases) likes giving 5xx or a broken body,
/// so a JSON parse failure (200 with a cut body) retries too.
Future<Map<String, dynamic>> apiGet(
  String path, [
  Map<String, String> query = const {},
]) async {
  final token = _requireToken();
  final uri = Uri.parse(
    '$kApi$path',
  ).replace(queryParameters: query.isEmpty ? null : query);

  for (var attempt = 1; ; attempt++) {
    http.Response? resp;
    try {
      resp = await _http
          .get(uri, headers: _authHeaders(token))
          .timeout(_timeout);
    } catch (_) {
      // a network error is transient
    }
    final status = resp?.statusCode ?? 0;
    final transient =
        resp == null || status == 429 || (status >= 500 && status <= 599);
    if (transient && attempt < _maxAttempts) {
      await Future<void>.delayed(_retryDelay);
      continue;
    }
    if (resp == null) throw const YmException('ym.err.network');
    if (status == 401) throw const YmException('ym.err.auth');

    final v = _decode(resp.bodyBytes);
    if (v != null) return v;
    if (attempt < _maxAttempts) {
      await Future<void>.delayed(_retryDelay);
      continue;
    }
    throw const YmException('ym.err.badJson');
  }
}

// ---- Parsing entities ----

/// Id from a number or string: Yandex gives either, even in one answer.
String? idStr(Object? v) {
  if (v is String) return v.isEmpty ? null : v;
  if (v is num) return v.toString();
  return null;
}

String coverUrl(Object? coverUri) {
  final u = coverUri;
  if (u is String && u.isNotEmpty) {
    return 'https://${u.replaceAll('%%', '400x400')}';
  }
  return '';
}

/// Cover from different JSON places (`coverUri`, `cover.uri`, `ogImage`).
String coverFrom(Object? node) {
  if (node is! Map) return '';
  final direct = node['coverUri'];
  if (direct is String) return coverUrl(direct);
  final cover = node['cover'];
  if (cover is Map && cover['uri'] is String) return coverUrl(cover['uri']);
  final og = node['ogImage'];
  if (og is String) return coverUrl(og);
  return '';
}

String _artistsJoin(Object? node) {
  final names = _artistNames(node);
  return names.isEmpty ? kYmDash : names.join(', ');
}

List<String> _artistNames(Object? node) {
  if (node is! Map) return const [];
  final arr = node['artists'];
  if (arr is! List) return const [];
  return [
    for (final a in arr)
      if (a is Map && a['name'] is String) a['name'] as String,
  ];
}

YmRawTrack? parseTrack(Object? node) {
  if (node is! Map) return null;
  final id = idStr(node['id']);
  if (id == null) return null;
  final names = _artistNames(node);
  final artists = node['artists'];
  final firstArtist = (artists is List && artists.isNotEmpty)
      ? artists.first
      : null;
  final albums = node['albums'];
  final firstAlbum = (albums is List && albums.isNotEmpty)
      ? albums.first
      : null;
  return YmRawTrack(
    id: id,
    title: node['title'] as String? ?? kYmUntitled,
    artist: names.isEmpty ? kYmUnknownArtist : names.join(', '),
    artistId: (firstArtist is Map ? idStr(firstArtist['id']) : null) ?? '',
    artists: [
      if (artists is List)
        for (final a in artists)
          if (a is Map && a['name'] is String && (a['name'] as String) != '')
            (id: idStr(a['id']) ?? '', name: a['name'] as String),
    ],
    cover: coverUrl(node['coverUri']),
    duration: Duration(
      milliseconds: (node['durationMs'] as num?)?.toInt() ?? 0,
    ),
    // Year from the track's first album, already in the /search answer with no
    // extra requests. No year gives empty.
    year: firstAlbum is Map
        ? ((firstAlbum['year'] as num?)?.toInt().toString() ?? '')
        : '',
    releaseDate: firstAlbum is Map ? _releaseDate(firstAlbum) : '',
    available: node['available'] as bool? ?? true,
  );
}

/// Album's full release date. Not all have it: for old ones and compilations
/// Yandex knows only `year`, so it's empty and the UI keeps the year.
String _releaseDate(Map<Object?, Object?> album) =>
    album['releaseDate'] as String? ?? '';

YmRawArtist? parseArtist(Object? node) {
  if (node is! Map) return null;
  final id = idStr(node['id']);
  if (id == null) return null;
  return YmRawArtist(
    id: id,
    name: node['name'] as String? ?? kYmDash,
    cover: coverFrom(node),
  );
}

YmRawAlbum? parseAlbum(Object? node) {
  if (node is! Map) return null;
  final id = idStr(node['id']);
  if (id == null) return null;
  final artists = node['artists'];
  final first = (artists is List && artists.isNotEmpty) ? artists.first : null;
  return YmRawAlbum(
    id: id,
    title: node['title'] as String? ?? kYmDash,
    artist: _artistsJoin(node),
    cover: coverFrom(node),
    year: (node['year'] as num?)?.toInt().toString() ?? '',
    releaseDate: _releaseDate(node),
    trackCount: (node['trackCount'] as num?)?.toInt() ?? 0,
    artistId: (first is Map ? idStr(first['id']) : null) ?? '',
    artistCover: _artistPhoto(first),
    albumType: node['type'] as String? ?? '',
  );
}

/// Artist's 1000×1000 photo, for a release card's large circle.
String _artistPhoto(Object? artist) {
  final cover = artist is Map ? artist['cover'] : null;
  final uri = cover is Map ? cover['uri'] : null;
  if (uri is! String || uri.isEmpty) return '';
  return 'https://${uri.replaceAll('%%', '1000x1000')}';
}

YmRawPlaylist? parsePlaylist(Object? node) {
  if (node is! Map) return null;
  final kind = idStr(node['kind']);
  if (kind == null) return null;
  final ownerNode = node['owner'];
  final owner = ownerNode is Map
      ? (ownerNode['login'] as String? ?? idStr(ownerNode['uid']))
      : null;
  return YmRawPlaylist(
    kind: kind,
    owner: owner ?? idStr(node['uid']) ?? '',
    title: node['title'] as String? ?? kYmDash,
    cover: coverFrom(node),
    trackCount: (node['trackCount'] as num?)?.toInt() ?? 0,
  );
}

List<Object?> _results(Object? node) {
  if (node is! Map) return const [];
  final r = node['results'];
  return r is List ? r : const [];
}

List<T> _parseAll<T>(Object? list, T? Function(Object?) parse, int take) {
  if (list is! List) return const [];
  final out = <T>[];
  for (final item in list) {
    final parsed = parse(item);
    if (parsed != null) {
      out.add(parsed);
      if (out.length >= take) break;
    }
  }
  return out;
}

// ── Search ──────────────────────────────────────────────────────────────

Future<YmSearch> search(String query, {int page = 0}) async {
  final v = await apiGet('/search', {
    'text': query,
    'type': 'all',
    'page': '$page',
    'nocorrect': 'false',
  });
  final r = v['result'];
  if (r is! Map) return const YmSearch();
  return YmSearch(
    tracks: _parseAll(_results(r['tracks']), parseTrack, 24),
    artists: _parseAll(_results(r['artists']), parseArtist, 12),
    albums: _parseAll(_results(r['albums']), parseAlbum, 18),
    playlists: _parseAll(_results(r['playlists']), parsePlaylist, 12),
  );
}

/// One track by id, for resolving `.../track/{id}` links.
Future<YmRawTrack> trackOne(String id) async {
  final v = await apiGet('/tracks/$id');
  final arr = v['result'];
  final first = (arr is List && arr.isNotEmpty) ? parseTrack(arr.first) : null;
  if (first == null) throw const YmException('ym.err.trackNotFound');
  return first;
}

/// Track id from a popularTracks or collection element: a full track object,
/// `{id, albumId}` or a bare id (string or number).
String? _trackIdOf(Object? v) => v is Map ? idStr(v['id']) : idStr(v);

/// A batch of full tracks by id in one `/tracks/{id1,id2,...}` request.
Future<List<YmRawTrack>> tracksByIds(List<String> ids) async {
  if (ids.isEmpty) return const [];
  final v = await apiGet('/tracks/${ids.join(',')}');
  return _parseAll(v['result'], parseTrack, ids.length);
}

// ── Entities ────────────────────────────────────────────────────────────

Future<YmEntity> album(String id) async {
  final v = await apiGet('/albums/$id/with-tracks');
  final r = v['result'];
  if (r is! Map) throw const YmException('ym.err.albumNotFound');
  final tracks = <YmRawTrack>[];
  final volumes = r['volumes'];
  if (volumes is List) {
    for (final vol in volumes) {
      if (vol is! List) continue;
      for (final t in vol) {
        final parsed = parseTrack(t);
        if (parsed != null) tracks.add(parsed);
      }
    }
  }
  final artists = r['artists'];
  return YmEntity(
    title: r['title'] as String? ?? 'Альбом',
    subtitle: _artistsJoin(r),
    cover: coverFrom(r),
    tracks: tracks,
    year: (r['year'] as num?)?.toInt().toString() ?? '',
    releaseDate: _releaseDate(r),
    // Avatar of the album's first artist (artist objects have their own cover).
    ownerAvatar: (artists is List && artists.isNotEmpty)
        ? coverFrom(artists.first)
        : '',
  );
}

/// Size of an artist's tracks page, both the first batch and each load.
const int kYmArtistTracksPage = 50;

/// A page of an artist's discography, `/artists/{id}/tracks`. [artist] takes
/// the first, the rest load by Load more.
Future<YmTracksPage> artistTracksPage(String id, int page) async {
  final v = await apiGet('/artists/$id/tracks', {
    'page': '$page',
    'page-size': '$kYmArtistTracksPage',
  });
  return parseArtistTracksPage(v['result'], page);
}

/// Parses a tracks page, apart from the network for tests. Whether there's more
/// goes by `pager` (`total`, `perPage`) if Yandex gave it; with none, a full
/// page means maybe, and an empty next just ends the list.
YmTracksPage parseArtistTracksPage(Object? result, int page) {
  final r = result is Map ? result : const {};
  final raw = r['tracks'];
  final rawLen = raw is List ? raw.length : 0;
  final pager = r['pager'];
  final total = pager is Map ? (pager['total'] as num?)?.toInt() : null;
  final perPage =
      (pager is Map ? (pager['perPage'] as num?)?.toInt() : null) ??
      kYmArtistTracksPage;
  final hasMore =
      rawLen > 0 &&
      (total != null
          ? page * perPage + rawLen < total
          : rawLen >= kYmArtistTracksPage);
  return YmTracksPage(
    tracks: _parseAll(raw, parseTrack, rawLen),
    nextPage: hasMore ? page + 1 : null,
    total: total,
  );
}

Future<YmEntity> artist(String id) async {
  final v = await apiGet('/artists/$id/brief-info');
  final r = v['result'];
  if (r is! Map) throw const YmException('ym.err.artistNotFound');
  final a = r['artist'];
  final pop = r['popularTracks'];

  // brief-info often gives popularTracks as ids or {id, albumId} with NO
  // metadata, and parseTrack gives nothing or untitled. Then I fetch full
  // tracks in one /tracks request, or popular stays empty.
  var popularTracks = _parseAll(pop, parseTrack, 30);
  final needsFetch =
      popularTracks.isEmpty ||
      popularTracks.every((t) => t.title == kYmUntitled);
  if (needsFetch && pop is List) {
    final ids = [for (final item in pop) ?_trackIdOf(item)];
    final full = await tracksByIds(ids).catchError((_) => <YmRawTrack>[]);
    if (full.isNotEmpty) popularTracks = full;
  }

  // First discography page; more load by page number. Best effort: if the
  // endpoint gave nothing, at least popular remains.
  final first = await artistTracksPage(
    id,
    0,
  ).catchError((_) => const YmTracksPage());

  return YmEntity(
    title: (a is Map ? a['name'] as String? : null) ?? 'Артист',
    subtitle: 'Артист',
    cover: coverFrom(a),
    tracks: first.tracks,
    tracksNextPage: first.nextPage,
    tracksTotal: first.total,
    popularTracks: popularTracks,
    albums: _parseAll(r['albums'], parseAlbum, 18),
    // Similar artists: brief-info gives ready artist objects.
    similarArtists: _parseAll(r['similarArtists'], parseArtist, 18),
  );
}

/// Parses a playlist's `result` object, shared by both URL formats.
YmEntity playlistEntity(Object? node) {
  if (node is! Map) {
    return const YmEntity(title: 'Плейлист', subtitle: '', cover: '');
  }
  final rawTracks = node['tracks'];
  final tracks = <YmRawTrack>[];
  if (rawTracks is List) {
    for (final w in rawTracks) {
      // A `{track: {...}}` wrapper (rich-tracks) or the track itself.
      final inner = (w is Map && w['track'] is Map) ? w['track'] : w;
      final parsed = parseTrack(inner);
      if (parsed != null) tracks.add(parsed);
    }
  }
  // Owner: a flat ownerName (old format) OR a nested owner.name or login (new).
  final ownerNode = node['owner'];
  final owner =
      node['ownerName'] as String? ??
      (ownerNode is Map
          ? (ownerNode['name'] as String? ?? ownerNode['login'] as String?)
          : null) ??
      'Плейлист';
  return YmEntity(
    title: node['title'] as String? ?? 'Плейлист',
    subtitle: owner,
    cover: coverFrom(node),
    tracks: tracks,
    // A playlist's owner avatar exists only in the new format.
    ownerAvatar: coverFrom(ownerNode),
  );
}

/// Old playlist format: `/users/<owner>/playlists/<kind>`.
Future<YmEntity> playlist(String owner, String kind) async {
  final v = await apiGet('/users/$owner/playlists/$kind');
  return playlistEntity(v['result']);
}

/// New public playlist format: `/playlists/<uuid>` to API `/playlist/<uuid>`.
Future<YmEntity> playlistByUuid(String uuid) async {
  final v = await apiGet('/playlist/$uuid', {'rich-tracks': 'true'});
  return playlistEntity(v['result']);
}

// ── Links ───────────────────────────────────────────────────────────────

final RegExp reAlbumTrack = RegExp(r'/album/\d+/track/(\d+)');
final RegExp reTrack = RegExp(r'/track/(\d+)');
final RegExp reAlbum = RegExp(r'/album/(\d+)');
final RegExp reArtist = RegExp(r'/artist/(\d+)');
final RegExp reUserPlaylist = RegExp(r'/users/([^/?#]+)/playlists/(\d+)');

/// New public format: `/playlists/<id>`, where id is a uuid (8-4-4-4-12 hex) OR
/// prefixed (like `lk.<uuid>`, the liked list).
final RegExp rePublicPlaylist = RegExp(r'/playlists/([0-9A-Za-z.-]+)');

/// Resolves a music.yandex.ru (.com) link: track, album, artist or playlist.
Future<YmResolved> resolve(String url) async {
  final u = url.trim();
  if (reAlbumTrack.firstMatch(u) case final m?) {
    return YmResolved.track(await trackOne(m.group(1)!));
  }
  if (reTrack.firstMatch(u) case final m?) {
    return YmResolved.track(await trackOne(m.group(1)!));
  }
  if (reAlbum.firstMatch(u) case final m?) {
    return YmResolved.album(await album(m.group(1)!));
  }
  if (reArtist.firstMatch(u) case final m?) {
    return YmResolved.artist(await artist(m.group(1)!));
  }
  if (reUserPlaylist.firstMatch(u) case final m?) {
    return YmResolved.playlist(await playlist(m.group(1)!, m.group(2)!));
  }
  // The id goes to /playlist/<id> as is, whole, with no prefix cut.
  if (rePublicPlaylist.firstMatch(u) case final m?) {
    return YmResolved.playlist(await playlistByUuid(m.group(1)!));
  }
  throw const YmException('ym.err.badUrl');
}

// ── Similar (home shelves) ──────────────────────────────────────────────

/// Similar to a track for home shelves, `/tracks/{id}/similar`. For niche
/// tracks similar may be empty, and the fallback is the first station batch for
/// this track: an empty strip is worse than a slightly loose selection. The
/// seed goes from the station's results: it already tops its listener's chart.
Future<List<YmRawTrack>> similarTracks(String trackId) async {
  final v = await apiGet('/tracks/$trackId/similar');
  final result = v['result'];
  final raw = result is Map ? result['similarTracks'] : null;
  if (raw is List) {
    final tracks = _parseAll(raw, parseTrack, raw.length);
    if (tracks.isNotEmpty) return tracks;
  }
  final wave = await waveTracks('track:$trackId');
  return [
    for (final t in wave.tracks)
      if (t.id != trackId) t,
  ];
}

// ── Charts and new releases (home) ──────────────────────────────────────

/// Yandex Music's general chart, for the home shelf and chart page. The whole
/// chart (~100 positions): home cuts it itself, and the page needs all.
Future<List<YmRawTrack>> chart() async =>
    parseChart((await apiGet('/landing3/chart'))['result']);

/// Parses `/landing3/chart`, apart from the network for tests. An element of
/// `result.chart.tracks[]` has `.track` (sometimes itself a track) and a
/// `.chart` wrapper with position and trend. A bare track has no wrapper:
/// position comes from order, and the trend counts as unknown.
List<YmRawTrack> parseChart(Object? result) {
  final chartNode = result is Map ? result['chart'] : null;
  final arr = chartNode is Map ? chartNode['tracks'] : null;
  if (arr is! List) return const [];
  final out = <YmRawTrack>[];
  for (var i = 0; i < arr.length; i++) {
    final it = arr[i];
    final track = parseTrack(
      (it is Map && it['track'] != null) ? it['track'] : it,
    );
    if (track == null) continue;
    final c = it is Map ? it['chart'] : null;
    out.add(
      track.withChart(
        pos: (c is Map ? (c['position'] as num?)?.toInt() : null) ?? i + 1,
        shift: (c is Map ? (c['shift'] as num?)?.toInt() : null) ?? 0,
        // progress: new, up, down or same. The arrow draws by shift, and
        // progress is needed only as the new mark.
        isNew: c is Map && c['progress'] == 'new',
      ),
    );
  }
  return out;
}

/// Releases returned. The home shelf takes the first 10, the releases page
/// shows the rest as a grid. The platform really gives ~80, varying by day, so
/// this is a roomy cap rather than a limit.
const int _newReleasesMax = 100;

/// New releases (fresh albums), for the home shelf and releases page. The main
/// path is `landing3?blocks=new-releases` (full albums in `entities[].data`),
/// but the landing block is a carousel and nearly always short, so ids from
/// `/landing3/new-releases` fill up the list.
Future<List<YmRawAlbum>> newReleases() async {
  final v = await apiGet('/landing3', {'blocks': 'new-releases'});
  final out = <YmRawAlbum>[];
  final result = v['result'];
  final blocks = result is Map ? result['blocks'] : null;
  if (blocks is List) {
    for (final b in blocks) {
      final entities = b is Map ? b['entities'] : null;
      if (entities is! List) continue;
      for (final e in entities) {
        if (out.length >= _newReleasesMax) break;
        // entity.data is a full album; sometimes the entity itself is one.
        final data = (e is Map && e['data'] is Map) ? e['data'] : e;
        final parsed = parseAlbum(data);
        if (parsed != null) out.add(parsed);
      }
    }
  }
  if (out.length < _newReleasesMax) {
    try {
      // Duplicates by id go: the id list overlaps the landing carousel.
      for (final a in await _newReleasesByIds()) {
        if (out.length >= _newReleasesMax) break;
        if (!out.any((x) => x.id == a.id)) out.add(a);
      }
    } on Object {
      // Filling up failed, so I stay with what the landing gave.
    }
  }
  if (out.isEmpty) return const [];
  // Landing entities can be thin, with no artist photo or release date, and a
  // release card needs both. I fetch full albums; failing that, the landing
  // stays.
  if (out.any((a) => a.artistCover.isEmpty || a.releaseDate.isEmpty)) {
    try {
      final full = {
        for (final a in await _albumsByIds([for (final a in out) a.id]))
          a.id: a,
      };
      for (var i = 0; i < out.length; i++) {
        out[i] = full[out[i].id] ?? out[i];
      }
    } on Object {
      // see above
    }
  }
  return out;
}

/// `/landing3/new-releases` gives `newReleases[]`, album ids.
Future<List<YmRawAlbum>> _newReleasesByIds() async {
  final v = await apiGet('/landing3/new-releases');
  final result = v['result'];
  final raw = result is Map ? result['newReleases'] : null;
  final ids = raw is List
      ? [for (final item in raw.take(_newReleasesMax)) ?idStr(item)]
      : const <String>[];
  return _albumsByIds(ids);
}

/// Full albums by id through `/albums?album-ids=…`, in batches of 50: ids go in
/// the query string, and at sixty the URL is indecently long. Answer order is
/// release order.
Future<List<YmRawAlbum>> _albumsByIds(List<String> ids) async {
  final out = <YmRawAlbum>[];
  for (var i = 0; i < ids.length; i += 50) {
    final chunk = ids.sublist(i, i + 50 < ids.length ? i + 50 : ids.length);
    final av = await apiGet('/albums', {'album-ids': chunk.join(',')});
    out.addAll(_parseAll(av['result'], parseAlbum, chunk.length));
  }
  return out;
}

// ── My wave (rotor) ─────────────────────────────────────────────────────

/// My wave's default station. Rotor takes other seeds in the same format:
/// `track:<id>`, `artist:<id>`, `genre:<tag>`.
const String kWaveStation = 'user:onyourwave';

/// Next rotor station batch. [station] is the seed (`user:onyourwave`,
/// `track:<id>`, …); [lastId] is the last played track's id, so the station
/// continues the chain rather than starting over. Empty starts the station.
Future<YmWaveBatch> waveTracks(String station, {String lastId = ''}) async {
  final s = station.isEmpty ? kWaveStation : station;
  final v = await apiGet('/rotor/station/$s/tracks', {
    'settings2': 'true',
    if (lastId.isNotEmpty) 'queue': lastId,
  });
  final result = v['result'];
  final seq = result is Map ? result['sequence'] : null;
  final tracks = seq is! List
      ? const <YmRawTrack>[]
      : _parseAll(
          [
            for (final it in seq)
              (it is Map && it['track'] is Map) ? it['track'] : it,
          ],
          parseTrack,
          seq.length,
        );
  return YmWaveBatch(
    tracks: tracks,
    batchId: (result is Map ? result['batchId'] : null) as String? ?? '',
  );
}

/// Station feedback (`radioStarted`, `trackStarted`, `trackFinished`, `skip`),
/// by which My wave learns in the account itself. Best effort: the answer isn't
/// parsed and errors are swallowed. Teaching a station isn't worth breaking
/// playback for.
Future<void> waveFeedback({
  required String station,
  required String event,
  String trackId = '',
  String batchId = '',
  double played = 0,
}) async {
  final token = _token;
  if (token == null) return;
  final s = station.isEmpty ? kWaveStation : station;
  final body = <String, dynamic>{
    'type': event,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'from': 'android',
    if (trackId.isNotEmpty) 'trackId': trackId,
    if (event == 'trackFinished' || event == 'skip')
      'totalPlayedSeconds': (played * 10).roundToDouble() / 10,
  };
  final uri = Uri.parse(
    '$kApi/rotor/station/$s/feedback',
  ).replace(queryParameters: batchId.isEmpty ? null : {'batch-id': batchId});
  try {
    await _http
        .post(
          uri,
          headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
  } catch (_) {
    // The station won't learn from this event, with no harm to playback.
  }
}

// ── Account ─────────────────────────────────────────────────────────────

/// Whether the account has active Yandex Plus. Only for the settings badge:
/// playback is decided per track at stream resolve anyway.
Future<bool> hasPlus() async {
  final v = await apiGet('/account/status');
  final result = v['result'];
  final plus = result is Map ? result['plus'] : null;
  return plus is Map ? plus['hasPlus'] == true : false;
}

// ── Stream ──────────────────────────────────────────────────────────────

/// Rough extraction of the first `<tag>...</tag>`'s content.
String? xmlTag(String xml, String tag) {
  final open = '<$tag>';
  final close = '</$tag>';
  final s = xml.indexOf(open);
  if (s < 0) return null;
  final from = s + open.length;
  final e = xml.indexOf(close, from);
  if (e < 0) return null;
  return xml.substring(from, e);
}

/// Direct link signature: `md5(SALT + path[1:] + s)`.
String signPath(String path, String s) =>
    md5.convert(utf8.encode('$kSignSalt${path.substring(1)}$s')).toString();

/// Direct mp3 URL for playback. Throws if the track is unavailable (no Plus,
/// region).
Future<String> streamUrl(String trackId) async {
  final token = _requireToken();
  final headers = _authHeaders(token);

  // 1. List of download options.
  final infoResp = await _http
      .get(Uri.parse('$kApi/tracks/$trackId/download-info'), headers: headers)
      .timeout(_timeout);
  if (infoResp.statusCode == 401) throw const YmException('ym.err.auth');
  final info = _decode(infoResp.bodyBytes);
  final variants = info?['result'];
  if (variants is! List || variants.isEmpty) {
    throw const YmException('ym.err.needPlus');
  }

  // Best mp3 by bitrate.
  Map? best;
  var bestRate = -1;
  for (final x in variants) {
    if (x is! Map || x['codec'] != 'mp3') continue;
    final rate = (x['bitrateInKbps'] as num?)?.toInt() ?? 0;
    if (rate > bestRate) {
      bestRate = rate;
      best = x;
    }
  }
  best ??= variants.first is Map ? variants.first as Map : null;
  final infoUrl = best?['downloadInfoUrl'];
  if (infoUrl is! String || infoUrl.isEmpty) {
    throw const YmException('ym.err.noDownloadInfo');
  }

  // 2. XML with host, path, ts and s.
  final xmlResp = await _http
      .get(Uri.parse(infoUrl), headers: headers)
      .timeout(_timeout);
  final xml = utf8.decode(xmlResp.bodyBytes, allowMalformed: true);
  final host = xmlTag(xml, 'host');
  final path = xmlTag(xml, 'path');
  final ts = xmlTag(xml, 'ts');
  final s = xmlTag(xml, 's');
  if (host == null || path == null || path.isEmpty || ts == null || s == null) {
    throw const YmException('ym.err.badDownloadXml');
  }

  // 3–4. The signature and final direct link.
  final url = 'https://$host/get-mp3/${signPath(path, s)}/$ts$path';

  // 5. Checks the link really gives audio. With no Plus or in a region,
  // download-info still gives a URL, but it returns 403, and with no check the
  // track would silently play silence. Range bytes=0-1 avoids fetching the
  // whole file.
  final probe = await _http
      .get(
        Uri.parse(url),
        headers: {
          'User-Agent': kUserAgent,
          'X-Yandex-Music-Client': kYmClient,
          'Range': 'bytes=0-1',
        },
      )
      .timeout(_timeout);
  final st = probe.statusCode;
  if (!(st >= 200 && st < 300)) throw const YmException('ym.err.needPlus');

  return url;
}
