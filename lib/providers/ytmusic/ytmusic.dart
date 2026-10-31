/// YouTube Music — неофициальный InnerTube API (`music.youtube.com/youtubei`),
/// порт десктопного `src-tauri/src/ytm.rs` (c:\bloom\bloom), функция-в-функцию.
///
/// На десктопе весь этот код живёт в Rust: у `music.youtube.com` нет CORS, а
/// аудио с `googlevideo.com` — range-based и в WebView2 напрямую не отдаётся
/// (идёт через локальный `audio_proxy`). В мобилке обе причины отпадают: HTTP
/// делает само приложение, а прямую ссылку `googlevideo` плеер тянет сам —
/// прокси не переносился намеренно.
///
/// Без авторизации (публичный поиск/стрим). Поиск и страницы — клиент
/// `WEB_REMIX`, разбор `musicResponsiveListItemRenderer`. Стрим — клиент
/// `VISIONOS` к `player`-эндпоинту: он отдаёт `streamingData.adaptiveFormats[]`
/// с ПРЯМЫМИ url (без расшифровки signatureCipher / n-throttling) и, в отличие
/// от web/ios/android, **не требует PoToken** (гайд yt-dlp «PO Token»).
///
/// ВАЖНО (2026-08-31): раньше основным был `ANDROID_VR`, теперь он мёртв —
/// googlevideo отдаёт по его ссылкам 403 на всё, что выходит за первый 1 MiB
/// файла. Симптом коварный: `player` отвечает `OK` и с прямыми url, ссылка
/// «выглядит рабочей», а ExoPlayer/AVPlayer первым делом просит файл целиком
/// → 403 → трек включается и стоит на 0:00. yt-dlp подтверждает пометкой у
/// `android_vr`: «Since 2026.08.17, ALL formats are 403'd». Здесь прокси нет,
/// перехватить 403 негде, поэтому ANDROID_VR убран из цепочки совсем.
///
/// КРИТИЧНО: во все запросы идёт `visitorData` (см. [visitorData]). Без него
/// `player` отвечает `LOGIN_REQUIRED` («Sign in to confirm you're not a bot»).
///
/// Константы клиентов YouTube время от времени ломает — все собраны вверху
/// файла, обновлять из yt-dlp `yt_dlp/extractor/youtube/_base.py`,
/// `INNERTUBE_CLIENTS`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

const String kSearchUrl =
    'https://music.youtube.com/youtubei/v1/search?prettyPrint=false';
const String kBrowseUrl =
    'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false';
const String kPlayerUrl =
    'https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false';
const String kVisitorUrl =
    'https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false';

/// Веб-клиент YouTube Music — поиск/браузинг (ключ публичный, общеизвестен).
const String kWebKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
const String kWebClientName = 'WEB_REMIX';
const String kWebClientVersion = '1.20260707.12.00';
const String kWebUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

/// Клиент обычного youtube.com — только чтобы выпросить `visitorData`.
const String kYtClientVersion = '2.20260708.00.00';

/// VISIONOS (Apple Vision Pro) — основной (и единственный) клиент для `player`.
/// Не требует PoToken, отдаёт прямые url и, в отличие от ANDROID_VR, честно
/// обслуживает произвольные Range-запросы: файл целиком, перемотку в середину
/// и в хвост. Версию/UA/deviceModel обновлять по yt-dlp `INNERTUBE_CLIENTS`.
const String kVisionClientVersion = '1.02';
const String kVisionUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

final http.Client _http = http.Client();

const int _maxAttempts = 3;
const Duration _retryDelay = Duration(milliseconds: 600);
const Duration _timeout = Duration(seconds: 20);

// ============================ visitorData ============================

/// Кеш `visitorData` на процесс. Это идентификатор анонимной сессии: без него
/// каждый запрос выглядит как новый холодный клиент, и YouTube помечает его
/// ботом. Сбрасывается в [resetVisitorData] при отказе `player`.
String? _visitor;
Future<String>? _visitorInFlight;

/// Достать `visitorData` (из кеша либо у `visitor_id`-эндпоинта). Ошибку не
/// поднимаем: пустая строка означает «шлём без него» — поиск/браузинг работают
/// и так, страдает только `player`.
///
/// Отличие от десктопа: параллельные запросы ждут ОДИН поход в сеть. На старте
/// поиск уходит пятью запросами разом, и без этого мобилка брала бы пять разных
/// `visitorData` — пять «холодных клиентов» подряд ровно то, что YouTube и
/// считает ботом.
Future<String> visitorData() async {
  final cached = _visitor;
  if (cached != null) return cached;
  final inflight = _visitorInFlight ??= _fetchVisitorData();
  String v;
  try {
    v = await inflight;
  } catch (_) {
    v = '';
  }
  _visitor ??= v;
  _visitorInFlight = null;
  return v;
}

Future<String> _fetchVisitorData() async {
  final r = await _http
      .post(
        Uri.parse(kVisitorUrl),
        headers: {'User-Agent': kWebUa, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'context': {
            'client': {
              'clientName': 'WEB',
              'clientVersion': kYtClientVersion,
              'hl': 'en',
              'gl': 'US',
            },
          },
        }),
      )
      .timeout(_timeout);
  final v = _decode(r.bodyBytes);
  return str(at(v, ['responseContext', 'visitorData']));
}

/// Забыть текущий `visitorData` — следующий вызов возьмёт свежий.
void resetVisitorData() {
  _visitor = null;
  _visitorInFlight = null;
}

// ============================ HTTP ============================

