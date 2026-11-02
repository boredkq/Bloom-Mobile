/// A network smoke run against the live Yandex Music API, not for CI. The
/// provider is plain Dart, no Flutter runtime needed.
///
/// With a token: `dart run tool/ym_smoke.dart <OAuth token>`, or put it in the
/// YM_TOKEN environment variable.
///
/// Without one it goes through the device flow: it prints the address and code,
/// waits for confirmation in a browser and goes on with the token, which works
/// for later runs too.
library;

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/providers/yandex/ym_provider.dart';
import 'package:bloom/providers/yandex/yandex.dart' as ym;

var failed = 0;

void check(bool cond, String what) {
  if (!cond) {
    failed++;
    stderr.writeln('FAIL: $what');
  }
}

Future<String?> deviceFlow() async {
  final d = await ym.authStart('bloomsmoke0000ff');
  print('Open ${d.verificationUrl} and enter the code: ${d.userCode}');
  final deadline = DateTime.now().add(d.expiresIn);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(d.interval);
    final r = await ym.authPoll(d.deviceCode);
    if (!r.isPending) return r.token;
    stdout.write('.');
  }
  return null;
}

Future<void> main(List<String> args) async {
  final token =
      args.firstOrNull ??
      Platform.environment['YM_TOKEN'] ??
      await deviceFlow();
  if (token == null || token.isEmpty) {
    stderr.writeln('no token: sign-in did not finish');
    exit(1);
  }
  ym.setToken(token);
  print('token: ${token.substring(0, 6)}… (save it to YM_TOKEN)');

  const provider = YandexProvider();
  check(provider.isEnabled, 'the provider is off with a live token');

  // The subscription: without Plus the stream gives 403, an expected outcome of
  // a run.
  final plus = await ym.hasPlus();
  print('Yandex Plus: $plus');

  // Search: all four sections in one request.
  final found = await provider.search('земфира');
  print(
    'search: ${found.tracks.length} tracks, ${found.artists.length} artists, '
    '${found.albums.length} albums, ${found.playlists.length} playlists',
  );
  check(found.tracks.isNotEmpty, 'empty search results');
  check(found.artists.isNotEmpty, 'search with no artists');

  // The second page: its own pager, not the common store's offset.
  final more = await provider.loadMoreTracks('земфира', 24);
  print('loadMoreTracks: ${more?.tracks.length ?? 0} more tracks');
  check((more?.tracks.length ?? 0) > 0, 'the second page is empty');
  final firstIds = found.tracks.map((t) => t.id).toSet();
  check(
    (more?.tracks.any((t) => !firstIds.contains(t.id)) ?? false),
    'the second page repeats the first entirely',
  );

  // The stream: a signed link plus real bytes by range GET, as the player does.
  final track = found.tracks.firstWhere(
    (t) => t.sourceData?['available'] != false,
    orElse: () => found.tracks.first,
  );
  try {
    final stream = await provider.resolveStream(track);
    check(
      stream != null && stream.url.contains('/get-mp3/'),
      'the stream is not mp3',
    );
    print('stream: ${stream?.url.substring(0, 60)}…');

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(stream!.url));
    req.headers.add('Range', 'bytes=0-1023');
    final resp = await req.close();
    final bytes = await resp.fold<int>(0, (n, ch) => n + ch.length);
    check(
      resp.statusCode == 200 || resp.statusCode == 206,
      'CDN status ${resp.statusCode}',
    );
    check(bytes > 0, 'the CDN gave 0 bytes');
    print('bytes: $bytes (status ${resp.statusCode})');
    client.close();
  } catch (e) {
    // Without Plus this is normal: the track just doesn't play.
    check(plus == false, 'the stream failed with active Plus: $e');
    print('stream: unavailable ($e)');
  }

  // The artist page: popular, discography, albums, similar.
  final artistPage = await provider.getArtist(found.artists.first.id);
  print(
    'getArtist ${artistPage?.artist.name}: '
    '${artistPage?.topTracks.length} popular, ${artistPage?.tracks.length} tracks, '
    '${artistPage?.albums.length} albums, ${artistPage?.similarArtists.length} similar',
  );
  check(
    (artistPage?.topTracks.length ?? 0) > 0,
    'the artist has no popular tracks',
  );
  check(
    artistPage?.topTracks.every((t) => t.name.isNotEmpty) ?? false,
    'popular tracks with no titles: brief-info gave bare ids and the follow-up failed',
  );

  // An album: tracks are gathered from all volumes.
  final albums = artistPage?.albums ?? const [];
  if (albums.isNotEmpty) {
    final album = await provider.getAlbum(albums.first.id);
    print('getAlbum ${album?.playlist.title}: ${album?.tracks.length} tracks');
    check((album?.tracks.length ?? 0) > 0, 'an album with no tracks');
    check(
      album?.playlist.ownerName?.isNotEmpty ?? false,
      'the album has no artist in its header',
    );
  }

  // A playlist from the results: the /users/<owner>/playlists/<kind> format.
  if (found.playlists.isNotEmpty) {
    final pl = await provider.getPlaylist(found.playlists.first.id);
    print('getPlaylist ${pl?.playlist.title}: ${pl?.tracks.length} tracks');
    check((pl?.tracks.length ?? 0) > 0, 'a playlist with no tracks');
  }

  // Links: track, album, artist. The id comes from live results, not hardcoded.
  final trackNum = ymNumericId(track.id);
  final resolvedTrack = await provider.resolveUrl(
    'https://music.yandex.ru/track/$trackNum',
  );
  check(resolvedTrack is ResolvedTrack, 'a track link gave no track');

  if (albums.isNotEmpty) {
    final albumNum = ymNumericId(albums.first.id);
    final resolvedAlbum = await provider.resolveUrl(
      'https://music.yandex.ru/album/$albumNum',
    );
    check(
      resolvedAlbum is ResolvedSet && resolvedAlbum.playlist.isAlbum,
      'an album link gave no album',
    );
    // A "track inside an album" link must open the track, not the album.
    final inAlbum = await provider.resolveUrl(
      'https://music.yandex.ru/album/$albumNum/track/$trackNum',
    );
    check(
      inAlbum is ResolvedTrack,
      'an album/track link did not open the track',
    );
  }

  final artistNum = ymNumericId(found.artists.first.id);
  final resolvedArtist = await provider.resolveUrl(
    'https://music.yandex.ru/artist/$artistNum',
  );
  check(resolvedArtist is ResolvedArtist, 'an artist link gave no artist');

  // A foreign link goes on through the registry, with no request to Yandex.
  check(
    await provider.resolveUrl('https://soundcloud.com/x/y') == null,
    'Yandex tried to resolve a foreign link',
  );

  // The home shelves: I check that data arrives.
  final charts = await provider.getCharts();
  print('getCharts: ${charts?.length} tracks');
  check((charts?.length ?? 0) > 0, 'the chart is empty');

  final releases = await provider.getNewReleases();
  final newCount = releases is NewAlbums ? releases.albums.length : 0;
  print('getNewReleases: $newCount albums');
  check(newCount > 0, 'new releases are empty');

  print(failed == 0 ? '\nALL OK' : '\nFAILED: $failed');
  exit(failed == 0 ? 0 : 1);
}
