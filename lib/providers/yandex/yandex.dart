/// Яндекс.Музыка, неофициальный API (`api.music.yandex.net`) — порт
/// десктопного `src-tauri/src/yandex.rs` (c:\bloom\bloom), функция-в-функцию.
///
/// На десктопе весь этот код живёт в Rust по одной причине: у API нет
/// CORS-заголовков, из WebView2 туда не сходить, а гонять OAuth-токен через
/// публичные прокси недопустимо. В мобилке HTTP идёт из самого приложения,
/// поэтому обе проблемы отпадают: ходим напрямую, токен никуда не уезжает, и
/// прокси-гонки (как у SoundCloud) здесь нет намеренно — через чужой прокси
/// пошёл бы заголовок `Authorization`.
///
/// Авторизация — OAuth Device Flow. Алгоритм подписи прямой mp3-ссылки и
/// эндпоинты воспроизведены по поведению неофициального API.
///
/// Ошибки — [YmException] с кодом (`ym.err.*`); переводит их слой UI.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

const String kApi = 'https://api.music.yandex.net';
const String kOauth = 'https://oauth.yandex.ru';

/// Публичные константы клиента приложения Яндекс.Музыка (общеизвестны, не
/// секрет). Дублируются с десктопом вручную — общего файла нет намеренно.
const String kClientId = '23cabbbdc6cd418abb4b39c32c41195d';
const String kClientSecret = '53bc75238f0c4d08a118e51fe9203300';

/// Соль для подписи прямой mp3-ссылки. Стабильна годами во всех клиентах.
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

/// Отдать провайдеру сохранённый токен (или снять его при выходе). Зовётся
/// стором авторизации — модульное состояние здесь по тому же образцу, что
/// `setManualClientId` у SoundCloud.
void setToken(String? token) {
  final v = token?.trim();
  _token = (v == null || v.isEmpty) ? null : v;
}

String? activeToken() => _token;

/// Токен для запроса; без него ходить в API бессмысленно — API отвечает 401
/// вообще на всё.
String _requireToken() {
  final t = _token;
  if (t == null) throw const YmException('ym.err.noToken');
  return t;
}

// ============================ Device Flow ============================

/// Шаг 1: получить код устройства и ссылку для подтверждения.
///
/// `deviceId` на десктопе выводится из пути LocalAppData; здесь его хранит и
/// передаёт стор авторизации — Яндекс не валидирует его строго, важна лишь
/// стабильность между запусками.
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

/// Шаг 2: один опрос — обменять `device_code` на токен. «Ещё не подтвердил» —
/// [YmPollOutcome.pending]; исключение — фатально (код истёк/отклонён).
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

/// GET к API с авторизацией + единая обработка 401/JSON.
///
/// Лёгкий ретрай на транзиентные сбои (сеть/5xx/429), как у SC: 3 попытки,
/// бэкофф 600 мс. 401 — фатально (не ретраим). Без этого одиночный сетевой
/// блип ронял весь поиск. landing3 (чарты/новинки) особенно любит отдавать
/// 5xx/битое тело — ретраим и провал разбора JSON (200 с оборванным телом).
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
      // сетевая ошибка — транзиентна
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

// ---- Разбор сущностей ----

/// id из числа или строки: Яндекс отдаёт то одно, то другое даже в одном
/// ответе.
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

/// Обложка из разных мест JSON (`coverUri` | `cover.uri` | `ogImage`).
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
    // Год из первого альбома трека — в ответе /search он уже есть, доп.
    // запросов не нужно. Нет года → пусто (фильтр пропустит).
    year: firstAlbum is Map
        ? ((firstAlbum['year'] as num?)?.toInt().toString() ?? '')
        : '',
    releaseDate: firstAlbum is Map ? _releaseDate(firstAlbum) : '',
    available: node['available'] as bool? ?? true,
  );
}

/// Полная дата релиза альбома. Есть не у всех: у старых и у сборников Яндекс
/// знает только `year` — тогда пусто, и в UI остаётся год.
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

/// Фото артиста 1000×1000 — для крупного круга карточки релиза (порт
/// `artist_cover` из `yandex.rs`).
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

// ============================ Поиск ============================

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

