/// The wave: an endless queue of tracks similar to its start, from platforms'
/// own radio.
///
/// My wave starts from the library (most played and likes), others from a
/// track, artist or queue. SoundCloud and YouTube Music radio go through my
/// selection and order (`pickBatch`); Yandex's station learns from the
/// listener, so its order stays and it's told what was finished and skipped.
/// Dislikes are forever, in the wave and out.
///
/// No toasts here: methods return [WaveStartResult] and the UI picks the text.
/// The controller outlives any screen, with no `BuildContext` to take.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers/artist_lookup.dart';
import '../../core/providers/music_provider.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_stats.dart';
import '../../providers/soundcloud/sc_sources.dart';
import '../../providers/yandex/yandex.dart' show kWaveStation;
import '../../providers/yandex/ym_provider.dart' show ymNumericId;
import '../../shared/util/taste.dart';
import '../pc/pc_remote.dart';
import '../player/play_source.dart';
import '../player/player_controller.dart';
import 'wave_engine.dart';
import 'wave_seeds.dart';
import 'wave_store.dart';
import 'wave_types.dart';

/// How an attempt to start the wave ended. All but [ok] and [busy] show as a
/// toast.
enum WaveStartResult {
  ok,

  /// The wave is already starting: a second tap does nothing.
  busy,

  /// Too little listened yet, with no seeds gathered.
  notEnoughData,

  /// The track has no radio to start from.
  noSeed,

  /// The queue is empty: nothing to build similar from.
  queueEmpty,

  /// No tracks with radio in the queue.
  noSeedsInQueue,

  /// The artist has no tracks fit to be seeds.
  artistNoSeeds,

  /// The platform returned no similar tracks.
  noSimilar,

  /// A Yandex wave with no login.
  ymNoAuth,
}

class WaveRunState {
  const WaveRunState({this.starting = false, this.mode, this.about = ''});

  /// The wave is being built right now: the start button spins.
  final bool starting;

  /// Running wave's mode; `null` if not playing.
  final WaveMode? mode;

  /// What the wave on now was started from ([WaveRun.about]).
  final String about;

  bool get active => mode != null;
}

final waveProvider = NotifierProvider<WaveController, WaveRunState>(
  WaveController.new,
);

/// Stations asked at once.
const int _kParallel = 3;

class WaveController extends Notifier<WaveRunState> {
  final Random _rnd = Random();

  WaveRun? _run;

  /// A new wave or its end makes old network answers foreign.
  int _gen = 0;
  bool _refilling = false;

  @override
  WaveRunState build() => const WaveRunState();

  PlaybackController get _playback => ref.read(playbackProvider.notifier);
  PlaybackState get _queue => ref.read(playbackProvider);
  WaveStore get _store => ref.read(waveStoreProvider.notifier);

  MusicProvider? _provider(String code) =>
      ref.read(registryProvider).byId(MusicSource.fromCode(code).id);

  /// A track's radio on its platform.
  WaveSeed? seedOf(Track t) {
    final p = ref.read(registryProvider).byId(t.source.id);
    if (p == null || !p.isEnabled) return null;
    final station = p.trackStation(t);
    return station.isEmpty ? null : WaveSeed(t.source.code, station);
  }

  WaveLibrary _view({Iterable<Track> extras = const []}) => WaveLibrary(
    lib: ref.read(libraryProvider),
    disliked: ref.read(waveStoreProvider).dislikedIds,
    stats: ref.read(playStatsProvider),
    extras: extras,
    seedOf: seedOf,
  );

  /// In the wave right now: it's running and the queue is its.
  bool get _inWave => _run != null && _queue.source is WaveSource;

  // ── Starting ────────────────────────────────────────────────────────────

  /// The phone is a remote: the computer picks and loads the wave, with none of
  /// its own here.
  PcRemoteController? get _remote => ref.read(pcRemoteProvider) == null
      ? null
      : ref.read(pcRemoteProvider.notifier);

  Future<WaveStartResult> _onPc(Future<void> sent) =>
      sent.then((_) => WaveStartResult.ok);

