/// Kept lyrics: the `lyrics` table of the database, as on the PC. Written only
/// while "keep lyrics" is on, read always; 30 days at most whatever the
/// policy. Nothing found is remembered in memory for 5 minutes: someone may
/// upload them tomorrow.
library;

import '../../core/db/db.dart';
import 'lyrics_api.dart';

const int _missedMs = 5 * 60 * 1000;
const int _keptMs = 30 * 24 * 3600 * 1000;

/// How long kept lyrics live: the PC's `lyricsKeep`.
enum LyricsKeep {
  never('never', _keptMs),
  restart('restart', _keptMs),
  day('24h', 24 * 3600 * 1000),
  days3('3d', 3 * 24 * 3600 * 1000),
  week('1w', 7 * 24 * 3600 * 1000),
  month('1m', _keptMs);

  const LyricsKeep(this.id, this.ms);

  final String id;
  final int ms;

  static LyricsKeep of(Object? id) =>
      values.firstWhere((k) => k.id == id, orElse: () => never);
}

class LyricsCache {
  LyricsCache(this._db);

  final BloomDb _db;
  final Map<String, int> _missed = {};

  static String keyOf(String artist, String title) =>
      '${artist.toLowerCase()}::${title.toLowerCase()}';

  /// Known lyrics, [LyricsResult.none] for ones missed just now, `null` to
  /// ask the network.
  LyricsResult? read(String key) {
    final missed = _missed[key];
    if (missed != null && BloomDb.now() - missed < _missedMs) {
      return LyricsResult.none;
    }
    final row = _db.select(
      'SELECT synced, plain, source, at FROM lyrics WHERE key = ?',
      [key],
    );
    if (row.isEmpty || BloomDb.now() - (row.first['at'] as int) > _keptMs) {
      return null;
    }
    final found = LyricsResult(
      synced: row.first['synced'] as String,
      plain: row.first['plain'] as String,
      source: row.first['source'] as String,
    );
    return found.ok ? found : null;
  }

  void remember(String key, LyricsResult found, {required bool keep}) {
    if (!found.ok) {
      _missed[key] = BloomDb.now();
      return;
    }
    _missed.remove(key);
    if (!keep) return;
    _db.exec(
      'INSERT INTO lyrics (key, synced, plain, source, at) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(key) DO UPDATE SET synced = excluded.synced, plain = excluded.plain, '
      'source = excluded.source, at = excluded.at',
      [key, found.synced, found.plain, found.source, BloomDb.now()],
    );
  }

  /// At launch: "until restart" empties the table, a time limit trims it.
  void start(LyricsKeep keep) {
    keep == LyricsKeep.restart ? clear() : purge(keep);
  }

  ({int count, int bytes}) stats() {
    final r = _db.select(
      'SELECT count(*) AS n, coalesce(sum(length(CAST(synced AS BLOB)) + '
      'length(CAST(plain AS BLOB))), 0) AS b FROM lyrics',
    );
    return r.isEmpty
        ? (count: 0, bytes: 0)
        : (count: r.first['n'] as int, bytes: r.first['b'] as int);
  }

  /// Returns how many were dropped.
  int clear() {
    _missed.clear();
    _db.exec('DELETE FROM lyrics');
    return _db.changes;
  }

  /// Drops the ones older than [keep] allows; returns how many.
  int purge(LyricsKeep keep) {
    _db.exec('DELETE FROM lyrics WHERE at < ?', [BloomDb.now() - keep.ms]);
    return _db.changes;
  }
}
