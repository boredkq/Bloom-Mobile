/// The phone as the computer's remote (Connect): while the computer is online
/// and played later than the phone, the screen shows what plays there and all
/// buttons press there. Sound stays on the device it played on last; Play on
/// moves it.
///
/// The phone's own state (queue, session) stays untouched: if the link drops,
/// the phone shows its own again.
///
/// The reverse too: while sound is here, the phone sends its state to the
/// computer (`/v1/connect/state`), which shows it, and what's pressed there
/// arrives as a `command` event.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/entities/entities.dart';
import '../../core/log/bloom_log.dart';
import '../../core/sync/pc_client.dart';
import '../../core/sync/sync_log.dart';
import '../../providers/yandex/ym_provider.dart' show ymNumericId;
import '../player/play_source.dart';
import '../player/player_controller.dart';
import '../player/session_store.dart' show SessionData;

/// When sound last played on this device, ms. The player writes it.
const String kConnectPlayed = 'connect.played';

/// What plays on the computer.
@immutable
class PcPlayback {
  const PcPlayback({
    required this.playback,
    required this.playing,
    required this.position,
    required this.positionAt,
    required this.duration,
    required this.liked,
  });

  /// Queue, index, modes and source, in the form of my own player.
  final PlaybackState playback;
  final bool playing;

  /// Position the computer gave and when: it moves on by itself after that.
  final Duration position;
  final DateTime positionAt;
  final Duration duration;
  final bool liked;

  Playhead playheadAt(DateTime now) {
    var p = position;
    if (playing) p += now.difference(positionAt);
    if (duration > Duration.zero && p > duration) p = duration;
    return (position: p, total: duration);
  }
}

/// `null`: the phone isn't a remote and plays its own.
final pcRemoteProvider = NotifierProvider<PcRemoteController, PcPlayback?>(
  PcRemoteController.new,
);

class PcRemoteController extends Notifier<PcPlayback?> {
  BloomDb get _db => ref.read(dbProvider);

  PcClient? _client;

  /// Last thing the computer said; `null` if not asked yet.
  _Pc? _pc;
  StreamSubscription<bool>? _ownPlaying;
  Timer? _refetch;

  /// Sound was taken here: the phone isn't a remote until the computer plays
  /// again itself.
  bool _pinned = false;
  int _pinnedAt = 0;

  /// Mine as told to the computer: the queue (showing whether to send it again)
  /// and whether sound is here.
  List<Track>? _sentQueue;
  bool _reported = false;
  Timer? _report;
  late final String _me = SyncLog(_db).device();

  @override
  PcPlayback? build() {
    ref.onDispose(() {
      _refetch?.cancel();
      _report?.cancel();
      _ownPlaying?.cancel();
    });
    return null;
  }

  // ── Link (held by PcController) ─────────────────────────────────────────

  /// The computer's event stream opened.
  void attach(PcClient client) {
    _client = client;
    _sentQueue = null;
    _reported = false;
    _ownPlaying ??= ref
        .read(audioPlayerProvider)
        .playingStream
        .listen((_) => _decide());
    unawaited(_fetch());
  }

  /// The stream dropped: the phone is on its own again.
  void detach() {
    _client = null;
    _pc = null;
    _pinned = false;
    _refetch?.cancel();
    _report?.cancel();
    _ownPlaying?.cancel();
    _ownPlaying = null;
    if (state != null) logInfo('connect', 'телефон больше не пульт ПК');
    state = null;
  }

  void onEvent(PcEvent e) {
    final d = e.data;
    // Sound is moved from the computer, but the phone does it, knowing both
    // queues.
    if (e.name == 'connect') {
      switch (d['do']) {
        case 'take':
          unawaited(playHere());
        case 'give':
          unawaited(playOnPc());
      }
      return;
    }
    if (e.name == 'command') {
      _carryOut(d);
      return;
    }
    final pc = _pc;
    if (pc == null) return;
    switch (e.name) {
      case 'player':
        pc.mirrorsMe = d['active'] == _me;
        pc.playing = d['playing'] == true;
        pc.liked = d['liked'] == true;
        pc.shuffle = d['shuffle'] == true;
        pc.repeat = _repeat(d['repeat']);
        pc.source = PlaySource.fromJson(d['source']);
        _setPosition(pc, d);
        final index = _int(d['index'], -1);
        final id = (d['track'] as Map?)?['id'];
        // The queue changed by no event of mine, so I take it whole again.
        if (_int(d['queueLength'], 0) != pc.tracks.length ||
            index < 0 ||
            index >= pc.tracks.length ||
            pc.tracks[index].id != id) {
          _fetchSoon();
        } else {
          pc.index = index;
        }
      case 'position':
        pc.playing = d['playing'] == true;
        _setPosition(pc, d);
      case 'queue':
        _fetchSoon();
      default:
        return;
    }
    // While the computer shows this phone, its playing is mine.
    if (pc.playing && !pc.mirrorsMe) pc.at = BloomDb.now();
    _decide();
  }