  /// My wave from the set platform. Yandex with no login goes from SoundCloud
  /// (see [effectiveWaveSourceProvider]).
  Future<WaveStartResult> startPersonal() async {
    if (_remote case final pc?) return _onPc(pc.wavePersonal());
    final src = ref.read(effectiveWaveSourceProvider);
    if (src == MusicSource.yandex) {
      return _begin(WaveMode.personal, const [
        WaveSeed('ym', kWaveStation),
      ], native: true);
    }
    final seeds = personalSeeds(_view(), src.code, _store.takeRotation());
    if (seeds.isEmpty) return WaveStartResult.notEnoughData;
    return _begin(WaveMode.personal, seeds);
  }

  /// Wave by track. A Yandex track's radio is its own and learns; others go
  /// through my selection. [seedFirst] starts with the track itself, then moves
  /// to picks.
  Future<WaveStartResult> startByTrack(Track track, {bool seedFirst = false}) {
    if (_remote case final pc?) return _onPc(pc.waveTrack(track));
    final s = seedOf(track);
    if (s == null) return Future.value(WaveStartResult.noSeed);
    return _begin(
      WaveMode.track,
      [s],
      native: s.provider == MusicSource.yandex.code,
      about: waveAboutTrack(track.id),
      first: seedFirst ? track : null,
    );
  }

  /// Similar to queue: the queue is replaced by tracks like what's in it.
  Future<WaveStartResult> startByQueue([List<Track>? tracks]) {
    if (_remote case final pc?) return _onPc(pc.waveQueue());
    final source = (tracks == null || tracks.isEmpty) ? _queue.queue : tracks;
    if (source.isEmpty) return Future.value(WaveStartResult.queueEmpty);
    final seeds = queueSeeds(source, _view(extras: source));
    if (seeds.isEmpty) return Future.value(WaveStartResult.noSeedsInQueue);
    return _begin(WaveMode.queue, seeds);
  }

  /// Wave by artist: an artist station on Yandex, elsewhere seeds from what
  /// their page loaded ([seedTracks]: popular and all).
  Future<WaveStartResult> startByArtist(
    Artist artist, {
    List<Track> seedTracks = const [],
  }) {
    if (_remote case final pc?) return _onPc(pc.waveArtist(artist, seedTracks));
    final about = waveAboutArtist(artist.name);
    if (artist.source == MusicSource.yandex) {
      final id = ymNumericId(artist.id);
      if (id.isEmpty) return Future.value(WaveStartResult.artistNoSeeds);
      if (!(_provider('ym')?.isEnabled ?? false)) {
        return Future.value(WaveStartResult.ymNoAuth);
      }
      return _begin(
        WaveMode.artist,
        [WaveSeed('ym', 'artist:$id')],
        native: true,
        about: about,
      );
    }
    final seeds = queueSeeds(seedTracks, _view(extras: seedTracks));
    if (seeds.isEmpty) return Future.value(WaveStartResult.artistNoSeeds);
    return _begin(WaveMode.artist, seeds, about: about);
  }

  /// A wave in the style of [name], one of [track]'s artists:
  /// a Yandex track has its artist's own
  /// station, the rest are seeded with the artist's tracks the listener has
  /// (the top and the library).
  Future<WaveStartResult> startByArtistName(Track track, String name) async {
    if (state.starting) return WaveStartResult.busy;
    final ym = _provider(MusicSource.yandex.code);
    if (track.source == MusicSource.yandex && ym != null && ym.isEnabled) {
      Artist? found;
      try {
        found = await findArtistCached(ym, name);
      } on Object {
        // No network or no such artist there: seeded from their tracks below.
      }
      if (found != null && found.source == MusicSource.yandex) {
        return startByArtist(found);
      }
    }
    final input = recsInputOf(ref);
    final key = artistKey(name);
    final seen = <String>{};
    final theirs = [
      for (final t in [
        for (final r in recsTopPlayed(input, limit: 400)) ?input.trackOf(r.id),
        ...input.lib.allTracks,
      ])
        if (artistKeys(t).contains(key) && seen.add(t.id)) t,
    ];
    // No station of their own: the artist stands for their name alone.
    return startByArtist(
      Artist(id: '', name: name, source: MusicSource.local),
      seedTracks: theirs,
    );
  }

