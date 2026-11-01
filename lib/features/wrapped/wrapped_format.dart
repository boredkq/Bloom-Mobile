/// Numbers and words for the reviews.
library;

import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';

/// "12 часов 34 минуты", "45 минут", "Меньше минуты".
String fmtListenTime(AppLocalizations l, int seconds) {
  final totalMin = (seconds / 60).round();
  if (totalMin < 1) return l.wrTimeLessThanMin;
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h == 0) return l.wrMinutesN(m);
  if (m == 0) return l.wrHoursN(h);
  return '${l.wrHoursN(h)} ${l.wrMinutesN(m)}';
}

/// The time as big numbers with their words; empty under a minute. No seconds:
/// it's an estimate.
List<({int n, String word})> splitListenTime(AppLocalizations l, int seconds) {
  final totalMin = (seconds / 60).round();
  if (totalMin < 1) return const [];
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return [
    if (h > 0) (n: h, word: l.wrHoursWord(h)),
    if (m > 0 || h == 0) (n: m, word: l.wrMinutesWord(m)),
  ];
}

/// "14:00 — 15:00".
String fmtHourRange(AppLocalizations l, int hour) => l.wrHourRange(
  '${hour.toString().padLeft(2, '0')}:00',
  '${((hour + 1) % 24).toString().padLeft(2, '0')}:00',
);

/// 12 345 with the language's grouping.
String fmtCount(String locale, int n) =>
    NumberFormat.decimalPattern(locale).format(n);
