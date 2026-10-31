/// Timed lyrics (LRC): `[mm:ss.xx]text` rows, read as the PC's `Lyrics::apply`
/// reads them.
library;

/// One line of timed lyrics.
class LrcLine {
  const LrcLine(this.time, this.text);

  /// Seconds from the start of the track.
  final double time;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LrcLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => 'LrcLine($time, $text)';
}

final RegExp _stamp = RegExp(r'^\s*\[(\d+):(\d+(?:[.:]\d+)?)\]');
final RegExp _anyStamp = RegExp(r'\[\d+:\d+(?:[.:]\d+)?\]');

/// LRC rows → lines by time. "[01:02.30][02:10.00]text" stands at both
/// times; a stamp with no text (a gap between verses) is dropped.
List<LrcLine> parseLrc(String lrc) {
  final out = <LrcLine>[];
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
    final text = rest.trim();
    if (text.isEmpty) continue;
    for (final t in at) {
      out.add(LrcLine(t, text));
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