  /// Shakes up My Wave: what follows the playing track turns into a fresh
  /// batch from new seeds. Outside My Wave it starts it.
  Future<WaveStartResult> shake() async {
    if (_remote case final pc?) return _onPc(pc.waveShake());
    final run = _run;
    if (run == null || !_inWave || run.mode != WaveMode.personal) {
      return startPersonal();
    }
    if (state.starting) return WaveStartResult.busy;
    // A Yandex station learns by itself and its next batch is new anyway.
    if (!run.native) {
      final seeds = personalSeeds(
        _view(),
        run.seeds.first.provider,
        _store.takeRotation(),
      );
      if (seeds.isEmpty) return WaveStartResult.notEnoughData;
      run.seeds = seeds;
    }
    final gen = ++_gen;
    _refilling = false;
    state = WaveRunState(starting: true, mode: state.mode, about: state.about);
    resetWaveSourceCache();
    try {
      final pages = await _gather(run.seeds);
      if (gen != _gen || !_inWave) return WaveStartResult.busy;
      final batch = pickBatch(pages, _pick(run));
      if (batch.isEmpty) return WaveStartResult.noSimilar;
      _markShown(batch);
      _playback.replaceUpcoming(batch);
      _save();
      return WaveStartResult.ok;
    } finally {
      if (gen == _gen) {
        state = WaveRunState(mode: state.mode, about: state.about);
      }
    }
  }

  /// Whether My Wave has something to start from: Yandex's own station, or a
  /// track of the chosen platform with a radio.
  bool canPersonal() {
    final src = ref.read(effectiveWaveSourceProvider);
    if (src == MusicSource.yandex) return true;
    return _view().tracks.any((t) => t.source == src && seedOf(t) != null);
  }

  /// [replace] makes the batch the queue; otherwise it goes on the end (auto
  /// similar), while [isValid] holds: something else may have been started
  /// during the wait.
  Future<WaveStartResult> _begin(
    WaveMode mode,
    List<WaveSeed> seeds, {
    bool native = false,
    bool replace = true,
    String about = '',
    Track? first,
    bool Function()? isValid,
  }) async {
    if (state.starting) return WaveStartResult.busy;
    final gen = ++_gen;
    final run = WaveRun(mode: mode, seeds: seeds, about: about, native: native);
    _run = run;
    _refilling = false;
    if (replace) {
      state = WaveRunState(
        starting: true,
        mode: state.mode,
        about: state.about,
      );
    }
    // A new wave mustn't be built from the same answers as the last.
    resetWaveSourceCache();
    try {
      final pages = await _gather(seeds);
      if (gen != _gen) return WaveStartResult.busy;
      if (!replace && !(isValid?.call() ?? true)) {
        _end();
        return WaveStartResult.noSimilar;
      }
      final batch = pickBatch(pages, _pick(run));
      if (batch.isEmpty) {
        _end();
        return WaveStartResult.noSimilar;
      }
      _markShown(batch);
      final source = WaveSource(label: waveLabel(mode), mode: mode);
      if (replace) {
        state = WaveRunState(starting: true, mode: mode, about: about);
        _save();
        await _playback.playWave([
          ?first,
          for (final t in batch)
            if (t.id != first?.id) t,
        ], source);
      } else if (!_playback.continueAsWave(batch, source)) {
        _end();
        return WaveStartResult.noSimilar;
      } else {
        state = WaveRunState(mode: mode, about: about);
        _save();
      }
      if (native) {
        _provider(
          seeds.first.provider,
        )?.stationFeedback(seeds.first.station, 'radioStarted');
      }
      return WaveStartResult.ok;
    } finally {
      if (replace && gen == _gen) {
        state = _run == null
            ? const WaveRunState()
            : WaveRunState(mode: state.mode, about: state.about);
      }
    }
  }

