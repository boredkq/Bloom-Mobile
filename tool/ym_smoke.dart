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
  print('Открой ${d.verificationUrl} и введи код: ${d.userCode}');
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
    stderr.writeln('нет токена — авторизация не завершилась');
    exit(1);
  }
  ym.setToken(token);
  print('token: ${token.substring(0, 6)}… (сохрани в YM_TOKEN)');

  const provider = YandexProvider();
  check(provider.isEnabled, 'провайдер выключен при живом токене');

  // The subscription: without Plus the stream gives 403, an expected outcome of
  // a run.
  final plus = await ym.hasPlus();
  print('Яндекс Плюс: $plus');

  // Search: all four sections in one request.
  final found = await provider.search('земфира');
  print(
    'search: ${found.tracks.length} треков, ${found.artists.length} артистов, '
    '${found.albums.length} альбомов, ${found.playlists.length} плейлистов',
  );
  check(found.tracks.isNotEmpty, 'пустая выдача поиска');
  check(found.artists.isNotEmpty, 'поиск без артистов');

  // The second page: its own pager, not the common store's offset.
  final more = await provider.loadMoreTracks('земфира', 24);
  print('loadMoreTracks: ещё ${more?.tracks.length ?? 0} треков');
  check((more?.tracks.length ?? 0) > 0, 'вторая страница пуста');
  final firstIds = found.tracks.map((t) => t.id).toSet();
  check(
    (more?.tracks.any((t) => !firstIds.contains(t.id)) ?? false),
    'вторая страница целиком повторяет первую',
  );

  // The stream: a signed link plus real bytes by range GET, as the player does.
  final track = found.tracks.firstWhere(
    (t) => t.sourceData?['available'] != false,
    orElse: () => found.tracks.first,
  );
  try {
    final stream = await provider.resolveStream(track);
    check(stream != null && stream.url.contains('/get-mp3/'), 'стрим не mp3');
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
    check(bytes > 0, 'CDN отдал 0 байт');
    print('bytes: $bytes (status ${resp.statusCode})');
    client.close();
  } catch (e) {
    // Without Plus this is normal: the track just doesn't play.
    check(plus == false, 'стрим упал при активном Плюсе: $e');
    print('stream: недоступен ($e)');
  }

  // The artist page: popular, discography, albums, similar.
  final artistPage = await provider.getArtist(found.artists.first.id);
  print(
    'getArtist ${artistPage?.artist.name}: '
    '${artistPage?.topTracks.length} популярных, ${artistPage?.tracks.length} треков, '
    '${artistPage?.albums.length} альбомов, ${artistPage?.similarArtists.length} похожих',
  );
  check(
    (artistPage?.topTracks.length ?? 0) > 0,
    'у артиста пусто в популярных',
  );
  check(
    artistPage?.topTracks.every((t) => t.name.isNotEmpty) ?? false,
    'популярные без названий — brief-info отдал голые id, добор не сработал',
  );

  // An album: tracks are gathered from all volumes.
  final albums = artistPage?.albums ?? const [];
  if (albums.isNotEmpty) {
    final album = await provider.getAlbum(albums.first.id);
    print('getAlbum ${album?.playlist.title}: ${album?.tracks.length} треков');
    check((album?.tracks.length ?? 0) > 0, 'альбом без треков');
    check(
      album?.playlist.ownerName?.isNotEmpty ?? false,
      'у альбома нет исполнителя в шапке',
    );
  }

  // A playlist from the results: the /users/<owner>/playlists/<kind> format.
  if (found.playlists.isNotEmpty) {
    final pl = await provider.getPlaylist(found.playlists.first.id);
    print('getPlaylist ${pl?.playlist.title}: ${pl?.tracks.length} треков');
    check((pl?.tracks.length ?? 0) > 0, 'плейлист без треков');
  }

  // Links: track, album, artist. The id comes from live results, not hardcoded.
  final trackNum = ymNumericId(track.id);
  final resolvedTrack = await provider.resolveUrl(
    'https://music.yandex.ru/track/$trackNum',
  );
  check(resolvedTrack is ResolvedTrack, 'ссылка на трек не дала трек');

  if (albums.isNotEmpty) {
    final albumNum = ymNumericId(albums.first.id);
    final resolvedAlbum = await provider.resolveUrl(
      'https://music.yandex.ru/album/$albumNum',
    );
    check(
      resolvedAlbum is ResolvedSet && resolvedAlbum.playlist.isAlbum,
      'ссылка на альбом не дала альбом',
    );
    // A "track inside an album" link must open the track, not the album.
    final inAlbum = await provider.resolveUrl(
      'https://music.yandex.ru/album/$albumNum/track/$trackNum',
    );
    check(inAlbum is ResolvedTrack, 'ссылка album/track открыла не трек');
  }

  final artistNum = ymNumericId(found.artists.first.id);
  final resolvedArtist = await provider.resolveUrl(
    'https://music.yandex.ru/artist/$artistNum',
  );
  check(resolvedArtist is ResolvedArtist, 'ссылка на артиста не дала артиста');

  // A foreign link goes on through the registry, with no request to Yandex.
  check(
    await provider.resolveUrl('https://soundcloud.com/x/y') == null,
    'Яндекс взялся резолвить чужую ссылку',
  );

  // The home shelves: I check that data arrives.
  final charts = await provider.getCharts();
  print('getCharts: ${charts?.length} треков');
  check((charts?.length ?? 0) > 0, 'чарт пуст');

  final releases = await provider.getNewReleases();
  final newCount = releases is NewAlbums ? releases.albums.length : 0;
  print('getNewReleases: $newCount альбомов');
  check(newCount > 0, 'новинки пусты');

  print(failed == 0 ? '\nВСЁ ОК' : '\nПРОВАЛОВ: $failed');
  exit(failed == 0 ? 0 : 1);
}
