/// The Last.fm scrobbler: app keys, session key, two switches, and when a track
/// counts: at least [kLfmMinListen], and either [kLfmAbsolute] or half of its
/// length.
///
/// It knows nothing of the player: `PlaybackController` brings the events. No
/// texts here either: [LfmNote] is a typed reason, the settings screen words
/// it.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/db/db.dart';
import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;
import 'lastfm_api.dart';

/// Below this nothing counts at all.
const Duration kLfmMinListen = Duration(seconds: 30);

/// A long track counts after this, without waiting for its half.
const Duration kLfmAbsolute = Duration(seconds: 240);

const String _kPending = 'lastfm.pending';
const int _kBatch = 50; // the most track.scrobble takes at once
const int _kKeep = 1000; // waiting ones beyond that: the oldest go
const int _kMaxAgeSec = 14 * 24 * 3600; // older ones the service turns down
const Duration _kRetry = Duration(minutes: 5);
const Duration _kFirstSend = Duration(seconds: 10);
const int _kSessionGone = 9;

/// The service's hiccups and its rate limit, or no answer: worth another go.
bool _transient(int? error) =>
    error == null || error == 8 || error == 11 || error == 16 || error == 29;

enum LfmNoteKind {
  /// `auth.getToken` is running.
  gettingToken,

  /// Token in hand, browser open, waiting for the confirmation.
  confirmAccess,

  /// `auth.getSession` is running.
  checking,

  /// Not confirmed yet; "Done" can be pressed again.
  notConfirmed,

  /// Sign-in never started, nothing to confirm.
  loginFirst,

  /// No app keys: save them first.
  needKeys,

  /// No answer from the network.
  networkError,

  /// Refused by the service; the text is in [LfmNote.message].
  error,

  /// The saved session stopped working.
  sessionLost,
}

class LfmNote {
  const LfmNote(this.kind, [this.message]);

  final LfmNoteKind kind;
  final String? message;
}

class LastfmState {
  const LastfmState({
    this.sk,
    this.apiKey = '',
    this.apiSecret = '',
    this.scrobbleEnabled = false,
    this.nowPlayingEnabled = false,
    this.user = '',
    this.pending = 0,
    this.note,
    this.oauthPending = false,
    this.busy = false,
  });

  /// Connected if present.
  final String? sk;

  /// Everyone's own, none built in.
  final String apiKey;
  final String apiSecret;

  final bool scrobbleEnabled;
  final bool nowPlayingEnabled;

  /// The nickname.
  final String user;

  /// Scrobbles not sent yet.
  final int pending;

  /// What shows under the sign-in buttons.
  final LfmNote? note;

  /// Token in hand, browser open: "Done" shows.
  final bool oauthPending;

  /// A network step of the sign-in is running.
  final bool busy;

  bool get connected => (sk ?? '').isNotEmpty;
  bool get hasKeys => apiKey.isNotEmpty && apiSecret.isNotEmpty;

  LastfmState copyWith({
    String? sk,
    bool clearSk = false,
    String? apiKey,
    String? apiSecret,
    bool? scrobbleEnabled,
    bool? nowPlayingEnabled,
    String? user,
    int? pending,
    LfmNote? note,
    bool clearNote = false,
    bool? oauthPending,
    bool? busy,
  }) => LastfmState(
    sk: clearSk ? null : (sk ?? this.sk),
    apiKey: apiKey ?? this.apiKey,
    apiSecret: apiSecret ?? this.apiSecret,
    scrobbleEnabled: scrobbleEnabled ?? this.scrobbleEnabled,
    nowPlayingEnabled: nowPlayingEnabled ?? this.nowPlayingEnabled,
    user: user ?? this.user,
    pending: pending ?? this.pending,
    note: clearNote ? null : (note ?? this.note),
    oauthPending: oauthPending ?? this.oauthPending,
    busy: busy ?? this.busy,
  );
}

final lastfmProvider = NotifierProvider<LastfmController, LastfmState>(
  LastfmController.new,
);

/// The clock, swapped in tests.
final lfmClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

class LastfmController extends Notifier<LastfmState> {
  static const _key = 'lastfm';

  /// Between `auth.getToken` and `auth.getSession`. Never on disk: it lives
  /// minutes and works once.
  String? _pendingToken;

