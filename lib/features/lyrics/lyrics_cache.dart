/// Kept lyrics: the `lyrics` table of the database. Written only while "keep
/// lyrics" is on, read always; 30 days at most whatever the policy. Nothing
/// found is remembered in memory for 5 minutes: someone may upload them tomorrow.
library;

import '../../core/db/db.dart';
import '../../core/store/cache_keep.dart';
import 'lyrics_api.dart';

const int _missedMs = 5 * 60 * 1000;
const int _dayMs = 24 * 3600 * 1000;
const int _keptMs = 30 * _dayMs;

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
  void start(CacheKeep keep) {
    keep == CacheKeep.restart ? clear() : purge(keep);
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
  int purge(CacheKeep keep) {
    final limit = keep.days == null ? _keptMs : keep.days! * _dayMs;
    _db.exec('DELETE FROM lyrics WHERE at < ?', [BloomDb.now() - limit]);
    return _db.changes;
  }
}
