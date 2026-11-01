/// The reviews' periods. The month's is always there once it has plays; the
/// year's only on Dec 21–31.
library;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum PeriodKind {
  month('month'),
  year('year');

  const PeriodKind(this.id);

  /// The key in the seen and notified marks.
  final String id;
}

const int _kYearFromDay = 21;
const int _kMonthToastDay = 1;

/// The stats row swaps its value for the review's name through this day.
const int _kHintToDay = 7;

@immutable
class PeriodRange {
  const PeriodRange(this.kind, this.from, this.to);

  final PeriodKind kind;

  /// Local midnight, inclusive.
  final DateTime from;

  /// Exclusive.
  final DateTime to;

  int get fromMs => from.millisecondsSinceEpoch;
  int get toMs => to.millisecondsSinceEpoch;
}

/// The month is the last one whole, the year runs from Jan 1 until now. A
/// checking run ([force]) takes the month going on: the last one may be empty.
PeriodRange periodRange(PeriodKind kind, [DateTime? now, bool force = false]) {
  final at = now ?? DateTime.now();
  switch (kind) {
    case PeriodKind.month:
      final thisMonth = DateTime(at.year, at.month, 1);
      if (force) return PeriodRange(kind, thisMonth, at);
      return PeriodRange(kind, DateTime(at.year, at.month - 1, 1), thisMonth);
    case PeriodKind.year:
      return PeriodRange(kind, DateTime(at.year, 1, 1), at);
  }
}

bool inYearWindow(DateTime now, {bool force = false}) =>
    force || (now.month == DateTime.december && now.day >= _kYearFromDay);

bool inMonthHintWindow(DateTime now, {bool force = false}) =>
    force || now.day <= _kHintToDay;

/// The toasts due today: the year's any day of its window, the month's on the
/// 1st only.
List<PeriodKind> scheduledPeriods(DateTime now, {bool force = false}) => [
  if (inYearWindow(now, force: force)) PeriodKind.year,
  if (force || now.day == _kMonthToastDay) PeriodKind.month,
];

/// "2026-07" / "2026": what the seen and notified marks hold.
String periodKey(PeriodRange r) {
  final d = r.from;
  return switch (r.kind) {
    PeriodKind.year => '${d.year}',
    PeriodKind.month => '${d.year}-${d.month.toString().padLeft(2, '0')}',
  };
}

/// "Июль 2026" / "2026". LLLL is the form that stands alone.
String periodDatesLabel(PeriodRange r, String locale) {
  final from = r.from;
  if (r.kind == PeriodKind.year) return '${from.year}';
  final month = DateFormat('LLLL', locale).format(from);
  return '${month[0].toUpperCase()}${month.substring(1)} ${from.year}';
}
