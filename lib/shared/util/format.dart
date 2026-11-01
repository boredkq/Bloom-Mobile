/// Formats durations, numbers and release dates.
library;

import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

String mmss(Duration d) {
  final s = d.inSeconds.clamp(0, 24 * 3600);
  final m = s ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  if (m < 60) return '$m:$sec';
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:$sec';
}

String mmssMs(int ms) => mmss(Duration(milliseconds: ms));

/// Total time of a list: 1h 23m or 45 min. Not [mmss]: for a hundred tracks
/// hours, minutes and seconds read as a timecode, and a caption doesn't need
/// seconds. Under a minute is 0 min, but the caller need not caption such a
/// list.
String totalDur(AppLocalizations l, Duration d) {
  final m = d.inMinutes;
  return m >= 60 ? l.commonDurHm(m ~/ 60, m % 60) : l.commonDurMin(m);
}

/// Full release date for the language: "2024-05-13T00:00:00Z" becomes "13 мая
/// 2024" or "May 13, 2024". `null` if the platform sent only a year or no date,
/// and the caller shows the year.
///
/// I take only the calendar part: SoundCloud and Yandex attach a time with a
/// zone, and converting to local would move the day: a May 13 00:00 +03 release
/// would be May 12 in London.
String? releaseDateLabel(String? raw, String locale) {
  final day = _releaseDay(raw);
  if (day == null) return null;
  // Russian `yMMMMd` ends in "г.", noise in a three-part caption; the word
  // order is still the native one.
  return DateFormat.yMMMMd(
    locale,
  ).format(day).replaceFirst(RegExp(r'\s*г\.$'), '');
}

/// An album card's date line: "13 мая 2024 г." / "May 13, 2024", short and
/// standing alone, so the Russian "г." stays. Only a year → null, as above.
String? releaseDayShort(String? raw, String locale) {
  final day = _releaseDay(raw);
  return day == null ? null : DateFormat.yMMMd(locale).format(day);
}

DateTime? _releaseDay(String? raw) => raw == null
    ? null
    : DateTime.tryParse(raw.length > 10 ? raw.substring(0, 10) : raw);

/// Short event date from a timestamp, for sheet headers (Added, Created).
/// Unlike [releaseDateLabel] the Russian "г." stays: the line stands alone and
/// would look cut off.
String stampDate(int ms, String locale) =>
    DateFormat.yMMMd(locale).format(DateTime.fromMillisecondsSinceEpoch(ms));
