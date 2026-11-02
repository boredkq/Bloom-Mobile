/// The player: track queue, stream resolving through the platform's provider,
/// auto-advance.
///
/// It knows nothing of platforms: it takes the provider by the track id's
/// prefix and asks [MusicProvider.resolveStream]. The stream resolves at the
/// moment of the change, not ahead: SoundCloud's signed URL expires, so
/// `ConcatenatingAudioSource` won't do. A track with a downloaded copy plays
/// from disk with no platform asked.
///
/// Background, shade and headset are in [BloomAudioHandler], which owns
/// [AudioPlayer] and sends outside commands back here ([PlaybackCommands]), so
/// next in the shade and in the app are one code.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/providers.dart';
import '../../core/db/db.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/log/bloom_log.dart';
import '../../core/store/library_store.dart';
import '../../core/store/settings_store.dart';
import '../../shared/ui/bloom_toast.dart';
import '../lastfm/lastfm_store.dart';
import '../library/local_tracks.dart';
import '../offline/offline_store.dart';
import '../wave/wave_controller.dart';
import '../../core/store/play_log.dart';
import '../pc/pc_remote.dart';
import 'audio_handler.dart';
import 'nightcore_ios.dart';
import 'notification_permission.dart';
import 'play_error.dart';
import 'play_source.dart';
import 'session_store.dart';
import 'sleep_timer_store.dart';
import 'speed_store.dart';
import 'track_swap_dir.dart';

enum PlayerRepeat { off, all, one }

/// Overridden in `main()` with the instance from `AudioService.init`.
final audioHandlerProvider = Provider<BloomAudioHandler>((ref) {
  throw StateError('audioHandlerProvider is not overridden in main()');
});

final audioPlayerProvider = Provider<AudioPlayer>(
  (ref) => ref.watch(audioHandlerProvider).player,
);

/// The playhead: where we are and how long in all.
typedef Playhead = ({Duration position, Duration total});

/// Position and duration as one stream. Apart they drift: on a track change the
/// position ticks from the new one while `player.duration` read past the stream
/// is still the old, and the share jumps. Duration also arrives with no
/// position tick (pause, loading).
final playheadProvider = StreamProvider<Playhead>((ref) {
  // Computer remote: its position, moving on its own between its ticks.
  final remote = ref.watch(pcRemoteProvider);
  if (remote != null) {
    Playhead now() => remote.playheadAt(DateTime.now());
    if (!remote.playing) return Stream.value(now());
    Stream<Playhead> ticks() async* {
      yield now();
      yield* Stream.periodic(const Duration(milliseconds: 250), (_) => now());
    }

    return ticks();
  }
  final player = ref.watch(audioPlayerProvider);
  final out = StreamController<Playhead>();
  var position = player.position;
  var total = player.duration ?? Duration.zero;
  void emit() {
    if (!out.isClosed) out.add((position: position, total: total));
  }

  final subs = [
    player.positionStream.listen((p) {
      position = p;
      emit();
    }),
    player.durationStream.listen((d) {
      total = d ?? Duration.zero;
      emit();
    }),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    out.close();
  });
  emit(); // first value at once, before the first tick
  return out.stream;
});

/// Whether sound plays. A separate stream because `playing` also changes past
/// me: the shade, a headset, audio focus.
final playingProvider = StreamProvider<bool>((ref) {
  final remote = ref.watch(pcRemoteProvider.select((r) => r?.playing));
  if (remote != null) return Stream.value(remote);
  final player = ref.watch(audioPlayerProvider);
  return player.playingStream;
});

/// The same at once, with no wait for the stream's first value: buttons and
/// bars need it right on the first frame. As a remote, it's the computer's
/// state.
final playingNowProvider = Provider<bool>(
  (ref) =>
      ref.watch(playingProvider).value ??
      ref.watch(pcRemoteProvider.select((r) => r?.playing)) ??
      ref.read(audioPlayerProvider).playing,
);

class PlaybackState {
  final List<Track> queue;
  final int index;
  final bool loading;
  final String? error;
  final PlayerRepeat repeat;
  final bool shuffle;

  /// Where the queue came from; see [PlaySource]. `null` means no source. Used
  /// by the player's pill and by cards: by [sourceId] a set tile shows the
  /// equalizer. It can't be worked out from the queue: one set of tracks can
  /// sit in two lists.
  final PlaySource? source;

  const PlaybackState({
    this.queue = const [],
    this.index = -1,
    this.loading = false,
    this.error,
    this.repeat = PlayerRepeat.off,
    this.shuffle = false,
    this.source,
  });

  Track? get track =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  /// What plays after this track, for the Next plate. `null` when nothing does:
  /// the queue ended and doesn't loop. On the last track I look at repeat,
  /// because [next] does the looping (`(index + 1) % length`): with `all` it's
  /// the first track, with `off` and `one` silence or the same track. A
  /// one-track queue never has a next.
  Track? get nextTrack {
    if (index < 0 || queue.length < 2) return null;
    if (index + 1 < queue.length) return queue[index + 1];
    return repeat == PlayerRepeat.all ? queue.first : null;
  }

  /// Source key for comparing with a list id; see [PlaySource.id].
  String? get sourceId => source?.id;

  PlaybackState copyWith({
    List<Track>? queue,
    int? index,
    bool? loading,
    String? error,
    bool clearError = false,
    PlayerRepeat? repeat,
    bool? shuffle,
    PlaySource? source,
    bool clearSource = false,
  }) => PlaybackState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    repeat: repeat ?? this.repeat,
    shuffle: shuffle ?? this.shuffle,
    source: clearSource ? null : (source ?? this.source),
  );
}

final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);

/// Where the playing track ([current]) lands when row [from] moves to [target]
/// (both real indices, with no list correction). The same track keeps playing,
/// only its index changes. A bug here is quiet: the same sound plays, but next
/// goes astray.
int indexAfterReorder(int current, int from, int target) {
  if (current == from) return target;
  if (from < current && target >= current) return current - 1;
  if (from > current && target <= current) return current + 1;
  return current;
}

/// Queue after Play next: [track] goes right behind the playing one ([index]),
/// and if already queued it moves rather than duplicates. Returns the new order
/// and the playing index. A separate function, like [indexAfterReorder], so it
/// can be checked with lists.
(List<Track>, int) queueWithNext(List<Track> queue, int index, Track track) =>
    queueWithNextAll(queue, index, [track]);

