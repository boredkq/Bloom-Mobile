/// Lyrics from LRCLIB: the exact match with the
/// length, then with a cleaned title, then a search scored against the query;
/// an "Artist - Title" upload title is tried as such last.
///
/// My tag reading (MediaMetadataRetriever) has no lyrics, so I start at LRCLIB.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../providers/yandex/yandex.dart' as ym;
import 'lrc.dart';
import 'lyrics_plus.dart';

/// What was found. Both texts empty — nothing.
class LyricsResult {
  const LyricsResult({
    this.synced = '',
    this.plain = '',
    this.source = '',
    this.lines = const [],
  });

  static const none = LyricsResult();

  final String synced;
  final String plain;

  /// Where they came from: `lyricsplus`, `yandex`, `lrclib`.
  final String source;

  /// Parsed lines with word-by-word karaoke, if available.
  final List<LrcLine> lines;

  bool get ok =>
      lines.isNotEmpty ||
      synced.trim().isNotEmpty ||
      plain.trim().isNotEmpty;
}

const String _base = 'https://lrclib.net/api/';
// LRCLIB asks clients to say who they are.
const String _ua = 'Bloom/1.0 (https://github.com/use-bloom/mobile)';
const Duration _timeout = Duration(seconds: 15);

/// A search hit below this is some other song.
const int kMinSearchScore = 20;

Future<LyricsResult> fetchLyrics({
  required String artist,
  required String title,
  int? durationSec,
  String? trackId,
  String? album,
  http.Client? client,
}) async {
  if (title.trim().isEmpty) return LyricsResult.none;
  final c = client ?? _shared;
  final d = durationSec ?? 0;

  // 1. Try LyricsPlus mirrors pool (all tracks including Yandex Music!).
  final plusResult = await fetchLyricsPlus(
    title: title,
    artist: artist,
    durationSec: d > 0 ? d : null,
    album: album,
    client: c,
  );
  if (plusResult != null && plusResult.lines.isNotEmpty) {
    return LyricsResult(
      source: plusResult.source,
      lines: plusResult.lines,
      plain: plusResult.lines.map((l) => l.text).join('\n'),
    );
  }

  // 2. Direct fetch from Yandex Music if track originates from Yandex.
  if (trackId != null && trackId.startsWith('ym:')) {
    final ymResult = await ym.trackLyrics(trackId, client: c);
    if (ymResult != null) {
      final res = LyricsResult(
        synced: ymResult.synced,
        plain: ymResult.plain.isNotEmpty
            ? ymResult.plain
            : stripLrc(ymResult.synced),
        source: 'yandex',
      );
      if (res.synced.isNotEmpty) return res;
      // If Yandex gave plain text, try LRCLIB for synced lyrics.
      final lrclibFound = await _lrclib(c, artist, title, d);
      if (lrclibFound.synced.isNotEmpty) return lrclibFound;
      return res;
    }
  }

  // 3. Query LRCLIB.
  final found = await _lrclib(c, artist, title, d);
  if (found.ok) return found;
  // Uploads are often titled "Artist - Title" under someone else's name.
  final dash = title.indexOf(' - ');
  if (dash < 0 || title.substring(dash + 3).trim().isEmpty) return found;
  return _lrclib(
    c,
    title.substring(0, dash).trim(),
    title.substring(dash + 3).trim(),
    d,
  );
}

Future<LyricsResult> _lrclib(
  http.Client c,
  String artist,
  String title,
  int duration,
) async {
  if (duration > 0 && artist.isNotEmpty) {
    final r = await _exact(c, artist, title, duration);
    if (r.ok) return r;
  }
  final cleanTitle = normalizeForSearch(title);
  final cleanArtist = normalizeForSearch(artist);
  final cleaner =
      cleanArtist.isNotEmpty &&
      !(_same(cleanTitle, title) && _same(cleanArtist, artist));
  if (cleaner && duration > 0) {
    final r = await _exact(c, cleanArtist, cleanTitle, duration);
    if (r.ok) return r;
  }
  return _search(c, artist, title);
}

Future<LyricsResult> _exact(
  http.Client c,
  String artist,
  String title,
  int duration,
) async {
  final body = await _json(c, 'get', {
    'artist_name': artist,
    'track_name': title,
    'duration': '$duration',
  });
  return body is Map ? _found(body.cast()) : LyricsResult.none;
}