/// Один трек по id (для резолва ссылок вида `.../track/{id}`).
Future<YmRawTrack> trackOne(String id) async {
  final v = await apiGet('/tracks/$id');
  final arr = v['result'];
  final first = (arr is List && arr.isNotEmpty) ? parseTrack(arr.first) : null;
  if (first == null) throw const YmException('ym.err.trackNotFound');
  return first;
}

/// id трека из элемента popularTracks/коллекции: либо полный объект-трек, либо
/// `{id, albumId}`, либо bare id (строка/число).
String? _trackIdOf(Object? v) => v is Map ? idStr(v['id']) : idStr(v);

/// Пачка полных треков по id одним запросом `/tracks/{id1,id2,...}`.
Future<List<YmRawTrack>> tracksByIds(List<String> ids) async {
  if (ids.isEmpty) return const [];
  final v = await apiGet('/tracks/${ids.join(',')}');
  return _parseAll(v['result'], parseTrack, ids.length);
}

// ============================ Сущности ============================

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
    // Аватар первого артиста альбома (у объектов artists есть свой cover).
    ownerAvatar: (artists is List && artists.isNotEmpty)
        ? coverFrom(artists.first)
        : '',
  );
}

/// Размер страницы «Треков» артиста — и первая порция, и каждая догрузка.
const int kYmArtistTracksPage = 50;

/// Страница дискографии артиста (секция «Треки») — `/artists/{id}/tracks`.
/// Первую берёт [artist], остальные догружаются по «Загрузить ещё» (порт
/// `artist_tracks` из `yandex.rs`, 3.0).
Future<YmTracksPage> artistTracksPage(String id, int page) async {
  final v = await apiGet('/artists/$id/tracks', {
    'page': '$page',
    'page-size': '$kYmArtistTracksPage',
  });
  return parseArtistTracksPage(v['result'], page);
}

/// Разбор страницы «Треков» — отдельно от сети, ради тестов. Есть ли ещё —
/// по `pager` (`total`/`perPage`), если Яндекс его отдал; без него полная
/// страница значит «возможно, есть»: пустая следующая просто закончит список.
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

  // brief-info часто отдаёт popularTracks как id / {id, albumId} БЕЗ метаданных
  // → parseTrack даёт пусто или «Без названия». В этом случае дотягиваем полные
  // треки одним запросом /tracks (иначе «Популярные» пусты).
  var popularTracks = _parseAll(pop, parseTrack, 30);
  final needsFetch =
      popularTracks.isEmpty ||
      popularTracks.every((t) => t.title == kYmUntitled);
  if (needsFetch && pop is List) {
    final ids = [for (final item in pop) ?_trackIdOf(item)];
    final full = await tracksByIds(ids).catchError((_) => <YmRawTrack>[]);
    if (full.isNotEmpty) popularTracks = full;
  }

  // Первая страница дискографии (секция «Треки», как на SoundCloud); дальше —
  // догрузка по номеру страницы. Best-effort — если эндпоинт не отдал,
  // остаются хотя бы «Популярные».
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
    // Похожие исполнители — brief-info отдаёт готовые объекты артистов.
    similarArtists: _parseAll(r['similarArtists'], parseArtist, 18),
  );
}

/// Разобрать `result`-объект плейлиста (общий для обоих форматов URL).
YmEntity playlistEntity(Object? node) {
  if (node is! Map) {
    return const YmEntity(title: 'Плейлист', subtitle: '', cover: '');
  }
  final rawTracks = node['tracks'];
  final tracks = <YmRawTrack>[];
  if (rawTracks is List) {
    for (final w in rawTracks) {
      // Обёртка `{track: {...}}` (rich-tracks) либо сам трек.
      final inner = (w is Map && w['track'] is Map) ? w['track'] : w;
      final parsed = parseTrack(inner);
      if (parsed != null) tracks.add(parsed);
    }
  }
  // Владелец: плоский ownerName (старый формат) ИЛИ вложенный owner.name/login
  // (новый).
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
    // У плейлиста аватар владельца бывает только в новом формате.
    ownerAvatar: coverFrom(ownerNode),
  );
}

/// Старый формат плейлиста: `/users/<owner>/playlists/<kind>`.
Future<YmEntity> playlist(String owner, String kind) async {
  final v = await apiGet('/users/$owner/playlists/$kind');
  return playlistEntity(v['result']);
}

