/// History captions. A group header: Today, Yesterday, N days ago, A week ago
/// or a date. Days are CALENDAR days rather than 86,400,000 ms: otherwise a
/// play at 00:30 would land in yesterday until noon, and with clock changes day
/// edges move an hour too.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n.dart';

/// Calendar day number, in UTC from the same Y-M-D triple, so subtraction
/// doesn't depend on local day length.
int _dayNumber(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// Group header for a history entry made at [at].
String historyLabel(BuildContext context, DateTime at, {DateTime? now}) {
  final l = context.l;
  final days = _dayNumber(now ?? DateTime.now()) - _dayNumber(at);
  if (days <= 0) return l.histToday;
  if (days == 1) return l.histYesterday;
  if (days < 7) return l.histDaysAgo(days);
  if (days < 14) return l.histWeekAgo;
  // A date with no year: past two weeks the exact date matters more than how
  // long ago, and a year isn't needed in a 200-entry history.
  return DateFormat.MMMMd(
    Localizations.localeOf(context).toString(),
  ).format(at);
}

/// Time on a history row. Material's format knows the locale and the system's
/// 12/24 hour setting.
String historyTime(BuildContext context, DateTime at) =>
    TimeOfDay.fromDateTime(at).format(context);
