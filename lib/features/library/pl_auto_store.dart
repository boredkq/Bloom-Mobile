/// Playlist auto-update. Marked playlists are visited in turn and get new
/// tracks from their sources (`pl.sources`, possibly several, from different
/// platforms), so any playlist with ties is a candidate.
///
/// The mark is the playlist's own flag ([UserPlaylist.autoRefresh]); the
/// schedule (on, period, at launch) is settings; when the last pass was and how
/// it ended per playlist are database kv (`autoRefresh.last`,
/// `autoRefresh.runs`).
///
/// The schedule is a timer inside the process: nothing can wake a closed app.
/// So a pass happens at launch or while the app is open; `lastRun` is on disk,
/// and after a long gap the first tick sees it's overdue.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/db/db.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';
import 'refresh_playlist.dart';

/// Period options, in minutes.
const List<int> kPlAutoIntervals = [30, 60, 180, 720, 1440];

/// kv keys.
const String _kLast = 'autoRefresh.last';
const String _kRuns = 'autoRefresh.runs';

/// Pause before the launch pass: platforms need time to come up.
const Duration _onStartDelay = Duration(seconds: 12);

/// How often I check whether an update is due.
const Duration _tick = Duration(minutes: 1);

/// How the last pass over one playlist ended.
class PlAutoRun {
  const PlAutoRun({required this.at, this.added = 0, this.failed = false});

  final int at;
  final int added;
  final bool failed;

  Map<String, dynamic> toJson() => {
    'at': at,
    'added': added,
    if (failed) 'failed': true,
  };

  static PlAutoRun? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    if (at is! num) return null;
    return PlAutoRun(
      at: at.toInt(),
      added: (json['added'] as num?)?.toInt() ?? 0,
      failed: json['failed'] == true,
    );
  }
}

class PlAutoState {
  const PlAutoState({
    this.enabled = false,
    this.everyMin = 180,
    this.onStart = true,
    this.lastRun = 0,
    this.runs = const {},
    this.busy,
  });

  final bool enabled;
  final int everyMin;
  final bool onStart;

  /// When the last pass ended; the next counts from it.
  final int lastRun;

  /// Last update of each playlist, by hand too.
  final Map<String, PlAutoRun> runs;

  /// A pass is on: `null` is idle, otherwise the updating playlist's id (an
  /// empty string means it just started).
  final String? busy;

  bool get running => busy != null;

  PlAutoState copyWith({
    bool? enabled,
    int? everyMin,
    bool? onStart,
    int? lastRun,
    Map<String, PlAutoRun>? runs,
    String? busy,
    bool clearBusy = false,
  }) => PlAutoState(
    enabled: enabled ?? this.enabled,
    everyMin: everyMin ?? this.everyMin,
    onStart: onStart ?? this.onStart,
    lastRun: lastRun ?? this.lastRun,
    runs: runs ?? this.runs,
    busy: clearBusy ? null : (busy ?? this.busy),
  );
}

/// A pass's result, for those who started it by hand.
class PlAutoSweep {
  const PlAutoSweep({
    this.added = 0,
    this.changed = 0,
    this.failed = 0,
    this.skipped = false,
  });

  /// Total tracks added.
  final int added;

  /// Playlists in which something appeared.
  final int changed;

  final int failed;

  /// The pass didn't start: nothing to update, or one is running.
  final bool skipped;
}

final plAutoProvider = NotifierProvider<PlAutoController, PlAutoState>(
  PlAutoController.new,
);

class PlAutoController extends Notifier<PlAutoState> {
  Timer? _timer;
  bool _scheduled = false;

  BloomDb get _db => ref.read(dbProvider);

  @override
  PlAutoState build() {
    final raw = ref.read(jsonStoreProvider).readMap('plAuto');
    final everyMin = (raw['everyMin'] as num?)?.toInt();
    // Playlists that are gone get forgotten.
    final alive = {for (final p in ref.read(libraryProvider).playlists) p.id};
    final saved = _db.getMap(_kRuns);
    final runs = <String, PlAutoRun>{};
    saved.forEach((id, value) {
      final run = PlAutoRun.fromJson(value);
      if (alive.contains(id) && run != null) runs[id] = run;
    });
    if (runs.length != saved.length) _saveRuns(runs);
    return PlAutoState(
      enabled: raw['enabled'] == true,
      everyMin: everyMin != null && everyMin >= 5 ? everyMin : 180,
      onStart: raw['onStart'] != false,
      lastRun: (_db.get(_kLast) as num?)?.toInt() ?? 0,
      runs: runs,
    );
  }

  void _saveSettings() => ref.read(jsonStoreProvider).write('plAuto', {
    'enabled': state.enabled,
    'everyMin': state.everyMin,
    'onStart': state.onStart,
  });

