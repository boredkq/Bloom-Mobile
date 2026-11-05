/// Timed lyrics (LRC): `[mm:ss.xx]text` rows. Supports section labels
/// ([Chorus], [Verse], [Припев]) and romanization.
library;

import 'romanization.dart';

/// One line of timed lyrics.
class LrcLine {
  const LrcLine(this.time, this.text, {this.romanized, this.section});

  /// Seconds from the start of the track.
  final double time;
  final String text;

  /// Latin transliteration for non-Latin scripts, if available.
  final String? romanized;

  /// Structural section label (e.g. 'Chorus', 'Припев', 'Verse 1').
  final String? section;

  @override
  bool operator ==(Object other) =>
      other is LrcLine &&
      other.time == time &&
      other.text == text &&
      other.romanized == romanized &&
      other.section == section;

  @override
  int get hashCode => Object.hash(time, text, romanized, section);

  @override
  String toString() =>
      'LrcLine($time, $text${romanized != null ? ', rom: $romanized' : ''}${section != null ? ', sec: $section' : ''})';
}

final RegExp _stamp = RegExp(r'^\s*\[(\d+):(\d+(?:[.:]\d+)?)\]');
final RegExp _anyStamp = RegExp(r'\[\d+:\d+(?:[.:]\d+)?\]');

/// Recognizes section labels like [Chorus], [Verse 1], [Припев], [Куплет].
final RegExp _sectionHeader = RegExp(
  r'^\s*\[(Chorus|Verse(?:\s+\d+)?|Hook|Bridge|Outro|Intro|Drop|Pre-Chorus|Solo|Припев|Куплет(?:\s+\d+)?|Интро|Аутро|Бридж|Кода)\]\s*(.*)$',
  caseSensitive: false,
);

/// LRC rows → lines by time. "[01:02.30][02:10.00]text" stands at both
/// times; a stamp with no text (a gap between verses) is dropped.
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
      // If the line only had a section header and no timestamps, keep it for the next timed line
      if (text.isEmpty && at.isEmpty) {
        pendingSection = currentSection;
        continue;
      }
    }

    if (text.isEmpty) continue;
    pendingSection = null;

    final rom = romanize(text);
    for (final t in at) {
      out.add(LrcLine(t, text, romanized: rom, section: currentSection));
    }
  }

  // List.sort is not stable; the row order breaks ties, as stable_sort does.
  final indexed = out.indexed.toList()
    ..sort((a, b) {
      final byTime = a.$2.time.compareTo(b.$2.time);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final (_, line) in indexed) line];
}

/// The text without its time stamps.
String stripLrc(String s) => s.replaceAll(_anyStamp, '').trim();

/// The line being sung at [sec]; −1 during the intro. A line lights up a
/// quarter of a second early: stamps mark the voice, the eye wants it sooner.
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
