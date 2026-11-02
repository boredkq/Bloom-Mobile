/// The listener's database, `bloom.db`, SQLite. The schema, tables and `kv` are
/// shared across devices, so data on each is one model.
///
/// Holds tracks, library and playlists, likes, follows, the play log, days,
/// dislikes, the session, offline and the lyrics cache. Settings and platform
/// logins stay out: they belong to each device.
///
/// The API is synchronous: a write is one WAL insert, and stores answer the UI
/// right away with no loading states.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../log/bloom_log.dart';
import '../store/app_dirs.dart';

/// Schema steps. A released step is never edited, the next goes at the end;
/// version numbers are shared across devices.
///
/// Ids are track ids (`sc:123`, `lf:…`). Whatever refers to a track does so
/// through tracks(id) ON UPDATE CASCADE, so a new id carries likes, list places
/// and plays along. A new table with track_id also goes in [TrackStore.rekey]
/// and [TrackStore.prune].
///
/// This app has no folders, so `folders` and `files` go unused, but the schema
/// is shared: one version number and one layout.
const List<List<String>> kMigrations = [
  [
    '''CREATE TABLE tracks (
            id TEXT PRIMARY KEY,
            provider TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            artist TEXT NOT NULL DEFAULT '',
            album TEXT NOT NULL DEFAULT '',
            cover TEXT NOT NULL DEFAULT '',
            duration REAL NOT NULL DEFAULT 0,
            extra TEXT NOT NULL DEFAULT '{}',
            updated_at INTEGER NOT NULL
        ) WITHOUT ROWID''',
    '''CREATE TABLE folders (
            path TEXT PRIMARY KEY COLLATE NOCASE,
            copied INTEGER NOT NULL DEFAULT 0,
            added_at INTEGER NOT NULL,
            side_pos INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0
        ) WITHOUT ROWID''',
    '''CREATE TABLE files (
            path TEXT PRIMARY KEY COLLATE NOCASE,
            track_id TEXT NOT NULL REFERENCES tracks(id) ON UPDATE CASCADE ON DELETE CASCADE,
            folder TEXT REFERENCES folders(path) ON UPDATE CASCADE ON DELETE CASCADE,
            size INTEGER NOT NULL,
            mtime INTEGER NOT NULL
        ) WITHOUT ROWID''',
    'CREATE INDEX files_track ON files(track_id)',
    'CREATE INDEX files_folder ON files(folder)',
    '''CREATE TABLE lists (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            cover TEXT NOT NULL DEFAULT '',
            sources TEXT NOT NULL DEFAULT '[]',
            auto_refresh INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            side_pos INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0
        ) WITHOUT ROWID''',
    '''CREATE TABLE list_tracks (
            list_id TEXT NOT NULL REFERENCES lists(id) ON UPDATE CASCADE ON DELETE CASCADE,
            track_id TEXT NOT NULL REFERENCES tracks(id) ON UPDATE CASCADE ON DELETE CASCADE,
            pos INTEGER NOT NULL,
            added_at INTEGER NOT NULL,
            PRIMARY KEY (list_id, track_id)
        ) WITHOUT ROWID''',
    'CREATE INDEX list_tracks_order ON list_tracks(list_id, pos)',
    'CREATE INDEX list_tracks_track ON list_tracks(track_id)',
    '''CREATE TABLE plays (
            ts INTEGER NOT NULL,
            track_id TEXT NOT NULL REFERENCES tracks(id) ON UPDATE CASCADE ON DELETE CASCADE
        )''',
    'CREATE INDEX plays_ts ON plays(ts)',
    'CREATE INDEX plays_track ON plays(track_id, ts)',
    '''CREATE TABLE follows (
            id TEXT PRIMARY KEY,
            provider TEXT NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            avatar TEXT NOT NULL DEFAULT '',
            extra TEXT NOT NULL DEFAULT '{}',
            at INTEGER NOT NULL,
            side_pos INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0
        ) WITHOUT ROWID''',
    'CREATE TABLE loudness (track_id TEXT PRIMARY KEY, lufs REAL NOT NULL) WITHOUT ROWID',
    '''CREATE TABLE lyrics (
            key TEXT PRIMARY KEY,
            synced TEXT NOT NULL DEFAULT '',
            plain TEXT NOT NULL DEFAULT '',
            source TEXT NOT NULL DEFAULT '',
            at INTEGER NOT NULL
        ) WITHOUT ROWID''',
    '''CREATE TABLE session_tracks (
            list TEXT NOT NULL,
            pos INTEGER NOT NULL,
            track_id TEXT NOT NULL REFERENCES tracks(id) ON UPDATE CASCADE ON DELETE CASCADE,
            PRIMARY KEY (list, pos)
        ) WITHOUT ROWID''',
    'CREATE INDEX session_tracks_track ON session_tracks(track_id)',
    '''CREATE TABLE days (
            day TEXT PRIMARY KEY,
            app_ms INTEGER NOT NULL DEFAULT 0
        ) WITHOUT ROWID''',
    '''CREATE TABLE dislikes (
            track_id TEXT PRIMARY KEY REFERENCES tracks(id) ON UPDATE CASCADE ON DELETE CASCADE,
            at INTEGER NOT NULL
        ) WITHOUT ROWID''',
    'CREATE TABLE wave_shown (track_id TEXT PRIMARY KEY, at INTEGER NOT NULL) WITHOUT ROWID',
    '''CREATE TABLE offline (
            track_id TEXT PRIMARY KEY REFERENCES tracks(id) ON UPDATE CASCADE ON DELETE CASCADE,
            file TEXT NOT NULL,
            bytes INTEGER NOT NULL DEFAULT 0,
            at INTEGER NOT NULL
        ) WITHOUT ROWID''',
    'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID',
    "INSERT INTO lists (id, kind, created_at, updated_at) VALUES ('lib', 'lib', 0, 0), ('fav', 'fav', 0, 0)",
  ],
  // Sync. What the listener changes is marked in `changes`, one row per thing:
  // on the other side the later change wins, and a deleted thing keeps its row
  // so it doesn't come back. Triggers below mark any write; what came from
  // another device is marked by [SyncLog] (device is its id, '' means this
  // one). seq only grows: "after N" is a cursor.
  [
    r'''CREATE TABLE changes (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            key TEXT NOT NULL,
            mod INTEGER NOT NULL,
            device TEXT NOT NULL DEFAULT '',
            UNIQUE (kind, key)
        )''',
    // A trigger can't use INSERT OR REPLACE: the query that fired it imposes
    // its conflict rule, and the cascade fails. So delete, then insert.
    'CREATE VIEW stamp (kind, key) AS SELECT kind, key FROM changes',
    r'''CREATE TRIGGER stamp_now INSTEAD OF INSERT ON stamp BEGIN
            DELETE FROM changes WHERE kind = NEW.kind AND key = NEW.key;
            INSERT INTO changes (kind, key, mod) VALUES (NEW.kind, NEW.key, CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER));
        END''',

    // What exists already goes out on the first sync.
    r"INSERT INTO changes (kind, key, mod) SELECT 'list', id, updated_at FROM lists WHERE kind NOT IN ('lib', 'fav')",
    r"INSERT INTO changes (kind, key, mod) SELECT 'item', list_id || char(9) || track_id, added_at FROM list_tracks",
    r"INSERT INTO changes (kind, key, mod) SELECT 'follow', id, at FROM follows",
    r"INSERT INTO changes (kind, key, mod) SELECT 'dislike', track_id, at FROM dislikes",
    r"INSERT INTO stamp SELECT 'kv', key FROM kv WHERE key IN ('profile', 'profile.since')",
    r"INSERT INTO changes (kind, key, mod) SELECT 'track', id, updated_at FROM tracks WHERE extra ->> '$.edited'",

    // Playlists, not all tracks and likes: every device has those. Their
    // updated_at alone moves with every added track and isn't a change.
    r'''CREATE TRIGGER lists_ins AFTER INSERT ON lists WHEN NEW.kind NOT IN ('lib', 'fav') BEGIN
            INSERT INTO stamp VALUES ('list', NEW.id);
        END''',
    r'''CREATE TRIGGER lists_upd AFTER UPDATE ON lists WHEN NEW.kind NOT IN ('lib', 'fav') AND (NEW.name IS NOT OLD.name
            OR NEW.description IS NOT OLD.description OR NEW.cover IS NOT OLD.cover OR NEW.sources IS NOT OLD.sources
            OR NEW.auto_refresh IS NOT OLD.auto_refresh OR NEW.side_pos IS NOT OLD.side_pos OR NEW.pinned IS NOT OLD.pinned) BEGIN
            INSERT INTO stamp VALUES ('list', NEW.id);
        END''',
    r'''CREATE TRIGGER lists_del AFTER DELETE ON lists WHEN OLD.kind NOT IN ('lib', 'fav') BEGIN
            INSERT INTO stamp VALUES ('list', OLD.id);
        END''',
    // Track in a list: "list_id<TAB>track_id".
    r'''CREATE TRIGGER list_tracks_ins AFTER INSERT ON list_tracks BEGIN
            INSERT INTO stamp VALUES ('item', NEW.list_id || char(9) || NEW.track_id);
        END''',
    r'''CREATE TRIGGER list_tracks_upd AFTER UPDATE ON list_tracks WHEN NEW.list_id IS NOT OLD.list_id OR NEW.track_id IS NOT OLD.track_id
            OR NEW.pos IS NOT OLD.pos OR NEW.added_at IS NOT OLD.added_at BEGIN
            INSERT INTO stamp VALUES ('item', OLD.list_id || char(9) || OLD.track_id);
            INSERT INTO stamp VALUES ('item', NEW.list_id || char(9) || NEW.track_id);
        END''',
    r'''CREATE TRIGGER list_tracks_del AFTER DELETE ON list_tracks BEGIN
            INSERT INTO stamp VALUES ('item', OLD.list_id || char(9) || OLD.track_id);
        END''',
    r'''CREATE TRIGGER follows_ins AFTER INSERT ON follows BEGIN
            INSERT INTO stamp VALUES ('follow', NEW.id);
        END''',
    r'''CREATE TRIGGER follows_upd AFTER UPDATE ON follows WHEN NEW.id IS NOT OLD.id OR NEW.provider IS NOT OLD.provider
            OR NEW.name IS NOT OLD.name OR NEW.avatar IS NOT OLD.avatar OR NEW.extra IS NOT OLD.extra OR NEW.at IS NOT OLD.at
            OR NEW.side_pos IS NOT OLD.side_pos OR NEW.pinned IS NOT OLD.pinned BEGIN
            INSERT INTO stamp VALUES ('follow', OLD.id);
            INSERT INTO stamp VALUES ('follow', NEW.id);
        END''',
    r'''CREATE TRIGGER follows_del AFTER DELETE ON follows BEGIN
            INSERT INTO stamp VALUES ('follow', OLD.id);
        END''',
    r'''CREATE TRIGGER dislikes_ins AFTER INSERT ON dislikes BEGIN
            INSERT INTO stamp VALUES ('dislike', NEW.track_id);
        END''',
    r'''CREATE TRIGGER dislikes_upd AFTER UPDATE ON dislikes WHEN NEW.track_id IS NOT OLD.track_id OR NEW.at IS NOT OLD.at BEGIN
            INSERT INTO stamp VALUES ('dislike', OLD.track_id);
            INSERT INTO stamp VALUES ('dislike', NEW.track_id);
        END''',
    r'''CREATE TRIGGER dislikes_del AFTER DELETE ON dislikes BEGIN
            INSERT INTO stamp VALUES ('dislike', OLD.track_id);
        END''',
    // Profile card, member since, and the last stats clear.
    r'''CREATE TRIGGER kv_ins AFTER INSERT ON kv WHEN NEW.key IN ('profile', 'profile.since', 'stats.cleared') BEGIN
            INSERT INTO stamp VALUES ('kv', NEW.key);
        END''',
    r'''CREATE TRIGGER kv_upd AFTER UPDATE ON kv WHEN NEW.key IN ('profile', 'profile.since', 'stats.cleared') AND NEW.value IS NOT OLD.value BEGIN
            INSERT INTO stamp VALUES ('kv', NEW.key);
        END''',
    r'''CREATE TRIGGER kv_del AFTER DELETE ON kv WHEN OLD.key IN ('profile', 'profile.since', 'stats.cleared') BEGIN
            INSERT INTO stamp VALUES ('kv', OLD.key);
        END''',
    // Tags edited by hand; platform data doesn't travel.
    r'''CREATE TRIGGER tracks_edit AFTER UPDATE ON tracks WHEN NEW.id IS OLD.id AND (NEW.extra ->> '$.edited' OR OLD.extra ->> '$.edited')
            AND (NEW.title IS NOT OLD.title OR NEW.artist IS NOT OLD.artist OR NEW.album IS NOT OLD.album
                 OR NEW.cover IS NOT OLD.cover OR NEW.extra IS NOT OLD.extra) BEGIN
            INSERT INTO stamp VALUES ('track', NEW.id);
        END''',

    // Plays and days belong to the device that made them (device is its id, ''
    // means this one): nothing to merge, only copy. The play id is the cursor.
    r'''CREATE TABLE plays_v2 (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            track_id TEXT NOT NULL REFERENCES tracks(id) ON UPDATE CASCADE ON DELETE CASCADE,
            device TEXT NOT NULL DEFAULT ''
        )''',
    'INSERT INTO plays_v2 (ts, track_id) SELECT ts, track_id FROM plays ORDER BY ts',
    'DROP TABLE plays',
    'ALTER TABLE plays_v2 RENAME TO plays',
    'CREATE INDEX plays_ts ON plays(ts)',
    'CREATE INDEX plays_track ON plays(track_id, ts)',
    'CREATE INDEX plays_device ON plays(device, ts)',
    r'''CREATE TABLE days_v2 (
            day TEXT NOT NULL,
            device TEXT NOT NULL DEFAULT '',
            app_ms INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (day, device)
        ) WITHOUT ROWID''',
    'INSERT INTO days_v2 (day, app_ms) SELECT day, app_ms FROM days',
    'DROP TABLE days',
    'ALTER TABLE days_v2 RENAME TO days',
  ],
];

