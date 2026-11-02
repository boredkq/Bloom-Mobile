/// Play log, the only store of what was played when: the `plays` table. One row
/// per counted play; history, profile stats, wave seeds and Wrapped all derive
/// from it, with no counters elsewhere.
///
/// A track's snapshot (title, cover, duration) lies in the database's `tracks`:
/// it's needed a year on, when the track has long left the library.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../db/track_store.dart';
import '../entities/entities.dart';

/// The log's clock, for tests.
final playLogClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// One counted play.
@immutable
class PlayEvent {
  const PlayEvent(this.ts, this.id);

  /// When the play was counted (90% of the track or its end).
  final int ts;
  final String id;
}

@immutable
class PlayLog {
  const PlayLog({this.events = const [], this.tracks = const {}});

  /// All events, by ascending `ts`.
  final List<PlayEvent> events;

  /// Snapshots of all tracks ever played.
  final Map<String, Track> tracks;

  bool get isEmpty => events.isEmpty;
}

final playLogProvider = NotifierProvider<PlayLogController, PlayLog>(
  PlayLogController.new,
);

class PlayLogController extends Notifier<PlayLog> {
  BloomDb get _db => ref.read(dbProvider);

  @override
  PlayLog build() => _read();

  PlayLog _read() {
    final events = [
      for (final r in _db.select('SELECT ts, track_id FROM plays ORDER BY ts'))
        PlayEvent(r['ts'] as int, r['track_id'] as String),
    ];
    final ids = {for (final e in events) e.id}.toList();
    return PlayLog(
      events: events,
      tracks: {for (final t in TrackStore(_db).get(ids)) t.id: t},
    );
  }

  /// Records a play. Called from the player, the one point in the app.
  void log(Track track) {
    if (track.id.isEmpty) return;
    final ts = ref.read(playLogClockProvider)().millisecondsSinceEpoch;
    _db.tx(() {
      TrackStore(_db).put([track]);
      _db.exec('INSERT INTO plays (ts, track_id) VALUES (?, ?)', [
        ts,
        track.id,
      ]);
    });
    state = PlayLog(
      events: [...state.events, PlayEvent(ts, track.id)],
      tracks: {...state.tracks, track.id: track},
    );
  }

  /// Re-reads the log after a platform switch: its plays already moved to the
  /// new id in the database ([TrackStore.rekey]).
  void reload() => state = _read();

  /// Clears the log, part of clearing stats.
  void clear() {
    _db.tx(() {
      _db.exec('DELETE FROM plays');
      TrackStore(_db).prune();
    });
    state = const PlayLog();
  }
}
