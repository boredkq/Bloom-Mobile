/// YouTube Music, the unofficial InnerTube API (`music.youtube.com/youtubei`).
/// HTTP comes from the app itself, and the player fetches the direct
/// `googlevideo` link. No auth (public search and stream).
///
/// Search and pages use the `WEB_REMIX` client, parsing
/// `musicResponsiveListItemRenderer`. The stream uses the `VISIONOS` client on
/// the `player` endpoint: it gives `streamingData.adaptiveFormats[]` with
/// DIRECT urls (no signatureCipher or n-throttling) and, unlike web, ios and
/// android, **needs no PoToken**.
///
/// Don't use `ANDROID_VR`: googlevideo answers its links with 403 past the
/// file's first 1 MiB. `player` still says `OK` with direct urls, the link
/// looks alive, ExoPlayer and AVPlayer ask for the whole file, and the track
/// sits at 0:00.
///
/// CRITICAL: all requests carry `visitorData` (see [visitorData]). Without it
/// `player` answers `LOGIN_REQUIRED`.
///
/// YouTube breaks client constants now and then; they're all at the top of the
/// file.
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

/// YouTube Music's web client, for search and browsing (the key is public and
/// widely known).
const String kWebKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
const String kWebClientName = 'WEB_REMIX';
const String kWebClientVersion = '1.20260707.12.00';
const String kWebUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

/// Plain youtube.com's client, only to get `visitorData`.
const String kYtClientVersion = '2.20260708.00.00';

/// VISIONOS (Apple Vision Pro), the main and only client for `player`. It needs
/// no PoToken, gives direct urls and honestly serves any Range request: the
/// whole file, a seek to the middle and to the tail.
const String kVisionClientVersion = '1.02';
const String kVisionUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

final http.Client _http = http.Client();

const int _maxAttempts = 3;
const Duration _retryDelay = Duration(milliseconds: 600);
const Duration _timeout = Duration(seconds: 20);

// ============================ visitorData ============================

/// `visitorData` cache per process. It identifies an anonymous session: without
/// it each request looks like a new cold client, which YouTube marks as a bot.
/// [resetVisitorData] clears it when `player` refuses.
String? _visitor;
Future<String>? _visitorInFlight;

/// Gets `visitorData`, from cache or the `visitor_id` endpoint. No error is
/// raised: an empty string means send without it; search and browsing work
/// anyway, and only `player` suffers.
///
/// Parallel requests wait for ONE network trip: search goes out as five
/// requests at once, and five different `visitorData`, five cold clients in a
/// row, is just what YouTube counts as a bot.
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

/// Forgets the current `visitorData`, so the next call takes a fresh one.
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

/// POST with a JSON body and one way of handling failures. A light retry on
/// transient ones (network, 5xx, 429): 3 tries, 600 ms backoff. A mobile
/// network would otherwise bring down all search.
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
      // a network error is transient
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

/// InnerTube request body with the web context, plus `visitorData`.
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

// ── JSON walking ────────────────────────────────────────────────────────

/// Value by path: string keys in objects, numeric ones in arrays.
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

/// Recursively collects all values of [key] (`musicResponsiveListItemRenderer`
/// and such). More reliable than an exact path: section structure changes.
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

/// Result rows.
List<Object?> collectMrlir(Object? v) {
  final out = <Object?>[];
  collectRenderers(v, 'musicResponsiveListItemRenderer', out);
  return out;
}

/// Carousel cards.
List<Object?> collectTwoRow(Object? v) {
  final out = <Object?>[];
  collectRenderers(v, 'musicTwoRowItemRenderer', out);
  return out;
}

/// First renderer by key, recursively.
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

/// Walks all `text` and `simpleText` string fields of a node. `visit` returns
/// `false` when it found what it wants, stopping there.
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

