/// Last.fm's web API: plain requests signed with `api_sig`. Each user has their
/// own app keys, none are built in.
///
/// Nothing is thrown: scrobbling is background work and must not bring playback
/// down. A failure is `null`.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const String kLastfmBase = 'https://ws.audioscrobbler.com/2.0/';

/// Where the browser goes after `auth.getToken`.
String lastfmAuthUrl(String apiKey, String token) =>
    'https://www.last.fm/api/auth/?api_key=$apiKey&token=$token';

/// Where one's own keys come from; shown in the guide.
const String kLastfmApiAccountUrl = 'https://www.last.fm/api/account/create';

/// Keys sorted, values joined, the secret at the end, md5 over UTF-8. `format`
/// stays out of the signature: it's added after.
String lastfmSign(Map<String, String> params, String apiSecret) {
  final keys = params.keys.toList()..sort();
  final buffer = StringBuffer();
  for (final k in keys) {
    buffer
      ..write(k)
      ..write(params[k]);
  }
  buffer.write(apiSecret);
  return md5.convert(utf8.encode(buffer.toString())).toString();
}

/// A variable, so tests stay off the network.
typedef LastfmTransport =
    Future<Map<String, dynamic>?> Function(
      Map<String, String> form, {
      bool get,
    });

LastfmTransport lastfmTransport = defaultLastfmTransport;

final http.Client _http = http.Client();

/// Named, so a test can put it back.
Future<Map<String, dynamic>?> defaultLastfmTransport(
  Map<String, String> form, {
  bool get = false,
}) async {
  try {
    final res = get
        ? await _http.get(Uri.parse(kLastfmBase).replace(queryParameters: form))
        : await _http.post(Uri.parse(kLastfmBase), body: form);
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : null;
  } catch (_) {
    // No network or not JSON: for scrobbling it's just "didn't work".
    return null;
  }
}

/// A signed POST; the parsed answer or `null`.
Future<Map<String, dynamic>?> lastfmPost(
  Map<String, String> params, {
  required String apiKey,
  required String apiSecret,
}) {
  if (apiKey.isEmpty || apiSecret.isEmpty) return Future.value(null);
  final p = {...params, 'api_key': apiKey};
  return lastfmTransport({
    ...p,
    'api_sig': lastfmSign(p, apiSecret),
    'format': 'json',
  }, get: false);
}

/// Either a token or the service's reason.
class LastfmTokenResult {
  const LastfmTokenResult({this.token, this.message});

  final String? token;

  /// Last.fm's `message` when no token came.
  final String? message;
}

/// Sign-in, step 1: a one-time token. Needs no signature.
Future<LastfmTokenResult> lastfmGetToken(String apiKey) async {
  final data = await lastfmTransport({
    'method': 'auth.getToken',
    'api_key': apiKey,
    'format': 'json',
  }, get: true);
  if (data == null) return const LastfmTokenResult();
  final token = data['token'];
  final message = data['message'];
  return LastfmTokenResult(
    token: token is String && token.isNotEmpty ? token : null,
    message: message is String ? message : null,
  );
}

/// A session: its key and the nickname.
class LastfmSession {
  const LastfmSession({required this.key, required this.name});

  final String key;
  final String name;
}

/// No session: access isn't confirmed in the browser yet, or [message] says
/// why.
class LastfmSessionResult {
  const LastfmSessionResult({this.session, this.message});

  final LastfmSession? session;
  final String? message;
}

/// Sign-in, step 2: a confirmed token for a session key.
Future<LastfmSessionResult> lastfmGetSession({
  required String apiKey,
  required String apiSecret,
  required String token,
}) async {
  final data = await lastfmPost(
    {'method': 'auth.getSession', 'token': token},
    apiKey: apiKey,
    apiSecret: apiSecret,
  );
  if (data == null) return const LastfmSessionResult();
  final session = data['session'];
  final message = data['message'];
  if (session is Map) {
    final key = session['key'];
    final name = session['name'];
    if (key is String && key.isNotEmpty) {
      return LastfmSessionResult(
        session: LastfmSession(key: key, name: name is String ? name : ''),
      );
    }
  }
  return LastfmSessionResult(message: message is String ? message : null);
}

/// "Now playing". The answer matters only for a session that's gone.
Future<Map<String, dynamic>?> lastfmNowPlaying({
  required String apiKey,
  required String apiSecret,
  required String sk,
  required String artist,
  required String track,
  required String album,
}) => lastfmPost(
  {
    'method': 'track.updateNowPlaying',
    'artist': artist,
    'track': track,
    'album': album,
    'sk': sk,
  },
  apiKey: apiKey,
  apiSecret: apiSecret,
);

/// One waiting scrobble. [ts] is when the track started, Unix seconds.
class LfmScrobble {
  const LfmScrobble({
    required this.artist,
    required this.track,
    required this.album,
    required this.duration,
    required this.ts,
  });

  factory LfmScrobble.fromJson(Map<String, dynamic> raw) => LfmScrobble(
    artist: raw['artist'] as String? ?? '',
    track: raw['track'] as String? ?? '',
    album: raw['album'] as String? ?? '',
    duration: (raw['duration'] as num?)?.toInt() ?? 0,
    ts: (raw['ts'] as num?)?.toInt() ?? 0,
  );

  final String artist;
  final String track;
  final String album;
  final int duration;
  final int ts;

  Map<String, Object> toJson() => {
    'artist': artist,
    'track': track,
    'album': album,
    'duration': duration,
    'ts': ts,
  };
}

/// Sends a batch at once; `null` means no answer.
Future<Map<String, dynamic>?> lastfmScrobble({
  required String apiKey,
  required String apiSecret,
  required String sk,
  required List<LfmScrobble> batch,
}) => lastfmPost(
  {
    'method': 'track.scrobble',
    'sk': sk,
    for (final (i, s) in batch.indexed) ...{
      'artist[$i]': s.artist,
      'track[$i]': s.track,
      'timestamp[$i]': '${s.ts}',
      if (s.album.isNotEmpty) 'album[$i]': s.album,
      if (s.duration > 0) 'duration[$i]': '${s.duration}',
    },
  },
  apiKey: apiKey,
  apiSecret: apiSecret,
);