/// The same for a batch, like a whole playlist. Batch order stays, repeats
/// within it collapse, queued tracks move rather than double. The playing track
/// drops from the batch: it's already sounding.
(List<Track>, int) queueWithNextAll(
  List<Track> queue,
  int index,
  List<Track> batch,
) {
  final current = (index >= 0 && index < queue.length) ? queue[index] : null;
  final seen = <String>{};
  final add = [
    for (final t in batch)
      if (t.id != current?.id && seen.add(t.id)) t,
  ];
  if (add.isEmpty) return (queue, index);
  final rest = [
    for (final t in queue)
      if (!seen.contains(t.id)) t,
  ];
  // The playing index is found AFTER removal: tracks may have been pulled from
  // above it.
  final at = current == null ? -1 : rest.indexWhere((t) => t.id == current.id);
  return ([...rest]..insertAll(at + 1, add), at < 0 ? index : at);
}

/// Shuffled copy of [tracks]. Track [keep] goes first and stays out of the
/// shuffle (`-1` shuffles all), the rest by Fisher–Yates. The playing track
/// must come first: shuffling doesn't break what's sounding, only what's next.
List<Track> shuffledQueue(List<Track> tracks, int keep, Random rnd) {
  final rest = [...tracks];
  final head = (keep >= 0 && keep < rest.length) ? rest.removeAt(keep) : null;
  for (var i = rest.length - 1; i > 0; i--) {
    final j = rnd.nextInt(i + 1);
    final tmp = rest[i];
    rest[i] = rest[j];
    rest[j] = tmp;
  }
  return head == null ? rest : [head, ...rest];
}

