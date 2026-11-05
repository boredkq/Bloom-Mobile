/// LyricsPlus provider: connects to the full pool of LyricsPlus and Binimum
/// mirrors to fetch rich word-by-word (syllable-timed) TTML and JSON lyrics.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lrc.dart';
import 'lyrics_api.dart' show normalizeForSearch, scoreHit;
import 'romanization.dart';
import 'ttml.dart';

const List<String> kLyricsPlusMirrors = [
  'https://lyricsplus.binimum.org',
  'https://lyricsplus.atomix.one',
  'https://lyricsplus.prjktla.my.id',
  'https://lyricsplus-seven.vercel.app',
];

const String kBinimumApiBase = 'https://lyrics-api.binimum.org/';
const String _userAgent = 'LEVYRA Lyrics Engine/3.5 Android';
const Duration _mirrorTimeout = Duration(milliseconds: 3200);

String? _lastWorkingServer;

/// Queries the LyricsPlus mirror pool and Binimum API for word-synced lyrics.
Future<({List<LrcLine> lines, String source})?> fetchLyricsPlus({
  required String title,
  required String artist,
  int? durationSec,
  String? album,
  http.Client? client,
}) async {
  if (title.trim().isEmpty) return null;
  final c = client ?? http.Client();

  // 1. Try preferred or working mirror first
  if (_lastWorkingServer != null) {
    final res = await _fetchMirror(
      _lastWorkingServer!,
      title,
      artist,
      durationSec,
      album,
      c,
    );
    if (res != null && res.isNotEmpty) {
      return (lines: res, source: 'LyricsPlus · ${_host(_lastWorkingServer!)}');
    }
  }

  // 2. Try the mirror pool in parallel
  final candidateMirrors =
      kLyricsPlusMirrors.where((m) => m != _lastWorkingServer).toList();

  for (final mirror in candidateMirrors) {
    final res = await _fetchMirror(mirror, title, artist, durationSec, album, c);
    if (res != null && res.isNotEmpty) {
      _lastWorkingServer = mirror;
      return (lines: res, source: 'LyricsPlus · ${_host(mirror)}');
    }
  }

  // 3. Fallback to Binimum API (which serves TTML with word-by-word karaoke)
  final binimumRes = await _fetchBinimum(title, artist, durationSec, c);
  if (binimumRes != null && binimumRes.isNotEmpty) {
    return (lines: binimumRes, source: 'LyricsPlus · TTML');
  }

  return null;
}

Future<List<LrcLine>?> _fetchMirror(
  String server,
  String title,
  String artist,
  int? durationSec,
  String? album,
  http.Client client,
) async {
  try {
    final uri = Uri.parse('${server.replaceAll(RegExp(r'/+$'), '')}/v2/lyrics/get')
        .replace(
      queryParameters: {
        'title': title,
        'artist': artist,
        if (durationSec != null && durationSec > 0)
          'duration': '$durationSec',
        if (album != null && album.isNotEmpty) 'album': album,
      },
    );

    final res = await client.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    ).timeout(_mirrorTimeout);

    if (res.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is! Map<String, dynamic>) return null;

    final lyrics = json['lyrics'] as List<dynamic>?;
    if (lyrics == null || lyrics.isEmpty) return null;

    final lines = <LrcLine>[];
    for (final item in lyrics) {
      if (item is! Map) continue;
      final rawLine = item.cast<String, dynamic>();
      final startMs = (rawLine['time'] as num?)?.toDouble() ?? 0.0;
      final durMs = (rawLine['duration'] as num?)?.toDouble() ?? 0.0;
      final lineStart = startMs / 1000.0;
      final lineEnd = (startMs + durMs) / 1000.0;
      final lineText = (rawLine['text'] as String? ?? '').trim();

      final words = <LrcWord>[];
      final syllabus = rawLine['syllabus'] as List<dynamic>?;
      if (syllabus != null) {
        for (final w in syllabus) {
          if (w is! Map) continue;
          final wm = w.cast<String, dynamic>();
          final wText = (wm['text'] as String? ?? '').trim();
          if (wText.isEmpty) continue;
          final wStartMs = (wm['time'] as num?)?.toDouble() ?? startMs;
          final wDurMs = (wm['duration'] as num?)?.toDouble() ?? 300.0;
          final wStart = wStartMs / 1000.0;
          final wEnd = (wStartMs + wDurMs) / 1000.0;
          words.add(LrcWord(
            start: wStart,
            end: wEnd > wStart ? wEnd : wStart + 0.25,
            text: wText,
            romanized: romanize(wText),
          ));
        }
      }

      final effectiveText = lineText.isNotEmpty
          ? lineText
          : words.map((w) => w.text).join(' ').trim();

      if (effectiveText.isEmpty && words.isEmpty) continue;

      lines.add(LrcLine(
        lineStart,
        effectiveText,
        words: words,
        endTime: lineEnd > lineStart ? lineEnd : null,
        romanized: romanize(effectiveText),
      ));
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines.isNotEmpty ? lines : null;
  } catch (_) {
    return null;
  }
}

Future<List<LrcLine>?> _fetchBinimum(
  String title,
  String artist,
  int? durationSec,
  http.Client client,
) async {
  try {
    final uri = Uri.parse(kBinimumApiBase).replace(
      queryParameters: {
        'track': title,
        'artist': artist,
        if (durationSec != null && durationSec > 0)
          'duration': '$durationSec',
      },
    );

    final res = await client.get(
      uri,
      headers: {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
    ).timeout(_mirrorTimeout);

    if (res.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is! Map<String, dynamic>) return null;

    final results = json['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    // Pick candidate with best score and preference for word timing
    Map<String, dynamic>? best;
    var bestScore = -1;

    for (final r in results) {
      if (r is! Map) continue;
      final candidate = r.cast<String, dynamic>();
      final lyricsUrl = candidate['lyricsUrl'] as String? ?? '';
      if (!lyricsUrl.startsWith('http')) continue;

      final hitTitle = candidate['track_name'] as String? ?? '';
      final hitArtist = candidate['artist_name'] as String? ?? '';
      final timingType =
          (candidate['timing_type'] as String? ?? '').toLowerCase();

      var score = scoreHit(
        hitTitle: hitTitle,
        hitArtist: hitArtist,
        queryTitle: title,
        queryArtist: artist,
      );

      if (timingType == 'word') score += 25;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    if (best == null || bestScore < 30) return null;
    final lyricsUrl = best['lyricsUrl'] as String;

    final lyricsResp = await client.get(
      Uri.parse(lyricsUrl),
      headers: {'User-Agent': _userAgent},
    ).timeout(const Duration(seconds: 6));

    if (lyricsResp.statusCode != 200) return null;
    final body = utf8.decode(lyricsResp.bodyBytes);

    if (body.trim().startsWith('<tt') || body.contains('xmlns="http://www.w3.org/ns/ttml"')) {
      final ttmlLines = parseTtml(body);
      if (ttmlLines.isNotEmpty) return ttmlLines;
    }

    return parseLrc(body);
  } catch (_) {
    return null;
  }
}

String _host(String url) {
  try {
    return Uri.parse(url).host;
  } catch (_) {
    return url;
  }
}