  /// Pressed on the computer while it shows this phone: carried out here.
  void _carryOut(Map<String, Object?> d) {
    final p = ref.read(playbackProvider.notifier);
    List<Track> tracks() => [
      for (final t in (d['tracks'] as List?) ?? const []) ?Track.fromJson(t),
    ];
    final source = PlaySource.fromJson(d['source']);
    final index = _int(d['index'], 0);
    switch (d['do']) {
      case 'toggle':
        unawaited(p.toggle());
      case 'play':
        unawaited(p.commandPlay());
      case 'pause':
        unawaited(p.commandPause());
      case 'next':
        unawaited(p.next());
      case 'prev':
        unawaited(p.prev());
      case 'seek':
        final at = d['position'];
        if (at is num) {
          unawaited(p.seek(Duration(milliseconds: (at * 1000).round())));
        }
      case 'jump':
        unawaited(p.jumpTo(index));
      case 'remove':
        unawaited(p.removeAt(index));
      case 'move':
        // The computer's `to` is the place after moving, mine is before the row
        // is removed.
        final from = _int(d['from'], -1), to = _int(d['to'], -1);
        if (from >= 0 && to >= 0) p.reorder(from, to > from ? to + 1 : to);
      case 'shuffle':
        p.toggleShuffle();
      case 'repeat':
        p.cycleRepeat();
      case 'clear':
        p.clearExceptCurrent();
      case 'playList':
        final list = tracks();
        if (list.isEmpty) return;
        unawaited(
          d['shuffle'] == true
              ? p.playQueueShuffled(list, source: source)
              : p.playQueue(
                  list,
                  index.clamp(0, list.length - 1),
                  source: source,
                ),
        );
      case 'enqueue':
        d['next'] == true
            ? p.queueTracksNext(tracks(), source: source)
            : p.queueTracks(tracks(), source: source);
    }
  }

  // ── Mine to the computer ────────────────────────────────────────────────

  /// Mine changed (track, queue, pause, seek): tells the computer if sound is
  /// here. A burst of edits goes as one.
  void reportSoon() {
    if (_client == null || state != null) return;
    _report?.cancel();
    _report = Timer(const Duration(milliseconds: 150), _sendReport);
  }

  Future<void> _sendReport() async {
    final client = _client;
    if (client == null || state != null) return;
    final playback = ref.read(playbackProvider.notifier);
    final own = playback.localSession();
    final Map<String, Object?> body;
    if (own == null) {
      if (!_reported) return;
      body = {'active': false};
    } else {
      body = {
        'active': true,
        'id': own.track.id,
        'playing': ref.read(audioPlayerProvider).playing,
        'position': own.position.inMilliseconds / 1000,
        'duration': playback.localDuration.inMilliseconds / 1000,
        'shuffle': own.shuffle,
        'repeat': own.repeat.name,
        'source': own.source?.toJson() ?? const {},
        // The queue only when it changed: it may be hundreds of tracks.
        if (!identical(own.queue, _sentQueue)) ...{
          'tracks': [for (final t in own.queue) t.toJson()],
          'orig': [for (final t in own.orig) t.toJson()],
        },
      };
    }
    try {
      await client.json(
        'POST',
        '/v1/connect/state',
        body: body,
        timeout: const Duration(seconds: 8),
      );
      _sentQueue = own?.queue;
      _reported = own != null;
    } catch (e) {
      logWarn('connect', 'своё состояние до ПК не дошло: $e');
    }
  }

  // ── Play on ─────────────────────────────────────────────────────────────

  /// Sound comes here: the computer's queue plays on the phone from that
  /// second, and the computer goes quiet.
  Future<void> playHere() async {
    final client = _client;
    if (client == null) return;
    try {
      final d = await client.json('GET', '/v1/connect');
      List<Track> tracks(Object? list) => [
        for (final t in (list as List?) ?? const []) ?Track.fromJson(t),
      ];
      final queue = tracks(d['tracks']);
      final index = _int(d['index'], -1);
      if (index < 0 || index >= queue.length) return;
      final position = d['position'] is num
          ? Duration(milliseconds: ((d['position'] as num) * 1000).round())
          : Duration.zero;
      _pinned = true;
      _pinnedAt = BloomDb.now();
      state = null;
      logInfo('connect', 'звук — на телефон');
      await ref
          .read(playbackProvider.notifier)
          .resumeSession(
            SessionData(
              queue: queue,
              orig: tracks(d['orig']),
              index: index,
              position: position,
              savedAt: DateTime.now(),
              source: PlaySource.fromJson(d['source']),
              shuffle: d['shuffle'] == true,
              repeat: _repeat(d['repeat']),
            ),
          );
      await client.json('POST', '/v1/connect/took', body: const {});
    } catch (e) {
      logWarn('connect', 'звук с ПК не забран: $e');
    }
  }