Map<String, dynamic>? _decode(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

/// POST с телом-JSON и единой обработкой сбоев.
///
/// Лёгкий ретрай на транзиентное (сеть/5xx/429), как у SC и Яндекса: 3 попытки,
/// бэкофф 600 мс. На десктопе его нет — там одиночный блип виден в UI, здесь же
/// мобильная сеть роняла бы весь поиск.
Future<Map<String, dynamic>> _postJson(
  String url,
  Map<String, dynamic> body, {
  required String userAgent,
  Map<String, String> extraHeaders = const {},
  required String errCode,
}) async {
  final uri = Uri.parse(url);
  final headers = {
    'User-Agent': userAgent,
    'Content-Type': 'application/json',
    ...extraHeaders,
  };
  final payload = jsonEncode(body);

  for (var attempt = 1; ; attempt++) {
    http.Response? resp;
    try {
      resp = await _http
          .post(uri, headers: headers, body: payload)
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
    if (resp == null) throw const YtmException('ytm.err.network');
    if (status < 200 || status >= 300) throw YtmException('$errCode:$status');

    final v = _decode(resp.bodyBytes);
    if (v != null) return v;
    if (attempt < _maxAttempts) {
      await Future<void>.delayed(_retryDelay);
      continue;
    }
    throw const YtmException('ytm.err.badJson');
  }
}

/// Тело запроса InnerTube с веб-контекстом (+ `visitorData` — см. модуль-док).
Future<Map<String, dynamic>> _webBody(Map<String, dynamic> extra) async => {
  'context': {
    'client': {
      'clientName': kWebClientName,
      'clientVersion': kWebClientVersion,
      'hl': 'en',
      'gl': 'US',
      'visitorData': await visitorData(),
    },
  },
  ...extra,
};

const Map<String, String> _musicHeaders = {
  'Origin': 'https://music.youtube.com',
  'Referer': 'https://music.youtube.com/',
};

// ============================ Обход JSON ============================

/// Значение по пути: строковые ключи — в объектах, числовые — в массивах.
/// Аналог `Value::pointer` из Rust, но без склейки пути в строку.
Object? at(Object? v, List<Object> path) {
  var cur = v;
  for (final k in path) {
    if (k is String && cur is Map) {
      cur = cur[k];
    } else if (k is int && cur is List && k >= 0 && k < cur.length) {
      cur = cur[k];
    } else {
      return null;
    }
  }
  return cur;
}

String str(Object? v) => v is String ? v : '';

/// Рекурсивно собрать все значения ключа [key] (`musicResponsiveListItemRenderer`
/// и т.п.). Надёжнее навигации по точному пути — структура секций меняется.
void collectRenderers(Object? v, String key, List<Object?> out) {
  if (v is Map) {
    for (final e in v.entries) {
      if (e.key == key) out.add(e.value);
      collectRenderers(e.value, key, out);
    }
  } else if (v is List) {
    for (final x in v) {
      collectRenderers(x, key, out);
    }
  }
}

/// Строки выдачи.
List<Object?> collectMrlir(Object? v) {
  final out = <Object?>[];
  collectRenderers(v, 'musicResponsiveListItemRenderer', out);
  return out;
}

/// Карточки каруселей.
List<Object?> collectTwoRow(Object? v) {
  final out = <Object?>[];
  collectRenderers(v, 'musicTwoRowItemRenderer', out);
  return out;
}

/// Первый рендерер по ключу (рекурсивно).
Object? findRenderer(Object? v, String key) {
  if (v is Map) {
    final direct = v[key];
    if (direct != null) return direct;
    for (final x in v.values) {
      final f = findRenderer(x, key);
      if (f != null) return f;
    }
  } else if (v is List) {
    for (final x in v) {
      final f = findRenderer(x, key);
      if (f != null) return f;
    }
  }
  return null;
}

/// Обойти все строковые поля `text`/`simpleText` узла. `visit` возвращает
/// `false`, когда искомое найдено, — дальше не идём (Rust обходит всё и
/// проверяет флаг внутри, здесь дешевле остановиться).
bool collectText(Object? v, bool Function(String) visit) {
  if (v is Map) {
    for (final e in v.entries) {
      if ((e.key == 'text' || e.key == 'simpleText') && e.value is String) {
        if (!visit(e.value as String)) return false;
      } else if (!collectText(e.value, visit)) {
        return false;
      }
    }
  } else if (v is List) {
    for (final x in v) {
      if (!collectText(x, visit)) return false;
    }
  }
  return true;
}

/// Первый токен продолжения в ответе. InnerTube кладёт его то в
/// `nextContinuationData.continuation`, то в `continuationCommand.token` —
/// ищем оба, не привязываясь к пути (структура секций плавает).
String? findContinuation(Object? v) {
  if (v is Map) {
    for (final e in v.entries) {
      final val = e.value;
      // Короткие строки с таким ключом встречаются в трекинге.
      if ((e.key == 'continuation' || e.key == 'token') &&
          val is String &&
          val.length > 20) {
        return val;
      }
      final found = findContinuation(val);
      if (found != null) return found;
    }
  } else if (v is List) {
    for (final x in v) {
      final found = findContinuation(x);
      if (found != null) return found;
    }
  }
  return null;
}

// ============================ Разбор строк ============================

/// pageType основного перехода строки (ARTIST/ALBUM/PLAYLIST) либо null (трек).
String? pageType(Object? it) {
  final v = at(it, [
    'navigationEndpoint',
    'browseEndpoint',
    'browseEndpointContextSupportedConfigs',
    'browseEndpointContextMusicConfig',
    'pageType',
  ]);
  return v is String ? v : null;
}

/// browseId основного перехода строки.
String? itemBrowseId(Object? it) {
  final v = at(it, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
  return v is String && v.isNotEmpty ? v : null;
}

/// flexColumn[i] → его узел `text` (с runs).
Object? flexText(Object? it, int i) => at(it, [
  'flexColumns',
  i,
  'musicResponsiveListItemFlexColumnRenderer',
  'text',
]);

/// Метки типа сущности, с которых YTM начинает подпись строки или карточки
/// («Song • Artist • Album», «Single • BahaVibe»). Это не имя артиста и не
/// владелец — из подписей их выкидываем, иначе они утекают в UI. Запросы уходят
/// с `hl=en`, поэтому список английский; русские — на случай, если YTM всё же
/// ответит на языке региона.
const List<String> kTypeLabels = [
  'song',
  'video',
  'album',
  'single',
  'ep',
  'playlist',
  'artist',
  'podcast',
  'episode',
  'песня',
  'видео',
  'альбом',
  'сингл',
  'плейлист',
  'исполнитель',
  'подкаст',
  'эпизод',
];

bool isTypeLabel(String s) => kTypeLabels.contains(s.trim().toLowerCase());

/// Смысловые куски подписи (`{runs:[…]}`): без сепараторов и без метки типа.
List<String> meaningfulRuns(Object? node) {
  final runs = at(node, ['runs']);
  if (runs is! List) return const [];
  return runs
      .map((r) => str(at(r, ['text'])).trim())
      .where((s) => s.isNotEmpty && s != '•' && s != '&' && !isTypeLabel(s))
      .toList();
}

/// text.runs[0].text.
String firstRun(Object? text) => str(at(text, ['runs', 0, 'text']));

/// Самая крупная обложка строки (`thumbnail.musicThumbnailRenderer…`).
String thumb(Object? it) {
  final arr = at(it, [
    'thumbnail',
    'musicThumbnailRenderer',
    'thumbnail',
    'thumbnails',
  ]);
  return upscaleThumb(_lastThumbUrl(arr));
}

String _lastThumbUrl(Object? arr) =>
    arr is List && arr.isNotEmpty ? str(at(arr.last, ['url'])) : '';

/// YTM-обложки масштабируются параметрами в URL: `=w120-h120` → `=w544-h544`.
String upscaleThumb(String url) {
  final i = url.indexOf('=w');
  if (i < 0) return url;
  final dash = url.indexOf('-', i);
  if (dash < 0) return url;
  final tail = url.substring(dash + 1);
  if (!tail.startsWith('h')) return url;
  final after = tail.substring(1).replaceFirst(RegExp(r'^\d+'), '');
  return '${url.substring(0, i)}=w544-h544$after';
}

/// Самая крупная обложка из первого `thumbnails`-массива в поддереве (апскейл).
String biggestThumb(Object? v) => upscaleThumb(_lastThumbUrl(_findThumbs(v)));

Object? _findThumbs(Object? v) {
  if (v is Map) {
    final arr = v['thumbnails'];
    if (arr is List) return arr;
    for (final x in v.values) {
      final f = _findThumbs(x);
      if (f != null) return f;
    }
  } else if (v is List) {
    for (final x in v) {
      final f = _findThumbs(x);
      if (f != null) return f;
    }
  }
  return null;
}

/// videoId трека: playlistItemData либо play-button overlay.
String? videoId(Object? it) {
  final direct = at(it, ['playlistItemData', 'videoId']);
  if (direct is String && direct.isNotEmpty) return direct;
  final overlay = at(it, [
    'overlay',
    'musicItemThumbnailOverlayRenderer',
    'content',
    'musicPlayButtonRenderer',
    'playNavigationEndpoint',
    'watchEndpoint',
    'videoId',
  ]);
  return overlay is String && overlay.isNotEmpty ? overlay : null;
}

/// «m:ss»/«h:mm:ss» → секунды; null, если это не часы.
int? parseClock(String s) {
  final parts = s.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  var secs = 0;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null) return null;
    secs = secs * 60 + n;
  }
  return secs;
}

/// Имя артиста из col1. В неотфильтрованном поиске первый run — это ТИП
/// («Song»/«Video»), поэтому [firstRun] бесполезен. Берём runs со ссылкой на
/// артиста (pageType ARTIST); если их нет — первый смысловой run.
String col1Artist(Object? col1) {
  // Артисты-ссылки (может быть несколько — джойним).
  final names = col1Artists(col1);
  if (names.isNotEmpty) return names.map((a) => a.name).join(', ');

  // Фолбэк — первый смысловой кусок подписи. Безусловно пропускать нулевой run
  // нельзя: в строках плейлиста артист как раз в нулевом (у чарт-плейлистов
  // подпись = один run с каналом), и все треки чарта выходили без исполнителя.
  for (final s in meaningfulRuns(col1)) {
    if (parseClock(s) == null) return s;
  }
  return '';
}

/// Every run that links an artist's page, in order.
List<({String id, String name})> col1Artists(Object? col1) {
  final runs = at(col1, ['runs']);
  if (runs is! List) return const [];
  return [
    for (final r in runs)
      if (pageType(r) == 'MUSIC_PAGE_TYPE_ARTIST' &&
          str(at(r, ['text'])).isNotEmpty)
        (id: itemBrowseId(r) ?? '', name: str(at(r, ['text']))),
  ];
}

/// The first of them whose page is known.
String _firstPage(List<({String id, String name})> artists) => artists
    .map((a) => a.id)
    .firstWhere((id) => id.isNotEmpty, orElse: () => '');

/// Длительность из последнего run col1 формата «m:ss» → секунды.
int col1Duration(Object? col1) {
  final runs = at(col1, ['runs']);
  if (runs is! List) return 0;
  for (final r in runs.reversed) {
    final sec = parseClock(str(at(r, ['text'])));
    if (sec != null) return sec;
  }
  return 0;
}

/// Длительность из fixedColumns (строки альбома: «m:ss» отдельной колонкой).
int fixedDuration(Object? it) =>
    parseClock(
      str(
        at(it, [
          'fixedColumns',
          0,
          'musicResponsiveListItemFixedColumnRenderer',
          'text',
          'runs',
          0,
          'text',
        ]),
      ),
    ) ??
    0;

YtmRawTrack? parseTrack(Object? it) {
  final id = videoId(it);
  if (id == null) return null;
  final title = firstRun(flexText(it, 0));
  if (title.isEmpty) return null;
  final col1 = flexText(it, 1);

  final artists = col1Artists(col1);

  // Длительность: в строках поиска — в col1; в строках альбома — в fixedColumns.
  final d = col1Duration(col1);
  return YtmRawTrack(
    id: id,
    title: title,
    artist: col1Artist(col1),
    artistId: _firstPage(artists),
    artists: artists,
    cover: thumb(it),
    duration: Duration(seconds: d > 0 ? d : fixedDuration(it)),
  );
}

YtmRawArtist? parseArtist(Object? it) {
  final id = itemBrowseId(it);
  if (id == null) return null;
  final name = firstRun(flexText(it, 0));
  if (name.isEmpty) return null;
  return YtmRawArtist(id: id, name: name, cover: thumb(it));
}

bool _isYear(String s) => s.length == 4 && RegExp(r'^\d{4}$').hasMatch(s);

YtmRawAlbum? parseAlbum(Object? it) {
  final id = itemBrowseId(it);
  if (id == null) return null;
  final title = firstRun(flexText(it, 0));
  if (title.isEmpty) return null;
  final col1 = flexText(it, 1);
  // Год — 4-значный run в col1.
  var year = '';
  final runs = at(col1, ['runs']);
  if (runs is List) {
    for (final r in runs) {
      final s = str(at(r, ['text']));
      if (_isYear(s)) {
        year = s;
        break;
      }
    }
  }
  // The caption opens with the kind ("Album", "Single", "EP"), not the
  // artist: the artist is the linked runs, as on the PC.
  final artist = col1Artist(col1);
  return YtmRawAlbum(
    id: id,
    title: title,
    artist: _isYear(artist) ? '' : artist,
    cover: thumb(it),
    year: year,
    kind: releaseKindOf(firstRun(col1)),
  );
}

/// A caption's type label as [Playlist.albumType]: single, ep; else null.
String? releaseKindOf(String label) => switch (label.trim().toLowerCase()) {
  'single' || 'сингл' => 'single',
  'ep' => 'ep',
  _ => null,
};

YtmRawPlaylist? parsePlaylist(Object? it) {
  final id = itemBrowseId(it);
  if (id == null) return null;
  final title = firstRun(flexText(it, 0));
  if (title.isEmpty) return null;
  return YtmRawPlaylist(
    id: id,
    title: title,
    cover: thumb(it),
    ownerName: firstRun(flexText(it, 1)),
    trackCount: rowTrackCount(it),
  );
}

/// Число треков из подписи строки. Официальные плейлисты YTM пишут его в
/// подзаголовке («Playlist • YouTube Music • 48 songs»), пользовательские —
/// нет (у них «автор • 4.3M views»), а у альбомов его нет вовсе. Поэтому
/// nullable: «неизвестно» и «ноль треков» — разные вещи, и UI не должен
/// показывать «0 тр.» там, где счётчика просто не дали.
int? rowTrackCount(Object? it) {
  int? found;
  collectText(it, (s) {
    // «48 songs» / «104 треков» — число, за ним слово про треки.
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length < 2) return true;
    const words = {'songs', 'song', 'треков', 'трека', 'трек'};
    if (!words.contains(parts[1])) return true;
    found = int.tryParse(parts[0].replaceAll(RegExp(r'[,\s\u00a0]'), ''));
    return found == null;
  });
  return found;
}

