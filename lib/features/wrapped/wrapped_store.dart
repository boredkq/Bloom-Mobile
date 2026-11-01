/// What the reviews show today, and the marks of what was watched and told.
/// A review doesn't get set up: it just happens, there are no settings.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/store/days_store.dart' show dayKey;
import '../../core/store/play_log.dart';
import 'periods.dart';
import 'wrapped_data.dart';

const String _kSeen = 'wrapped.seen'; // {month: "2026-09", year: "2026"}
const String _kNotified = 'wrapped.notified'; // the same, for the toasts

/// A checking run (`--dart-define=WRAPPED_FORCE=true`): the windows are open
/// and the month is the current one. It keeps its own marks, or this month
/// marked seen would hide its real review a month later.
final wrappedForceProvider = Provider<bool>(
  (_) => const bool.fromEnvironment('WRAPPED_FORCE'),
);

@immutable
class WrappedMarks {
  const WrappedMarks({this.seen = const {}, this.notified = const {}});

  final Map<String, dynamic> seen;
  final Map<String, dynamic> notified;
}

final wrappedMarksProvider =
    NotifierProvider<WrappedMarksController, WrappedMarks>(
      WrappedMarksController.new,
    );

class WrappedMarksController extends Notifier<WrappedMarks> {
  BloomDb get _db => ref.read(dbProvider);

  String _key(String base) =>
      ref.read(wrappedForceProvider) ? '$base.force' : base;

  @override
  WrappedMarks build() => WrappedMarks(
    seen: _db.getMap(_key(_kSeen)),
    notified: _db.getMap(_key(_kNotified)),
  );

  void markSeen(PeriodRange range) {
    if (state.seen[range.kind.id] == periodKey(range)) return;
    final seen = {...state.seen, range.kind.id: periodKey(range)};
    _db.set(_key(_kSeen), seen);
    state = WrappedMarks(seen: seen, notified: state.notified);
  }

  bool isNotified(PeriodRange range) =>
      state.notified[range.kind.id] == periodKey(range);

  void markNotified(PeriodRange range) {
    if (isNotified(range)) return;
    final notified = {...state.notified, range.kind.id: periodKey(range)};
    _db.set(_key(_kNotified), notified);
    state = WrappedMarks(seen: state.seen, notified: notified);
  }
}

/// Today as the reviews see it: the app can stay open into the 1st, so the
/// date is checked on coming back from the background.
final wrappedDayProvider = NotifierProvider<WrappedDayController, String>(
  WrappedDayController.new,
);

class WrappedDayController extends Notifier<String> {
  @override
  String build() => dayKey(ref.read(playLogClockProvider)());

  /// True when the day has turned.
  bool refresh() {
    final now = dayKey(ref.read(playLogClockProvider)());
    if (now == state) return false;
    state = now;
    return true;
  }
}

/// The reviews there are right now. No plays in a period: no review of it, and
/// no way in.
@immutable
class WrappedEntries {
  const WrappedEntries({
    this.month,
    this.year,
    this.monthUnseen = false,
    this.monthHint = false,
    this.yearUnseen = false,
  });

  final WrappedData? month;

  /// Only in December's window.
  final WrappedData? year;

  /// Until it's watched, the stats row is the way into the month's review.
  final bool monthUnseen;

  /// The first week: the stats row now and then says the review's name.
  final bool monthHint;
  final bool yearUnseen;

  bool get isEmpty => month == null && year == null;

  WrappedData? of(PeriodKind kind) => kind == PeriodKind.year ? year : month;
}

final wrappedEntriesProvider = Provider<WrappedEntries>((ref) {
  final marks = ref.watch(wrappedMarksProvider);
  ref.watch(wrappedDayProvider);
  final force = ref.watch(wrappedForceProvider);
  final now = ref.watch(playLogClockProvider)();
  final log = ref.watch(playLogProvider);
  if (log.isEmpty) return const WrappedEntries();

  WrappedData? built(PeriodKind kind) {
    final data = buildWrapped(log, periodRange(kind, now, force));
    return data.isEmpty ? null : data;
  }

  bool unseen(WrappedData? data) =>
      data != null && marks.seen[data.range.kind.id] != periodKey(data.range);

  final month = built(PeriodKind.month);
  final year = inYearWindow(now, force: force) ? built(PeriodKind.year) : null;
  return WrappedEntries(
    month: month,
    year: year,
    monthUnseen: unseen(month),
    monthHint: month != null && inMonthHintWindow(now, force: force),
    yearUnseen: unseen(year),
  );
});
