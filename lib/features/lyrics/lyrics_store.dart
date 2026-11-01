/// The lyrics of the playing track, as the PC's `Lyrics`: looked up on every
/// change of track once something shows them, the line being sung follows the
/// position. Kept lyrics and the missed ones — [LyricsCache].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../player/player_controller.dart';
import 'lrc.dart';
import 'lyrics_api.dart';
import 'lyrics_cache.dart';

export 'lyrics_cache.dart' show LyricsKeep;

/// Where the lyrics go in the player: over the cover, as the PC's panel, or
/// in its place (the phone's "lyrics instead of queue").
enum LyricsMode { overlay, replace }

@immutable
class LyricsPrefs {
  const LyricsPrefs({
    this.mode = LyricsMode.overlay,
    this.cache = false,
    this.keep = LyricsKeep.never,
  });

  factory LyricsPrefs.fromJson(Map<String, Object?> raw) => LyricsPrefs(
    mode: LyricsMode.values.firstWhere(
      (m) => m.name == raw['mode'],
      orElse: () => LyricsMode.overlay,
    ),
    cache: raw['cache'] == true,
    keep: LyricsKeep.of(raw['keep']),
  );

  final LyricsMode mode;

  /// Keep found lyrics on the phone — the PC's `lyricsCache`, off by default.
  final bool cache;

  /// For how long — the PC's `lyricsKeep`.
  final LyricsKeep keep;

  LyricsPrefs copyWith({LyricsMode? mode, bool? cache, LyricsKeep? keep}) =>
      LyricsPrefs(
        mode: mode ?? this.mode,
        cache: cache ?? this.cache,
        keep: keep ?? this.keep,
      );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'cache': cache,
    'keep': keep.id,
  };
}

final lyricsPrefsProvider =
    NotifierProvider<LyricsPrefsController, LyricsPrefs>(
      LyricsPrefsController.new,
    );

class LyricsPrefsController extends Notifier<LyricsPrefs> {
  @override
  LyricsPrefs build() =>
      LyricsPrefs.fromJson(ref.read(jsonStoreProvider).readMap('lyrics'));

  void setMode(LyricsMode mode) => _set(state.copyWith(mode: mode));

  void setCache(bool on) => _set(state.copyWith(cache: on));

  /// A time limit applies at once; returns how many went out of date.
  int setKeep(LyricsKeep keep) {
    _set(state.copyWith(keep: keep));
    return keep == LyricsKeep.restart
        ? 0
        : ref.read(lyricsCacheProvider).purge(keep);
  }

  void _set(LyricsPrefs next) {
    state = next;
    ref.read(jsonStoreProvider).write('lyrics', next.toJson());
  }
}

enum LyricsStatus { idle, loading, ready, empty }

@immutable
class LyricsState {
  const LyricsState({
    this.trackId,
    this.status = LyricsStatus.idle,
    this.lines = const [],
    this.plain = '',
  });

  final String? trackId;
  final LyricsStatus status;

  /// Timed lines; empty — only [plain].
  final List<LrcLine> lines;
  final String plain;
}

final lyricsCacheProvider = Provider<LyricsCache>(
  (ref) => LyricsCache(ref.watch(dbProvider)),
);

/// The network — swapped in tests.
typedef LyricsFetcher =
    Future<LyricsResult> Function({
      required String artist,
      required String title,
      int? durationSec,
      String? trackId,
    });

final lyricsFetcherProvider = Provider<LyricsFetcher>(
  (ref) =>
      ({required artist, required title, durationSec, trackId}) => fetchLyrics(
        artist: artist,
        title: title,
        durationSec: durationSec,
        trackId: trackId,
      ),
);

/// Whose lyrics to show — swapped in tests.
final lyricsTrackProvider = Provider<Track?>(
  (ref) => ref.watch(playbackProvider.select((s) => s.track)),
);

final lyricsProvider = NotifierProvider<LyricsController, LyricsState>(
  LyricsController.new,
);

class LyricsController extends Notifier<LyricsState> {
  String? _id;
  // An answer for a track already left behind is dropped.
  int _token = 0;
  bool _gone = false;

  @override
  LyricsState build() {
    ref.onDispose(() => _gone = true);
    ref.listen(lyricsTrackProvider, (_, track) => load(track));
    // Not from build itself: loading sets the state.
    scheduleMicrotask(() => load(ref.read(lyricsTrackProvider)));
    return const LyricsState();
  }

  Future<void> load(Track? t) async {
    if (_gone || t?.id == _id) return;
    _id = t?.id;
    final token = ++_token;
    if (t == null || t.name.trim().isEmpty) {
      return _set(
        LyricsState(
          trackId: t?.id,
          status: t == null ? LyricsStatus.idle : LyricsStatus.empty,
        ),
      );
    }
    _set(LyricsState(trackId: t.id, status: LyricsStatus.loading));

    final cache = ref.read(lyricsCacheProvider);
    final key = LyricsCache.keyOf(t.artist, t.name);
    var found = cache.read(key);
    if (found == null) {
      found = await ref.read(lyricsFetcherProvider)(
        artist: t.artist,
        title: t.name,
        durationSec: t.duration.inSeconds > 0 ? t.duration.inSeconds : null,
        trackId: t.id,
      );
      cache.remember(key, found, keep: ref.read(lyricsPrefsProvider).cache);
    }
    if (_gone || token != _token) return;
    if (!found.ok) {
      return _set(LyricsState(trackId: t.id, status: LyricsStatus.empty));
    }
    _set(
      LyricsState(
        trackId: t.id,
        status: LyricsStatus.ready,
        lines: found.synced.trim().isEmpty ? const [] : parseLrc(found.synced),
        plain: found.plain.trim().isEmpty
            ? stripLrc(found.synced)
            : found.plain.trim(),
      ),
    );
  }

  void _set(LyricsState next) {
    final gone =
        next.status == LyricsStatus.empty && state.status != LyricsStatus.empty;
    state = next;
    // A track without lyrics closes them: an empty panel would stay, with the
    // lyrics button only to close it. Loading between tracks leaves them be.
    if (gone) ref.read(lyricsOpenProvider.notifier).state = false;
  }
}

/// The line being sung; −1 in the intro or without timed lines.
final lyricsLineProvider = Provider<int>((ref) {
  final lines = ref.watch(lyricsProvider.select((s) => s.lines));
  if (lines.isEmpty) return -1;
  final pos = ref.watch(playheadProvider.select((h) => h.value?.position));
  return activeLineAt(lines, (pos ?? Duration.zero).inMilliseconds / 1000);
});

/// Whether the player shows the lyrics; outlives the track, as `Nav.lyricsOpen`.
final lyricsOpenProvider = StateProvider<bool>((ref) => false);