  void _saveRuns(Map<String, PlAutoRun> runs) =>
      _db.set(_kRuns, {for (final e in runs.entries) e.key: e.value.toJson()});

  void _setLastRun(int at) {
    state = state.copyWith(lastRun: at);
    _db.set(_kLast, at);
  }

  /// Remembers how a playlist's update ended: a `null` [added] means no source
  /// answered. Updates by hand count too.
  void record(String id, int? added) {
    final runs = {
      ...state.runs,
      id: PlAutoRun(
        at: DateTime.now().millisecondsSinceEpoch,
        added: added ?? 0,
        failed: added == null,
      ),
    };
    state = state.copyWith(runs: runs);
    _saveRuns(runs);
  }

  // ── Settings ────────────────────────────────────────────────────────────

  /// Turning on moves the count, or a library long without updates would start
  /// a pass as the switch is pressed.
  void setEnabled(bool value) {
    state = state.copyWith(enabled: value);
    if (value) _setLastRun(DateTime.now().millisecondsSinceEpoch);
    _saveSettings();
  }

  void setEveryMin(int min) {
    state = state.copyWith(everyMin: min);
    _saveSettings();
  }

  void setOnStart(bool value) {
    state = state.copyWith(onStart: value);
    _saveSettings();
  }

  // ── Targets ─────────────────────────────────────────────────────────────

  /// Playlists with somewhere to pull tracks from.
  List<UserPlaylist> candidates() => ref
      .read(libraryProvider)
      .playlists
      .where((p) => p.sources.isNotEmpty)
      .toList();

  /// Those marked for auto-update.
  List<UserPlaylist> targets() =>
      candidates().where((p) => p.autoRefresh).toList();

  // ── Pass ────────────────────────────────────────────────────────────────

  /// Visits the marked playlists in turn. [silent] is a scheduled pass, quiet
  /// until it finds something. One started by hand shows a live progress toast.
  Future<PlAutoSweep> runSweep({bool silent = false}) async {
    if (state.running) return const PlAutoSweep(skipped: true);
    final targets = this.targets();
    if (targets.isEmpty) return const PlAutoSweep(skipped: true);

    final messenger = bloomMessengerKey.currentState;
    // A scheduled pass speaks from a timer with no screen of its own, so the
    // language comes from the global messenger (see `globalL10n`).
    final l10n = globalL10n;
    final toast = silent || l10n == null
        ? null
        : messenger?.busyToast(l10n.paBusy(targets.length));

    state = state.copyWith(busy: '');
    final registry = ref.read(registryProvider);
    final library = ref.read(libraryProvider.notifier);
    var added = 0;
    var changed = 0;
    var failed = 0;

    try {
      for (var i = 0; i < targets.length; i++) {
        final pl = targets[i];
        state = state.copyWith(busy: pl.id);
        toast?.update(
          l10n!.paProgress(i + 1, targets.length),
          progress: i / targets.length,
        );
        final got = await refreshPlaylistFromSource(registry, library, pl);
        record(pl.id, got);
        if (got == null) {
          failed++;
          continue;
        }
        added += got;
        if (got > 0) changed++;
      }
    } finally {
      state = state.copyWith(clearBusy: true);
      _setLastRun(DateTime.now().millisecondsSinceEpoch);
    }

    final result = PlAutoSweep(added: added, changed: changed, failed: failed);
    if (l10n == null) return result;
    if (added > 0) {
      final text = l10n.paNewTracks(added, changed);
      toast == null
          ? messenger?.toast(text, kind: ToastKind.success)
          : toast.finish(text);
    } else if (failed > 0) {
      final text = l10n.paFailed(failed);
      toast == null
          ? messenger?.toast(text, kind: ToastKind.warn)
          : toast.finish(text, kind: ToastKind.warn);
    } else {
      toast?.finish(l10n.paNoNewTracks, kind: ToastKind.info);
    }
    return result;
  }

  // ── Schedule ────────────────────────────────────────────────────────────

  /// Starts the background timer. Idempotent, called once from `main`.
  void startScheduler() {
    if (_scheduled) return;
    _scheduled = true;

    if (state.enabled && state.onStart) {
      Timer(_onStartDelay, () {
        if (state.enabled) unawaited(runSweep(silent: true));
      });
    }

    _timer = Timer.periodic(_tick, (_) {
      if (!state.enabled) return;
      final due =
          DateTime.now().millisecondsSinceEpoch - state.lastRun >=
          state.everyMin * 60 * 1000;
      if (due) unawaited(runSweep(silent: true));
    });
    ref.onDispose(() => _timer?.cancel());
  }
}