/// Новый формат публичного плейлиста: `/playlists/<uuid>` → API
/// `/playlist/<uuid>`.
Future<YmEntity> playlistByUuid(String uuid) async {
  final v = await apiGet('/playlist/$uuid', {'rich-tracks': 'true'});
  return playlistEntity(v['result']);
}

// ============================ Ссылки ============================

final RegExp reAlbumTrack = RegExp(r'/album/\d+/track/(\d+)');
final RegExp reTrack = RegExp(r'/track/(\d+)');
final RegExp reAlbum = RegExp(r'/album/(\d+)');
final RegExp reArtist = RegExp(r'/artist/(\d+)');
final RegExp reUserPlaylist = RegExp(r'/users/([^/?#]+)/playlists/(\d+)');

/// Новый публичный формат: `/playlists/<id>`, где id = uuid (8-4-4-4-12 hex)
/// ИЛИ префиксный (напр. `lk.<uuid>` — «Мне нравится»).
final RegExp rePublicPlaylist = RegExp(r'/playlists/([0-9A-Za-z.-]+)');

/// Резолв ссылки music.yandex.ru (.com): трек/альбом/артист/плейлист.
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
  // Идентификатор передаём в /playlist/<id> как есть, целиком — без срезания
  // префикса.
  if (rePublicPlaylist.firstMatch(u) case final m?) {
    return YmResolved.playlist(await playlistByUuid(m.group(1)!));
  }
  throw const YmException('ym.err.badUrl');
}

// ======================= Похожие (витрины главной) =======================

/// Похожие на трек для «Для вас» и «Похожие на» — `/tracks/{id}/similar`, порт
/// `similar_tracks` из `yandex.rs`. У нишевых треков similar бывает пуст, и
/// тогда фолбэк — первый батч станции по этому треку: пустая полоса на главной
/// хуже слегка размытой подборки. Сид из выдачи станции убираем — он и так
/// стоит в топе того, для кого подборка.
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

// ======================= Чарты и новинки (главная) =======================

/// Общий чарт Яндекс.Музыки — витрина на главной и страница «Чарт». Отдаём
/// весь чарт (у Яндекса это ~100 позиций): главная режет до 15 сама, странице
/// нужен полный список.
Future<List<YmRawTrack>> chart() async =>
    parseChart((await apiGet('/landing3/chart'))['result']);

/// Разбор `/landing3/chart` — отдельно от сети, ради тестов. Элемент
/// `result.chart.tracks[]` несёт `.track` (иногда сам уже трек) и обёртку
/// `.chart` с местом и динамикой. У «голого» трека обёртки нет — место тогда
/// берётся из порядка, а динамика считается неизвестной.
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
        // progress: new | up | down | same. Стрелку рисуем по shift, от
        // progress нужен только признак новичка.
        isNew: c is Map && c['progress'] == 'new',
      ),
    );
  }
  return out;
}

/// Сколько релизов отдаём. Витрина на главной берёт первые 10, остальное
/// показывает страница «Релизы» сеткой. Реально площадка отдаёт ~80 (число
/// плавает по дням), так что это потолок с запасом, а не ограничение.
const int _newReleasesMax = 100;

/// Новинки (свежие альбомы) — витрина на главной и страница «Релизы».
/// Основной путь — `landing3?blocks=new-releases` (полные альбомы в
/// `entities[].data`), но блок лендинга это карусель и коротким бывает почти
/// всегда — поэтому список добирается id-шниками из `/landing3/new-releases`.
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
        // entity.data — полный альбом; иногда сам entity уже альбом.
        final data = (e is Map && e['data'] is Map) ? e['data'] : e;
        final parsed = parseAlbum(data);
        if (parsed != null) out.add(parsed);
      }
    }
  }
  if (out.length < _newReleasesMax) {
    try {
      // Дубли по id отсеиваем: id-список пересекается с каруселью лендинга.
      for (final a in await _newReleasesByIds()) {
        if (out.length >= _newReleasesMax) break;
        if (!out.any((x) => x.id == a.id)) out.add(a);
      }
    } on Object {
      // Добор не вышел — остаёмся на том, что дал лендинг.
    }
  }
  if (out.isEmpty) return const [];
  // Сущности лендинга бывают «худыми»: без фото артиста и даты выхода, а
  // карточке релиза нужно и то и другое. Добираем полные альбомы; не вышло —
  // остаёмся на лендинге.
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
      // см. выше
    }
  }
  return out;
}