// ============================ Поиск ============================

/// Фильтр выдачи «только песни» — тот же `params`, что шлёт веб-клиент при
/// выборе вкладки «Songs». Без него YTM подмешивает в треки любые ролики
/// (каверы, хореографию, реакции) и они всплывают выше оригинала.
const String kParamsSongs = 'EgWKAQIIAWoKEAkQBRAKEAMQBA==';

/// Фильтр «только артисты». В общей выдаче искомый артист лежит в карточке
/// топ-результата, а строками идут «похожие» — из-за этого по «the weeknd» в
/// артистах оказывались Gesaffelstein и Metro Boomin, а самого The Weeknd не
/// было. Вкладка отдаёт нужного первым.
const String kParamsArtists = 'EgWKAQIgAWoKEAkQChAFEAMQBA==';

/// Фильтры «только альбомы» / «только плейлисты».
const String kParamsAlbums = 'EgWKAQIYAWoKEAkQChAFEAMQBA==';
const String kParamsPlaylists = 'EgWKAQIoAWoKEAkQChAFEAMQBA==';

/// Состояние листания поиска. Держим только последний запрос — пользователь
/// листает одну выдачу за раз, а привязка к строке запроса не даёт отдать
/// чужую страницу, если поиск успели сменить.
class _SearchPaging {
  final String query;

  /// Токен следующей страницы; null — страницы кончились.
  String? token;

  /// Уже отданные videoId: YTM повторяет треки между страницами, и без этого
  /// в выдаче появляются дубли (проверено — «Ashura-chan» на 1-й и 3-й).
  final Set<String> seen;

  _SearchPaging(this.query, this.token, this.seen);
}

_SearchPaging? _searchCont;

