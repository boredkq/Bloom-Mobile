/// Player session: the queue (`queue`) and its pre-shuffle order (`orig`) as
/// `session_tracks` rows, track snapshots in `tracks`; where we stand and the
/// modes in kv `session`: `{index, id, pos (s), source, shuffle, repeat
/// (0/1/2), ended, playing, at, cleared}`.
///
/// The `full` list is the queue before clearing: clearing leaves the one
/// playing track, and a resume brings all back.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/db/track_store.dart';
import '../../core/entities/entities.dart';
import '../../core/log/bloom_log.dart';
import '../../core/store/library_store.dart' show libraryProvider;
import 'play_source.dart';
import 'player_controller.dart' show PlayerRepeat;

const String kSessionKey = 'session';

@immutable
class SessionData {
  const SessionData({
    required this.queue,
    required this.index,
    required this.position,
    required this.savedAt,
    this.orig = const [],
    this.full = const [],
    this.source,
    this.shuffle = false,
    this.repeat = PlayerRepeat.off,
    this.ended = false,
    this.playing = false,
    this.cleared = false,
  });

  /// Not empty, or there's no session at all.
  final List<Track> queue;

  /// Pre-shuffle order; empty with no shuffle.
  final List<Track> orig;

  /// Queue before clearing; empty if not cleared.
  final List<Track> full;

  final int index;
  final Duration position;
  final DateTime savedAt;
  final PlaySource? source;
  final bool shuffle;
  final PlayerRepeat repeat;

  /// The queue played out with no repeat, standing at the start of the last
  /// track.
  final bool ended;
  final bool playing;

  /// The queue was removed entirely: at launch it doesn't come into the player,
  /// but stays for a resume.
  final bool cleared;

  Track get track => queue[index];

  /// For a resume: the queue before clearing, if any, on the same track. If
  /// that track isn't in it, from the start with no position: the position
  /// belonged to another.
  SessionData forContinue() {
    if (full.isEmpty) return this;
    final at = full.indexWhere((t) => t.id == track.id);
    return SessionData(
      queue: full,
      index: at < 0 ? 0 : at,
      position: at < 0 ? Duration.zero : position,
      savedAt: savedAt,
      source: source,
      shuffle: shuffle,
      repeat: repeat,
    );
  }
}

final sessionProvider = NotifierProvider<SessionStore, SessionData?>(
  SessionStore.new,
);

/// Writes and reads the session. State is the last written session.
class SessionStore extends Notifier<SessionData?> {
  BloomDb get _db => ref.read(dbProvider);

  /// Ids whose snapshots are in `tracks` since this launch: the queue is
  /// rewritten per edit, but snapshots only for new tracks.
  final Set<String> _stored = {};

  List<Track> _queue = const [], _orig = const [], _full = const [];

  @override
  SessionData? build() {
    _stored.clear();
    final ids = <String, List<String>>{'queue': [], 'orig': [], 'full': []};
    for (final r in _db.select(
      'SELECT list, track_id FROM session_tracks ORDER BY list, pos',
    )) {
      ids[r['list'] as String]?.add(r['track_id'] as String);
    }
    final store = TrackStore(_db);
    // Two ids merged into one (a platform switch) leave a repeat.
    List<Track> load(String list) => store.get(ids[list]!.toSet().toList());
    _queue = load('queue');
    _orig = load('orig');
    _full = load('full');
    for (final list in ids.values) {
      _stored.addAll(list);
    }
    return _read(_db.getMap(kSessionKey));
  }