Future<LyricsResult> _search(http.Client c, String artist, String title) async {
  final body = await _json(c, 'search', {
    'q': artist.isEmpty ? title : '$artist $title',
  });
  if (body is! List) return LyricsResult.none;
  var best = -1;
  var bestSynced = false;
  Map<String, Object?>? hit;
  for (final raw in body) {
    if (raw is! Map) continue;
    final o = raw.cast<String, Object?>();
    final synced = (o['syncedLyrics'] as String? ?? '').isNotEmpty;
    final s = scoreHit(
      hitTitle: o['trackName'] as String? ?? '',
      hitArtist: o['artistName'] as String? ?? '',
      queryTitle: title,
      queryArtist: artist,
    );
    // Timed lyrics win over a slightly better plain match.
    if (s > best || (s >= best - 10 && synced && !bestSynced)) {
      best = s;
      bestSynced = synced;
      hit = o;
    }
  }
  return hit != null && best >= kMinSearchScore
      ? _found(hit)
      : LyricsResult.none;
}

Future<Object?> _json(http.Client c, String path, Map<String, String> q) async {
  try {
    final res = await c
        .get(
          Uri.parse(_base + path).replace(queryParameters: q),
          headers: const {'User-Agent': _ua},
        )
        .timeout(_timeout);
    if (res.statusCode != 200) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  } catch (_) {
    // No network, a timeout, not JSON: no lyrics this time.
    return null;
  }
}

LyricsResult _found(Map<String, Object?> o) {
  final synced = o['syncedLyrics'] as String? ?? '';
  final plain = o['plainLyrics'] as String? ?? '';
  return LyricsResult(
    synced: synced,
    plain: plain.trim().isEmpty && synced.trim().isNotEmpty
        ? stripLrc(synced)
        : plain,
    source: 'lrclib',
  );
}

final http.Client _shared = http.Client();

RegExp _rx(String pattern) => RegExp(pattern, caseSensitive: false);

final RegExp _brackets = _rx(r'[\(\[][^\)\]]*[\)\]]');
final RegExp _junk = _rx(
  r'\b(?:official\s+(?:music\s+)?(?:video|audio|clip|lyric(?:s\s+)?video))'
  r'|\b(?:lyric(?:s)?\s+video|audio|visuali[sz]er)'
  r'|\s*\bprod\.?(?:\s+by)?\s+.+$'
  r'|\b(?:type\s+beat)',
);
final RegExp _spaces = RegExp(r'\s{2,}');
final RegExp _artistSep = _rx(
  r'\s*[,&/]\s*|\s+(?:feat\.?|ft\.?|featuring|and|x)\s+',
);

/// Brackets of any kind ("(feat. X)", "[Remix]") and the video junk of
/// upload titles, gone.
String normalizeForSearch(String s) {
  if (s.trim().isEmpty) return '';
  return s
      .replaceAll(_brackets, ' ')
      .replaceAll(_junk, ' ')
      .replaceAll(_spaces, ' ')
      .trim();
}

/// The first artist of a line ("A, B & C" → "A").
String primaryArtist(String artist) => artist.split(_artistSep).first.trim();

/// How well a search hit is the song asked for: the title up to 60, the
/// artist up to 40.
int scoreHit({
  required String hitTitle,
  required String hitArtist,
  required String queryTitle,
  required String queryArtist,
}) {
  final ht = hitTitle.trim();
  final ha = hitArtist.trim();
  final qt = queryTitle.trim();
  final qa = queryArtist.trim();
  var s = 0;
  if (_same(ht, qt)) {
    s += 60;
  } else if (_contains(ht, qt) || _contains(qt, ht)) {
    s += 40;
  } else {
    final nh = normalizeForSearch(ht);
    final nq = normalizeForSearch(qt);
    if (_same(nh, nq)) {
      s += 50;
    } else if (_contains(nh, nq) || _contains(nq, nh)) {
      s += 30;
    }
  }
  if (qa.isNotEmpty && ha.isNotEmpty) {
    if (_same(ha, qa)) {
      s += 40;
    } else if (_contains(ha, qa) || _contains(qa, ha)) {
      s += 30;
    } else {
      final ph = primaryArtist(ha);
      final pq = primaryArtist(qa);
      if (_same(ph, pq)) {
        s += 35;
      } else if (_contains(ph, pq) || _contains(pq, ph)) {
        s += 20;
      }
    }
  }
  return s;
}

bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

bool _contains(String hay, String needle) =>
    needle.isNotEmpty && hay.toLowerCase().contains(needle.toLowerCase());