/// Сколько раз подряд тянуть следующую страницу, если предыдущая целиком
/// оказалась дублями: иначе кнопка «Загрузить ещё» молча ничего не добавляет.
const int kPagingMaxFetches = 3;

/// Один запрос к `search`. [params] — фильтр вкладки (null = общая выдача).
Future<Map<String, dynamic>> searchRaw(String query, [String? params]) async =>
    _postJson(
      '$kSearchUrl&key=$kWebKey',
      await _webBody({'query': query, 'params': ?params}),
      userAgent: kWebUa,
      extraHeaders: _musicHeaders,
      errCode: 'ytm.err.search',
    );

Future<Map<String, dynamic>> _searchContinuation(String token) async =>
    _postJson(
      '$kSearchUrl&key=$kWebKey&continuation=$token',
      await _webBody(const {}),
      userAgent: kWebUa,
      extraHeaders: _musicHeaders,
      errCode: 'ytm.err.searchMore',
    );

/// Разобрать строки ответа отфильтрованной вкладки: отобрать по [keep],
/// распарсить, снять дубли по [key], обрезать до [limit].
List<T> filteredRows<T>(
  Object? v,
  bool Function(Object?) keep,
  T? Function(Object?) parse,
  int limit,
  String Function(T) key,
) {
  final seen = <String>{};
  final out = <T>[];
  for (final it in collectMrlir(v)) {
    if (out.length >= limit) break;
    if (!keep(it)) continue;
    final parsed = parse(it);
    if (parsed == null) continue;
    if (seen.add(key(parsed))) out.add(parsed);
  }
  return out;
}

/// Дописать в конец раздела то, чего в нём ещё нет (порядок базового списка
/// сохраняется — он же и есть порядок релевантности). [cap] — предел раздела
/// выдачи; null означает «без предела» (полная дискография артиста).
List<T> mergeById<T>(
  List<T> base,
  List<T> extra,
  int? cap,
  String Function(T) id,
) {
  final seen = base.map(id).toSet();
  final out = [...base];
  for (final x in extra) {
    if (seen.add(id(x))) out.add(x);
  }
  return (cap != null && out.length > cap) ? out.sublist(0, cap) : out;
}

Future<Map<String, dynamic>?> _searchOrNull(String query, String params) =>
    searchRaw(
      query,
      params,
    ).then<Map<String, dynamic>?>((v) => v, onError: (_) => null);

Future<YtmSearchRaw> search(String query) async {
  // Пять запросов параллельно: общая выдача + по вкладке на каждый раздел.
  // Вкладки дают чистые и правильно отсортированные списки, общая выдача
  // остаётся источником по умолчанию и даёт карточку топ-результата. Если
  // фильтр перестанет работать (YouTube меняет `params`), берём раздел из
  // общей выдачи — поломка фильтра деградирует, а не роняет поиск.
  final responses = await Future.wait([
    searchRaw(query),
    _searchOrNull(query, kParamsSongs),
    _searchOrNull(query, kParamsArtists),
    _searchOrNull(query, kParamsAlbums),
    _searchOrNull(query, kParamsPlaylists),
  ]);
  final v = responses[0]!;

  return parseSearch(
    v,
    query: query,
    songs: responses[1],
    artistsOnly: responses[2],
    albumsOnly: responses[3],
    playlistsOnly: responses[4],
  );
}

/// Сборка выдачи из ответов (вынесена из [search] отдельно — она чистая и
/// проверяется тестами без сети).
YtmSearchRaw parseSearch(
  Object? v, {
  required String query,
  Object? songs,
  Object? artistsOnly,
  Object? albumsOnly,
  Object? playlistsOnly,
}) {
  var tracks = <YtmRawTrack>[];
  var artists = <YtmRawArtist>[];
  var albums = <YtmRawAlbum>[];
  var playlists = <YtmRawPlaylist>[];
  final seen = <String>{};

  // Классифицируем строки общей выдачи по основному navigationEndpoint.
  for (final it in collectMrlir(v)) {
    switch (pageType(it)) {
      case 'MUSIC_PAGE_TYPE_ARTIST':
        if (artists.length < 8) {
          final a = parseArtist(it);
          if (a != null && seen.add(a.id)) artists.add(a);
        }
      case 'MUSIC_PAGE_TYPE_ALBUM':
        if (albums.length < 12) {
          final a = parseAlbum(it);
          if (a != null && seen.add(a.id)) albums.add(a);
        }
      case 'MUSIC_PAGE_TYPE_PLAYLIST' || 'MUSIC_PAGE_TYPE_AUDIOBOOK':
        if (playlists.length < 8) {
          final p = parsePlaylist(it);
          if (p != null && seen.add(p.id)) playlists.add(p);
        }
      // Нет browse-страницы → это трек/видео (играбельный videoId).
      default:
        if (tracks.length < 20) {
          final t = parseTrack(it);
          if (t != null && seen.add(t.id)) tracks.add(t);
        }
    }
  }

  if (songs != null) {
    final found = filteredRows(
      songs,
      (it) => pageType(it) == null,
      parseTrack,
      20,
      (t) => t.id,
    );
    if (found.isNotEmpty) {
      // Листаем именно вкладку «Songs» — так догрузка даёт чистые песни.
      _searchCont = _SearchPaging(
        query,
        findContinuation(songs),
        found.map((t) => t.id).toSet(),
      );
      tracks = found;
    }
  }
  if (artistsOnly != null) {
    final found = filteredRows(
      artistsOnly,
      (it) => pageType(it) == 'MUSIC_PAGE_TYPE_ARTIST',
      parseArtist,
      8,
      (a) => a.id,
    );
    if (found.isNotEmpty) artists = found;
  }
  // Альбомы и плейлисты вкладки не ЗАМЕЩАЮТ общую выдачу, а дополняют её.
  // Здесь, в отличие от артистов, общая выдача не врёт, зато содержит то, чего
  // во вкладке нет: официальные плейлисты YouTube Music («Presenting Ado») —
  // единственные, у кого известно число треков.
  if (albumsOnly != null) {
    albums = mergeById(
      albums,
      filteredRows(
        albumsOnly,
        (it) => pageType(it) == 'MUSIC_PAGE_TYPE_ALBUM',
        parseAlbum,
        12,
        (a) => a.id,
      ),
      12,
      (a) => a.id,
    );
  }
  if (playlistsOnly != null) {
    playlists = mergeById(
      playlists,
      filteredRows(
        playlistsOnly,
        (it) =>
            pageType(it) == 'MUSIC_PAGE_TYPE_PLAYLIST' ||
            pageType(it) == 'MUSIC_PAGE_TYPE_AUDIOBOOK',
        parsePlaylist,
        8,
        (p) => p.id,
      ),
      8,
      (p) => p.id,
    );
  }

  // Топ-результат — самая релевантная сущность по запросу; поднимаем её на
  // первое место своего раздела (вкладки сортируют внутри типа, но не знают,
  // что именно искал пользователь).
  final top = parseTopCard(v);
  switch (top) {
    case final YtmRawArtist a:
      artists = [a, ...artists.where((x) => x.id != a.id)];
    case final YtmRawAlbum a:
      albums = [a, ...albums.where((x) => x.id != a.id)];
    case final YtmRawPlaylist p:
      playlists = [p, ...playlists.where((x) => x.id != p.id)];
  }

  final cont = _searchCont;
  return YtmSearchRaw(
    tracks: tracks,
    artists: artists,
    albums: albums,
    playlists: playlists,
    tracksHasMore: cont != null && cont.query == query && cont.token != null,
  );
}

