/// The app's log, shown in settings. A ring buffer of [kLogMax] entries in
/// memory; the old get pushed out. The WHOLE buffer is written to disk,
/// deferred: appending would grow forever and trimming means rotation, while
/// rewriting the ring bounds the file by itself. At launch the file is read
/// back, because the log must survive a restart or a crash leaves nothing.
///
/// An entry is one line on file and on screen, so multi-line text (a stack
/// trace) is folded, or the file couldn't be parsed back.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../store/app_dirs.dart';

/// Entries kept. 500 lines is a few hundred KB and well beyond what it takes to
/// see what happened before a failure.
const int kLogMax = 500;

/// Wait after a write before rewriting the file. Errors come in bursts, and one
/// write each isn't needed.
const Duration _flushDelay = Duration(seconds: 2);

enum LogLevel { info, warn, error }

class LogEntry {
  const LogEntry(this.at, this.level, this.tag, this.message);

  final DateTime at;
  final LogLevel level;

  /// Where the entry comes from: `player`, `offline`, `flutter`…
  final String tag;
  final String message;

  /// `2026-08-20 14:03:11 ERROR [player] no provider for xx`
  String format() =>
      '${_stamp(at)} ${level.name.toUpperCase().padRight(5)} [$tag] $message';

  /// Parses a line from the file. `null` for a foreign or broken line: a log
  /// isn't worth crashing over, so these are skipped.
  static LogEntry? parse(String line) {
    final m = _lineRe.firstMatch(line);
    if (m == null) return null;
    final at = DateTime.tryParse(m.group(1)!);
    if (at == null) return null;
    final level = LogLevel.values.firstWhere(
      (l) => l.name == m.group(2)!.toLowerCase(),
      orElse: () => LogLevel.info,
    );
    return LogEntry(at, level, m.group(3)!, m.group(4)!);
  }

  static final RegExp _lineRe = RegExp(
    r'^(\S+ \S+) (INFO |WARN |ERROR) \[([^\]]*)\] (.*)$',
  );

  static String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}

class BloomLog {
  BloomLog._();

  /// One log per process: it's called from anywhere, including the unhandled
  /// error handler with no `ref` or context.
  static final BloomLog instance = BloomLog._();

  final List<LogEntry> _entries = [];
  File? _file;
  Timer? _debounce;

  /// Entries oldest first. A copy: the list is live and changes under the
  /// screen.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;

  /// Entry count for the settings row caption. A plain number won't do: the log
  /// page lies over that page, which stays alive in the stack and doesn't
  /// rebuild on return, so the caption would keep the old count after clearing.
  final ValueNotifier<int> count = ValueNotifier(0);

  /// Opens the log and reads earlier launches' file. Called from `main()`
  /// before the first frame.
  Future<void> open() async {
    try {
      final dir = Directory('${(await appPrivateDir()).path}/logs');
      if (!dir.existsSync()) await dir.create(recursive: true);
      final file = File('${dir.path}/bloom.log');
      _file = file;
      if (!file.existsSync()) return;
      final lines = await file.readAsLines();
      for (final line in lines) {
        final entry = LogEntry.parse(line);
        if (entry != null) _entries.add(entry);
      }
      _trim();
    } catch (_) {
      // No space, no rights, a broken file: the log lives in memory.
      // Diagnostics can't be a reason to crash.
    }
    _bump();
  }

  /// [now] writes to disk at once, not waiting for [_flushDelay]. Errors always
  /// do: an error is often the last thing before a crash, and the process may
  /// not live two more seconds.
  ///
  /// Ordinary entries need it too on paths where there may be no next line: a
  /// NATIVE crash (ExoPlayer, a screen driver) kills the process past all Dart
  /// handlers, leaving silence just where it's needed.
  void add(LogLevel level, String tag, String message, {bool now = false}) {
    _entries.add(LogEntry(DateTime.now(), level, tag, _flatten(message)));
    _trim();
    if (level == LogLevel.error || now) {
      _debounce?.cancel();
      _debounce = null;
      unawaited(flush());
    } else {
      _schedule();
    }
    _bump();
  }

  void info(String tag, String message, {bool now = false}) =>
      add(LogLevel.info, tag, message, now: now);
  void warn(String tag, String message, {bool now = false}) =>
      add(LogLevel.warn, tag, message, now: now);

  /// Error with an optional cause: `message — Exception: …`.
  void error(String tag, String message, [Object? cause]) =>
      add(LogLevel.error, tag, cause == null ? message : '$message — $cause');

  /// The whole log as text, for viewing, copying and export.
  String text() => _entries.map((e) => e.format()).join('\n');

  Future<void> clear() async {
    _entries.clear();
    _bump();
    _debounce?.cancel();
    _debounce = null;
    try {
      final file = _file;
      if (file != null && file.existsSync()) await file.delete();
    } catch (_) {
      // The file wasn't removed: the log is already empty in memory, and the
      // next write replaces it.
    }
  }

  /// Writes at once (tests, going to background).
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    final file = _file;
    if (file == null) return;
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text(), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // No space or rights: the log stays in memory.
    }
  }

  void _schedule() {
    // No log on disk (tests), so there's nothing to write and no timer: a
    // pending `Timer` fails widget tests as a leak.
    if (_file == null) return;
    _debounce?.cancel();
    _debounce = Timer(_flushDelay, flush);
  }

  /// Tells subscribers the new count. In a microtask: log writes come from the
  /// unhandled error handler too, even mid-frame, and changing [count] there
  /// fails the listener with `setState` during build.
  void _bump() {
    if (count.value == _entries.length) return;
    scheduleMicrotask(() => count.value = _entries.length);
  }

  void _trim() {
    if (_entries.length <= kLogMax) return;
    _entries.removeRange(0, _entries.length - kLogMax);
  }

  /// One entry, one line: line breaks collapse, long text is cut. The file's
  /// parsing relies on lines.
  static String _flatten(String message) {
    final one = message.replaceAll(RegExp(r'\s*\n+\s*'), ' · ').trim();
    return one.length <= 500 ? one : '${one.substring(0, 500)}…';
  }
}

void logInfo(String tag, String message, {bool now = false}) =>
    BloomLog.instance.info(tag, message, now: now);

void logWarn(String tag, String message, {bool now = false}) =>
    BloomLog.instance.warn(tag, message, now: now);

void logError(String tag, String message, [Object? cause]) =>
    BloomLog.instance.error(tag, message, cause);