  SessionData? _read(Map<String, dynamic> s) {
    if (s.isEmpty || _queue.isEmpty) return null;
    final id = s['id'];
    final saved = (s['index'] as num?)?.toInt() ?? 0;
    var index = saved >= 0 && saved < _queue.length && _queue[saved].id == id
        ? saved
        : _queue.indexWhere((t) => t.id == id);
    // The track is gone: the queue place stays, the position doesn't.
    final found = index >= 0;
    if (!found) index = saved.clamp(0, _queue.length - 1);
    return SessionData(
      queue: _queue,
      orig: _orig,
      full: _full,
      index: index,
      position: found
          ? Duration(milliseconds: (((s['pos'] as num?) ?? 0) * 1000).round())
          : Duration.zero,
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        (s['at'] as num?)?.toInt() ?? 0,
      ),
      source: PlaySource.fromJson(s['source']),
      shuffle: s['shuffle'] == true,
      repeat:
          PlayerRepeat.values.elementAtOrNull(
            (s['repeat'] as num?)?.toInt() ?? 0,
          ) ??
          PlayerRepeat.off,
      ended: found && s['ended'] == true,
      playing: s['playing'] == true,
      cleared: s['cleared'] == true,
    );
  }

  /// Writes the queue. An empty one isn't written: the rows stay for a resume.
  void saveQueue(List<Track> queue, List<Track>? orig, List<Track>? full) {
    if (queue.isEmpty) return;
    _queue = queue;
    _orig = orig ?? const [];
    _full = full ?? const [];
    final lists = {'queue': _queue, 'orig': _orig, 'full': _full};
    // A snapshot may have vanished since (the track left the library): the
    // write rolls back, and the second go writes all snapshots.
    if (_write(lists)) return;
    _stored.clear();
    _write(lists);
  }

  bool _write(Map<String, List<Track>> lists) {
    final fresh = [
      for (final list in lists.values)
        for (final t in list)
          if (_stored.add(t.id)) t,
    ];
    try {
      _db.tx(() {
        TrackStore(_db).put(fresh);
        _db.exec('DELETE FROM session_tracks');
        final ins = _db.prepare(
          'INSERT INTO session_tracks (list, pos, track_id) VALUES (?, ?, ?)',
        );
        try {
          lists.forEach((list, tracks) {
            for (var i = 0; i < tracks.length; i++) {
              ins.execute([list, i, tracks[i].id]);
            }
          });
        } finally {
          ins.close();
        }
      });
    } on Object catch (e) {
      logWarn('session', 'очередь не записана: $e');
    }
    return _db.value('SELECT count(*) FROM session_tracks WHERE list = ?', [
          'queue',
        ]) ==
        lists['queue']!.length;
  }

  /// Writes where we stand. The queue must already be written by [saveQueue].
  void saveState({
    required int index,
    required Duration position,
    required PlaySource? source,
    required bool shuffle,
    required PlayerRepeat repeat,
    required bool ended,
    required bool playing,
  }) {
    if (index < 0 || index >= _queue.length) return;
    _db.set(kSessionKey, {
      'index': index,
      'id': _queue[index].id,
      'pos': (position.inMilliseconds / 100).round() / 10,
      'source': source == null ? <String, dynamic>{} : _sourceJson(source),
      'shuffle': shuffle,
      'repeat': repeat.index,
      'ended': ended,
      'playing': playing,
      'at': BloomDb.now(),
    });
    state = _read(_db.getMap(kSessionKey));
  }

  /// The queue was removed entirely (the last track swiped): at launch it
  /// doesn't come up, but the rows stay for a resume.
  void markCleared() {
    final s = _db.getMap(kSessionKey);
    if (s.isEmpty || s['cleared'] == true) return;
    _db.set(kSessionKey, {...s, 'cleared': true});
    state = _read(_db.getMap(kSessionKey));
  }

  /// An own list is named in the map with the card's name and picture: another
  /// device won't ask the library.
  Map<String, dynamic> _sourceJson(PlaySource source) {
    final m = source.toJson();
    if (source is! LibSource) return m;
    final lib = ref.read(libraryProvider);
    for (final p in lib.playlists) {
      if (p.id != source.listId) continue;
      return {
        ...m,
        'name': p.name,
        'cover': p.cover ?? '',
        'covers': [
          for (final t in lib.tracksOf(p).take(4))
            if (t.cover != null) t.cover,
        ],
      };
    }
    return m;
  }
}
