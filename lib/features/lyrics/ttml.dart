/// TTML (Timed Text Markup Language) lyrics parser: reads Apple Music / LRC.red
/// rich lyrics with word-by-word and syllable timing.
library;

import 'lrc.dart';
import 'romanization.dart';

final RegExp _pRegex = RegExp(
  r'<p\s+([^>]*?)>(.*?)</p>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _spanRegex = RegExp(
  r'<span\s+([^>]*?)>(.*?)</span>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _attrRegex = RegExp(r'([a-zA-Z0-9:_-]+)="([^"]*)"');

/// Parses TTML document string into a list of [LrcLine]s with word timings.
List<LrcLine> parseTtml(String ttml) {
  if (ttml.trim().isEmpty) return const [];
  final lines = <LrcLine>[];

  // Try to find sections from enclosing <div> tags or attributes
  for (final pMatch in _pRegex.finditer(ttml)) {
    final pAttrs = _parseAttrs(pMatch.group(1) ?? '');
    final pBody = pMatch.group(2) ?? '';

    final start = _parseTtmlTime(pAttrs['begin'] ?? '0');
    final end = _parseTtmlTime(pAttrs['end'] ?? '${start + 3.0}');
    final songPart = pAttrs['songPart'] ?? pAttrs['lrc:songPart'];

    final words = <LrcWord>[];
    for (final sMatch in _spanRegex.finditer(pBody)) {
      final sAttrs = _parseAttrs(sMatch.group(1) ?? '');
      var sText = _unescapeXml(sMatch.group(2) ?? '');
      if (sText.isEmpty) continue;

      final wStart = _parseTtmlTime(sAttrs['begin'] ?? '$start');
      final wEnd = _parseTtmlTime(sAttrs['end'] ?? '${wStart + 0.3}');
      final rom = romanize(sText);
      words.add(LrcWord(
        start: wStart,
        end: wEnd,
        text: sText,
        romanized: rom,
      ));
    }

    final rawText = words.isNotEmpty
        ? words.map((w) => w.text).join('')
        : _unescapeXml(pBody.replaceAll(RegExp(r'<[^>]+>'), '')).trim();

    if (rawText.trim().isEmpty) continue;

    final lineText = rawText.trim();
    final romLine = romanize(lineText);

    lines.add(LrcLine(
      start,
      lineText,
      words: words,
      endTime: end > start ? end : null,
      section: songPart?.trim().isNotEmpty == true ? songPart!.trim() : null,
      romanized: romLine,
    ));
  }

  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

Map<String, String> _parseAttrs(String raw) {
  final out = <String, String>{};
  for (final m in _attrRegex.allMatches(raw)) {
    out[m.group(1)!] = m.group(2)!;
  }
  return out;
}

double _parseTtmlTime(String s) {
  final clean = s.trim();
  if (clean.isEmpty) return 0.0;
  if (clean.contains(':')) {
    final parts = clean.split(':');
    if (parts.length == 2) {
      return (double.tryParse(parts[0]) ?? 0) * 60 +
          (double.tryParse(parts[1]) ?? 0);
    } else if (parts.length == 3) {
      return (double.tryParse(parts[0]) ?? 0) * 3600 +
          (double.tryParse(parts[1]) ?? 0) * 60 +
          (double.tryParse(parts[2]) ?? 0);
    }
  }
  return double.tryParse(clean) ?? 0.0;
}

String _unescapeXml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");

extension on RegExp {
  Iterable<RegExpMatch> finditer(String input) => allMatches(input);
}