  /// Sound goes to the computer: my session plays there from that second, and
  /// the phone goes quiet and becomes a remote.
  Future<void> playOnPc() async {
    final client = _client;
    final playback = ref.read(playbackProvider.notifier);
    final own = playback.localSession();
    if (client == null || own == null) return;
    try {
      await client.json(
        'POST',
        '/v1/connect/take',
        body: {
          'tracks': [for (final t in own.queue) t.toJson()],
          'orig': [for (final t in own.orig) t.toJson()],
          'index': own.index,
          'position': own.position.inMilliseconds / 1000,
          'shuffle': own.shuffle,
          'repeat': own.repeat.name,
          'source': own.source?.toJson() ?? const {},
        },
      );
      logInfo('connect', 'звук — на ПК');
      _pinned = false;
      await playback.pauseLocal();
      _pc?.playing = true;
      _pc?.at = BloomDb.now();
      _decide();
    } catch (e) {
      logWarn('connect', 'звук на ПК не ушёл: $e');
    }
  }

  // ── Commands ────────────────────────────────────────────────────────────

  Future<void> toggle() {
    _pc?.playing = !(_pc?.playing ?? false);
    _decide();
    return _post('/v1/player/toggle');
  }

  Future<void> play() => _post('/v1/player/play');
  Future<void> pause() => _post('/v1/player/pause');
  Future<void> next() => _post('/v1/player/next');
  Future<void> prev() => _post('/v1/player/prev');

  Future<void> seek(Duration to) {
    final pc = _pc;
    if (pc != null) {
      pc.position = to;
      pc.positionAt = DateTime.now();
      _decide();
    }
    return _post('/v1/player/seek', {'position': to.inMilliseconds / 1000});
  }

  Future<void> jumpTo(int index) => _post('/v1/queue/jump', {'index': index});
  Future<void> removeAt(int index) =>
      _post('/v1/queue/remove', {'index': index});

  /// Indices as in my [PlaybackController.reorder] (`to` before removal).
  Future<void> reorder(int from, int to) =>
      _post('/v1/queue/move', {'from': from, 'to': to > from ? to - 1 : to});

  Future<void> cycleRepeat() => _post('/v1/player/repeat');
  Future<void> toggleShuffle() => _post('/v1/player/shuffle');
  Future<void> clearExceptCurrent() => _post('/v1/connect/clear');

  Future<void> playQueue(
    List<Track> tracks,
    int index, {
    PlaySource? source,
    bool shuffle = false,
  }) => _post('/v1/connect/play', {
    'tracks': [for (final t in tracks) t.toJson()],
    'index': index,
    'source': source?.toJson() ?? const {},
    'shuffle': shuffle,
  });

  /// How many go in isn't known ahead: the computer drops those already queued.
  int enqueue(List<Track> tracks, {bool next = false, PlaySource? source}) {
    if (tracks.isEmpty) return 0;
    unawaited(
      _post('/v1/connect/enqueue', {
        'tracks': [for (final t in tracks) t.toJson()],
        'next': next,
        'source': source?.toJson() ?? const {},
      }),
    );
    return tracks.length;
  }

  Future<void> wavePersonal() =>
      _post('/v1/connect/wave', {'from': 'personal'});
  Future<void> waveQueue() => _post('/v1/connect/wave', {'from': 'queue'});
  Future<void> waveShake() => _post('/v1/connect/wave', {'from': 'shake'});
  Future<void> waveTrack(Track track) =>
      _post('/v1/connect/wave', {'from': 'track', 'track': track.toJson()});
  Future<void> waveArtist(Artist artist, List<Track> tracks) =>
      _post('/v1/connect/wave', {
        'from': 'artist',
        'artist': {
          'id': artist.id,
          'name': artist.name,
          'provider': artist.source.code,
          'extra': {'ymId': ymNumericId(artist.id)},
        },
        'tracks': [for (final t in tracks) t.toJson()],
      });

