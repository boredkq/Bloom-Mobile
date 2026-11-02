/// Days Bloom was open and app time for each, in the `days` table. Plays per
/// day aren't here: they come from the log ([PlayStats.perDay]). Only visits
/// (for the level: a day counts if the app was opened or something played) and
/// `app_ms` (an achievement and app time in stats).
///
/// The day key is the LOCAL date `YYYY-MM-DD`, so today on the chart is the
/// listener's today.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../log/bloom_log.dart';
import 'play_log.dart' show playLogClockProvider;

/// `YYYY-MM-DD` in local time.
String dayKey(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

@immutable
class DaysState {
  const DaysState({this.visited = const {}, this.appMs = 0});

  /// Days the app was opened.
  final Set<String> visited;

  /// All-time app open time, ms.
  final int appMs;
}

final daysProvider = NotifierProvider<DaysController, DaysState>(
  DaysController.new,
);

class DaysController extends Notifier<DaysState> {
  BloomDb get _db => ref.read(dbProvider);

  String _today() => dayKey(ref.read(playLogClockProvider)());

  @override
  DaysState build() => _read();

  /// Re-reads: another device's days arrived.
  void reload() => state = _read();

  DaysState _read() {
    final rows = _db.select('SELECT day, app_ms FROM days');
    var ms = 0;
    for (final r in rows) {
      ms += r['app_ms'] as int;
    }
    return DaysState(
      visited: {for (final r in rows) r['day'] as String},
      appMs: ms,
    );
  }

  /// Today's visit, at launch and on return from background, since the date may
  /// have changed.
  void visit() {
    final today = _today();
    if (state.visited.contains(today)) return;
    _db.exec('INSERT OR IGNORE INTO days (day) VALUES (?)', [today]);
    state = DaysState(visited: {...state.visited, today}, appMs: state.appMs);
  }

  /// Adds app time to today.
  void addUsage(int ms) {
    final today = _today();
    _db.exec(
      'INSERT INTO days (day, app_ms) VALUES (?, ?) ON CONFLICT(day, device) DO UPDATE SET app_ms = app_ms + excluded.app_ms',
      [today, ms],
    );
    state = DaysState(
      visited: state.visited.contains(today)
          ? state.visited
          : {...state.visited, today},
      appMs: state.appMs + ms,
    );
  }

  /// Part of clearing stats: days go, today's visit stays, since the app is
  /// open.
  void clear() {
    final today = _today();
    _db.tx(() {
      _db.exec('DELETE FROM days');
      _db.exec('INSERT INTO days (day) VALUES (?)', [today]);
    });
    state = DaysState(visited: {today});
  }
}

/// Tracks time in the app. Every [_beat] I take the REAL clock delta, not the
/// timer step, and drop anything above [_maxDelta]: that's a gap (device sleep,
/// frozen engine). Leaving for background I take the tail, and on return the
/// count starts over, so time in another app doesn't land here.
class UsageTracker with WidgetsBindingObserver {
  UsageTracker(this._days);

  final DaysController _days;

  static const Duration _beat = Duration(seconds: 20);
  static const int _maxDelta = 90000;

  Timer? _timer;
  int _last = 0;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _days.visit();
    _last = DateTime.now().millisecondsSinceEpoch;
    _timer = Timer.periodic(_beat, (_) => _flush());
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  void _flush() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final delta = now - _last;
    _last = now;
    if (delta > 0 && delta < _maxDelta) _days.addUsage(delta);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The only point in the process that sees the lifecycle, so it goes to the
    // log: otherwise a log can't tell "the user left" from "the system killed
    // it", and diagnosing launch failures relies on that. On leaving active I
    // flush the log: the background process gets killed with no warning.
    logInfo('app', 'state: ${state.name}');
    if (state != AppLifecycleState.resumed) {
      unawaited(BloomLog.instance.flush());
    }
    if (state == AppLifecycleState.resumed) {
      _days.visit();
      _last = DateTime.now().millisecondsSinceEpoch;
    } else {
      _flush();
    }
  }
}
