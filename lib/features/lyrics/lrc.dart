/// Timed lyrics (LRC): `[mm:ss.xx]text` rows. Supports section labels
/// ([Chorus], [Verse]), syllable/word timings (`<mm:ss.xx>word`), and romanization.
library;

import 'romanization.dart';

/// One word or syllable within a line with exact start and end timestamps.
class LrcWord {
  const LrcWord({
    required this.start,
    required this.end,
    required this.text,
    this.romanized,
  });

  /// Seconds from track start.
  final double start;
  final double end;
  final String text;
  final String? romanized;

  double get duration => (end - start).clamp(0.04, 60.0);

  @override
  bool operator ==(Object other) =>
      other is LrcWord &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      other.romanized == romanized;

  @override
  int get hashCode => Object.hash(start, end, text, romanized);

  @override
  String toString() => 'LrcWord($start..$end, "$text")';
}

/// One line of timed lyrics.
class LrcLine {
  const LrcLine(
    this.time,
    this.text, {
    this.words = const [],
    this.endTime,
    this.romanized,
    this.section,
  });

  /// Seconds from the start of the track.
  final double time;
  final String text;

  /// Word or syllable timings for karaoke, if available.
  final List<LrcWord> words;

  /// Line finish timestamp, if known.
  final double? endTime;

  /// Latin transliteration for non-Latin scripts, if available.
  final String? romanized;

  /// Structural section label (e.g. 'Chorus', 'Припев', 'Verse 1').
  final String? section;

  bool get hasWords => words.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is LrcLine &&
      other.time == time &&
      other.text == text &&
      other.endTime == endTime &&
      other.romanized == romanized &&
      other.section == section;

  @override
  int get hashCode => Object.hash(time, text, endTime, romanized, section);

  @override
  String toString() =>
      'LrcLine($time, $text${words.isNotEmpty ? ', words: ${words.length}' : ''}${romanized != null ? ', rom: $romanized' : ''}${section != null ? ', sec: $section' : ''})';
}

final RegExp _stamp = RegExp(r'^\s*\[(\d+):(\d+(?:[.:]\d+)?)\]');
final RegExp _anyStamp = RegExp(r'\[\d+:\d+(?:[.:]\d+)?\]');
final RegExp _wordStamp = RegExp(r'<(\d+):(\d+(?:[.:]\d+)?)>([^<]*)');
final RegExp _anyWordStamp = RegExp(r'<\d+:\d+(?:[.:]\d+)?>');

/// Recognizes section labels like [Chorus], [Verse 1], [Припев], [Куплет].
final RegExp _sectionHeader = RegExp(
  r'^\s*\[(Chorus|Verse(?:\s+\d+)?|Hook|Bridge|Outro|Intro|Drop|Pre-Chorus|Solo|Припев|Куплет(?:\s+\d+)?|Интро|Аутро|Бридж|Кода)\]\s*(.*)$',
  caseSensitive: false,
);

/// LRC rows → lines by time. Supports enhanced LRC with `<mm:ss.xx>` words.
List<LrcLine> parseLrc(String lrc) {
  final out = <LrcLine>[];
  String? pendingSection;

  for (final raw in lrc.split('\n')) {
    var rest = raw;
    final at = <double>[];
    for (
      var m = _stamp.firstMatch(rest);
      m != null;
      m = _stamp.firstMatch(rest)
    ) {
      final min = int.parse(m.group(1)!);
      final sec = double.parse(m.group(2)!.replaceAll(':', '.'));
      at.add(min * 60 + sec);
      rest = rest.substring(m.end);
    }

    var text = rest.trim();
    if (text.isEmpty) continue;

    // Check if line starts with or is a section marker
    String? currentSection = pendingSection;
    final secMatch = _sectionHeader.firstMatch(text);
    if (secMatch != null) {
      currentSection = secMatch.group(1);
      text = secMatch.group(2)?.trim() ?? '';
      if (text.isEmpty && at.isEmpty) {
        pendingSection = currentSection;
        continue;
      }
    }

    if (text.isEmpty) continue;
    pendingSection = null;

    // Check for enhanced word-level timing: <00:12.30>word
    final words = <LrcWord>[];
    final wordMatches = _wordStamp.allMatches(text).toList();
    if (wordMatches.isNotEmpty) {
      for (var i = 0; i < wordMatches.length; i++) {
        final wm = wordMatches[i];
        final wMin = int.parse(wm.group(1)!);
        final wSec = double.parse(wm.group(2)!.replaceAll(':', '.'));
        final wStart = wMin * 60 + wSec;
        final wText = wm.group(3) ?? '';
        if (wText.trim().isEmpty) continue;

        double wEnd;
        if (i + 1 < wordMatches.length) {
          final nextM = wordMatches[i + 1];
          final nMin = int.parse(nextM.group(1)!);
          final nSec = double.parse(nextM.group(2)!.replaceAll(':', '.'));
          wEnd = nMin * 60 + nSec;
        } else {
          wEnd = wStart + 0.4;
        }
        words.add(LrcWord(
          start: wStart,
          end: wEnd > wStart ? wEnd : wStart + 0.3,
          text: wText,
          romanized: romanize(wText),
        ));
      }
      text = text.replaceAll(_anyWordStamp, '').trim();
    }

    final rom = romanize(text);
    for (final t in at) {
      out.add(LrcLine(
        t,
        text,
        words: words,
        romanized: rom,
        section: currentSection,
      ));
    }
  }

  // List.sort is not stable; the row order breaks ties.
  final indexed = out.indexed.toList()
    ..sort((a, b) {
      final byTime = a.$2.time.compareTo(b.$2.time);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });

  final result = <LrcLine>[];
  for (var i = 0; i < indexed.length; i++) {
    final line = indexed[i].$2;
    final nextTime = i + 1 < indexed.length ? indexed[i + 1].$2.time : null;
    result.add(LrcLine(
      line.time,
      line.text,
      words: line.words,
      endTime: line.endTime ?? nextTime,
      romanized: line.romanized,
      section: line.section,
    ));
  }
  return result;
}

/// The text without its time stamps.
String stripLrc(String s) =>
    s.replaceAll(_anyStamp, '').replaceAll(_anyWordStamp, '').trim();

/// The line being sung at [sec]; −1 during the intro. A line lights up a
/// quarter of a second early.
int activeLineAt(List<LrcLine> lines, double sec) {
  final pos = sec + 0.25;
  var lo = 0;
  var hi = lines.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].time <= pos) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo - 1;
}