class PlaybackController extends Notifier<PlaybackState>
    implements PlaybackCommands {
  final _rnd = Random();

  /// Queue order before shuffling, to return to when it's turned off. `null` if
  /// not shuffled.
  List<Track>? _origQueue;

  /// Launch counter: a stale stream answer mustn't override a track picked
  /// later.
  int _generation = 0;

  /// Notification permission is asked once per session and only before the
  /// first sound: no reason for a system dialog at app start.
  bool _askedForNotifications = false;

  /// This track's play is already counted. Reset only on a track change (in
  /// [_load]), so a repeat's second round doesn't count again.
  bool _credited = false;

  /// The queue as it was before clearing (the clear button, or removing the
  /// last track), restored on resume. A new queue resets it; clearing again
  /// doesn't overwrite the full queue with a cut one.
  List<Track>? _preClearQueue;

  /// Auto similar: the track a continuation was already asked for…
  String? _autoSimilarFor;

  /// …the request still in flight…
  bool _autoSimilarPending = false;

  /// …and next pressed before the batch came. All three reset on a track change
  /// (in [_load]).
  bool _autoSimilarAdvance = false;

  /// The queue played out with no repeat, and the player sits at the start of
  /// the last track. A late auto similar batch then moves on to it by itself.
  bool _queueEnded = false;

  @override
  PlaybackState build() {
    final handler = ref.read(audioHandlerProvider);
    handler.commands = this;
    final subs = [
      handler.player.processingStateStream.listen((s) {
        if (s == ProcessingState.completed) _onCompleted();
      }),
      // A play counts at 90% of the track; Last.fm has its own separate rule
      // (see [_onPosition]).
      handler.player.positionStream.listen(_onPosition),
      // The session saves on every play or pause: pause is when people most
      // often leave.
      handler.player.playingStream.listen((playing) {
        _stateDirty();
        _reportToPc();
        // Sound just played: the played here mark lands at the moment of pause.
        if (!playing && BloomDb.now() - _audibleAt < 6000) {
          _audibleAt = 0;
          _markAudible();
        }
      }),
    ];
    // And on a timer while playing: the process gets killed with no warning,
    // and with no tick a resume would return to the last pause.
    final ticker = Timer.periodic(_sessionEvery, (_) {
      if (handler.player.playing) {
        _stateDirty();
        _reportToPc(); // a computer showing this phone syncs its clock
      }
    });
    ref.onDispose(() {
      ticker.cancel();
      _queueSave?.cancel();
      _stateSave?.cancel();
      for (final s in subs) {
        s.cancel();
      }
      if (handler.commands == this) handler.commands = null;
    });
    // Speed and pitch are a separate setting while the player is here, so I
    // apply them and keep listening: a saved speed must work from the first
    // track, not once the picker opens.
    ref.listen(speedProvider, (_, next) => unawaited(_applySpeed(next)));
    unawaited(_applySpeed(ref.read(speedProvider)));
    // Sleep timer: the store ticks time, and pause and fade happen here, where
    // the player is. I listen to every tick: zero left is the command itself.
    ref.listen(sleepTimerProvider, (_, next) => _applySleep(next));
    ref.onDispose(_stopFade);
    // The shade's heart: a like can come from anywhere and a track can change a
    // dozen ways, so I watch both rather than buttons.
    ref.listen(libraryProvider.select((lib) => lib.favs), (_, _) => _syncFav());
    // Computer remote: while there is one, the screen shows what plays there
    // and commands go there (see [_pc]). My own queue and session stay as they
    // are.
    ref.listen(pcRemoteProvider, (_, remote) {
      state = remote?.playback ?? _local;
      _syncFav();
    });
    _local = const PlaybackState();
    return ref.read(pcRemoteProvider)?.playback ?? _local;
  }

  /// My own state, what plays on this phone. It goes out ([state]) only while
  /// the phone isn't a remote.
  PlaybackState _local = const PlaybackState();

  PlaybackState get _st => _local;

  set _st(PlaybackState next) {
    final prev = _local;
    _local = next;
    if (ref.read(pcRemoteProvider) == null) state = next;
    _reportToPc();
    if (prev.track?.id != next.track?.id) _syncFav();
    // Shuffling also changes the order to return to.
    if (!identical(prev.queue, next.queue) || prev.shuffle != next.shuffle) {
      _queueDirty();
    } else if (prev.index != next.index ||
        prev.loading != next.loading ||
        !identical(prev.source, next.source) ||
        prev.repeat != next.repeat) {
      _stateDirty();
    }
  }

  /// The computer remote, if the phone is one now.
  PcRemoteController? get _pc => ref.read(pcRemoteProvider) == null
      ? null
      : ref.read(pcRemoteProvider.notifier);

  /// Sleep fade tick. Not `null`: the volume is going down.
  Timer? _fadeTick;

  /// Reacts to the sleep timer state. No clock of my own: the only clock is
  /// `endsAt` in the store, so time left is counted from it. The store ticks
  /// every second and the fade every 100 ms: in one-second steps the volume
  /// drop is audible.
  void _applySleep(SleepTimerState sleep) {
    if (sleep.expired) {
      _fireSleep();
      return;
    }
    if (sleep.mode != SleepMode.timer || !sleep.fade) {
      _stopFade();
      return;
    }
    if (sleep.remaining <= kSleepFade) {
      _fadeTick ??= Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _fadeStep(),
      );
    } else {
      // The timer was extended or restarted, leaving the fade zone.
      _stopFade();
    }
  }

  /// Fade step: volume is the unspent share of the [kSleepFade] window.
  void _fadeStep() {
    final endsAt = ref.read(sleepTimerProvider).endsAt;
    if (endsAt == null) {
      _stopFade();
      return;
    }
    final left = endsAt.difference(ref.read(sleepClockProvider)());
    final k = (left.inMilliseconds / kSleepFade.inMilliseconds).clamp(0.0, 1.0);
    unawaited(_player.setVolume(k));
    // Zero is no reason to pause here: the store's tick does it through
    // [_fireSleep], and one stopping point leaves less to drift apart.
  }

  /// Restores the volume, from wherever the fade ended, whether fired or
  /// cancelled: a half-faded volume would carry into the next listen.
  void _stopFade() {
    if (_fadeTick == null) return;
    _fadeTick!.cancel();
    _fadeTick = null;
    unawaited(_player.setVolume(1));
  }

  /// Time's up: pause, restore the volume, clear the timer.
  void _fireSleep() {
    _fadeTick?.cancel();
    _fadeTick = null;
    unawaited(_player.pause());
    unawaited(_player.setVolume(1));
    ref.read(sleepTimerProvider.notifier).cancel();
  }

  /// Speed and pitch on the player. No need to repeat per track: just_audio
  /// keeps both and moves them to a new source.
  Future<void> _applySpeed(SpeedSettings speed) async {
    // iOS before speed: setting speed is what applies the algorithm to the
    // track.
    await setIosNightcore(speed.nightcore);
    await _player.setSpeed(speed.rate);
    try {
      await _player.setPitch(speed.pitch);
    } catch (_) {
      // Only Android has pitch (ExoPlayer). On iOS the channel answers with an
      // error, and `setIosNightcore` makes pitch follow tempo.
    }
  }

  /// How often the session position updates while playing. Rarer gives a
  /// noticeable jump back after a kill, more often a pointless write.
  static const Duration _sessionEvery = Duration(seconds: 10);

  /// Session writes wait 300 ms: a burst of queue edits becomes one write.
  Timer? _queueSave, _stateSave;

  void _queueDirty() {
    _stateSave?.cancel();
    _queueSave?.cancel();
    _queueSave = Timer(const Duration(milliseconds: 300), _saveQueue);
  }

  /// The queue is waiting to be written, and will write the state too.
  void _stateDirty() {
    if (_queueSave?.isActive == true || _stateSave?.isActive == true) return;
    _stateSave = Timer(const Duration(milliseconds: 300), _saveState);
  }

  /// Writes what's waiting at once.
  void _flushSession() {
    if (_queueSave?.isActive == true) {
      _saveQueue();
    } else if (_stateSave?.isActive == true) {
      _saveState();
    }
  }

  /// An empty queue leaves the row alone: a stop doesn't erase what was heard.
  void _saveQueue() {
    _queueSave?.cancel();
    ref
        .read(sessionProvider.notifier)
        .saveQueue(_st.queue, _st.shuffle ? _origQueue : null, _preClearQueue);
    _saveState();
  }

  void _saveState() {
    _stateSave?.cancel();
    final track = _st.track;
    if (track == null) return;
    ref
        .read(sessionProvider.notifier)
        .saveState(
          index: _st.index,
          // While a new track loads (or failed), the player's position is still
          // the last one's, so I write the one it started from.
          position: _st.loading || _loadedId != track.id
              ? _loadingAt
              : _player.position,
          source: _st.source,
          shuffle: _st.shuffle,
          repeat: _st.repeat,
          ended: _queueEnded,
          playing: _player.playing,
        );
  }

  BloomAudioHandler get _handler => ref.read(audioHandlerProvider);
  AudioPlayer get _player => _handler.player;

  /// Share of a track after which a play counts.
  static const double _creditAt = 0.9;

  /// When sound last played here (kv [kConnectPlayed]): Connect decides where
  /// to play by it. At most once in 5 s.
  ///
  /// The position tick has two listeners with DIFFERENT thresholds: my play
  /// credit (0.9 of the duration) and Last.fm's scrobble (30 s and half, the
  /// platform's own rule). While a new track loads, ticks still belong to the
  /// last one, so both wait.
  int _audibleAt = 0;

  void _markAudible() {
    final now = BloomDb.now();
    if (now - _audibleAt < 5000) return;
    _audibleAt = now;
    ref.read(dbProvider).set(kConnectPlayed, now);
  }

  void _onPosition(Duration position) {
    // Sound really plays, not getting ready on load.
    if (_player.playing && _player.processingState == ProcessingState.ready) {
      _markAudible();
    }
    if (_st.loading) return;
    _maybeCredit(position);
    ref.read(lastfmProvider.notifier).onProgress(position, _player.duration);
  }

  /// Position tick: at the threshold the play counts. While a new track loads,
  /// ticks belong to the last one and would count for the wrong track.
  void _maybeCredit(Duration position) {
    if (_credited || _st.loading) return;
    final total = _player.duration;
    if (total == null || total <= Duration.zero) return;
    if (position.inMilliseconds >= total.inMilliseconds * _creditAt) _credit();
  }

  /// Counts a play in the log. One point for all, and NOT at the start: a track
  /// skipped or never started isn't heard.
  void _credit() {
    if (_credited) return;
    final track = _st.track;
    if (track == null) return;
    _credited = true;
    // The "track X at time T" log: history, profile stats and days, the level,
    // wave seeds and Wrapped all derive from it.
    ref.read(playLogProvider.notifier).log(track);
    // In the wave the track is now heard, and its stock is due a check.
    ref.read(waveProvider.notifier).onCounted(track);
    // The queue's last track counted: I ask for a continuation early, so the
    // batch is there at the end and the change goes the usual way, with no
    // pause.
    _maybeAutoSimilar();
  }

  /// Auto similar: when the queue's last track is counted, ends or gets next
  /// pressed, similar tracks go on the tail (see
  /// `WaveController.continueQueue`). Not on repeat, which decides what follows
  /// itself, or in a live wave, which loads on its own.
  void _maybeAutoSimilar() {
    if (!ref.read(settingsProvider).autoSimilar) return;
    final track = _st.track;
    if (track == null || _st.repeat != PlayerRepeat.off) return;
    if (_st.index != _st.queue.length - 1) return;
    if (_st.source is WaveSource && ref.read(waveProvider).active) return;
    if (_autoSimilarFor == track.id) return;
    _autoSimilarFor = track.id;
    _autoSimilarPending = true;
    final source = _st.source;
    unawaited(
      ref
          .read(waveProvider.notifier)
          // The source changed while waiting for the network (a playlist
          // started), so I don't write to someone else's queue.
          .continueQueue(isValid: () => identical(_st.source, source))
          .catchError((Object _) => false)
          .then((ok) {
            // The track changed, so this continuation isn't mine any more.
            if (_autoSimilarFor != track.id) return;
            _autoSimilarPending = false;
            // The batch came late: the track ended or next was pressed, so I
            // move to the first added one.
            if (ok && (_queueEnded || _autoSimilarAdvance)) unawaited(next());
            _autoSimilarAdvance = false;
          }),
    );
  }

  /// Sets a queue and plays from [index]. [source] is where it came from
  /// ([PlaybackState.source]); if omitted the old source resets.
  ///
  /// With shuffle on the new queue is shuffled at once: queue order is playback
  /// order, or the flag would be up with tracks in sequence.
  Future<void> playQueue(List<Track> tracks, int index, {PlaySource? source}) {
    if (_pc case final pc?) return pc.playQueue(tracks, index, source: source);
    if (_st.shuffle && tracks.length > 1) {
      return _start(
        shuffledQueue(tracks, index, _rnd),
        0,
        source: source,
        orig: tracks,
      );
    }
    return _start(tracks, index, source: source, orig: null);
  }

  /// Shuffle from a list card: turns shuffle on and starts from a random track,
  /// not the first.
  Future<void> playQueueShuffled(List<Track> tracks, {PlaySource? source}) {
    if (tracks.isEmpty) return Future.value();
    if (_pc case final pc?) {
      return pc.playQueue(tracks, 0, source: source, shuffle: true);
    }
    _st = _st.copyWith(shuffle: true);
    return _start(
      shuffledQueue(tracks, -1, _rnd),
      0,
      source: source,
      orig: tracks,
    );
  }

  Future<void> _start(
    List<Track> tracks,
    int index, {
    required PlaySource? source,
    required List<Track>? orig,
    Duration? startAt,
    bool autoplay = true,
    List<Track>? preClear,
  }) async {
    if (tracks.isEmpty) return;
    _origQueue = orig;
    // A new queue leaves nothing to be before clearing. Except a restored cut
    // one: the full one stays, or the first snapshot write loses it and a
    // resume brings back one track.
    _preClearQueue = preClear;
    _st = _st.copyWith(
      queue: tracks,
      index: index,
      clearError: true,
      source: source,
      clearSource: source == null,
    );
    _handler.setQueue(tracks);
    await _load(index, startAt: startAt, autoplay: autoplay);
  }

  /// One track is a queue of itself, and the pill shows it.
  Future<void> play(Track track) =>
      playQueue([track], 0, source: PlainSource.single(track));

  /// Sets a wave queue. Apart from [playQueue] for shuffle's sake: the wave
  /// picks its own order, and reshuffling would throw away its work. So the
  /// flag goes off.
  Future<void> playWave(List<Track> tracks, WaveSource source) {
    if (_pc case final pc?) return pc.playQueue(tracks, 0, source: source);
    _st = _st.copyWith(shuffle: false);
    return _start(tracks, 0, source: source, orig: null);
  }

  /// Adds a batch to the queue's end, for wave loading. Unlike [addToQueue]
  /// there are many tracks and queued ones are skipped silently: picks may
  /// offer what's there already.
  void appendToQueue(List<Track> tracks) =>
      _pc?.enqueue(tracks) ?? _append(tracks);

  /// What follows the playing track, replaced by [tracks] ("Shake up My
  /// Wave"); the playing one plays on.
  void replaceUpcoming(List<Track> tracks) {
    if (_st.queue.isEmpty) return;
    final q = _st.queue.take(_st.index + 1).toList();
    _origQueue = null;
    _st = _st.copyWith(queue: q);
    _handler.setQueue(q);
    _append(tracks);
  }

  /// Adds and returns how many really went in.
  int _append(List<Track> tracks) {
    if (tracks.isEmpty || _st.queue.isEmpty) return 0;
    final have = {for (final t in _st.queue) t.id};
    final add = [
      for (final t in tracks)
        if (have.add(t.id)) t,
    ];
    if (add.isEmpty) return 0;
    final q = [..._st.queue, ...add];
    final orig = _origQueue;
    if (orig != null) _origQueue = [...orig, ...add];
    _st = _st.copyWith(queue: q);
    _handler.setQueue(q);
    return add.length;
  }

  /// Auto similar: adds the continuation and the queue becomes a wave, loading
  /// by itself from here. The current track plays on. Shuffle goes off with no
  /// return to the earlier snapshot: the wave sets its own order, and returning
  /// would drop what was just added. Returns whether anything went in.
  bool continueAsWave(List<Track> tracks, WaveSource source) {
    if (_pc != null) return false; // the computer continues its queue itself
    if (_append(tracks) == 0) return false;
    _origQueue = null;
    _st = _st.copyWith(source: source, shuffle: false);
    return true;
  }

  /// Resumes the last session: the same queue from the same position. It may
  /// have been a wave: the queue returns by itself, but picks' memory lives
  /// apart, and without it the wave would play out the saved tracks and stop.
  ///
  /// With [autoplay] `false` the session returns PAUSED, as for queue restore
  /// at launch.
  Future<void> resumeSession(SessionData data, {bool autoplay = true}) async {
    // Resuming my own session as a remote: the same queue, playing on the
    // computer.
    if (_pc case final pc?) {
      return pc.playQueue(data.queue, data.index, source: data.source);
    }
    ref.read(waveProvider.notifier).adoptRestored(data.source);
    // Modes go BEFORE the queue: `_start` leaves them alone and `_load` already
    // looks at repeat. The queue was saved shuffled, so shuffle returns as a
    // flag and the earlier order from `orig`.
    _st = _st.copyWith(shuffle: data.shuffle, repeat: data.repeat);
    await _start(
      data.queue,
      data.index,
      source: data.source,
      orig: data.shuffle && data.orig.isNotEmpty ? data.orig : null,
      // In the first couple of seconds there's nothing to seek past, so I start
      // from the top.
      startAt: data.position > const Duration(seconds: 2)
          ? data.position
          : null,
      autoplay: autoplay,
      preClear: data.full.isEmpty ? null : data.full,
    );
    // It played out: next and auto similar behave as they did then.
    if (data.ended && _st.track?.id == data.track.id) _queueEnded = true;
  }

  /// A track loaded but not started (restore on pause). The track-started
  /// events for the wave and Last.fm must happen when sound really goes: now
  /// playing while paused would be a lie to the platform. So it waits here and
  /// [commandPlay] fires them.
  Track? _pendingStart;

  /// Id of the track whose stream really opened. For the wave: on leaving,
  /// [_reportWaveTrackEnd] reports how long it was heard, but a skipped one
  /// wasn't, and `_player.duration` is still the last real track's. Without
  /// this mark a chain of auto-skips would teach picks something that never
  /// happened.
  String? _loadedId;

  /// Position the current track started from, written by the session while it
  /// loads.
  Duration _loadingAt = Duration.zero;

  /// [skipped] is how many unavailable tracks this chain already passed. The
  /// cap is the queue length: if none plays, the auto-skip must stop, not loop.
  /// A parameter rather than a field: the chain lives one run, with nowhere to
  /// reset it later.
  Future<void> _load(
    int index, {
    Duration? startAt,
    bool autoplay = true,
    int skipped = 0,
  }) async {
    final track = _st.queue[index];
    // Leaving a track is the only signal the wave learns from: how long it was
    // heard is how much it was liked. Counted before the state changes, while
    // position and duration are still its own.
    _reportWaveTrackEnd(track);
    // Which way the display moves is worked out here, on the real change: the
    // player's and mini player's animation layers must go one way, and by
    // repaint the old index is lost.
    commitSwapDir(_st.queue, index);
    final gen = ++_generation;
    _loadingAt = startAt ?? Duration.zero;
    // The last track goes quiet AT ONCE, not when the new link arrives.
    // just_audio swaps the source only in setUrl, after the network trip, and
    // the old track would keep playing under the new title. No waiting: pause
    // flips `playing` synchronously and sends the platform command by itself.
    unawaited(_player.pause());
    _st = _st.copyWith(index: index, loading: true, clearError: true);
    // Another track is current: its credit starts over, and the last one's
    // deferred start is no longer needed.
    _credited = false;
    _pendingStart = null;
    _autoSimilarFor = null;
    _autoSimilarPending = false;
    _autoSimilarAdvance = false;
    _queueEnded = false;
    // The shade's title goes up at once, with no wait for the stream link.
    _handler
      ..setTrack(track, queueIndex: index)
      ..setResolving(true);
    if (!_askedForNotifications) {
      _askedForNotifications = true;
      unawaited(ensureNotificationPermission());
    }
    // A track's path to sound, step by step, written to disk at once. If the
    // native side kills the process (ExoPlayer, a codec, a driver), Dart never
    // hears, and the log's last line shows what didn't survive: the link,
    // opening the stream or playback itself.
    final startedAt = DateTime.now();
    var via = 'stream';
    logInfo(
      'player',
      'loading: ${track.name} · ${track.source.name}',
      now: true,
    );
    try {
      // An offline copy beats a network stream. It's also the only way to play
      // with no network.
      final offlinePath = ref.read(offlineProvider.notifier).pathOf(track.id);
      if (offlinePath != null) {
        via = 'offline';
        await _player.setFilePath(offlinePath, initialPosition: startAt);
      } else if (isLocalTrack(track)) {
        via = 'own file';
        // A local file: no platform behind it to ask. The copy inside the app
        // comes as `file://`, a user's file as `content://`, and both take
        // `AudioSource.uri`.
        final uri = localTrackUri(track);
        if (uri == null) throw const LocalFileGone();
        await _player.setAudioSource(
          AudioSource.uri(uri),
          initialPosition: startAt,
        );
      } else {
        final provider = ref.read(registryProvider).forEntity(track.id);
        if (provider == null) {
          throw StateError('no provider for ${track.id}');
        }
        final stream = await provider.resolveStream(track);
        if (stream == null) throw StateError('search.err.noStream');
        if (gen != _generation) return; // the user already changed the track
        logInfo(
          'player',
          'link received in '
              '${DateTime.now().difference(startedAt).inMilliseconds} ms, '
              'opening the stream',
          now: true,
        );
        await _player.setUrl(
          stream.url,
          headers: stream.headers.isEmpty ? null : stream.headers,
          initialPosition: startAt,
        );
      }
      if (gen != _generation) return;
      logInfo(
        'player',
        'stream open: $via · '
            '${DateTime.now().difference(startedAt).inMilliseconds} ms',
        now: true,
      );
      _loadedId = track.id;
      _st = _st.copyWith(loading: false);
      _handler.setResolving(false);
      if (autoplay) {
        _fireTrackStart(track);
      } else {
        // Loaded but not playing: track-started events wait for the first play.
        _pendingStart = track;
      }
      if (autoplay) logInfo('player', 'playing', now: true);
      // just_audio's play() completes NOT when playback starts but when the
      // track ends or pauses. Waiting on it leaves `loading` up all song and
      // the play button a spinner.
      if (autoplay) unawaited(_player.play());
    } catch (e) {
      if (gen != _generation) return;
      final code = playErrorCode(e);
      _st = _st.copyWith(loading: false, error: code);
      _handler.setResolving(false);
      logError('player', 'the track did not play: ${track.id}', e);
      _skipUnplayable(track, code, autoplay: autoplay, skipped: skipped);
    }
  }

  /// An unavailable track moves on along the queue. Without this the queue
  /// stalls: a DRM track never plays, and next would need pressing by hand on
  /// each.
  void _skipUnplayable(
    Track failed,
    String code, {
    required bool autoplay,
    required int skipped,
  }) {
    final q = _st.queue;
    // Where to go next is decided BEFORE saying anything: a skipping toast on a
    // one-track queue promises what won't happen.
    //
    // Restoring a session on pause (`autoplay: false`) isn't a skip: nobody
    // asked to play, and I can't flip through the queue at launch, so the error
    // just stays on screen.
    final canSkip = autoplay && q.length > 1 && skipped + 1 < q.length;

    final l = globalL10n;
    if (l != null) {
      // One toast per chain: they show strictly one at a time and queue up, so
      // half a minute of plates would float by instead of music.
      final (String, ToastKind)? say = switch ((canSkip, skipped)) {
        (true, 0) => (
          isDrmError(code) ? l.playerSkipDrm : l.playerSkipUnavailable,
          ToastKind.info,
        ),
        (true, _) => null,
        // Went through the whole queue and none played.
        (false, > 0) => (l.playerNoPlayable, ToastKind.error),
        // Nowhere to skip, so the reason itself matters.
        (false, _) => (describePlayError(l, code), ToastKind.error),
      };
      if (say != null) {
        toaster.show(say.$1, kind: say.$2);
      }
    }

    if (!canSkip) return;
    markSwapDir(1);
    // No waiting: a skip chain would nest awaits the length of the queue, and
    // whoever called the first `_load` has no reason to wait for the whole run.
    unawaited(_load((_st.index + 1) % q.length, skipped: skipped + 1));
  }

  /// Track started, for those counting plays. Called on a successful start, or
  /// for a session restored on pause from [commandPlay], when sound really goes
  /// (see [_pendingStart]).
  void _fireTrackStart(Track track) {
    _pendingStart = null;
    // Time for the wave to decide on loading a batch and whether the listener
    // left it. A track that never played is no event for picks.
    ref.read(waveProvider.notifier).onTrackStart(track);
    // Last.fm on the same event: now playing makes sense only for a track
    // really playing, and the scrobble's time count starts here.
    ref.read(lastfmProvider.notifier).onTrackStart(track);
  }

  /// Tells the wave how much the track being left has played. [next] is the
  /// track being changed to: coming back to the same one (a restart after
  /// `stop()`, a seek to the start) isn't leaving, or the wave would count it
  /// as skipped.
  void _reportWaveTrackEnd(Track next) {
    final prev = _st.track;
    if (prev == null || prev.id == next.id) return;
    // Leaving a track that never played (an auto-skip chain): nothing was
    // heard, and `_player.duration` is still the last one's, which would give
    // picks a second, made-up review (see [_loadedId]).
    if (prev.id != _loadedId) return;
    final total = _player.duration;
    if (total == null || total <= Duration.zero) return;
    ref.read(waveProvider.notifier).onTrackEnd(prev, _player.position, total);
  }

  void _onCompleted() {
    // The track played out, so it counts if it hasn't: a short one may have
    // missed the threshold tick.
    _credit();
    // An end of track sleep timer beats both repeat and advancing: that's what
    // it's for, silence after THIS track.
    if (ref.read(sleepTimerProvider).mode == SleepMode.endOfTrack) {
      _player.seek(Duration.zero);
      _player.pause();
      ref.read(sleepTimerProvider.notifier).cancel();
      return;
    }
    if (_st.repeat == PlayerRepeat.one) {
      _credited = false; // the next round counts anew
      if (_st.track case final track?) {
        ref.read(lastfmProvider.notifier).onTrackStart(track);
      }
      _player.seek(Duration.zero);
      unawaited(_player.play());
      return;
    }
    final isLast = _st.index >= _st.queue.length - 1;
    if (isLast && _st.repeat == PlayerRepeat.off) {
      _queueEnded = true;
      _player.seek(Duration.zero);
      _player.pause();
      // A short track may end before a continuation was asked, or it's in
      // flight and will move on by itself (see [_queueEnded]).
      _maybeAutoSimilar();
      return;
    }
    next();
  }

  /// On along the queue. Shuffle is unknown here: it already rearranged the
  /// queue itself (see [toggleShuffle]), so next is always next.
  Future<void> next() async {
    if (_pc case final pc?) return pc.next();
    final q = _st.queue;
    if (q.isEmpty) {
      cancelSwapSilent();
      return;
    }
    // Last track with auto similar on: instead of looping I wait for the
    // continuation, which moves on by itself. If this track's request already
    // came back empty, I act as usual.
    final track = _st.track;
    if (track != null &&
        _st.index == q.length - 1 &&
        _st.repeat == PlayerRepeat.off &&
        ref.read(settingsProvider).autoSimilar &&
        !(_st.source is WaveSource && ref.read(waveProvider).active) &&
        (_autoSimilarFor != track.id || _autoSimilarPending)) {
      _autoSimilarAdvance = true;
      _maybeAutoSimilar();
      cancelSwapSilent();
      return;
    }
    // Direction set explicitly: on a loop (last to first) comparing indices
    // would say backwards.
    markSwapDir(1);
    await _load((_st.index + 1) % q.length);
  }

  /// Previous: in the first 3 seconds to the previous track, after that to the
  /// start of this one.
  Future<void> prev() async {
    if (_pc case final pc?) return pc.prev();
    if (_st.queue.isEmpty) {
      cancelSwapSilent();
      return;
    }
    if (_player.position > const Duration(seconds: 3)) {
      // The track doesn't change, so I clear the no-animate flag myself: there
      // was a gesture with no change, and it would land on the next real one.
      cancelSwapSilent();
      await _player.seek(Duration.zero);
      return;
    }
    await prevTrack();
  }

  /// Previous track with no first-3-seconds rule. For the mini player's
  /// carousel: the user pulls in the card they see and must get just that.
  /// Seeking to the start would look like a failed gesture.
  Future<void> prevTrack() async {
    if (_pc case final pc?) return pc.jumpTo(state.index - 1);
    final q = _st.queue;
    if (q.isEmpty) {
      cancelSwapSilent();
      return;
    }
    markSwapDir(-1);
    await _load((_st.index - 1 + q.length) % q.length);
  }

  Future<void> toggle() async {
    if (_pc case final pc?) return pc.toggle();
    if (_player.playing) {
      await _player.pause();
    } else {
      await commandPlay();
    }
  }

  Future<void> seek(Duration to) async {
    if (_pc case final pc?) return pc.seek(to);
    await _player.seek(to);
    _reportToPc();
  }

  /// Mine changed, so the computer learns if it's showing this phone.
  void _reportToPc() => ref.read(pcRemoteProvider.notifier).reportSoon();

  void cycleRepeat() {
    if (_pc case final pc?) {
      unawaited(pc.cycleRepeat());
      return;
    }
    const order = [PlayerRepeat.off, PlayerRepeat.all, PlayerRepeat.one];
    final nextMode = order[(order.indexOf(_st.repeat) + 1) % order.length];
    _st = _st.copyWith(repeat: nextMode);
  }

  /// Shuffle rearranges the queue itself rather than handing [next] a random
  /// index, or the queue sheet would lie about what's next. Turning it off
  /// returns the saved order.
  void toggleShuffle() {
    if (_pc case final pc?) {
      unawaited(pc.toggleShuffle());
      return;
    }
    final q = _st.queue;
    if (_st.shuffle) {
      final orig = _origQueue;
      _origQueue = null;
      if (orig == null) {
        _st = _st.copyWith(shuffle: false);
        return;
      }
      // I find the playing track in the original order by id: it stays the
      // same, only its index changes.
      final current = _st.track;
      final at = current == null
          ? -1
          : orig.indexWhere((t) => t.id == current.id);
      final index = at < 0 ? 0 : at;
      _st = _st.copyWith(queue: orig, index: index, shuffle: false);
      _handler
        ..setQueue(orig)
        ..setTrack(_st.track, queueIndex: index);
      return;
    }
    if (q.length <= 1) {
      _st = _st.copyWith(shuffle: true);
      return;
    }
    _origQueue = [...q];
    final shuffled = shuffledQueue(q, _st.index, _rnd);
    _st = _st.copyWith(queue: shuffled, index: 0, shuffle: true);
    _handler
      ..setQueue(shuffled)
      ..setTrack(_st.track, queueIndex: 0);
  }

  /// Goes to a queue track by index.
  Future<void> jumpTo(int index) async {
    if (_pc case final pc?) return pc.jumpTo(index);
    if (index < 0 || index >= _st.queue.length) return;
    await _load(index);
  }

  /// Drags a track. Indices follow `ReorderableListView`: [to] counts BEFORE
  /// the row is removed, so moving down it's one above the real one.
  void reorder(int from, int to) {
    if (_pc case final pc?) {
      unawaited(pc.reorder(from, to));
      return;
    }
    final q = [..._st.queue];
    if (from < 0 || from >= q.length) return;
    final target = (to > from ? to - 1 : to).clamp(0, q.length - 1);
    if (target == from) return;
    q.insert(target, q.removeAt(from));

    final index = indexAfterReorder(_st.index, from, target);
    // The order was changed by hand, so the pre-shuffle snapshot is stale:
    // turning shuffle off must return what was last arranged.
    if (_origQueue != null) _origQueue = q;
    _st = _st.copyWith(queue: q, index: index);
    _handler
      ..setQueue(q)
      ..setTrack(_st.track, queueIndex: index);
  }

  /// Adds a track to the queue's end. Returns `false` if it's already queued:
  /// it doesn't go in twice, and the caller has something to say.
  bool addToQueue(Track track) => queueTracks([track]) > 0;

  /// Puts a track right after the current one. One already queued moves rather
  /// than duplicates.
  void playNext(Track track) => queueTracksNext([track]);

  /// Adds a batch to the queue, as with a whole list from the playlist menu.
  /// Returns how many really went in: queued ones are skipped, and the caller
  /// has something to say.
  ///
  /// An empty queue has nothing to extend, so the batch just starts playing,
  /// and [source] becomes the queue's source.
  int queueTracks(List<Track> tracks, {PlaySource? source}) {
    if (_pc case final pc?) return pc.enqueue(_dedup(tracks), source: source);
    final batch = _dedup(tracks);
    if (batch.isEmpty) return 0;
    if (_st.queue.isEmpty) {
      unawaited(playQueue(batch, 0, source: source));
      return batch.length;
    }
    final have = {for (final t in _st.queue) t.id};
    final add = [
      for (final t in batch)
        if (!have.contains(t.id)) t,
    ];
    if (add.isEmpty) return 0;
    final q = [..._st.queue, ...add];
    // The pre-shuffle snapshot grows too, or turning shuffle off would drop the
    // added tracks.
    final orig = _origQueue;
    if (orig != null) _origQueue = [...orig, ...add];
    _st = _st.copyWith(queue: q);
    _handler.setQueue(q);
    return add.length;
  }

  /// Play next for a batch. Returns for how many it changed something: the
  /// playing one drops from the batch, it's already sounding.
  int queueTracksNext(List<Track> tracks, {PlaySource? source}) {
    if (_pc case final pc?) {
      return pc.enqueue(_dedup(tracks), next: true, source: source);
    }
    final batch = _dedup(tracks);
    if (batch.isEmpty) return 0;
    if (_st.queue.isEmpty) {
      unawaited(playQueue(batch, 0, source: source));
      return batch.length;
    }
    final current = _st.track;
    final (q, index) = queueWithNextAll(_st.queue, _st.index, batch);
    if (identical(q, _st.queue)) return 0;
    // The pre-shuffle snapshot gets the same edit: it has the same playing
    // track in a different order.
    final orig = _origQueue;
    if (orig != null) {
      final at = current == null
          ? -1
          : orig.indexWhere((t) => t.id == current.id);
      _origQueue = queueWithNextAll(orig, at, batch).$1;
    }
    _st = _st.copyWith(queue: q, index: index);
    _handler
      ..setQueue(q)
      ..setTrack(_st.track, queueIndex: index);
    return batch.where((t) => t.id != current?.id).length;
  }

  /// A batch with no repeats, in original order: a list may send one track
  /// twice, and the queue needs one place.
  List<Track> _dedup(List<Track> tracks) {
    final seen = <String>{};
    return [
      for (final t in tracks)
        if (seen.add(t.id)) t,
    ];
  }

  /// Replaces a track in the queue: Change platform replaced the library entry,
  /// and the queue shouldn't point at a gone track.
  ///
  /// Playback position stays: this replaces a RECORD. The current stream plays
  /// out, and later the queue takes the track from the new platform.
  void replaceInQueue(String oldId, Track next) {
    if (!_st.queue.any((t) => t.id == oldId)) return;
    final q = [
      for (final t in _st.queue)
        if (t.id == oldId) next else t,
    ];
    final orig = _origQueue;
    if (orig != null) {
      _origQueue = [
        for (final t in orig)
          if (t.id == oldId) next else t,
      ];
    }
    _st = _st.copyWith(queue: q);
    _handler.setQueue(q);
    // The playing one was replaced, so what the shade shows updates too; the
    // sound isn't touched.
    if (_st.track?.id == next.id) {
      _handler.setTrack(_st.track, queueIndex: _st.index);
    }
  }

  /// Removes a track from the queue (a row swipe).
  Future<void> removeAt(int index) async {
    if (_pc case final pc?) return pc.removeAt(index);
    final q = [..._st.queue];
    if (index < 0 || index >= q.length) return;
    if (q.length == 1) {
      // The last one: the queue is empty and the player resets. Its rows (and
      // the queue before clearing) stay for a resume, so I write what's
      // waiting.
      _flushSession();
      await commandStop();
      await _player.stop();
      // Nothing to restore after a restart, and writing an empty queue writes
      // nothing, so I mark the session explicitly, or a removed track would
      // come back. The wave ended too: its queue is gone.
      ref.read(sessionProvider.notifier).markCleared();
      ref.read(waveProvider.notifier).endSession();
      return;
    }
    final current = _st.index;
    final removed = q.removeAt(index);
    // The swiped track also leaves the pre-shuffle snapshot, or turning shuffle
    // off would bring it back.
    final orig = _origQueue;
    if (orig != null) {
      final at = orig.indexWhere((t) => t.id == removed.id);
      if (at >= 0) _origQueue = [...orig]..removeAt(at);
    }
    if (index == current) {
      // The playing one was removed, so I play what took its place (or the
      // last).
      final next = index.clamp(0, q.length - 1);
      _st = _st.copyWith(queue: q, index: next);
      _handler.setQueue(q);
      await _load(next);
      return;
    }
    final shifted = index < current ? current - 1 : current;
    _st = _st.copyWith(queue: q, index: shifted);
    _handler
      ..setQueue(q)
      ..setTrack(_st.track, queueIndex: shifted);
  }

  /// Clears the queue, keeping the playing track. Playback isn't broken.
  void clearExceptCurrent() {
    if (_pc case final pc?) {
      unawaited(pc.clearExceptCurrent());
      return;
    }
    final track = _st.track;
    if (track == null) return;
    // Clearing again mustn't overwrite the full queue with a cut one.
    _preClearQueue ??= _st.queue.length > 1 ? _st.queue : null;
    _origQueue = null;
    _st = _st.copyWith(queue: [track], index: 0);
    _handler
      ..setQueue([track])
      ..setTrack(track, queueIndex: 0);
  }

  // --- Connect: sound moves between the phone and the computer

  /// My session as it is, taken by the computer. `null` if there's no queue.
  SessionData? localSession() {
    final track = _st.track;
    if (track == null) return null;
    return SessionData(
      queue: _st.queue,
      orig: _origQueue ?? const [],
      index: _st.index,
      position: _loadedId == track.id ? _player.position : _loadingAt,
      savedAt: DateTime.now(),
      source: _st.source,
      shuffle: _st.shuffle,
      repeat: _st.repeat,
    );
  }

  /// My track's duration, for the computer showing it.
  Duration get localDuration =>
      _player.duration ?? _st.track?.duration ?? Duration.zero;

  /// Mine goes on pause: the sound went to the computer. A load in flight isn't
  /// mine any more: uncancelled, on failure it would advance by itself and play
  /// here.
  Future<void> pauseLocal() {
    ++_generation;
    if (_st.loading) {
      _st = _st.copyWith(loading: false);
      _handler.setResolving(false);
    }
    return _player.pause();
  }

  // --- PlaybackCommands: from the shade, lock screen and headset

  @override
  Future<void> commandPlay() async {
    if (_pc case final pc?) return pc.play();
    // A new track is loading, so there's nothing to play: the player's source
    // is still the last one, and play() would bring just that back. The load
    // starts it by itself.
    if (_st.loading) return;
    // After stop() (the shade was swiped) just_audio's source is released, so
    // play must restart the track rather than silently do nothing.
    final track = _st.track;
    if (_player.processingState == ProcessingState.idle && track != null) {
      // The track never played (a restored session with no network), so again
      // from that position, not the start.
      await _load(
        _st.index,
        startAt: _loadedId != track.id && _loadingAt > Duration.zero
            ? _loadingAt
            : null,
      );
      return;
    }
    // A session restored on pause was just started: the moment to tell the wave
    // and Last.fm.
    final pending = _pendingStart;
    if (pending != null) _fireTrackStart(pending);
    unawaited(_player.play()); // see the note in _load
  }

  @override
  Future<void> commandPause() => _pc?.pause() ?? _player.pause();

  @override
  Future<void> commandNext() => next();

  @override
  Future<void> commandPrev() => prev();

  @override
  Future<void> commandSkipTo(int index) => jumpTo(index);

  @override
  Future<void> commandToggleFav() async {
    final track = state.track;
    if (track != null) ref.read(libraryProvider.notifier).toggleFav(track);
  }

  void _syncFav() {
    final id = _st.track?.id;
    _handler.setFav(id != null && ref.read(libraryProvider).isFav(id));
  }

  @override
  Future<void> commandStop() async {
    ++_generation; // cancels a resolve that may be in flight
    _origQueue = null; // nothing to return to: the queue is gone
    // The queue goes, but repeat and shuffle don't: they're player settings,
    // not a queue's property.
    _st = PlaybackState(repeat: _st.repeat, shuffle: _st.shuffle);
    _handler
      ..setResolving(false)
      ..setQueue(const [])
      ..setTrack(null);
  }
}