/// Opened at launch and overridden in `main()`; in tests, [BloomDb.memory].
final dbProvider = Provider<BloomDb>(
  (ref) => throw UnimplementedError('dbProvider must be overridden'),
);

class BloomDb {
  BloomDb._(this._db, {this.path});

  final Database _db;

  /// Database file; `null` means in memory (tests).
  final String? path;

  int _depth = 0; // open tx
  bool _failed = false; // a nested tx left with no commit

  /// Whether the last outer [tx] committed rather than rolled back on an error.
  bool get committed => _committed;
  bool _committed = true;

  /// `bloom.db` in the app's private directory.
  static Future<BloomDb> open() async {
    final dir = await appPrivateDir();
    return BloomDb.at('${dir.path}/bloom.db');
  }

  factory BloomDb.at(String file) {
    final db = BloomDb._(sqlite3.open(file), path: file).._prepare();
    logInfo(
      'db',
      'open ${file.split(Platform.pathSeparator).last} · schema ${kMigrations.length}',
    );
    return db;
  }

  factory BloomDb.memory() => BloomDb._(sqlite3.openInMemory()).._prepare();

  void _prepare() {
    // WAL: a write is one append and readers don't wait. NORMAL with WAL is
    // safe: a power cut can lose the last moment but not corrupt the file.
    for (final p in const [
      'PRAGMA journal_mode = WAL',
      'PRAGMA synchronous = NORMAL',
      'PRAGMA foreign_keys = ON',
      'PRAGMA temp_store = MEMORY',
    ]) {
      _db.execute(p);
    }
    _migrate();
  }

