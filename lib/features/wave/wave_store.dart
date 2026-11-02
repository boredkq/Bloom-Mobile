/// The wave's lasting memory. Dislikes and already shown are the `dislikes` and
/// `wave_shown` tables; where each station stopped, the seed shift and the
/// running wave are database kv (`wave.cursors`, `wave.rotation`,
/// `wave.session`). My wave's platform is a setting, kept as the `wave` map in
/// bloom.json.
///
/// A dislike is ONE across all platforms: [Track] has no `disliked` flag.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/db/track_store.dart';
import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart';
import '../../core/store/library_store.dart' show libraryProvider;
import '../../providers/yandex/ym_auth.dart';
import 'wave_engine.dart' show kWaveShownDays;
import 'wave_types.dart';

/// Wave map key in bloom.json.
const String kWaveKey = 'wave';

const String _kSession = 'wave.session';
const String _kCursors = 'wave.cursors';
const String _kRotation = 'wave.rotation';

/// This many stations remember where they stopped; the oldest are forgotten
/// first.
const int kMaxCursors = 300;

const int _kDay = 24 * 3600 * 1000;

/// Platforms My wave can come from.
const List<MusicSource> kWaveSources = [
  MusicSource.soundcloud,
  MusicSource.ytmusic,
  MusicSource.yandex,
];

class WaveState {
  const WaveState({
    this.source = MusicSource.soundcloud,
    this.dislikes = const [],
    this.dislikedIds = const {},
  });

  /// Which platform My wave comes from.
  final MusicSource source;

  /// Disliked tracks, newest on top.
  final List<Track> dislikes;

  /// Their ids, to check for a dislike with no list search.
  final Set<String> dislikedIds;

  bool isDisliked(String trackId) => dislikedIds.contains(trackId);

  WaveState copyWith({
    MusicSource? source,
    List<Track>? dislikes,
    Set<String>? dislikedIds,
  }) => WaveState(
    source: source ?? this.source,
    dislikes: dislikes ?? this.dislikes,
    dislikedIds: dislikedIds ?? this.dislikedIds,
  );
}

final waveStoreProvider = NotifierProvider<WaveStore, WaveState>(WaveStore.new);

/// Platform My wave goes from RIGHT NOW: with Yandex picked and no login, the
/// wave doesn't refuse but goes from SoundCloud. The choice itself stays: when
/// login returns, so does the station.
final effectiveWaveSourceProvider = Provider<MusicSource>((ref) {
  final picked = ref.watch(waveStoreProvider).source;
  if (picked != MusicSource.yandex) return picked;
  return ref.watch(ymAuthProvider).authed ? picked : MusicSource.soundcloud;
});

class WaveStore extends Notifier<WaveState> {
  JsonStore get _store => ref.read(jsonStoreProvider);
  BloomDb get _db => ref.read(dbProvider);

  /// Seed key to `{c: cursor, at: ms}`: a new wave on the same seeds hears
  /// what's next.
  final Map<String, Map<String, Object?>> _cursors = {};

  @override
  WaveState build() {
    _cursors.clear();
    _db.getMap(_kCursors).forEach((k, v) {
      if (v is Map) _cursors[k] = v.cast<String, Object?>();
    });
    // Shown over two weeks ago no longer holds a track.
    _db.exec('DELETE FROM wave_shown WHERE at < ?', [
      BloomDb.now() - kWaveShownDays * _kDay,
    ]);
    // Changing a track's platform ([LibraryController.replaceTrack]) moves the
    // dislike too, so the list re-reads after the library.
    ref.listen(libraryProvider, (_, _) => _reloadDislikes());

    final picked = _store.readMap(kWaveKey)['source'];
    final dislikes = _readDislikes();
    return WaveState(
      source: kWaveSources.firstWhere(
        (s) => s.code == picked,
        orElse: () => MusicSource.soundcloud,
      ),
      dislikes: dislikes,
      dislikedIds: {for (final t in dislikes) t.id},
    );
  }