  /// Each seed's station, from where it stopped last time (a new wave on the
  /// same seeds hears what's next), several at once.
  Future<List<List<Track>>> _gather(List<WaveSeed> seeds) async {
    final pages = List<List<Track>>.filled(seeds.length, const []);
    final cursors = <WaveSeed, String>{};
    var next = 0;
    Future<void> worker() async {
      while (next < seeds.length) {
        final i = next++;
        final s = seeds[i];
        final p = _provider(s.provider);
        if (p == null) continue;
        final cursor = _store.cursorOf(s);
        var page = await p.station(s.station, cursor);
        // A stale cursor starts over.
        if (page.tracks.isEmpty && cursor.isNotEmpty) {
          page = await p.station(s.station, '');
        }
        cursors[s] = page.cursor;
        pages[i] = page.tracks;
      }
    }

    await Future.wait([
      for (var k = 0; k < min(_kParallel, seeds.length); k++) worker(),
    ]);
    _store.saveCursors(cursors);
    return pages;
  }

  WavePick _pick(WaveRun run) {
    final lib = ref.read(libraryProvider);
    final stats = ref.read(playStatsProvider);
    final queue = _queue;
    return WavePick(
      run: run,
      queue: queue.queue,
      currentId: queue.track?.id,
      library: lib.allTracks,
      inLibrary: lib.isInLib,
      isFav: lib.isFav,
      isDisliked: ref.read(waveStoreProvider).isDisliked,
      playedWithin: (id, days) => stats.recentlyPlayed(id, days),
      shown: _store.shownIds(),
      random: _rnd,
    );
  }

  /// Shown goes only on foreign tracks: own ones come as My wave's share, with
  /// no reason to strike them for two weeks.
  void _markShown(List<Track> batch) {
    final lib = ref.read(libraryProvider);
    _store.markShown([
      for (final t in batch)
        if (!lib.isInLib(t.id)) t.id,
    ]);
  }

  void _save() => _store.saveRun(_run);

  // ── Running ─────────────────────────────────────────────────────────────

  /// Few tracks ahead: the next batch comes from the last heard (the wave
  /// follows what the listener stays with) or the starting seeds.
  Future<void> _refill() async {
    final run = _run;
    if (run == null || !_inWave || state.starting || _refilling) return;
    final queue = _queue;
    final left = queue.queue.length - 1 - queue.index;
    if (left > (run.native ? kWaveRefillAtNative : kWaveRefillAt)) return;
    var seeds = run.seeds;
    if (!run.native) {
      final store = ref.read(waveStoreProvider);
      final recent = <WaveSeed>[];
      final heard = run.played.skip(max(0, run.played.length - 6)).toList();
      for (final id in heard.reversed) {
        if (recent.length >= 3) break;
        if (store.isDisliked(id)) continue;
        final t = queue.queue.where((t) => t.id == id).firstOrNull;
        final s = t == null ? null : seedOf(t);
        if (s != null) recent.add(s);
      }
      if (recent.isNotEmpty) seeds = recent;
    }
    _refilling = true;
    final gen = _gen;
    try {
      final pages = await _gather(seeds);
      if (gen != _gen || !_inWave) return;
      final batch = pickBatch(pages, _pick(run));
      if (batch.isEmpty) return;
      _markShown(batch);
      _playback.appendToQueue(batch);
      _save();
    } finally {
      if (gen == _gen) _refilling = false;
    }
  }

  /// The player started a track. Moved to another list, the wave quietly ends,
  /// or its loading would write to someone else's queue.
  void onTrackStart(Track track) {
    if (_queue.source is! WaveSource) {
      endSession();
      return;
    }
    final run = _run;
    if (run == null) return;
    final s = run.seeds.first;
    if (run.native && track.source.code == s.provider) {
      _provider(
        s.provider,
      )?.stationFeedback(s.station, 'trackStarted', track: track);
    }
    unawaited(_refill());
  }