  /// What plays, since when, whether it counted. Not provider state: it changes
  /// every tick and never shows.
  ({String artist, String track, String album})? _nowTrack;
  int _startedAt = 0;
  bool _scrobbled = false;

  bool _sending = false;
  Timer? _timer;
  bool _disposed = false;

  List<LfmScrobble> _queue() {
    final raw = ref.read(dbProvider).get(_kPending);
    if (raw is! List) return [];
    return [
      for (final item in raw)
        if (item is Map) LfmScrobble.fromJson(item.cast<String, dynamic>()),
    ];
  }

  void _setQueue(List<LfmScrobble> list) {
    ref.read(dbProvider).set(_kPending, [for (final s in list) s.toJson()]);
    state = state.copyWith(pending: list.length);
  }

  void _sendIn(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_send()));
  }

  /// The waiting scrobbles, oldest first, a batch at a time.
  Future<void> _send() async {
    final sk = state.sk;
    if (_sending || sk == null) return;
    final now = ref.read(lfmClockProvider)().millisecondsSinceEpoch ~/ 1000;
    final all = _queue();
    final list = [
      for (final s in all)
        if (s.ts >= now - _kMaxAgeSec) s,
    ];
    if (list.length != all.length) _setQueue(list);
    if (list.isEmpty) return;

    final n = list.length < _kBatch ? list.length : _kBatch;
    _sending = true;
    final answer = await lastfmScrobble(
      apiKey: state.apiKey,
      apiSecret: state.apiSecret,
      sk: sk,
      batch: list.sublist(0, n),
    );
    _sending = false;
    if (_disposed) return;

    final error = answer == null
        ? null
        : (answer['error'] as num?)?.toInt() ?? 0;
    // They wait for the next sign-in.
    if (error == _kSessionGone) return _sessionLost();
    if (_transient(error)) return _sendIn(_kRetry);
    // Sent, or turned down for good (a bad field): either way they're done.
    // New ones may have come meanwhile, at the end.
    final rest = _queue().sublist(n);
    _setQueue(rest);
    if (rest.isNotEmpty) unawaited(_send());
  }

  void _sessionLost() {
    _timer?.cancel();
    state = state.copyWith(
      clearSk: true,
      user: '',
      note: const LfmNote(LfmNoteKind.sessionLost),
    );
    _save();
  }

  @override
  LastfmState build() {
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    final waiting = _queue().length;
    if (waiting > 0) _sendIn(_kFirstSend);
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    String str(Object? v) => v is String ? v : '';
    final sk = str(raw['sk']);
    return LastfmState(
      sk: sk.isEmpty ? null : sk,
      apiKey: str(raw['apiKey']),
      apiSecret: str(raw['apiSecret']),
      scrobbleEnabled: raw['scrobble'] == true,
      nowPlayingEnabled: raw['nowPlaying'] == true,
      user: str(raw['user']),
      pending: waiting,
    );
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, {
    'sk': state.sk,
    'apiKey': state.apiKey,
    'apiSecret': state.apiSecret,
    'scrobble': state.scrobbleEnabled,
    'nowPlaying': state.nowPlayingEnabled,
    'user': state.user,
  });

  /// Empty keys aren't saved.
  bool saveKeys(String apiKey, String apiSecret) {
    final k = apiKey.trim();
    final s = apiSecret.trim();
    if (k.isEmpty || s.isEmpty) {
      state = state.copyWith(note: const LfmNote(LfmNoteKind.needKeys));
      return false;
    }
    state = state.copyWith(apiKey: k, apiSecret: s, clearNote: true);
    _save();
    return true;
  }

  /// Step 1: the token and off to the browser.
  Future<void> startOAuth() async {
    if (!state.hasKeys) {
      state = state.copyWith(note: const LfmNote(LfmNoteKind.needKeys));
      return;
    }
    _pendingToken = null;
    state = state.copyWith(
      busy: true,
      oauthPending: false,
      note: const LfmNote(LfmNoteKind.gettingToken),
    );
    final r = await lastfmGetToken(state.apiKey);
    final token = r.token;
    if (token == null) {
      state = state.copyWith(
        busy: false,
        note: r.message == null
            ? const LfmNote(LfmNoteKind.networkError)
            : LfmNote(LfmNoteKind.error, r.message),
      );
      return;
    }
    _pendingToken = token;
    state = state.copyWith(
      busy: false,
      oauthPending: true,
      note: const LfmNote(LfmNoteKind.confirmAccess),
    );
    // Confirmed in the browser: the password never enters the app.
    unawaited(openLastfmPage(lastfmAuthUrl(state.apiKey, token)));
  }

  /// Step 2: the confirmed token for a session key.
  ///
  /// [silent] is the try on coming back from the browser: it neither complains
  /// nor replaces the hint on screen.
  Future<bool> finishOAuth({bool silent = false}) async {
    final token = _pendingToken;
    if (token == null) {
      if (!silent) {
        state = state.copyWith(note: const LfmNote(LfmNoteKind.loginFirst));
      }
      return false;
    }
    if (state.busy) return false;
    // The silent try leaves "confirm access" on screen.
    state = silent
        ? state.copyWith(busy: true)
        : state.copyWith(busy: true, note: const LfmNote(LfmNoteKind.checking));
    final r = await lastfmGetSession(
      apiKey: state.apiKey,
      apiSecret: state.apiSecret,
      token: token,
    );
    final session = r.session;
    if (session == null) {
      // Normal for a silent try: they came back without pressing anything. Only
      // the button complains.
      state = silent
          ? state.copyWith(busy: false)
          : state.copyWith(
              busy: false,
              note: r.message == null
                  ? const LfmNote(LfmNoteKind.notConfirmed)
                  : LfmNote(LfmNoteKind.error, r.message),
            );
      return false;
    }
    _pendingToken = null;
    // Signed in: both switches go on, connecting and not scrobbling makes no
    // sense.
    state = state.copyWith(
      sk: session.key,
      user: session.name,
      scrobbleEnabled: true,
      nowPlayingEnabled: true,
      oauthPending: false,
      busy: false,
      clearNote: true,
    );
    _save();
    unawaited(_send());
    return true;
  }

  void logout() {
    _pendingToken = null;
    _nowTrack = null;
    _timer?.cancel();
    state = state.copyWith(
      clearSk: true,
      user: '',
      oauthPending: false,
      busy: false,
      clearNote: true,
    );
    _save();
  }

  void setScrobble(bool on) {
    state = state.copyWith(scrobbleEnabled: on);
    _save();
  }

  void setNowPlaying(bool on) {
    state = state.copyWith(nowPlayingEnabled: on);
    _save();
  }

  /// On leaving the screen, for one.
  void clearNote() {
    if (state.note == null) return;
    state = state.copyWith(clearNote: true);
  }

  // ── Scrobbling ─────────────────────────────────────────────────────────────

  /// A new track plays: I remember it and update "now playing".
  void onTrackStart(Track track) {
    _nowTrack = (
      artist: track.artist,
      track: track.name,
      album: track.album ?? '',
    );
    _startedAt = ref.read(lfmClockProvider)().millisecondsSinceEpoch ~/ 1000;
    _scrobbled = false;
    final sk = state.sk;
    if (sk == null || !state.nowPlayingEnabled) return;
    unawaited(
      lastfmNowPlaying(
        apiKey: state.apiKey,
        apiSecret: state.apiSecret,
        sk: sk,
        artist: _nowTrack!.artist,
        track: _nowTrack!.track,
        album: _nowTrack!.album,
      ).then((answer) {
        if (!_disposed && answer?['error'] == _kSessionGone) _sessionLost();
      }),
    );
  }

  /// A position tick: past the threshold it counts, once until the next
  /// [onTrackStart].
  void onProgress(Duration position, Duration? duration) {
    final now = _nowTrack;
    if (_scrobbled || now == null) return;
    if (duration == null || duration <= Duration.zero) return;
    if (position < kLfmMinListen) return;
    if (position < kLfmAbsolute &&
        position.inMilliseconds < duration.inMilliseconds / 2) {
      return;
    }
    _scrobbled = true;
    if (state.sk == null || !state.scrobbleEnabled) return;
    final list = _queue()
      ..add(
        LfmScrobble(
          artist: now.artist,
          track: now.track,
          album: now.album,
          duration: duration.inSeconds,
          ts: _startedAt,
        ),
      );
    _setQueue(list.length > _kKeep ? list.sublist(list.length - _kKeep) : list);
    unawaited(_send());
  }
}

/// A variable, so tests don't open a browser.
Future<bool> Function(String url) openLastfmPage = defaultOpenLastfmPage;

Future<bool> defaultOpenLastfmPage(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