  List<Track> _readDislikes() => TrackStore(_db).get([
    for (final r in _db.select(
      'SELECT track_id FROM dislikes ORDER BY at DESC',
    ))
      r['track_id'] as String,
  ]);

  void _reloadDislikes() {
    final list = _readDislikes();
    state = state.copyWith(
      dislikes: list,
      dislikedIds: {for (final t in list) t.id},
    );
  }

  // ── Platform ────────────────────────────────────────────────────────────

  void setSource(MusicSource source) {
    if (state.source == source || !kWaveSources.contains(source)) return;
    state = state.copyWith(source: source);
    _store.write(kWaveKey, {'source': source.code});
  }

  // ── Dislikes ────────────────────────────────────────────────────────────

  /// Sets or clears a dislike. Returns the new state, which the caller needs
  /// for the toast.
  bool toggleDislike(Track track) {
    final on = !state.isDisliked(track.id);
    _db.tx(() {
      if (on) {
        // A snapshot, so the dislikes list can show it later.
        TrackStore(_db).put([track]);
        _db.exec(
          'INSERT OR REPLACE INTO dislikes (track_id, at) VALUES (?, ?)',
          [track.id, BloomDb.now()],
        );
      } else {
        _db.exec('DELETE FROM dislikes WHERE track_id = ?', [track.id]);
      }
    });
    _reloadDislikes();
    return on;
  }

  void undislike(String trackId) {
    if (!state.isDisliked(trackId)) return;
    _db.exec('DELETE FROM dislikes WHERE track_id = ?', [trackId]);
    _reloadDislikes();
  }

  void clearDislikes() {
    if (state.dislikes.isEmpty) return;
    _db.exec('DELETE FROM dislikes');
    _reloadDislikes();
  }

  // ── Already shown ───────────────────────────────────────────────────────

  /// Marks tracks as having been in the wave's output, as a batch.
  void markShown(Iterable<String> trackIds) {
    final ids = trackIds.toList();
    if (ids.isEmpty) return;
    final now = BloomDb.now();
    _db.tx(() {
      for (final id in ids) {
        _db.exec(
          'INSERT OR REPLACE INTO wave_shown (track_id, at) VALUES (?, ?)',
          [id, now],
        );
      }
    });
  }

  /// What the wave showed in the last [withinDays] days: one query per batch,
  /// not one per candidate.
  Set<String> shownIds({int withinDays = kWaveShownDays}) => {
    for (final r in _db.select(
      'SELECT track_id FROM wave_shown WHERE at >= ?',
      [BloomDb.now() - withinDays * _kDay],
    ))
      r['track_id'] as String,
  };

  // ── Station cursors ─────────────────────────────────────────────────────

  String cursorOf(WaveSeed seed) => _cursors[seed.key]?['c'] as String? ?? '';

  /// Remembers where stations continue, as a batch per seed poll.
  void saveCursors(Map<WaveSeed, String> next) {
    if (next.isEmpty) return;
    final now = BloomDb.now();
    next.forEach((seed, c) => _cursors[seed.key] = {'c': c, 'at': now});
    if (_cursors.length > kMaxCursors) {
      final byAge = _cursors.entries.toList()
        ..sort(
          (a, b) => ((a.value['at'] as num?) ?? 0).compareTo(
            (b.value['at'] as num?) ?? 0,
          ),
        );
      for (final e in byAge.take(_cursors.length - kMaxCursors)) {
        _cursors.remove(e.key);
      }
    }
    _db.set(_kCursors, _cursors);
  }

  // ── My wave's seed shift ────────────────────────────────────────────────

  int get rotation => (_db.get(_kRotation, 0) as num?)?.toInt() ?? 0;

  /// The current shift, with the next for the next wave.
  int takeRotation() {
    final r = rotation;
    _db.set(_kRotation, r + 1);
    return r;
  }

  // ── Running wave ────────────────────────────────────────────────────────

  WaveRun? get savedRun => WaveRun.fromJson(_db.get(_kSession));

  void saveRun(WaveRun? run) => _db.set(_kSession, run?.toJson());
}
