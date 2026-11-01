/// The database side of sync: what to give another of the listener's devices
/// and how to take what it sent; the network only carries maps. The map format
/// is shared: change it on both sides together.
///
/// Shared things (playlists, tracks in lists, follows, dislikes, profile,
/// hand-edited tags) are marked in `changes`, and the later change wins; plays
/// and days belong to their device and are only copied. Local files don't
/// travel.
library;

import 'dart:convert';
import 'dart:math';

import '../db/db.dart';
import '../db/track_store.dart';
import '../log/bloom_log.dart';
import '../store/days_store.dart' show dayKey;

const String _kDevice = 'sync.device';
const String _kGot = 'sync.got';
const String _kCleared = 'stats.cleared';
const String _kSince = 'profile.since';
const int _kFormat = 1;
const String _tab = '\t';

/// Kinds in order of taking: a track before what's on it, a playlist before its
/// tracks, a move to a new id before lists see it.
const List<String> _kOrder = [
  'kv',
  'track',
  'list',
  'rekey',
  'item',
  'follow',
  'dislike',
];

bool _isLocal(String trackId) => trackId.startsWith('lf:');

/// JSON numbers: an integer can come as double.
int _int(Object? v) => v is num ? v.toInt() : 0;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

String _before(String key) {
  final i = key.indexOf(_tab);
  return i < 0 ? key : key.substring(0, i);
}

String _after(String key) {
  final i = key.indexOf(_tab);
  return i < 0 ? '' : key.substring(i + 1);
}

class SyncLog {
  const SyncLog(this.db);

  final BloomDb db;