/// Разобрать карточку топ-результата общей выдачи (`musicCardShelfRenderer`).
/// Она лежит НЕ в строках, поэтому обычный сбор её не видит, и самый
/// релевантный результат раньше терялся целиком.
///
/// Тип определяем по `navigationEndpoint` первого run'а заголовка (у карточки
/// трека там `watchEndpoint` без pageType — такие пропускаем: чистый список
/// песен даёт вкладка «Songs», а длительности в карточке нет).
Object? parseTopCard(Object? v) {
  final card = findRenderer(v, 'musicCardShelfRenderer');
  if (card == null) return null;
  final run = at(card, ['title', 'runs', 0]);
  final title = str(at(run, ['text']));
  if (title.isEmpty) return null;
  final id = itemBrowseId(run);
  if (id == null) return null;
  final cover = biggestThumb(at(card, ['thumbnail']));
  final parts = meaningfulRuns(at(card, ['subtitle']));

  switch (pageType(run)) {
    case 'MUSIC_PAGE_TYPE_ARTIST':
      return YtmRawArtist(id: id, name: title, cover: cover);
    case 'MUSIC_PAGE_TYPE_ALBUM':
      final year = parts.lastWhere(_isYear, orElse: () => '');
      return YtmRawAlbum(
        id: id,
        title: title,
        artist: parts.where((s) => s != year).join(', '),
        cover: cover,
        year: year,
        kind: releaseKindOf(firstRun(at(card, ['subtitle']))),
      );
    case 'MUSIC_PAGE_TYPE_PLAYLIST' || 'MUSIC_PAGE_TYPE_AUDIOBOOK':
      return YtmRawPlaylist(
        id: id,
        title: title,
        cover: cover,
        ownerName: parts.isEmpty ? '' : parts.first,
      );
    default:
      return null;
  }
}

/// Следующая страница треков поиска (по 20). Пусто + `false`, если продолжения
/// нет либо запрос сменился с момента прошлой выдачи.
Future<YtmSearchMore> searchMore(String query) async {
  final fresh = <YtmRawTrack>[];

  for (var i = 0; i < kPagingMaxFetches; i++) {
    final state = _searchCont;
    if (state == null || state.query != query) {
      return const YtmSearchMore(); // запрос сменился
    }
    final token = state.token;
    if (token == null) break; // страницы кончились

    final v = await _searchContinuation(token);
    final page = filteredRows(
      v,
      (it) => pageType(it) == null,
      parseTrack,
      20,
      (t) => t.id,
    );

    final now = _searchCont;
    if (now == null || now.query != query) {
      return const YtmSearchMore(); // запрос сменили, пока ходили в сеть
    }
    now.token = findContinuation(v);
    for (final t in page) {
      if (now.seen.add(t.id)) fresh.add(t);
    }
    if (fresh.isNotEmpty) break;
  }

  final s = _searchCont;
  return YtmSearchMore(
    tracks: fresh,
    hasMore: s != null && s.query == query && s.token != null,
  );
}

// ============================ Радио ============================

const String kNextUrl =
    'https://music.youtube.com/youtubei/v1/next?prettyPrint=false';

/// Радио трека — watch-плейлист с включённым радио, как
/// `get_watch_playlist(radio=True)` у ytmusicapi (и `YtMusic::station` ПК).
/// Открывается самим треком — его отбрасываем; дальше ведёт токен [cursor].
Future<({List<YtmRawTrack> tracks, String cursor})> radio(
  String id, {
  String cursor = '',
}) async {
  final tok = Uri.encodeQueryComponent(cursor);
  final v = await _postJson(
    '$kNextUrl&key=$kWebKey${cursor.isEmpty ? '' : '&ctoken=$tok&continuation=$tok'}',
    await _webBody({
      'videoId': id,
      'playlistId': 'RDAMVM$id',
      'params': 'wAEB',
      'isAudioOnly': true,
      'enablePersistentPlaylistPanel': true,
      'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
    }),
    userAgent: kWebUa,
    extraHeaders: _musicHeaders,
    errCode: 'ytm.err.radio',
  );
  final items = <Object?>[];
  collectRenderers(v, 'playlistPanelVideoRenderer', items);
  final seen = {id};
  final tracks = <YtmRawTrack>[];
  for (final it in items) {
    final vid = str(at(it, ['videoId']));
    final title = firstRun(at(it, ['title']));
    if (vid.isEmpty || title.isEmpty || !seen.add(vid)) continue;
    // «Артисты • Альбом • Год»: артисты — первая часть (игра или канал
    // дальше тоже бывают ссылкой на артиста).
    final first = <Object?>[];
    final runs = at(it, ['longBylineText', 'runs']);
    if (runs is List) {
      for (final r in runs) {
        if (str(at(r, ['text'])).trim() == '•') break;
        first.add(r);
      }
    }
    final byline = {'runs': first};
    final linked = col1Artists(byline);
    tracks.add(
      YtmRawTrack(
        id: vid,
        title: title,
        artist: linked.isEmpty
            ? meaningfulRuns(byline).join(', ')
            : col1Artist(byline),
        artistId: _firstPage(linked),
        artists: linked,
        cover: biggestThumb(at(it, ['thumbnail'])),
        duration: Duration(
          seconds: parseClock(firstRun(at(it, ['lengthText']))) ?? 0,
        ),
      ),
    );
  }
  final more = findRenderer(v, 'nextRadioContinuationData');
  return (tracks: tracks, cursor: str(at(more, ['continuation'])));
}

// ============================ Страницы (browse) ============================

/// POST browse с веб-контекстом → сырой JSON ответа. [params] — им YTM кодирует
/// «какую вкладку раздела показать» (например «Singles & EPs» у артиста).
Future<Map<String, dynamic>> browse(String browseId, [String? params]) async =>
    _postJson(
      '$kBrowseUrl&key=$kWebKey',
      await _webBody({'browseId': browseId, 'params': ?params}),
      userAgent: kWebUa,
      extraHeaders: _musicHeaders,
      errCode: 'ytm.err.browse',
    );

/// Альбом: шапка + треки (videoId в строках, длительность в fixedColumns).
Future<YtmEntity> album(String browseId) async =>
    parseAlbumPage(await browse(browseId));

YtmEntity parseAlbumPage(Object? v) {
  final h = header(v);
  final cover = h == null ? '' : headerCover(h);
  final subtitle = h == null ? '' : headerSubtitle(h);
  final tracks = <YtmRawTrack>[];
  for (final it in collectMrlir(v)) {
    var t = parseTrack(it);
    if (t == null) continue;
    // У треков альбома часто нет своей обложки — подставляем обложку альбома.
    // Артист в строках альбома не повторяется (он один на всю страницу и указан
    // в шапке) — иначе в списке у каждого трека «Неизвестен».
    t = t.copyWith(
      cover: t.cover.isEmpty ? cover : null,
      artist: t.artist.isEmpty ? subtitle : null,
    );
    tracks.add(t);
  }
  return YtmEntity(
    title: h == null ? '' : headerTitle(h),
    subtitle: subtitle,
    cover: cover,
    tracks: tracks,
    year: h == null ? '' : headerYear(h),
    ownerAvatar: h == null ? '' : headerStraplineAvatar(h),
  );
}

/// Плейлист: шапка + треки. browseId плейлиста требует префикс `VL`.
Future<YtmEntity> playlist(String browseId) async {
  final id = browseId.startsWith('VL') ? browseId : 'VL$browseId';
  return parsePlaylistPage(await browse(id));
}