/// First continuation token in an answer. InnerTube puts it in
/// `nextContinuationData.continuation` or `continuationCommand.token`, so I
/// look for both with no fixed path.
String? findContinuation(Object? v) {
  if (v is Map) {
    for (final e in v.entries) {
      final val = e.value;
      // Short strings under this key occur in tracking.
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

// ── Parsing rows ────────────────────────────────────────────────────────

/// pageType of a row's main navigation (ARTIST, ALBUM, PLAYLIST), or null for a
/// track.
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

/// browseId of a row's main navigation.
String? itemBrowseId(Object? it) {
  final v = at(it, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
  return v is String && v.isNotEmpty ? v : null;
}

/// flexColumn[i] to its `text` node (with runs).
Object? flexText(Object? it, int i) => at(it, [
  'flexColumns',
  i,
  'musicResponsiveListItemFlexColumnRenderer',
  'text',
]);

/// Entity type labels YTM starts a row's or card's caption with ("Song • Artist
/// • Album", "Single • BahaVibe"). They aren't an artist's name or an owner,
/// and go from captions, or they leak into the UI. Requests go with `hl=en`, so
/// the list is English, with Russian in case YTM answers in the region's
/// language.
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

/// Meaningful caption pieces (`{runs:[…]}`), with no separators or type label.
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

/// A row's largest cover (`thumbnail.musicThumbnailRenderer…`).
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

/// YTM covers scale by URL parameters: `=w120-h120` to `=w544-h544`.
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

/// Largest cover from the first `thumbnails` array in the subtree, upscaled.
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

/// A track's videoId: playlistItemData or the play-button overlay.
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

/// m:ss or h:mm:ss to seconds; null if it isn't a time.
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

/// Artist's name from col1. In unfiltered search the first run is the TYPE
/// (Song, Video), so [firstRun] is no use. I take runs linking to an artist
/// (pageType ARTIST), or the first meaningful run if none.
String col1Artist(Object? col1) {
  // Artist links; there may be several, joined.
  final names = col1Artists(col1);
  if (names.isNotEmpty) return names.map((a) => a.name).join(', ');

  // Fallback: the first meaningful caption piece. Run zero can't be skipped
  // unconditionally: in playlist rows it's the artist (a chart playlist's
  // caption is one run with the channel), and all chart tracks would come out
  // with no artist.
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

/// Duration from col1's last m:ss run, in seconds.
int col1Duration(Object? col1) {
  final runs = at(col1, ['runs']);
  if (runs is! List) return 0;
  for (final r in runs.reversed) {
    final sec = parseClock(str(at(r, ['text'])));
    if (sec != null) return sec;
  }
  return 0;
}

/// Duration from fixedColumns (album rows have m:ss as a separate column).
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

  // Duration: in col1 for search rows, in fixedColumns for album rows.
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
  // Year, a 4-digit run in col1.
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
  // artist: the artist is the linked runs.
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

/// Track count from a row's caption. Official YTM playlists write it in the
/// subtitle ("Playlist • YouTube Music • 48 songs"), user ones don't, and
/// albums never do. So nullable: unknown and zero are different, and the UI
/// shouldn't show 0 where no count was given.
int? rowTrackCount(Object? it) {
  int? found;
  collectText(it, (s) {
    // "48 songs" or "104 треков": a number, then a word about tracks.
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length < 2) return true;
    const words = {'songs', 'song', 'треков', 'трека', 'трек'};
    if (!words.contains(parts[1])) return true;
    found = int.tryParse(parts[0].replaceAll(RegExp(r'[,\s\u00a0]'), ''));
    return found == null;
  });
  return found;
}

// ── Search ──────────────────────────────────────────────────────────────

/// Songs only result filter, the `params` the web client sends for the Songs
/// tab. Without it YTM mixes in any videos (covers, choreography, reactions),
/// which rise above the original.
const String kParamsSongs = 'EgWKAQIIAWoKEAkQBRAKEAMQBA==';

/// Artists only filter. In general results the wanted artist lies in the top
/// card, with similar ones as rows, so an artist's own name might not list them
/// at all. The tab gives the wanted one first.
const String kParamsArtists = 'EgWKAQIgAWoKEAkQChAFEAMQBA==';

/// Albums only and playlists only filters.
const String kParamsAlbums = 'EgWKAQIYAWoKEAkQChAFEAMQBA==';
const String kParamsPlaylists = 'EgWKAQIoAWoKEAkQChAFEAMQBA==';

/// Search paging state. Only the last query is held: the user pages one result
/// set at a time, and tying it to the query string won't give a foreign page if
/// search changed.
class _SearchPaging {
  final String query;

  /// Next page token; null when pages ran out.
  String? token;

  /// videoIds already given: YTM repeats tracks between pages, and without this
  /// duplicates appear.
  final Set<String> seen;

  _SearchPaging(this.query, this.token, this.seen);
}

_SearchPaging? _searchCont;

/// How many times in a row to fetch the next page if the last was all
/// duplicates, or Load more silently adds nothing.
const int kPagingMaxFetches = 3;

/// One `search` request. [params] is the tab filter (null for general results).
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

/// Parses a filtered tab's answer rows: selects by [keep], parses, removes
/// duplicates by [key], cuts to [limit].
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

/// Adds to a section's end what isn't in it (the base list's order stays, being
/// relevance order). [cap] is the section's limit; null means none (an artist's
/// whole discography).
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
  // Five requests in parallel: general results plus one tab per section. Tabs
  // give clean, properly sorted lists, and general results stay the default and
  // give the top card. If a filter stops working (YouTube changes `params`),
  // the section comes from general results: a broken filter degrades rather
  // than downing search.
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

/// Builds results from answers. Apart from [search]: it's pure, tested with no
/// network.
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

  // Classifies general result rows by their main navigationEndpoint.
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
      // No browse page means a track or video (a playable videoId).
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
      // Paging goes on the Songs tab, so loading gives clean songs.
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
  // Tab albums and playlists don't REPLACE general results but add to them.
  // Unlike artists, general results don't lie here and hold what the tab lacks:
  // official YouTube Music playlists, the only ones with a known track count.
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

  // The top result is the most relevant entity for the query, raised to first
  // in its section: tabs sort within a type but don't know what the user
  // searched for.
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

/// Parses the general results' top card (`musicCardShelfRenderer`). It's NOT
/// among rows, so the usual collection doesn't see it.
///
/// The type comes from the title's first run's `navigationEndpoint`. A track
/// card has `watchEndpoint` with no pageType and is skipped: the Songs tab
/// gives a clean list, and the card has no duration.
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

/// Next page of search tracks (20 at a time). Empty and `false` if there's no
/// continuation or the query changed since the last results.
Future<YtmSearchMore> searchMore(String query) async {
  final fresh = <YtmRawTrack>[];

  for (var i = 0; i < kPagingMaxFetches; i++) {
    final state = _searchCont;
    if (state == null || state.query != query) {
      return const YtmSearchMore(); // the query changed
    }
    final token = state.token;
    if (token == null) break; // pages ran out

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
      return const YtmSearchMore(); // the query changed during the network trip
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

// ── Radio ───────────────────────────────────────────────────────────────

const String kNextUrl =
    'https://music.youtube.com/youtubei/v1/next?prettyPrint=false';

/// A track's radio: a watch playlist with radio on. It opens with the track
/// itself, which is dropped; token [cursor] leads on.
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
    // "Artists • Album • Year": artists are the first part (a game or channel
    // further on can also link to an artist).
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

// ── Pages (browse) ──────────────────────────────────────────────────────

/// POST browse with the web context, giving raw answer JSON. [params] is how
/// YTM encodes which section tab to show (like an artist's Singles & EPs).
Future<Map<String, dynamic>> browse(String browseId, [String? params]) async =>
    _postJson(
      '$kBrowseUrl&key=$kWebKey',
      await _webBody({'browseId': browseId, 'params': ?params}),
      userAgent: kWebUa,
      extraHeaders: _musicHeaders,
      errCode: 'ytm.err.browse',
    );

/// Album: a header and tracks (videoId in rows, duration in fixedColumns).
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
    // Album tracks often have no cover, so I use the album's. The artist isn't
    // repeated in album rows (one for the page, in the header), or each track
    // would be unknown.
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

/// Playlist: a header and tracks. A playlist's browseId needs the `VL` prefix.
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

/// Artist: popular (top songs shelf), with releases and similar from carousels.
/// The header gives only 5–10 songs and 10 releases. Full lists come from the
/// more buttons: a `VL…` playlist on the songs shelf (≈100 tracks), `MPAD…`
/// with `params` on the singles carousel. Both are independent, so parallel.
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

/// Artist header with no trips for more, the pure part of [artist].
YtmEntity parseArtistPage(Object? v) {
  final h = header(v);
  // popular: rows (mrlir) on an artist page are the Songs shelf.
  final popular = <YtmRawTrack>[];
  for (final it in collectMrlir(v)) {
    if (popular.length >= 10) break;
    final t = parseTrack(it);
    if (t != null) popular.add(t);
  }
  // Carousel cards are both releases and similar artists. Parsed by browseId's
  // PREFIX rather than the section title: titles are localized, and YTM
  // shuffles carousels from artist to artist.
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

/// A section's more button link: (browseId, params).
typedef MoreLink = ({String id, String? params});

/// Finds the more button of a section with one of the given titles. Sections
/// are searched recursively with no fixed path: YTM shuffles order and contents
/// from artist to artist.
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

/// Whether a section title's texts include one expected, ignoring case.
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

/// First `browseEndpoint` in a node, as (browseId, params).
MoreLink? browseLink(Object? v) {
  final ep = findRenderer(v, 'browseEndpoint');
  final id = str(at(ep, ['browseId']));
  if (id.isEmpty) return null;
  final params = at(ep, ['params']);
  return (id: id, params: params is String ? params : null);
}

/// Full track list by a more link. Errors are dampened: an artist page must
/// open even without this list.
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

/// Full release list by a more link (singles, EPs). Errors are dampened, as
/// above.
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

/// musicTwoRowItemRenderer to an album (only cards with browseId `MPRE…`).
YtmRawAlbum? parseTwoRowAlbum(Object? it) {
  final id = _twoRowBrowseId(it, 'MPRE');
  if (id == null) return null; // not an album (a playlist or video carousel)
  final title = str(at(it, ['title', 'runs', 0, 'text']));
  if (title.isEmpty) return null;
  // A card's caption is "Single • Artist" or "Album • 2023": the type label
  // goes (or it lands in the artist's name), the year to its own field, and the
  // rest is the artist.
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

/// musicTwoRowItemRenderer to an artist (Fans might also like cards: `UC…`).
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

// ---- Page header ----

/// A page's first known header renderer.
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

/// Page cover. Its OWN `thumbnail` node first, and only then whatever's in the
/// subtree: new `musicResponsiveHeaderRenderer` has `straplineThumbnail` (the
/// artist's avatar) beside it, and a general walk could pass that off as the
/// album's cover.
String headerCover(Object? h) {
  final own = at(h, ['thumbnail']);
  final url = own == null ? '' : biggestThumb(own);
  return url.isNotEmpty ? url : biggestThumb(h);
}

/// Year from the header: a 4-digit run in `subtitle` ("Album • Artist • 2023").
String headerYear(Object? h) {
  final runs = at(h, ['subtitle', 'runs']);
  if (runs is! List) return '';
  for (final r in runs) {
    final s = str(at(r, ['text']));
    if (_isYear(s)) return s;
  }
  return '';
}

/// Header subtitle (artist or owner). `straplineTextOne` is exactly the
/// artist's or owner's name (with their avatar beside it, see
/// [headerStraplineAvatar]), so it comes first: on the new renderer `subtitle`
/// is metadata like "Album • 2023". The fallback to `subtitle` is for old
/// `musicDetailHeaderRenderer`, with no strapline.
String headerSubtitle(Object? h) {
  String join(Object? node) {
    final runs = at(node, ['runs']);
    if (runs is! List) return '';
    return runs.map((r) => str(at(r, ['text']))).join();
  }

  final strapline = join(at(h, ['straplineTextOne']));
  return strapline.isNotEmpty ? strapline : join(at(h, ['subtitle']));
}

/// Artist's or owner's avatar from the header: `straplineThumbnail` is the only
/// place it exists with no browse request to the artist's page.
String headerStraplineAvatar(Object? h) {
  final t = at(h, ['straplineThumbnail']);
  return t == null ? '' : biggestThumb(t);
}

/// Artist's bio from the header (`musicImmersiveHeaderRenderer.description`).
String headerDescription(Object? h) {
  final d = at(h, ['description']);
  final simple = at(d, ['simpleText']);
  if (simple is String) return simple;
  final runs = at(d, ['runs']);
  if (runs is! List) return '';
  return runs.map((r) => str(at(r, ['text']))).join();
}

// ── Parsing links ───────────────────────────────────────────────────────

/// A YouTube or YouTube Music link to an entity. Nearly all comes from the URL
/// itself, but two cases need the network: `list=OLAK5uy_…` is an album's
/// playlist version, while only `MPRE…` opens the album page, with the mapping
/// in the playlist page's HTML; and `/@handle`, `/c/<name>`, `/user/<name>` are
/// readable channel names, with browseId (`UC…`) also only in HTML.
///
/// Both network steps are soft: a failure degrades (the album opens as a
/// playlist, a handle doesn't resolve) rather than downing the import.
Future<YtmResolved> resolve(String url) async {
  final u = url.trim();
  if (!u.contains('youtube.com') && !u.contains('youtu.be')) {
    throw const YtmException('ytm.err.notYoutubeUrl');
  }

  // Track: watch?v=…, youtu.be/<id>, /shorts/<id>. Above a playlist: a track
  // from a playlist link has both parameters, and the track is what should
  // open.
  final v = queryParam(u, 'v');
  if (v != null) return YtmResolved('track', v);
  final short = pathAfter(u, 'youtu.be/') ?? pathAfter(u, '/shorts/');
  if (short != null) return YtmResolved('track', short);

  // Playlist or album: ?list=…
  final list = queryParam(u, 'list');
  if (list != null) {
    if (list.startsWith('OLAK5uy_')) {
      final mpre = await _albumBrowseId(list);
      if (mpre != null) return YtmResolved('album', mpre);
    }
    return YtmResolved('playlist', list);
  }

  // Direct browse links: /browse/<MPRE…|VL…|UC…>.
  final browseId = pathAfter(u, '/browse/');
  if (browseId != null) {
    if (browseId.startsWith('MPRE')) return YtmResolved('album', browseId);
    if (browseId.startsWith('VL')) return YtmResolved('playlist', browseId);
    if (browseId.startsWith('UC')) return YtmResolved('artist', browseId);
  }

  // Channel: /channel/UC… has browseId right in the link; other name kinds
  // (/@handle, /c/…, /user/…) come from the page's HTML.
  final channel = pathAfter(u, '/channel/');
  if (channel != null) return YtmResolved('artist', channel);
  if (u.contains('/@') || u.contains('/c/') || u.contains('/user/')) {
    final id = await _channelBrowseId(u);
    if (id != null) return YtmResolved('artist', id);
  }

  throw const YtmException('ytm.err.badUrl');
}

/// A query parameter's value (`?v=…&list=…`) with no parsing of the whole URL.
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

/// The path piece right after a marker, up to the next `/`, `?`, `#` or `&`.
String? pathAfter(String url, String marker) {
  final i = url.indexOf(marker);
  if (i < 0) return null;
  final rest = url.substring(i + marker.length);
  final id = rest.split(RegExp(r'[/?#&]')).first;
  return id.isEmpty ? null : id;
}

/// An album's browseId (`MPRE…`) by its playlist's id (`OLAK5uy_…`). InnerTube
/// has no such move: the mapping is only in the page's HTML.
Future<String?> _albumBrowseId(String listId) async {
  final html = await _getText(
    'https://music.youtube.com/playlist?list=$listId',
  );
  return html == null ? null : findId(html, 'MPRE');
}

/// A channel's browseId (`UC…`) from a `/@handle` page and the like.
Future<String?> _channelBrowseId(String url) async {
  final html = await _getText(url);
  if (html == null) return null;
  // A specific key rather than searching for UC across the text: those two
  // letters occur too often in markup and give false hits.
  for (final key in const ['"channelId":"', '"browseId":"', '"externalId":"']) {
    final i = html.indexOf(key);
    if (i < 0) continue;
    final rest = html.substring(i + key.length);
    if (rest.startsWith('UC')) return findId(rest, 'UC');
  }
  return null;
}

/// First id with the given prefix in a text.
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

// ── Stream ──────────────────────────────────────────────────────────────

Map<String, dynamic> _visionClient() => {
  'clientName': 'VISIONOS',
  'clientVersion': kVisionClientVersion,
  'deviceMake': 'Apple',
  'deviceModel': 'RealityDevice17,1',
  'osName': 'visionOS',
  'osVersion': '26.5.23O471',
};

/// One `player` request by a given client.
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

/// Audio formats with a ready url (no signatureCipher).
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

/// `true` if an answer is fit: status OK and audio with a direct url.
bool playable(Object? v) =>
    at(v, ['playabilityStatus', 'status']) == 'OK' &&
    audioFormats(v).isNotEmpty;

/// A player endpoint request (giving direct urls and videoDetails). VISIONOS,
/// then on refusal a fresh `visitorData` and a repeat. A stale `visitorData`
/// looks like `LOGIN_REQUIRED`, so one retry with a session reset covers the
/// most common failure.
///
/// No second client on purpose: `ANDROID_VR`'s link passes [playable] and then
/// gives 403, so a refusal would look like success.
Future<Map<String, dynamic>> player(String videoId) async {
  final first = await _playerWith(_visionClient(), kVisionUa, videoId);
  if (playable(first)) return first;

  resetVisitorData();
  final retry = await _playerWith(_visionClient(), kVisionUa, videoId);
  if (playable(retry)) return retry;

  // Nothing played: I return the first answer for its playabilityStatus, from
  // which the caller builds a readable reason.
  return first;
}

/// One track's metadata by videoId, for re-resolving from recents.
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

/// Audio URL for a videoId. m4a/aac preferred (itag 140, the most compatible
/// container), then the rest by bitrate.
///
/// [hls] asks for a playlist rather than a direct link, for AVPlayer on iOS;
/// see [_hlsAudioUrl]. With no playlist in the answer it silently gives the
/// direct one: worse, but it plays.
Future<String> streamUrl(String videoId, {bool hls = false}) async {
  final v = await player(videoId);

  final status = str(at(v, ['playabilityStatus', 'status']));
  if (status != 'OK') {
    final reason = str(at(v, ['playabilityStatus', 'reason']));
    // The reason comes as the platform's text and goes as is.
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

/// Audio track from the HLS manifest, a link for iOS. The direct itag 140 link
/// leads to FRAGMENTED mp4 (`moov` with `mvex`, then `sidx` and a chain of
/// `moof` and `mdat`), a DASH container. ExoPlayer plays it as an ordinary
/// file, while AVFoundation accepts fragmented mp4 only inside HLS: on a direct
/// link AVPlayer reads double the real duration. The sound is right, but the
/// track plays on in silence to a made-up end and doesn't advance.
///
/// The manifest has ready audio-only tracks: group `234` is the same AAC 128k
/// as itag 140, `233` a 48k reserve. The playlist comes as
/// `#EXT-X-PLAYLIST-TYPE:VOD` with `#EXT-X-ENDLIST`, so with an honest
/// duration, and segments are ADTS AAC, native to AVPlayer.
///
/// `null` means failed, and the caller takes the direct link.
Future<String?> _hlsAudioUrl(Object? v) async {
  final master = str(at(v, ['streamingData', 'hlsManifestUrl']));
  if (master.isEmpty) return null;
  final text = await _getText(master, userAgent: kVisionUa);
  if (text == null) return null;
  return _mediaPlaylist(text, '234') ?? _mediaPlaylist(text, '233');
}

/// URI of the `#EXT-X-MEDIA` track with the given `GROUP-ID` from the master
/// manifest.
String? _mediaPlaylist(String manifest, String group) {
  for (final line in const LineSplitter().convert(manifest)) {
    if (!line.startsWith('#EXT-X-MEDIA:')) continue;
    if (!line.contains('GROUP-ID="$group"')) continue;
    final uri = RegExp(r'URI="([^"]+)"').firstMatch(line)?.group(1);
    if (uri != null && uri.isNotEmpty) return uri;
  }
  return null;
}