  void _migrate() {
    final have = _db.select('PRAGMA user_version').first.values.first as int;
    if (have > kMigrations.length) {
      // A newer version wrote this database; working on it could damage its
      // data.
      throw StateError(
        'database version $have is newer than this build knows (${kMigrations.length})',
      );
    }
    for (var v = have; v < kMigrations.length; v++) {
      _db.execute('BEGIN');
      try {
        for (final sql in kMigrations[v]) {
          _db.execute(sql);
        }
        _db.execute('PRAGMA user_version = ${v + 1}');
        _db.execute('COMMIT');
      } catch (e) {
        _db.execute('ROLLBACK');
        logError('db', 'migration ${v + 1} failed', e);
        rethrow;
      }
      logInfo('db', 'schema $v → ${v + 1}');
    }
  }

  /// Erases all data, for reset everything. The schema stays; system lists are
  /// created again as in the first schema step.
  void wipe() {
    tx(() {
      final tables = [
        for (final r in select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        ))
          r['name'] as String,
      ];
      exec('PRAGMA defer_foreign_keys = ON');
      for (final t in tables) {
        exec('DELETE FROM $t');
      }
      exec(kMigrations.first.last);
      // Last: wiping marks itself with deletions, and they would go to other
      // devices. A reset is for this device; with a new id it takes everything
      // afresh.
      exec('DELETE FROM changes');
    });
  }

  /// Folds the WAL back so `bloom.db` is whole by itself.
  void close() {
    try {
      _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    _db.close();
  }

  // ── Queries ─────────────────────────────────────────────────────────────

  void exec(String sql, [List<Object?> args = const []]) {
    try {
      _db.execute(sql, args);
    } on SqliteException catch (e) {
      if (_depth > 0) _failed = true;
      logWarn('db', 'exec: ${e.message} · ${_short(sql)}');
    }
  }

  List<Row> select(String sql, [List<Object?> args = const []]) {
    try {
      return _db.select(sql, args).toList();
    } on SqliteException catch (e) {
      if (_depth > 0) _failed = true;
      logWarn('db', 'select: ${e.message} · ${_short(sql)}');
      return const [];
    }
  }

  /// First value of the first row; `null` if no rows.
  Object? value(String sql, [List<Object?> args = const []]) {
    final rows = select(sql, args);
    return rows.isEmpty ? null : rows.first.values.first;
  }

  /// Rows touched by the last write.
  int get changes => _db.updatedRows;

  /// Writes to rowid tables (`changes`, `plays`…), on the next event loop turn.
  /// WITHOUT ROWID tables don't show up.
  Stream<SqliteUpdate> get updates => _db.updates;

  /// A prepared query for batches: one SQL parse for a thousand rows.
  PreparedStatement prepare(String sql) => _db.prepare(sql);

  /// Runs everything inside in one transaction. Nested ones merge with the
  /// outer: all rolls back if anything inside failed or threw.
  T tx<T>(T Function() body) {
    if (_depth++ == 0) {
      _failed = false;
      _db.execute('BEGIN');
    }
    try {
      final result = body();
      if (--_depth == 0) {
        _committed = !_failed;
        if (_failed) {
          _db.execute('ROLLBACK');
          logWarn('db', 'transaction rolled back: a statement in it failed');
        } else {
          _db.execute('COMMIT');
        }
      }
      return result;
    } catch (_) {
      _failed = true;
      if (--_depth == 0) {
        _committed = false;
        _db.execute('ROLLBACK');
        logWarn('db', 'transaction rolled back');
      }
      rethrow;
    }
  }

  // ── kv ──────────────────────────────────────────────────────────────────

  /// Value by key. Wrapped in an array, so bare numbers and strings are valid
  /// JSON too.
  Object? get(String key, [Object? fallback]) {
    final raw = value('SELECT value FROM kv WHERE key = ?', [key]);
    if (raw is! String) return fallback;
    try {
      final wrapped = jsonDecode(raw);
      return wrapped is List && wrapped.isNotEmpty ? wrapped.first : fallback;
    } catch (_) {
      return fallback;
    }
  }

  Map<String, dynamic> getMap(String key) {
    final v = get(key);
    return v is Map ? v.cast<String, dynamic>() : {};
  }

  /// `null` erases the key.
  void set(String key, Object? value) {
    if (value == null) {
      exec('DELETE FROM kv WHERE key = ?', [key]);
      return;
    }
    exec(
      'INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [
        key,
        jsonEncode([value]),
      ],
    );
  }

  static int now() => DateTime.now().millisecondsSinceEpoch;

  static String _short(String sql) {
    final s = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > 200 ? s.substring(0, 200) : s;
  }
}