YtmEntity parsePlaylistPage(Object? v) {
  final h = header(v);
  final tracks = <YtmRawTrack>[];
  for (final it in collectMrlir(v)) {
    final t = parseTrack(it);
    if (t != null) tracks.add(t);
  }
  return YtmEntity(
    title: h == null ? '' : headerTitle(h),
    subtitle: h == null ? '' : headerSubtitle(h),
    cover: h == null ? '' : headerCover(h),
    tracks: tracks,
    year: h == null ? '' : headerYear(h),
    ownerAvatar: h == null ? '' : headerStraplineAvatar(h),
  );
}

/// Артист: «Популярные» (top songs shelf) + релизы и похожие из каруселей.
///
/// Шапка отдаёт только 5–10 песен и 10 релизов. За полными списками идём по
/// кнопкам «ещё»: у шелфа песен это плейлист `VL…` (≈100 треков), у карусели
/// синглов — `MPAD…` с `params`. Оба запроса независимы → параллельно.
Future<YtmEntity> artist(String browseId) async {
  final v = await browse(browseId);
  final base = parseArtistPage(v);

  final more = await Future.wait([
    _moreTracks(
      shelfMore(v, const ['Top songs', 'Songs', 'Популярные треки', 'Песни']),
    ),
    _moreAlbums(shelfMore(v, const ['Singles & EPs', 'Синглы и EP', 'Синглы'])),
  ]);
  final fullSongs = more[0] as List<YtmRawTrack>;
  final singles = more[1] as List<YtmRawAlbum>;

  return YtmEntity(
    title: base.title,
    cover: base.cover,
    tracks: fullSongs,
    popularTracks: base.popularTracks,
    albums: mergeById(base.albums, singles, null, (a) => a.id),
    similarArtists: base.similarArtists,
    description: base.description,
  );
}

/// Шапка артиста без походов за «ещё» — чистая часть [artist].
YtmEntity parseArtistPage(Object? v) {
  final h = header(v);
  // popular: строки (mrlir) на странице артиста — это шелф «Песни».
  final popular = <YtmRawTrack>[];
  for (final it in collectMrlir(v)) {
    if (popular.length >= 10) break;
    final t = parseTrack(it);
    if (t != null) popular.add(t);
  }
  // Карточки каруселей — это и релизы, и похожие исполнители сразу. Разбираем
  // по ПРЕФИКСУ browseId, а не по заголовку секции: заголовки локализованы и
  // YTM тасует состав каруселей от артиста к артисту.
  final albums = <YtmRawAlbum>[];
  final similar = <YtmRawArtist>[];
  final seen = <String>{};
  for (final r in collectTwoRow(v)) {
    final a = parseTwoRowAlbum(r);
    if (a != null) {
      if (seen.add(a.id)) albums.add(a);
      continue;
    }
    final s = parseTwoRowArtist(r);
    if (s != null && seen.add(s.id)) similar.add(s);
  }
  return YtmEntity(
    title: h == null ? '' : headerTitle(h),
    cover: h == null ? '' : headerCover(h),
    popularTracks: popular,
    albums: albums,
    similarArtists: similar,
    description: h == null ? '' : headerDescription(h),
  );
}

/// Ссылка кнопки «ещё» у секции: (browseId, params).
typedef MoreLink = ({String id, String? params});

/// Найти кнопку «ещё» у секции с одним из указанных заголовков.
///
/// Секции ищем рекурсивно, а не по фиксированному пути: YTM тасует их порядок и
/// состав от артиста к артисту (у кого-то нет синглов, у кого-то нет видео).
MoreLink? shelfMore(Object? v, List<String> titles) {
  MoreLink? out;
  void walk(Object? node) {
    if (out != null) return;
    if (node is Map) {
      for (final key in const [
        'musicShelfRenderer',
        'musicCarouselShelfRenderer',
      ]) {
        final shelf = node[key];
        if (shelf == null) continue;
        final head = (shelf is Map ? shelf['header'] : null) ?? shelf;
        if (shelfTitleMatches(head, titles)) {
          final link = browseLink(head);
          if (link != null) {
            out = link;
            return;
          }
        }
      }
      for (final x in node.values) {
        walk(x);
        if (out != null) return;
      }
    } else if (node is List) {
      for (final x in node) {
        walk(x);
        if (out != null) return;
      }
    }
  }

  walk(v);
  return out;
}