  Future<void> _post(String path, [Map<String, Object?>? body]) async {
    final client = _client;
    if (client == null) return;
    _pc?.at = BloomDb.now(); // what's pressed here played on the computer
    try {
      await client.json(
        'POST',
        path,
        body: body ?? const {},
        timeout: const Duration(seconds: 8),
      );
    } catch (e) {
      logWarn('connect', '$path не дошло до ПК: $e');
    }
  }

  // ── Internal ────────────────────────────────────────────────────────────

  void _fetchSoon() {
    _refetch?.cancel();
    _refetch = Timer(const Duration(milliseconds: 120), _fetch);
  }

  Future<void> _fetch() async {
    final client = _client;
    if (client == null) return;
    try {
      final d = await client.json('GET', '/v1/connect');
      if (!identical(client, _client)) return;
      final pc = _pc ?? _Pc();
      pc
        ..tracks = [
          for (final t in (d['tracks'] as List?) ?? const [])
            ?Track.fromJson(t),
        ]
        ..index = _int(d['index'], -1)
        ..playing = d['playing'] == true
        ..shuffle = d['shuffle'] == true
        ..repeat = _repeat(d['repeat'])
        ..liked = d['liked'] == true
        ..mirrorsMe = d['active'] == _me
        ..source = PlaySource.fromJson(d['source']);
      _setPosition(pc, d);
      if (_pc == null) pc.at = _int(d['at'], 0);
      if (pc.playing && !pc.mirrorsMe) pc.at = BloomDb.now();
      _pc = pc;
      _decide();
    } catch (e) {
      logWarn('connect', 'состояние ПК не получено: $e');
    }
  }

  /// Whether the phone is a remote. Not if its own is playing: I don't break
  /// what's in the ears. Otherwise, if the computer plays or played later. Once
  /// a remote it stays so while the link lives: all pressed here plays there.
  void _decide() {
    final pc = _pc;
    if (pc == null || _client == null) {
      state = null;
      return;
    }
    final ownPlaying = ref.read(audioPlayerProvider).playing;
    // The computer shows this phone, so sound is here.
    if (pc.mirrorsMe) {
      _local();
      return;
    }
    // Taken here: until the computer plays by itself, sound is here. For a
    // couple of seconds after a move it's still finishing, which isn't playing
    // by itself.
    if (_pinned &&
        pc.playing &&
        !ownPlaying &&
        BloomDb.now() - _pinnedAt > 3000) {
      _pinned = false;
    }
    if (_pinned) {
      _local();
      return;
    }
    final ownAt = _int(_db.get(kConnectPlayed), 0);
    final remote =
        !ownPlaying && (state != null || pc.playing || pc.at >= ownAt);
    if (!remote) {
      _local();
      return;
    }
    if (state == null) logInfo('connect', 'телефон — пульт ПК');
    state = PcPlayback(
      playback: PlaybackState(
        queue: pc.tracks,
        index: pc.index,
        shuffle: pc.shuffle,
        repeat: pc.repeat,
        source: pc.source,
      ),
      playing: pc.playing,
      position: pc.position,
      positionAt: pc.positionAt,
      duration: pc.duration,
      liked: pc.liked,
    );
  }

  /// Sound is here: the screen shows mine, and the computer learns what to
  /// show.
  void _local() {
    final was = state;
    state = null;
    // Only on the transition: each computer event is no reason to send mine
    // again (it would answer with an event, and round it goes).
    if (was != null || !_reported) reportSoon();
  }

  static void _setPosition(_Pc pc, Map<String, Object?> d) {
    if (d['position'] is num) {
      pc.position = Duration(
        milliseconds: ((d['position'] as num) * 1000).round(),
      );
      pc.positionAt = DateTime.now();
    }
    if (d['duration'] is num) {
      pc.duration = Duration(
        milliseconds: ((d['duration'] as num) * 1000).round(),
      );
    }
  }

  static PlayerRepeat _repeat(Object? v) => switch (v) {
    'all' => PlayerRepeat.all,
    'one' => PlayerRepeat.one,
    _ => PlayerRepeat.off,
  };

  static int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;
}

/// The computer's changing state inside the controller; outside, [PcPlayback].
class _Pc {
  List<Track> tracks = const [];
  int index = -1;
  bool playing = false;
  bool shuffle = false;
  bool liked = false;
  PlayerRepeat repeat = PlayerRepeat.off;
  PlaySource? source;
  Duration position = Duration.zero;
  DateTime positionAt = DateTime.now();
  Duration duration = Duration.zero;

  /// When it last played on the computer, ms.
  int at = 0;

  /// The computer now shows this phone (`active` is my id): its playing is
  /// mine.
  bool mirrorsMe = false;
}