  /// A track counted as heard: it's heard in the wave, and the stock is due a
  /// check.
  void onCounted(Track track) {
    final run = _run;
    if (run == null || !_inWave) return;
    if (!run.played.contains(track.id)) run.played.add(track.id);
    if (run.played.length > 200) {
      run.played.removeRange(0, run.played.length - 200);
    }
    _save();
    unawaited(_refill());
  }

  /// Leaving a track: finished (85%) or skipped early (under 20 s and 30%). The
  /// wave learns the artist, and a Yandex station gets told.
  void onTrackEnd(Track track, Duration played, Duration total) {
    final run = _run;
    if (run == null || !_inWave || total <= Duration.zero) return;
    if (run.native) {
      final s = run.seeds.first;
      if (track.source.code != s.provider) return;
      final ratio = played.inMilliseconds / total.inMilliseconds;
      _provider(s.provider)?.stationFeedback(
        s.station,
        ratio < 0.3 ? 'skip' : 'trackFinished',
        track: track,
        played: played.inMilliseconds / 1000,
      );
      return;
    }
    final step = completionStep(played, total);
    final artists = artistKeys(track);
    if (step == 0 || artists.isEmpty) return;
    for (final a in artists) {
      run.bonus[a] = (run.bonus[a] ?? 0) + step;
    }
    _save();
  }

  // ── Dislike ─────────────────────────────────────────────────────────────

  /// Sets or clears a dislike; returns whether it's set now. A disliked playing
  /// track leaves, staying struck through in the queue.
  bool toggleDislike(Track track) {
    final on = _store.toggleDislike(track);
    if (!on) return false;
    final queue = _queue;
    if (queue.track?.id == track.id) {
      if (queue.index < queue.queue.length - 1) {
        unawaited(_playback.next());
      } else if (_inWave) {
        unawaited(_refill());
      }
    }
    return true;
  }

  // ── Ending ──────────────────────────────────────────────────────────────

  /// Stops the wave explicitly. The queue plays out, but loads no more.
  void stop() => endSession();

  /// The wave ended; an answer still on its way is dropped.
  void endSession() {
    if (_run == null && !state.active) return;
    _end();
  }

  void _end() {
    ++_gen;
    _run = null;
    _refilling = false;
    _store.saveRun(null);
    state = const WaveRunState();
  }

  // ── Auto similar ────────────────────────────────────────────────────────

  /// The queue ended or nearly: adds tracks like what's in it to the tail (the
  /// Similar to queue button replaces instead). The tail then runs as a similar
  /// to queue wave. Quiet, with no toasts: this is background, not a pressed
  /// button. [isValid]: something else may have been started during the wait.
  Future<bool> continueQueue({required bool Function() isValid}) async {
    if (state.starting) return false;
    final queue = _queue.queue;
    final seeds = queueSeeds(queue, _view(extras: queue));
    if (seeds.isEmpty) return false;
    final r = await _begin(
      WaveMode.queue,
      seeds,
      replace: false,
      isValid: isValid,
    );
    return r == WaveStartResult.ok;
  }

  /// Picks up a wave the session returned: the snapshot brought the queue, and
  /// this brings picks' memory. If the session wasn't a wave, the saved one is
  /// forgotten.
  void adoptRestored(PlaySource? source) {
    final saved = _store.savedRun;
    if (source is! WaveSource) {
      if (saved != null) _store.saveRun(null);
      return;
    }
    if (saved == null) return;
    _run = saved;
    state = WaveRunState(mode: saved.mode, about: saved.about);
  }
}

/// Source caption for the player's pill. Taken once, when the queue is set: a
/// session snapshot outlives the chosen language, with nobody to translate it
/// later.
String waveLabel(WaveMode mode) {
  final l = globalL10n;
  return switch (mode) {
    WaveMode.personal => l?.waveTitle ?? 'My Wave',
    WaveMode.track => l?.waveLabelTrack ?? 'Track wave',
    WaveMode.queue => l?.waveLabelQueue ?? 'Similar to queue',
    WaveMode.artist => l?.waveLabelArtist ?? 'Artist wave',
  };
}
