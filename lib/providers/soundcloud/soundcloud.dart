/// SoundCloud api-v2 — порт десктопного `src-tauri/src/soundcloud.rs`
/// (c:\bloom\bloom), функция-в-функцию.
///
/// client_id: ручной (из настроек) → известные → скрейп ассетов soundcloud.com.
/// Каждый запрос — гонка «прямой + CORS-прокси»: прокси не для CORS (его тут
/// нет), а фолбэк на случай блокировки SC у пользователя; первый успешный
/// ответ побеждает.
///
/// Ошибки — коды i18n-словаря (`sc.err.*` / `search.err.*`) в [ScException];
/// переводит их слой UI.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

const List<String> kKnownClientIds = [
  'O7atZypwLvuWSY9hWnnQ3vrLTHH7wqMe', // актуальный на 2026-07 (со скрейпа)
  'iZIs9mchVcX5lhVRyQGGAYlNPa2Rp1jf',
  'a3e059563d7fd3372b49b37f00a00bcf',
  'fDoItMDbsbZz8dY16ZzARCZmzgHBPotA',
  'YUKXoArFcqrlQn9tfNHvvyfnDISj04zk',
];

const Duration _clientIdTtl = Duration(hours: 6);

// ============================ client_id state ============================

String? _manualId;
String? _autoId;

/// null — авто-кеш «протух»/не получен (в т.ч. после фолбэка на известный id).
DateTime? _fetchedAt;

/// Ручной client_id из настроек. null/пустая строка — сброс (вместе с
/// авто-кешем).
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

/// Сбросить авто-кеш (ручной не трогаем) — перед [checkConnection] и при
/// невалидном ответе SC.
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

// ============================ HTTP (гонка direct+прокси) ============================

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
    // Тело декодируем сами: без charset в Content-Type http падает на latin1
    // и ломает кириллицу в названиях.
    return (status, utf8.decode(r.bodyBytes, allowMalformed: true));
  }
  throw const ScException('not ok');
}

/// Гонка «прямой запрос (8с) + прокси (12с)», побеждает первый успешный.
/// [acceptAuthErr] — принять 401/403 от прямого запроса (нужно [apiFetch] для
/// ветки перебора известных client_id); от прокси — только 2xx.
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

/// Активный client_id: ручной → свежий авто → скрейп ассетов soundcloud.com →
/// первый известный (без отметки времени — перепроверится в следующий раз).
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

  // Сканируем ВСЕ ассеты (раньше первые 6 — SC переложил client_id в хвост
  // списка, и старый скрейп из-за этого молча ломался).
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
        // следующий ассет
      }
    }
  } catch (_) {
    // проваливаемся на известный id
  }

  final id = kKnownClientIds[0];
  _autoId = id;
  return id;
}

/// JS-falsy для полей ответа SC (`!data.errors`, `!data.status`).
bool _falsy(Object? v) {
  if (v == null) return true;
  if (v is bool) return !v;
  if (v is String) return v.isEmpty;
  if (v is num) return v == 0;
  return false;
}

/// Перебор известных client_id; валидная выдача — кешируем id и возвращаем её.
Future<Object?> _tryKnownIds(String url) async {
  for (final id in kKnownClientIds) {
    final sep = url.contains('?') ? '&' : '?';
    Object? data;
    try {
      final (_, body) = await _raceFetch('$url${sep}client_id=$id', false);
      data = jsonDecode(body);
    } catch (_) {
      continue; // недоступно или не JSON — пробуем следующий id
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

/// Запрос к api-v2 с client_id и авто-восстановлением при невалидном ключе
/// (401/403, `errors[]`, `status: "4xx"` → сброс кеша + перебор известных id).
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

  // Списочные ответы (`/tracks?ids=`) — ни errors, ни status в них не бывает.
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

// ============================ JSON-хелперы ============================

/// Непустая строка поля (пустая = JS-falsy, проваливается в фолбэк как `||`).
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

/// JS-truthiness поля (`!!x`).
bool _vbool(Object? v, String k) => v is Map ? !_falsy(v[k]) : false;

List<Object?> _varr(Object? v, String k) {
  if (v is! Map) return const [];
  final x = v[k];
  return x is List ? x : const [];
}

/// `-large` → `-t300x300` (обложка 300px), null при пустом значении.
String? _t300(String? raw) => _sized(raw, 't300x300');

/// Тот же URL в 500px — для шапки артиста во всю ширину экрана, где 300px
/// заметно мылит. В списках и плитках такой размер не нужен.
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

// ============================ Маппинг ============================

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

/// Дата плейлиста/альбома: `release_date` (у альбомов), иначе `created_at`.
String _playlistDate(Object? p) =>
    _vstr(p, 'release_date') ?? _vstr(p, 'created_at') ?? '';

/// Год из неё же — той самой, чтобы год и полная дата не разошлись источником.
String _playlistYear(Object? p) => _year(_playlistDate(p));

bool _hasId(Object? v) => _vu64(v, 'id') != null;

// ============================ Поиск ============================

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

/// Проверка соединения из настроек: сброс авто-кеша → тестовый поиск.
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

// ============================ Артист / профиль ============================

/// Числовой userId из id-строки ("12345") или permalink-URL (через /resolve).
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

/// Лайкнутые треки пользователя (профиль по ссылке); ошибки — пустой список.
/// SC отдаёт лайки страницами (в выдаче попадаются и плейлисты — их пропускаем),
/// поэтому идём по `next_href` до конца; ошибка на середине — отдаём накопленное.
Future<List<ScRawTrack>> userLikes(String idOrUrl) async {
  final out = <ScRawTrack>[];
  final seen = <int>{};
  try {
    final id = await _resolveUserId(idOrUrl);
    var url =
        'https://api-v2.soundcloud.com/users/$id/likes?limit=200&linked_partitioning=1';
    // Потолок в 25 страниц (~5000 лайков) — страховка от «висячего» курсора.
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

/// Данные пользователя (hero артиста); null при ошибке.
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

/// Популярные треки артиста: /toptracks → /spotlight → /tracks → поиск по имени.
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
    // 1. /toptracks — настоящие «популярные».
    try {
      final tt = await apiFetch(
        'https://api-v2.soundcloud.com/users/$userId/toptracks'
        '?limit=20&linked_partitioning=1',
      );
      if (_varr(tt, 'collection').isNotEmpty) {
        return _varr(tt, 'collection').where(_hasId).map(mapRawTrack).toList();
      }
    } catch (_) {
      // молча — падаем в следующий фолбэк
    }
    // 2. /spotlight — закреплённые артистом.
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
      // молча — падаем в следующий фолбэк
    }
    // 3. /tracks (может требовать сессию).
    try {
      final d = await apiFetch(
        'https://api-v2.soundcloud.com/users/$userId/tracks'
        '?limit=50&linked_partitioning=1',
      );
      if (_varr(d, 'collection').isNotEmpty) {
        return _varr(d, 'collection').where(_hasId).map(mapRawTrack).toList();
      }
    } catch (_) {
      // молча — падаем в следующий фолбэк
    }
  }

  // 4. Фолбэк: поиск по имени артиста (точное совпадение → первые 20).
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
      // молча — падаем в следующий фолбэк
    }
  }
  return [];
}