  /// This device's id, made on first use (a new database is a new device).
  String device() {
    final have = db.get(_kDevice);
    if (have is String && have.isNotEmpty) return have;
    final rnd = Random.secure();
    final id = [
      for (var i = 0; i < 16; i++)
        rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    db.set(_kDevice, id);
    return id;
  }

  /// What goes to [peer]: changes after cursor [seq], plays after cursor [play]
  /// (at most [limit] each; `more` means ask again from the returned cursors),
  /// all app days and the tracks all this refers to. [ownOnly] is only what was
  /// made here: the phone sends so, while the computer passes on what others
  /// sent too.
  Map<String, Object?> outgoing(
    String peer, {
    int seq = 0,
    int play = 0,
    bool ownOnly = false,
    int limit = 2000,
  }) {
    final me = device();
    String origin(Object? d) => _str(d).isEmpty ? me : d as String;
    final own = ownOnly ? 1 : 0;

    final changes = <Map<String, Object?>>[];
    final refs = <String>[];
    final lists = <String>{}, listed = <String>{};
    var lastSeq = seq;
    final scanned = db.select(
      '''SELECT seq, kind, key, mod, device FROM changes
        WHERE seq > ? AND device != ? AND (? = 0 OR device = '') ORDER BY seq LIMIT ?''',
      [seq, peer, own, limit],
    );
    for (final c in scanned) {
      lastSeq = c['seq'] as int;
      final kind = c['kind'] as String, key = c['key'] as String;
      final out = _rowFor(kind, key, refs);
      if (out == null) continue;
      if (out.list != null) lists.add(out.list!);
      if (kind == 'list') listed.add(key);
      changes.add({
        'kind': kind,
        'key': key,
        'mod': c['mod'],
        'device': origin(c['device']),
        'row': out.row,
      });
    }
    // A playlist's track travels with the playlist, or the other side may not
    // know where to put it: the playlist's change may be past this round or
    // already there.
    for (final id in lists) {
      if (listed.contains(id)) continue;
      final c = db.select(
        "SELECT mod, device FROM changes WHERE kind = 'list' AND key = ?",
        [id],
      );
      final out = _rowFor('list', id, refs);
      if (c.isEmpty || out == null || out.row == null) continue;
      changes.insert(0, {
        'kind': 'list',
        'key': id,
        'mod': c.first['mod'],
        'device': origin(c.first['device']),
        'row': out.row,
      });
    }

    final plays = <Map<String, Object?>>[];
    var lastPlay = play;
    for (final p in db.select(
      '''SELECT id, ts, track_id, device FROM plays
        WHERE id > ? AND device != ? AND (? = 0 OR device = '') AND track_id NOT LIKE 'lf:%' ORDER BY id LIMIT ?''',
      [play, peer, own, limit],
    )) {
      lastPlay = p['id'] as int;
      refs.add(p['track_id'] as String);
      plays.add({
        'ts': p['ts'],
        'track': p['track_id'],
        'device': origin(p['device']),
      });
    }

    final days = [
      for (final d in db.select(
        "SELECT day, device, app_ms FROM days WHERE device != ? AND (? = 0 OR device = '')",
        [peer, own],
      ))
        {'day': d['day'], 'device': origin(d['device']), 'app_ms': d['app_ms']},
    ];

    final tracks = <Map<String, Object?>>[];
    final ids = refs.toSet().toList();
    const chunk = 500;
    for (var at = 0; at < ids.length; at += chunk) {
      final part = ids.sublist(at, min(at + chunk, ids.length));
      for (final t in db.select(
        'SELECT id, provider, title, artist, album, cover, duration, extra, updated_at FROM tracks WHERE id IN (${List.filled(part.length, '?').join(',')})',
        part,
      )) {
        tracks.add(Map<String, Object?>.of(t));
      }
    }

    return {
      'v': _kFormat,
      'device': me,
      'seq': lastSeq,
      'play': lastPlay,
      'more': scanned.length == limit || plays.length == limit,
      'changes': changes,
      'tracks': tracks,
      'plays': plays,
      'days': days,
    };
  }

  /// Takes what [outgoing] gave on another device, in one transaction, and
  /// remembers its cursors ([got]). [touched] gets kinds changed here: list,
  /// item, follow, dislike, kv, track, rekey, plays, days. `false`: the parcel
  /// isn't for us (broken or our own).
  bool apply(Map<String, Object?> payload, {Set<String>? touched}) {
    final me = device();
    final from = _str(payload['device']);
    if (_int(payload['v']) != _kFormat || from.isEmpty || from == me) {
      logWarn('sync', 'payload refused: format ${payload['v']} from $from');
      return false;
    }

    final did = <String>{};
    final moves = _Moves(db);
    final changes = (payload['changes'] as List?) ?? const [];
    final plays = (payload['plays'] as List?) ?? const [];
    db.tx(() {
      var cleared = false;

      // Tracks as they are there, for what's missing here; a known one keeps
      // its own.
      for (final v in (payload['tracks'] as List?) ?? const []) {
        if (v is! Map) continue;
        final id = _str(v['id']);
        if (id.isEmpty || _isLocal(id) || moves.of(id) != id) continue;
        db.exec(
          '''INSERT OR IGNORE INTO tracks (id, provider, title, artist, album, cover, duration, extra, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            id,
            _str(v['provider']),
            _str(v['title']),
            _str(v['artist']),
            _str(v['album']),
            _str(v['cover']),
            (v['duration'] as num?)?.toDouble() ?? 0,
            _str(v['extra'], '{}'),
            _int(v['updated_at']),
          ],
        );
      }

      for (final kind in _kOrder) {
        for (final v in changes) {
          if (v is! Map || v['kind'] != kind) continue;
          final row = v['row'];
          final mod = _int(v['mod']);
          final by = _str(v['device']);
          final key = _movedKey(kind, _str(v['key']), row == null, moves);
          if (key.isEmpty || by.isEmpty || by == me) continue;
          if (kind == 'kv' && key == _kSince) {
            if (_takeSince(row, mod, by)) did.add(kind);
            continue;
          }
          if (!_newer(kind, key, mod, by, me)) continue;
          final wrote = _write(kind, key, row is Map ? row : null, row == null);
          if (wrote == null) continue;
          if (wrote) cleared = true;
          _stamp(kind, key, mod, by);
          did.add(kind);
        }
        if (kind == 'rekey') moves.forget();
      }

      final clearedAt = _int(db.getMap(_kCleared)['at']);
      final before = db.value('SELECT count(*) FROM plays') as int;
      for (final v in plays) {
        if (v is! Map) continue;
        final ts = _int(v['ts']);
        final track = moves.of(_str(v['track']));
        final by = _str(v['device']);
        if (by.isEmpty ||
            by == me ||
            track.isEmpty ||
            _isLocal(track) ||
            ts < clearedAt) {
          continue;
        }
        db.exec(
          '''INSERT INTO plays (ts, track_id, device) SELECT ?, ?, ?
            WHERE NOT EXISTS (SELECT 1 FROM plays WHERE device = ? AND ts = ?) AND EXISTS (SELECT 1 FROM tracks WHERE id = ?)''',
          [ts, track, by, by, ts, track],
        );
      }
      if (db.value('SELECT count(*) FROM plays') != before) did.add('plays');

      final clearedDay = clearedAt > 0
          ? dayKey(DateTime.fromMillisecondsSinceEpoch(clearedAt))
          : '';
      for (final v in (payload['days'] as List?) ?? const []) {
        if (v is! Map) continue;
        final day = _str(v['day']), by = _str(v['device']);
        if (day.isEmpty ||
            by.isEmpty ||
            by == me ||
            day.compareTo(clearedDay) < 0) {
          continue;
        }
        db.exec(
          '''INSERT INTO days (day, device, app_ms) VALUES (?, ?, ?)
            ON CONFLICT(day, device) DO UPDATE SET app_ms = excluded.app_ms WHERE excluded.app_ms > app_ms''',
          [day, by, _int(v['app_ms'])],
        );
        if (db.changes > 0) did.add('days');
      }

      if (cleared) TrackStore(db).prune();

      final all = db.getMap(_kGot);
      all[from] = {'seq': _int(payload['seq']), 'play': _int(payload['play'])};
      db.set(_kGot, all);
    });
    if (!db.committed) return false;
    touched?.addAll(did);
    logInfo(
      'sync',
      'took from ${from.substring(0, min(8, from.length))} · ${changes.length} changes, ${plays.length} plays · ${did.join(' ')}',
    );
    return true;
  }

  /// How far [peer]'s parcels got.
  ({int seq, int play}) got(String peer) {
    final at = db.getMap(_kGot)[peer];
    return at is Map
        ? (seq: _int(at['seq']), play: _int(at['play']))
        : (seq: 0, play: 0);
  }

  /// How far [outgoing] would go for [peer]. With [ownOnly], only what was made
  /// here: past the computer's cursor means there's something to give.
  ({int seq, int play}) head(String peer, {bool ownOnly = false}) {
    final own = ownOnly ? 1 : 0;
    // From the end: the scan stops at the first fitting row.
    return (
      seq: _int(
        db.value(
          "SELECT seq FROM changes WHERE device != ? AND (? = 0 OR device = '') ORDER BY seq DESC LIMIT 1",
          [peer, own],
        ),
      ),
      play: _int(
        db.value(
          "SELECT id FROM plays WHERE device != ? AND (? = 0 OR device = '') AND track_id NOT LIKE 'lf:%' ORDER BY id DESC LIMIT 1",
          [peer, own],
        ),
      ),
    );
  }

  /// For writes triggers don't see as one change: a track moved to a new id,
  /// and the stats clear ([banked] is XP kept for the level).
  void markRekey(String from, String to) =>
      db.exec("INSERT INTO stamp VALUES ('rekey', ?)", ['$from$_tab$to']);

  void markCleared(int banked) =>
      db.set(_kCleared, {'at': BloomDb.now(), 'banked': banked});

  // ── Internal ────────────────────────────────────────────────────────────

  Map<String, Object?>? _one(String sql, List<Object?> args) {
    final rows = db.select(sql, args);
    return rows.isEmpty ? null : Map<String, Object?>.of(rows.first);
  }

  bool _exists(String table, String id) =>
      db.value('SELECT 1 FROM $table WHERE id = ?', [id]) != null;

  void _stamp(String kind, String key, int mod, String device) {
    db.exec('DELETE FROM changes WHERE kind = ? AND key = ?', [kind, key]);
    db.exec(
      'INSERT INTO changes (kind, key, mod, device) VALUES (?, ?, ?, ?)',
      [kind, key, mod, device],
    );
  }

  /// The thing as it is now, for an outgoing change; `null` if it doesn't
  /// travel. [tracks] gets the tracks it refers to.
  ({Map<String, Object?>? row, String? list})? _rowFor(
    String kind,
    String key,
    List<String> tracks,
  ) {
    switch (kind) {
      case 'list':
        return (
          row: _one(
            'SELECT kind, name, description, cover, sources, auto_refresh, created_at, updated_at, side_pos, pinned FROM lists WHERE id = ?',
            [key],
          ),
          list: null,
        );
      case 'item':
        final l = _before(key), t = _after(key);
        if (_isLocal(t)) return null;
        final row = _one(
          'SELECT pos, added_at FROM list_tracks WHERE list_id = ? AND track_id = ?',
          [l, t],
        );
        if (row != null) tracks.add(t);
        return (row: row, list: row != null ? l : null);
      case 'follow':
        return (
          row: _one(
            'SELECT provider, name, avatar, extra, at, side_pos, pinned FROM follows WHERE id = ?',
            [key],
          ),
          list: null,
        );
      case 'dislike':
        if (_isLocal(key)) return null;
        final row = _one('SELECT at FROM dislikes WHERE track_id = ?', [key]);
        if (row != null) tracks.add(key);
        return (row: row, list: null);
      case 'kv':
        return (
          row: _one('SELECT value FROM kv WHERE key = ?', [key]),
          list: null,
        );
      case 'track':
        if (_isLocal(key)) return null;
        return (
          row: _one(
            'SELECT provider, title, artist, album, cover, duration, extra, updated_at FROM tracks WHERE id = ?',
            [key],
          ),
          list: null,
        );
      case 'rekey':
        final to = _after(key);
        if (_isLocal(_before(key)) || _isLocal(to)) return null;
        tracks.add(to);
        return (row: const <String, Object?>{}, list: null);
    }
    return null;
  }

  /// Whether the change from [mod] on [device] is later than what's here. For
  /// the same moment on two devices the larger id wins, the same on both.
  bool _newer(String kind, String key, int mod, String device, String me) {
    final rows = db.select(
      'SELECT mod, device FROM changes WHERE kind = ? AND key = ?',
      [kind, key],
    );
    if (rows.isEmpty) return true;
    final have = rows.first['mod'] as int;
    final d = rows.first['device'] as String;
    final by = d.isEmpty ? me : d;
    return mod > have || (mod == have && device.compareTo(by) > 0);
  }

  /// A change's key with the track where it moved here; empty means nothing to
  /// take (deletion of an old id: the move already did it).
  String _movedKey(String kind, String key, bool gone, _Moves moves) {
    final item = kind == 'item';
    if (!item && kind != 'dislike' && kind != 'track') return key;
    final track = item ? _after(key) : key;
    final to = moves.of(track);
    if (to == track) return key;
    if (gone) return '';
    return item ? '${_before(key)}$_tab$to' : to;
  }

  /// Writes one change from another device. `null` if not taken, `true` if it
  /// was the stats clear (track cleanup follows).
  bool? _write(String kind, String key, Map? r, bool gone) {
    switch (kind) {
      case 'list':
        if (gone) {
          db.exec(
            "DELETE FROM lists WHERE id = ? AND kind NOT IN ('lib', 'fav')",
            [key],
          );
          return false;
        }
        final lk = _str(r!['kind']);
        if (lk.isEmpty || lk == 'lib' || lk == 'fav') return null;
        db.exec(
          '''INSERT INTO lists (id, kind, name, description, cover, sources, auto_refresh, created_at, updated_at, side_pos, pinned)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, description = excluded.description, cover = excluded.cover,
                sources = excluded.sources, auto_refresh = excluded.auto_refresh, updated_at = excluded.updated_at,
                side_pos = excluded.side_pos, pinned = excluded.pinned''',
          [
            key,
            lk,
            _str(r['name']),
            _str(r['description']),
            _str(r['cover']),
            _str(r['sources'], '[]'),
            _int(r['auto_refresh']),
            _int(r['created_at']),
            _int(r['updated_at']),
            _int(r['side_pos']),
            _int(r['pinned']),
          ],
        );
        return false;
      case 'item':
        final l = _before(key), t = _after(key);
        if (_isLocal(t)) return null;
        if (gone) {
          db.exec(
            'DELETE FROM list_tracks WHERE list_id = ? AND track_id = ?',
            [l, t],
          );
          return false;
        }
        if (!_exists('lists', l) || !_exists('tracks', t)) return null;
        db.exec(
          '''INSERT INTO list_tracks (list_id, track_id, pos, added_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(list_id, track_id) DO UPDATE SET pos = excluded.pos, added_at = excluded.added_at''',
          [l, t, _int(r!['pos']), _int(r['added_at'])],
        );
        return false;
      case 'follow':
        if (gone) {
          db.exec('DELETE FROM follows WHERE id = ?', [key]);
          return false;
        }
        db.exec(
          '''INSERT INTO follows (id, provider, name, avatar, extra, at, side_pos, pinned) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET provider = excluded.provider, name = excluded.name, avatar = excluded.avatar,
                extra = excluded.extra, at = excluded.at, side_pos = excluded.side_pos, pinned = excluded.pinned''',
          [
            key,
            _str(r!['provider']),
            _str(r['name']),
            _str(r['avatar']),
            _str(r['extra'], '{}'),
            _int(r['at']),
            _int(r['side_pos']),
            _int(r['pinned']),
          ],
        );
        return false;
      case 'dislike':
        if (_isLocal(key)) return null;
        if (gone) {
          db.exec('DELETE FROM dislikes WHERE track_id = ?', [key]);
          return false;
        }
        if (!_exists('tracks', key)) return null;
        db.exec(
          'INSERT INTO dislikes (track_id, at) VALUES (?, ?) ON CONFLICT(track_id) DO UPDATE SET at = excluded.at',
          [key, _int(r!['at'])],
        );
        return false;
      case 'kv':
        if (key != 'profile' && key != _kCleared) return null;
        if (gone) {
          db.exec('DELETE FROM kv WHERE key = ?', [key]);
          return false;
        }
        db.exec(
          'INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key, _str(r!['value'])],
        );
        if (key != _kCleared) return false;
        final c = db.getMap(_kCleared);
        _clearBefore(_int(c['at']), _int(c['banked']));
        return true;
      case 'track':
        if (gone || _isLocal(key)) return null;
        db.exec(
          '''INSERT INTO tracks (id, provider, title, artist, album, cover, duration, extra, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET provider = excluded.provider, title = excluded.title, artist = excluded.artist,
                album = excluded.album, cover = excluded.cover, duration = excluded.duration, extra = excluded.extra,
                updated_at = excluded.updated_at''',
          [
            key,
            _str(r!['provider']),
            _str(r['title']),
            _str(r['artist']),
            _str(r['album']),
            _str(r['cover']),
            (r['duration'] as num?)?.toDouble() ?? 0,
            _str(r['extra'], '{}'),
            _int(r['updated_at']),
          ],
        );
        return false;
      case 'rekey':
        final from = _before(key), to = _after(key);
        if (_isLocal(from) || _isLocal(to)) return null;
        // Unknown here: nothing to move, but it's passed on.
        if (_exists('tracks', from)) TrackStore(db).rekey(from, to);
        return false;
    }
    return null;
  }

  /// What a stats clear on another device also removes here.
  void _clearBefore(int at, int banked) {
    db.exec('DELETE FROM plays WHERE ts < ?', [at]);
    db.exec(
      "DELETE FROM days WHERE day < date(? / 1000, 'unixepoch', 'localtime')",
      [at],
    );
    db.set('level.banked', banked);
    db.set('ach.at', <String, Object?>{});
  }

  /// Member since takes the earlier of the two, whoever wrote last.
  bool _takeSince(Object? row, int mod, String device) {
    var theirs = 0;
    if (row is Map) {
      try {
        final wrapped = jsonDecode(_str(row['value']));
        if (wrapped is List && wrapped.isNotEmpty) theirs = _int(wrapped.first);
      } catch (_) {}
    }
    final ours = _int(db.get(_kSince, 0));
    if (theirs <= 0 || (ours > 0 && ours <= theirs)) return false;
    db.set(_kSince, theirs);
    _stamp('kv', _kSince, mod, device);
    return true;
  }
}

/// Where a track's id went here: by its moves, each later than the last (a→b,
/// then b→a is a again). Late news of an old id (a play, a like made before the
/// other side heard of the move) lands on the new one.
class _Moves {
  _Moves(this.db);

  final BloomDb db;
  final Map<String, String> _seen = {};

  String of(String id) {
    final known = _seen[id];
    if (known != null) return known;
    var at = id;
    var after = 0;
    for (var step = 0; step < 16; step++) {
      final rows = db.select(
        '''SELECT seq, key FROM changes WHERE kind = 'rekey' AND key >= ? AND key < ? AND seq > ?
            ORDER BY seq DESC LIMIT 1''',
        ['$at$_tab', '$at\n', after],
      );
      if (rows.isEmpty) break;
      after = rows.first['seq'] as int;
      at = _after(rows.first['key'] as String);
    }
    return _seen[id] = at;
  }

  /// After new moves arrive.
  void forget() => _seen.clear();
}
