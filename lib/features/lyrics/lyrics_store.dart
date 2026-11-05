/// The lyrics of the playing track: looked up on every change of track once
/// something shows them, the line being sung follows the position. Kept lyrics
/// and the missed ones — [LyricsCache].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../player/player_controller.dart';
import '../../core/store/cache_keep.dart';
import 'lrc.dart';
import 'lyrics_api.dart';
import 'lyrics_cache.dart';

export '../../core/store/cache_keep.dart' show CacheKeep;

/// Where the lyrics go in the player: over the cover, or in its place.
enum LyricsMode { overlay, replace }

/// Font size presets for lyrics text.
enum LyricsFontSize {
  compact,
  normal,
  large;

  static LyricsFontSize of(Object? id) =>
      values.firstWhere((v) => v.name == id, orElse: () => normal);
}

/// Text alignment presets for lyrics.
enum LyricsAlign {
  auto,
  center,
  left;

  static LyricsAlign of(Object? id) =>
      values.firstWhere((v) => v.name == id, orElse: () => auto);
}

@immutable
class LyricsPrefs {
  const LyricsPrefs({
    this.mode = LyricsMode.overlay,
    this.cache = false,
    this.keep = CacheKeep.never,
    this.romanize = true,
    this.syllables = true,
    this.fontSize = LyricsFontSize.normal,
    this.align = LyricsAlign.auto,
  });

  factory LyricsPrefs.fromJson(Map<String, Object?> raw) => LyricsPrefs(
    mode: LyricsMode.values.firstWhere(
      (m) => m.name == raw['mode'],
      orElse: () => LyricsMode.overlay,
    ),
    cache: raw['cache'] == true,
    keep: CacheKeep.of(raw['keep']),
    romanize: raw['romanize'] != false,
    syllables: raw['syllables'] != false,
    fontSize: LyricsFontSize.of(raw['fontSize']),
    align: LyricsAlign.of(raw['align']),
  );

  final LyricsMode mode;

  /// Keep found lyrics on the phone; off by default.
  final bool cache;

  /// For how long.
  final CacheKeep keep;

  /// Show Latin transliteration under foreign scripts (Hangul, Kana, Cyrillic).
  final bool romanize;

  /// Highlight lyrics word-by-word and syllable-by-syllable when timing is available.
  final bool syllables;

  /// Font size for lyrics text.
  final LyricsFontSize fontSize;

  /// Text alignment.
  final LyricsAlign align;

  LyricsPrefs copyWith({
    LyricsMode? mode,
    bool? cache,
    CacheKeep? keep,
    bool? romanize,
    bool? syllables,
    LyricsFontSize? fontSize,
    LyricsAlign? align,
  }) => LyricsPrefs(
    mode: mode ?? this.mode,
    cache: cache ?? this.cache,
    keep: keep ?? this.keep,
    romanize: romanize ?? this.romanize,
    syllables: syllables ?? this.syllables,
    fontSize: fontSize ?? this.fontSize,
    align: align ?? this.align,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'cache': cache,
    'keep': keep.id,
    'romanize': romanize,
    'syllables': syllables,
    'fontSize': fontSize.name,
    'align': align.name,
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

  void setRomanize(bool on) => _set(state.copyWith(romanize: on));

  void setSyllables(bool on) => _set(state.copyWith(syllables: on));

  void setFontSize(LyricsFontSize size) => _set(state.copyWith(fontSize: size));

  void setAlign(LyricsAlign align) => _set(state.copyWith(align: align));

  /// A time limit applies at once; returns how many went out of date.
  int setKeep(CacheKeep keep) {
    _set(state.copyWith(keep: keep));
    return keep == CacheKeep.restart
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
      String? album,
    });

final lyricsFetcherProvider = Provider<LyricsFetcher>(
  (ref) =>
      ({required artist, required title, durationSec, trackId, album}) =>
          fetchLyrics(
            artist: artist,
            title: title,
            durationSec: durationSec,
            trackId: trackId,
            album: album,
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

  Future<void> load(Track? t, {bool force = false}) async {
    if (_gone || (!force && t?.id == _id && state.status == LyricsStatus.ready)) return;
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
    var found = force ? null : cache.read(key);
    if (found == null) {
      found = await ref.read(lyricsFetcherProvider)(
        artist: t.artist,
        title: t.name,
        durationSec: t.duration.inSeconds > 0 ? t.duration.inSeconds : null,
        trackId: t.id,
        album: t.album,
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
        lines: found.lines.isNotEmpty
            ? found.lines
            : (found.synced.trim().isEmpty ? const [] : parseLrc(found.synced)),
        plain: found.plain.trim().isEmpty
            ? stripLrc(found.synced)
            : found.plain.trim(),
      ),
    );
  }

  void _set(LyricsState next) {
    state = next;
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