/// Треки (первая страница + курсор) и альбомы артиста; фолбэк — поиск по имени.
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
      // молча — падаем в следующий фолбэк
    }
  }

  // Фолбэк: пусто — ищем по имени.
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
      // молча — падаем в следующий фолбэк
    }
  }

  return ScArtistData(tracks: tracks, tracksNext: tracksNext, albums: albums);
}

/// Похожие исполнители (`/users/{id}/relatedartists`) — секция «Похожие» на
/// странице артиста. У малоизвестных профилей SC отдаёт пустую коллекцию;
/// ошибки тоже гасим в пустой список (секция просто не рисуется).
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

// ============================ Плейлисты / треки ============================

/// Треки из данных плейлиста: полные + дозагрузка stub'ов (только id) батчами
/// по 50.
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
      // молча — падаем в следующий фолбэк
    }
    if ((i + 1) * 50 < stubs.length) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  return [...full, ...fetched].where(_hasId).map(mapRawTrack).toList();
}

/// Треки плейлиста/альбома по permalink-URL (ошибки пробрасываются — импорт
/// должен их показать).
Future<List<ScRawTrack>> playlistTracks(String permalinkUrl) async {
  final data = await apiFetch(
    'https://api-v2.soundcloud.com/resolve?url=${Uri.encodeComponent(permalinkUrl)}',
  );
  return _loadTracksFromPlaylistData(data);
}

/// Полные данные плейлиста по числовому SC-id (открытие из «недавних»).
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

/// Один трек по числовому SC-id; null при ошибке.
Future<ScRawTrack?> trackById(int id) async {
  try {
    final data = await apiFetch('https://api-v2.soundcloud.com/tracks/$id');
    if (!_hasId(data)) return null;
    return mapRawTrack(data);
  } catch (_) {
    return null;
  }
}

// ============================ Волна: похожие треки ============================

/// Треки станции трека (`stations/soundcloud:track-stations:<id>/tracks`) —
/// главный источник кандидатов волны. Листается смещением: [offset] двигает
/// движок волны, чтобы каждый новый сеанс не начинался с тех же двадцати.
///
/// Сбой пробрасывается, а не превращается в пустоту: пустой ответ значит
/// «станция кончилась» и двигает курсор, и путать его с обрывом сети нельзя.
/// Гасит ошибки слой выше (`sc_sources.dart`), там же и повтор.
Future<List<ScRawTrack>> stationTracks(Object scTrackId, {int offset = 0}) =>
    _waveTracks(
      'https://api-v2.soundcloud.com/stations/'
      'soundcloud:track-stations:$scTrackId/tracks?limit=20&offset=$offset',
    );

/// Похожие на трек (`tracks/<id>/related`). Не пагинируется, зато для волны по
/// одному треку это главный источник вкусовых рекомендаций.
Future<List<ScRawTrack>> relatedTracks(Object scTrackId) => _waveTracks(
  'https://api-v2.soundcloud.com/tracks/$scTrackId/related?limit=20',
);

/// Разбор обоих ответов: элемент коллекции — либо сам трек, либо обёртка
/// `{track: {...}}` (так отдаёт станция).
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

// ============================ Резолв ссылки ============================

/// SC-ссылка → сущность (трек / артист / плейлист / альбом); null если не
/// распознали.
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

// ============================ Стрим ============================

/// Играбельный signed CDN-URL из `media.transcodings`: progressive (mp3) → hls →
/// любой не-DRM; одна повторная попытка через 500мс.
///
/// [progressiveOnly] — для скачивания: HLS это плейлист с кусками, файлом его
/// не сохранить, а «любой не-DRM» может оказаться тем же HLS под другим именем.
/// Такой трек честно падает `sc.err.hlsOnly`, как и на десктопе.
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