/// Есть ли среди текстов заголовка секции один из ожидаемых (без учёта регистра).
bool shelfTitleMatches(Object? head, List<String> titles) {
  var found = false;
  collectText(head, (s) {
    if (titles.any((t) => t.toLowerCase() == s.toLowerCase())) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// Первый `browseEndpoint` внутри узла → (browseId, params).
MoreLink? browseLink(Object? v) {
  final ep = findRenderer(v, 'browseEndpoint');
  final id = str(at(ep, ['browseId']));
  if (id.isEmpty) return null;
  final params = at(ep, ['params']);
  return (id: id, params: params is String ? params : null);
}

/// Полный список треков по ссылке «ещё». Ошибку глушим: страница артиста должна
/// открыться даже без этого списка.
Future<List<YtmRawTrack>> _moreTracks(MoreLink? link) async {
  if (link == null) return const [];
  final Object? v;
  try {
    v = await browse(link.id, link.params);
  } catch (_) {
    return const [];
  }
  final seen = <String>{};
  final out = <YtmRawTrack>[];
  for (final it in collectMrlir(v)) {
    final t = parseTrack(it);
    if (t != null && seen.add(t.id)) out.add(t);
  }
  return out;
}

/// Полный список релизов по ссылке «ещё» (синглы/EP). Ошибку глушим, см. выше.
Future<List<YtmRawAlbum>> _moreAlbums(MoreLink? link) async {
  if (link == null) return const [];
  final Object? v;
  try {
    v = await browse(link.id, link.params);
  } catch (_) {
    return const [];
  }
  final out = <YtmRawAlbum>[];
  for (final r in collectTwoRow(v)) {
    final a = parseTwoRowAlbum(r);
    if (a != null) out.add(a);
  }
  return out;
}

/// musicTwoRowItemRenderer → альбом (только карточки с browseId `MPRE…`).
YtmRawAlbum? parseTwoRowAlbum(Object? it) {
  final id = _twoRowBrowseId(it, 'MPRE');
  if (id == null) return null; // не альбом (плейлист/видео карусель)
  final title = str(at(it, ['title', 'runs', 0, 'text']));
  if (title.isEmpty) return null;
  // Подпись карточки — «Single • Артист» или «Album • 2023»: метку типа
  // отбрасываем (иначе она уезжает в имя исполнителя), год забираем в своё
  // поле, остальное и есть артист.
  final parts = meaningfulRuns(at(it, ['subtitle']));
  final year = parts.lastWhere(_isYear, orElse: () => '');
  return YtmRawAlbum(
    id: id,
    title: title,
    artist: parts.where((s) => s != year).join(', '),
    cover: biggestThumb(it),
    year: year,
    kind: releaseKindOf(firstRun(at(it, ['subtitle']))),
  );
}

/// musicTwoRowItemRenderer → артист (карточки «Fans might also like»: `UC…`).
YtmRawArtist? parseTwoRowArtist(Object? it) {
  final id = _twoRowBrowseId(it, 'UC');
  if (id == null) return null;
  final name = str(at(it, ['title', 'runs', 0, 'text']));
  if (name.isEmpty) return null;
  return YtmRawArtist(id: id, name: name, cover: biggestThumb(it));
}

String? _twoRowBrowseId(Object? it, String prefix) {
  final id = at(it, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
  return id is String && id.startsWith(prefix) ? id : null;
}

// ---- Шапка страницы ----

/// Первый известный header-рендерер страницы.
Object? header(Object? v) {
  for (final key in const [
    'musicDetailHeaderRenderer',
    'musicResponsiveHeaderRenderer',
    'musicImmersiveHeaderRenderer',
    'musicVisualHeaderRenderer',
  ]) {
    final h = findRenderer(v, key);
    if (h != null) return h;
  }
  return null;
}

String headerTitle(Object? h) => str(at(h, ['title', 'runs', 0, 'text']));

/// Обложка страницы. Сначала СВОЙ узел `thumbnail`, и только потом что найдётся
/// в поддереве: у нового `musicResponsiveHeaderRenderer` рядом лежит
/// `straplineThumbnail` (аватар артиста), и общий обход может подсунуть его
/// вместо обложки альбома — на десктопе здесь просто `biggest_thumb(h)`.
String headerCover(Object? h) {
  final own = at(h, ['thumbnail']);
  final url = own == null ? '' : biggestThumb(own);
  return url.isNotEmpty ? url : biggestThumb(h);
}

/// Год из шапки: 4-значный run в `subtitle` («Альбом • Артист • 2023»).
String headerYear(Object? h) {
  final runs = at(h, ['subtitle', 'runs']);
  if (runs is! List) return '';
  for (final r in runs) {
    final s = str(at(r, ['text']));
    if (_isYear(s)) return s;
  }
  return '';
}

/// Подзаголовок шапки (артист/владелец).
///
/// `straplineTextOne` — ровно имя артиста/владельца (рядом с ним лежит его
/// аватар, см. [headerStraplineAvatar]), поэтому он в приоритете: `subtitle` у
/// нового рендерера — метаданные вида «Альбом • 2023», а не имя. Фолбэк на
/// `subtitle` нужен старому `musicDetailHeaderRenderer`, где strapline нет.
String headerSubtitle(Object? h) {
  String join(Object? node) {
    final runs = at(node, ['runs']);
    if (runs is! List) return '';
    return runs.map((r) => str(at(r, ['text']))).join();
  }

  final strapline = join(at(h, ['straplineTextOne']));
  return strapline.isNotEmpty ? strapline : join(at(h, ['subtitle']));
}

/// Аватар артиста/владельца из шапки: `straplineThumbnail` — единственное
/// место, где он есть без отдельного browse-запроса на страницу артиста.
String headerStraplineAvatar(Object? h) {
  final t = at(h, ['straplineThumbnail']);
  return t == null ? '' : biggestThumb(t);
}

/// Биография артиста из шапки (`musicImmersiveHeaderRenderer.description`).
String headerDescription(Object? h) {
  final d = at(h, ['description']);
  final simple = at(d, ['simpleText']);
  if (simple is String) return simple;
  final runs = at(d, ['runs']);
  if (runs is! List) return '';
  return runs.map((r) => str(at(r, ['text']))).join();
}

// ============================ Разбор ссылок ============================

/// Ссылка YouTube/YouTube Music → сущность.
///
/// Почти всё выводится из самого URL, но два случая требуют сети:
///   * `list=OLAK5uy_…` — «плейлист-версия» альбома, а страницу альбома
///     открывает только `MPRE…`; соответствие лежит в HTML страницы плейлиста;
///   * `/@handle`, `/c/<name>`, `/user/<name>` — человекочитаемое имя канала,
///     browseId (`UC…`) тоже есть только в HTML.
///
/// Оба сетевых шага мягкие: не получилось — деградируем (альбом откроется как
/// плейлист, хэндл не резолвится), а не роняем весь импорт.
Future<YtmResolved> resolve(String url) async {
  final u = url.trim();
  if (!u.contains('youtube.com') && !u.contains('youtu.be')) {
    throw const YtmException('ytm.err.notYoutubeUrl');
  }

  // Трек: watch?v=…, youtu.be/<id>, /shorts/<id>. Приоритет выше плейлиста — у
  // ссылки «трек из плейлиста» есть оба параметра, а открыть надо трек.
  final v = queryParam(u, 'v');
  if (v != null) return YtmResolved('track', v);
  final short = pathAfter(u, 'youtu.be/') ?? pathAfter(u, '/shorts/');
  if (short != null) return YtmResolved('track', short);

  // Плейлист/альбом: ?list=…
  final list = queryParam(u, 'list');
  if (list != null) {
    if (list.startsWith('OLAK5uy_')) {
      final mpre = await _albumBrowseId(list);
      if (mpre != null) return YtmResolved('album', mpre);
    }
    return YtmResolved('playlist', list);
  }

  // Прямые browse-ссылки: /browse/<MPRE…|VL…|UC…>.
  final browseId = pathAfter(u, '/browse/');
  if (browseId != null) {
    if (browseId.startsWith('MPRE')) return YtmResolved('album', browseId);
    if (browseId.startsWith('VL')) return YtmResolved('playlist', browseId);
    if (browseId.startsWith('UC')) return YtmResolved('artist', browseId);
  }

  // Канал: /channel/UC… — browseId прямо в ссылке; остальные виды имени
  // (/@handle, /c/…, /user/…) достаём из HTML страницы.
  final channel = pathAfter(u, '/channel/');
  if (channel != null) return YtmResolved('artist', channel);
  if (u.contains('/@') || u.contains('/c/') || u.contains('/user/')) {
    final id = await _channelBrowseId(u);
    if (id != null) return YtmResolved('artist', id);
  }

  throw const YtmException('ytm.err.badUrl');
}

/// Значение query-параметра (`?v=…&list=…`) без разбора всего URL.
String? queryParam(String url, String key) {
  final i = url.indexOf('?');
  if (i < 0) return null;
  for (final kv in url.substring(i + 1).split('&')) {
    final eq = kv.indexOf('=');
    if (eq <= 0) continue;
    if (kv.substring(0, eq) != key) continue;
    final value = kv.substring(eq + 1).split('#').first;
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// Кусок пути сразу после маркера, до следующего `/`, `?`, `#` или `&`.
String? pathAfter(String url, String marker) {
  final i = url.indexOf(marker);
  if (i < 0) return null;
  final rest = url.substring(i + marker.length);
  final id = rest.split(RegExp(r'[/?#&]')).first;
  return id.isEmpty ? null : id;
}

/// browseId альбома (`MPRE…`) по id его плейлиста (`OLAK5uy_…`). InnerTube
/// такого перехода не даёт — соответствие есть только в HTML страницы.
Future<String?> _albumBrowseId(String listId) async {
  final html = await _getText(
    'https://music.youtube.com/playlist?list=$listId',
  );
  return html == null ? null : findId(html, 'MPRE');
}

/// browseId канала (`UC…`) со страницы `/@handle` и подобных.
Future<String?> _channelBrowseId(String url) async {
  final html = await _getText(url);
  if (html == null) return null;
  // Отдельный ключ, а не поиск «UC…» по всему тексту: две эти буквы слишком
  // часто встречаются в разметке и дают ложные срабатывания.
  for (final key in const ['"channelId":"', '"browseId":"', '"externalId":"']) {
    final i = html.indexOf(key);
    if (i < 0) continue;
    final rest = html.substring(i + key.length);
    if (rest.startsWith('UC')) return findId(rest, 'UC');
  }
  return null;
}

/// Первый идентификатор с указанным префиксом в тексте.
String? findId(String text, String prefix) {
  final i = text.indexOf(prefix);
  if (i < 0) return null;
  final id = text
      .substring(i)
      .split('')
      .takeWhile((c) => RegExp(r'[A-Za-z0-9_-]').hasMatch(c))
      .join();
  return id.length > prefix.length ? id : null;
}

Future<String?> _getText(String url, {String userAgent = kWebUa}) async {
  try {
    final r = await _http
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent': userAgent,
            'Accept-Language': 'en-US,en;q=0.9',
          },
        )
        .timeout(_timeout);
    if (r.statusCode < 200 || r.statusCode >= 300) return null;
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

// ============================ Стрим ============================

Map<String, dynamic> _visionClient() => {
  'clientName': 'VISIONOS',
  'clientVersion': kVisionClientVersion,
  'deviceMake': 'Apple',
  'deviceModel': 'RealityDevice17,1',
  'osName': 'visionOS',
  'osVersion': '26.5.23O471',
};

/// Один запрос к `player` конкретным клиентом.
Future<Map<String, dynamic>> _playerWith(
  Map<String, dynamic> client,
  String ua,
  String videoId,
) async => _postJson(
  kPlayerUrl,
  {
    'context': {
      'client': {
        ...client,
        'hl': 'en',
        'gl': 'US',
        'visitorData': await visitorData(),
      },
    },
    'videoId': videoId,
    'contentCheckOk': true,
    'racyCheckOk': true,
  },
  userAgent: ua,
  extraHeaders: const {'X-Goog-Api-Format-Version': '2'},
  errCode: 'ytm.err.player',
);

/// Аудио-форматы с готовым url (без signatureCipher).
List<Object?> audioFormats(Object? v) {
  final arr = at(v, ['streamingData', 'adaptiveFormats']);
  if (arr is! List) return const [];
  return arr
      .where(
        (f) =>
            str(at(f, ['mimeType'])).startsWith('audio/') &&
            str(at(f, ['url'])).isNotEmpty,
      )
      .toList();
}

/// `true`, если ответ пригоден: статус OK и есть аудио с прямым url.
bool playable(Object? v) =>
    at(v, ['playabilityStatus', 'status']) == 'OK' &&
    audioFormats(v).isNotEmpty;

/// Запрос к player-эндпоинту (даёт прямые url + videoDetails).
///
/// Порядок: VISIONOS → (при отказе) свежий `visitorData` и повтор. Протухший
/// `visitorData` выглядит как `LOGIN_REQUIRED`, поэтому одна ретрай-попытка со
/// сбросом сессии закрывает самый частый сбой.
///
/// Второго клиента в цепочке намеренно нет (почему — док библиотеки): ссылка
/// от ANDROID_VR проходит проверку [playable], но затем отдаёт 403, то есть
/// отказ выглядел бы как успех.
Future<Map<String, dynamic>> player(String videoId) async {
  final first = await _playerWith(_visionClient(), kVisionUa, videoId);
  if (playable(first)) return first;

  resetVisitorData();
  final retry = await _playerWith(_visionClient(), kVisionUa, videoId);
  if (playable(retry)) return retry;

  // Ничего не сыграло — возвращаем первый ответ ради его playabilityStatus:
  // из него вызывающий соберёт человекочитаемую причину.
  return first;
}

/// Метаданные одного трека по videoId (для ре-резолва из «недавних»).
Future<YtmRawTrack> track(String videoId) async {
  final v = await player(videoId);
  final d = at(v, ['videoDetails']);
  final title = str(at(d, ['title']));
  if (title.isEmpty) throw const YtmException('ytm.err.trackNotFound');
  return YtmRawTrack(
    id: videoId,
    title: title,
    artist: str(at(d, ['author'])),
    artistId: '',
    cover: biggestThumb(at(d, ['thumbnail'])),
    duration: Duration(
      seconds: int.tryParse(str(at(d, ['lengthSeconds']))) ?? 0,
    ),
  );
}

/// Аудио-URL для videoId.
///
/// Предпочтение: m4a/aac (itag 140 — самый совместимый контейнер), затем всё
/// остальное по битрейту.
///
/// [hls] просит вместо прямой ссылки плейлист — он нужен AVPlayer'у на iOS,
/// см. [_hlsAudioUrl]. Если плейлиста в ответе нет, молча отдаём прямую: это
/// хуже, но играет.
Future<String> streamUrl(String videoId, {bool hls = false}) async {
  final v = await player(videoId);

  final status = str(at(v, ['playabilityStatus', 'status']));
  if (status != 'OK') {
    final reason = str(at(v, ['playabilityStatus', 'reason']));
    // Причина приходит текстом от самой площадки — отдаём как есть.
    throw YtmException(reason.isEmpty ? 'ytm.err.unplayable' : reason);
  }

  if (hls) {
    final playlist = await _hlsAudioUrl(v);
    if (playlist != null) return playlist;
  }

  Object? best;
  var bestRank = -1;
  for (final f in audioFormats(v)) {
    final itag = at(f, ['itag']);
    final bitrate = at(f, ['bitrate']);
    final rank = itag == 140
        ? 10000000
        : (bitrate is num ? bitrate.toInt() : 0);
    if (rank > bestRank) {
      bestRank = rank;
      best = f;
    }
  }
  final url = str(at(best, ['url']));
  if (url.isEmpty) throw const YtmException('ytm.err.noAudio');
  return url;
}

/// Аудио-дорожка из HLS-манифеста — ссылка для iOS.
///
/// Зачем отдельный путь. Прямая ссылка itag 140 ведёт на ФРАГМЕНТИРОВАННЫЙ mp4
/// (`moov` с `mvex`, дальше `sidx` и цепочка `moof`/`mdat`) — контейнер DASH.
/// ExoPlayer и Chromium играют его как обычный файл, а AVFoundation признаёт
/// фрагментированный mp4 только внутри HLS: по прямой ссылке AVPlayer читает
/// длительность вдвое больше настоящей. Звук при этом верный, но трек
/// «доигрывает» в тишину до выдуманного конца и не уходит на следующий.
///
/// В манифесте есть готовые дорожки только со звуком: группа `234` — тот же
/// AAC 128k, что и itag 140, `233` — 48k про запас. Плейлист приходит как
/// `#EXT-X-PLAYLIST-TYPE:VOD` с `#EXT-X-ENDLIST`, то есть с честной
/// длительностью, а сегменты — ADTS AAC, родной для AVPlayer формат.
///
/// `null` значит «не вышло» — вызывающий возьмёт прямую ссылку.
Future<String?> _hlsAudioUrl(Object? v) async {
  final master = str(at(v, ['streamingData', 'hlsManifestUrl']));
  if (master.isEmpty) return null;
  final text = await _getText(master, userAgent: kVisionUa);
  if (text == null) return null;
  return _mediaPlaylist(text, '234') ?? _mediaPlaylist(text, '233');
}

/// URI дорожки `#EXT-X-MEDIA` с нужным `GROUP-ID` из мастер-манифеста.
String? _mediaPlaylist(String manifest, String group) {
  for (final line in const LineSplitter().convert(manifest)) {
    if (!line.startsWith('#EXT-X-MEDIA:')) continue;
    if (!line.contains('GROUP-ID="$group"')) continue;
    final uri = RegExp(r'URI="([^"]+)"').firstMatch(line)?.group(1);
    if (uri != null && uri.isNotEmpty) return uri;
  }
  return null;
}