/// `/landing3/new-releases` отдаёт `newReleases[]` — id альбомов.
Future<List<YmRawAlbum>> _newReleasesByIds() async {
  final v = await apiGet('/landing3/new-releases');
  final result = v['result'];
  final raw = result is Map ? result['newReleases'] : null;
  final ids = raw is List
      ? [for (final item in raw.take(_newReleasesMax)) ?idStr(item)]
      : const <String>[];
  return _albumsByIds(ids);
}

/// Полные альбомы по id через `/albums?album-ids=…`, пачками по 50: id уходят в
/// строку запроса, и на шестидесяти URL уже неприлично длинный. Порядок
/// ответа — порядок новинок.
Future<List<YmRawAlbum>> _albumsByIds(List<String> ids) async {
  final out = <YmRawAlbum>[];
  for (var i = 0; i < ids.length; i += 50) {
    final chunk = ids.sublist(i, i + 50 < ids.length ? i + 50 : ids.length);
    final av = await apiGet('/albums', {'album-ids': chunk.join(',')});
    out.addAll(_parseAll(av['result'], parseAlbum, chunk.length));
  }
  return out;
}

// ============================ Моя волна (rotor) ============================

/// Станция «Моей волны» по умолчанию. Rotor принимает и другие сиды в том же
/// формате: `track:<id>` (волна по треку), `artist:<id>`, `genre:<tag>`.
const String kWaveStation = 'user:onyourwave';

/// Очередной батч rotor-станции. [station] — сид (`user:onyourwave`,
/// `track:<id>`, …); [lastId] — id последнего сыгранного трека, чтобы станция
/// продолжила цепочку, а не начала её заново. Пусто — старт станции.
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

/// Фидбек станции (`radioStarted` / `trackStarted` / `trackFinished` / `skip`)
/// — им «Моя волна» и учится в самом аккаунте.
///
/// Best-effort: ответ не разбираем и ошибки глотаем. Обучение станции — не та
/// операция, ради которой стоит рвать воспроизведение.
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
    // Станция не обучится на этом событии — воспроизведению это не мешает.
  }
}

// ============================ Аккаунт ============================

/// Есть ли у аккаунта активный Яндекс Плюс. Только для бейджа в настройках:
/// воспроизведение всё равно решается per-track при резолве стрима.
Future<bool> hasPlus() async {
  final v = await apiGet('/account/status');
  final result = v['result'];
  final plus = result is Map ? result['plus'] : null;
  return plus is Map ? plus['hasPlus'] == true : false;
}

// ============================ Стрим ============================

/// Грубое извлечение содержимого первого тега `<tag>...</tag>`.
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

/// Подпись прямой ссылки: `md5(SALT + path[1:] + s)`.
String signPath(String path, String s) =>
    md5.convert(utf8.encode('$kSignSalt${path.substring(1)}$s')).toString();

/// Прямой mp3-URL для воспроизведения. Бросает, если трек недоступен (нет
/// Плюса/регион).
Future<String> streamUrl(String trackId) async {
  final token = _requireToken();
  final headers = _authHeaders(token);

  // 1. Список вариантов загрузки.
  final infoResp = await _http
      .get(Uri.parse('$kApi/tracks/$trackId/download-info'), headers: headers)
      .timeout(_timeout);
  if (infoResp.statusCode == 401) throw const YmException('ym.err.auth');
  final info = _decode(infoResp.bodyBytes);
  final variants = info?['result'];
  if (variants is! List || variants.isEmpty) {
    throw const YmException('ym.err.needPlus');
  }

  // Лучший mp3 по битрейту.
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

  // 2. XML с host/path/ts/s.
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

  // 3–4. Подпись и финальная прямая ссылка.
  final url = 'https://$host/get-mp3/${signPath(path, s)}/$ts$path';

  // 5. Проверяем, что ссылка реально отдаёт аудио. Без Плюса/в регионе
  //    download-info всё равно отдаёт URL, но он возвращает 403 — без этой
  //    проверки трек молча «играл» бы тишину. Range bytes=0-1 — не качаем
  //    весь файл.
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
