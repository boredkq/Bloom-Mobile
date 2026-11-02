/// A network smoke run against the live API, not for CI. Run: `dart run
/// tool/sc_smoke.dart`.
///
/// It needs no Flutter runtime: the provider is plain Dart.
library;

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/core/providers/registry.dart';
import 'package:bloom/providers/soundcloud/sc_provider.dart';
import 'package:bloom/providers/soundcloud/soundcloud.dart';

Future<void> main() async {
  var failed = 0;
  void check(bool cond, String what) {
    if (!cond) {
      failed++;
      stderr.writeln('FAIL: $what');
    }
  }

  // Track search plus mapping.
  final page = await searchTracks('daft punk', limit: 5);
  check(page.items.isNotEmpty, 'пустая выдача поиска');
  final t = page.items.first;
  check(t.id > 0 && t.title.isNotEmpty, 'трек без id/названия');
  print(
    'track: ${t.artist} — ${t.title} (id ${t.id}, media: ${t.media != null})',
  );
  print('client_id: ${activeClientId()}');

  // Resolving the stream from media.transcodings.
  final stream = await streamUrl(t.media);
  check(stream.url.startsWith('http'), 'стрим не url');
  final head = stream.url.substring(0, stream.url.length.clamp(0, 60));
  print('stream: hls=${stream.isHls} url=$head…');

  // Bytes really come through (a range GET, as the player does).
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(stream.url));
  req.headers.add('Range', 'bytes=0-1023');
  final resp = await req.close();
  final bytes = await resp.fold<int>(0, (n, ch) => n + ch.length);
  check(
    resp.statusCode == 200 || resp.statusCode == 206,
    'CDN status ${resp.statusCode}',
  );
  print('cdn: status ${resp.statusCode}, $bytes байт');
  client.close();

  // Artist: search, then profile.
  final arts = await searchArtists('skrillex', limit: 3);
  check(arts.items.isNotEmpty, 'пустая выдача артистов');
  final a = arts.items.first;
  final user = await getUser('${a.id}');
  check(user != null && user.id == a.id, 'get_user не сошёлся');
  print('artist: ${user?.username}');

  // Top tracks and artist data.
  final top = await artistTopTracks('${a.id}', artistName: a.title);
  print('top tracks: ${top.length}');
  final data = await artistData('${a.id}', artistName: a.title);
  print(
    'artist data: ${data.tracks.length} треков, ${data.albums.length} альбомов',
  );
  final rel = await relatedArtists('${a.id}');
  print('related: ${rel.length}');

  // Resolving a track's permalink.
  final resolved = await resolveUrl(t.permalink!);
  check(resolved?.kind == 'track', 'resolve не распознал трек');
  print('resolve ok');

  // ── The provider contract on top of it ───────────────────────────
  print('\n— провайдер —');
  final registry = ProviderRegistry()..register(const SoundCloudProvider());

  final results = await registry.searchAll('daft punk');
  check(results.tracks.isNotEmpty, 'пустая выдача через реестр');
  print(
    'searchAll: ${results.tracks.length} треков, ${results.artists.length} артистов, '
    '${results.albums.length} альбомов, ${results.playlists.length} плейлистов',
  );

  final entity = results.tracks.first;
  check(entity.id.startsWith('sc_'), 'id без префикса источника: ${entity.id}');
  check(entity.duration > Duration.zero, 'нулевая длительность');

  // This is how the player goes: a provider by id prefix, then the stream.
  final provider = registry.forEntity(entity.id);
  check(provider != null, 'реестр не нашёл провайдера по id трека');
  final playable = await provider!.resolveStream(entity);
  check(
    playable != null && playable.url.startsWith('http'),
    'стрим не резолвится',
  );
  print('resolveStream: hls=${playable?.isHls}');

  // An offline copy: the same chain, but the link must point to a whole file
  // and bytes must really flow, or offline listening silently fails.
  check(provider.canDownload(entity), 'трек площадки не считается скачиваемым');
  final downloadable = await provider.resolveDownload(entity);
  check(
    downloadable != null && !downloadable.isHls,
    'скачивание отдало не файл, а поток',
  );
  final dlClient = HttpClient();
  final dlResp = await (await dlClient.getUrl(
    Uri.parse(downloadable!.url),
  )).close();
  check(dlResp.statusCode == 200, 'файл: CDN status ${dlResp.statusCode}');
  final first = await dlResp.first;
  // The magic bytes the offline store picks an extension by: `ftyp` from the
  // fourth byte is m4a, else mp3.
  final isM4a =
      first.length > 8 && String.fromCharCodes(first.sublist(4, 8)) == 'ftyp';
  check(first.isNotEmpty, 'файл: пустое тело');
  print(
    'resolveDownload: status ${dlResp.statusCode}, '
    '${dlResp.contentLength} байт, формат ${isM4a ? 'm4a' : 'mp3'}',
  );
  dlClient.close(force: true);

  // The artist page: six endpoints in parallel.
  final artistEntity = results.artists.isNotEmpty
      ? results.artists.first
      : (await registry.searchAll('skrillex')).artists.first;
  final artistPage = await provider.getArtist(artistEntity.id);
  check(artistPage != null, 'страница артиста не собралась');
  print(
    'getArtist ${artistPage?.artist.name}: топ ${artistPage?.topTracks.length}, '
    'треков ${artistPage?.tracks.length}, альбомов ${artistPage?.albums.length}, '
    'плейлистов ${artistPage?.playlists.length}, '
    'похожих ${artistPage?.similarArtists.length}',
  );
  check(
    (artistPage?.topTracks.length ?? 0) > 0,
    'у артиста пусто в популярных',
  );

  // An artist's album opens by its composite id.
  final albums = artistPage?.albums ?? const [];
  final album = albums.isEmpty
      ? null
      : await provider.getAlbum(albums.first.id);
  if (album != null) {
    print('getAlbum ${album.playlist.title}: ${album.tracks.length} треков');
    check(album.tracks.isNotEmpty, 'альбом без треков');
  }

  // An account link opens the account's page.
  final handle = artistPage?.artist.permalink ?? artistEntity.permalink;
  if (handle != null) {
    final hit = await registry.resolveUrlAny(handle);
    check(hit?.resolved is ResolvedArtist, 'ссылка аккаунта не дала артиста');
    if (hit?.resolved case ResolvedArtist(:final artist)) {
      print('resolve аккаунта ${artist.name}');
    }
  }

  // A foreign link mustn't go to `/resolve`: the provider passes it on.
  check(
    await provider.resolveUrl('https://music.yandex.ru/album/1') == null,
    'SC взялся резолвить чужую ссылку',
  );

  print(failed == 0 ? '\nВСЁ ОК' : '\nПРОВАЛОВ: $failed');
  exit(failed == 0 ? 0 : 1);
}
