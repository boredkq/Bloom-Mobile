/// A network smoke run against live YouTube Music, not for CI: search by
/// section, pages, links, paging without duplicates, the stream with real
/// bytes.
///
/// Run: `dart run tool/ytm_smoke.dart [query]` ("ado" by default).
///
/// Run it when YouTube Music stops playing: it shows at once whether the client
/// constants have gone stale (`kVrClientVersion`/`kWebClientVersion`).
library;

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/providers/ytmusic/models.dart';
import 'package:bloom/providers/ytmusic/ytm_provider.dart';
import 'package:bloom/providers/ytmusic/ytmusic.dart' as ytm;

var failed = 0;

void check(bool cond, String what) {
  if (!cond) {
    failed++;
    stderr.writeln('FAIL: $what');
  }
}

Future<void> main(List<String> args) async {
  final query = args.firstOrNull ?? 'ado';
  const provider = YtmusicProvider();

  // visitorData: without it `player` answers LOGIN_REQUIRED. It's the first
  // thing to break and the first to look for in the output.
  final visitor = await ytm.visitorData();
  print(
    'visitorData: ${visitor.isEmpty ? "ПУСТО" : "${visitor.length} симв."}',
  );
  check(visitor.isNotEmpty, 'visitorData не получен');

  // ---- Search: sections don't mix ----
  final found = await provider.search(query);
  print(
    'search «$query»: ${found.tracks.length} треков, '
    '${found.artists.length} артистов, ${found.albums.length} альбомов, '
    '${found.playlists.length} плейлистов',
  );
  check(found.tracks.isNotEmpty, 'треков нет');
  check(found.artists.isNotEmpty, 'артистов нет');
  check(
    found.tracks.every((t) => t.duration > Duration.zero),
    'у трека нулевая длительность',
  );
  check(
    found.tracks.every((t) => t.artist != kYtmUnknownArtist),
    'трек без исполнителя (метка типа съела артиста)',
  );
  // What I search for must land in its own section (catches mixed-up results).
  check(
    found.artists.any(
      (a) => a.name.toLowerCase().contains(query.toLowerCase()),
    ),
    'искомого артиста нет среди артистов',
  );

  final track = found.tracks.first;
  print('первый трек: ${track.artist} — ${track.name} (${track.duration})');

  // ---- Paging: pages without duplicates ----
  if (found.tracksHasMore) {
    final more = await provider.loadMoreTracks(query, found.tracks.length);
    final ids = found.tracks.map((t) => t.id).toSet();
    final dupes = (more?.tracks ?? const []).where((t) => ids.contains(t.id));
    print(
      'loadMoreTracks: +${more?.tracks.length} треков, дублей ${dupes.length}',
    );
    check((more?.tracks.length ?? 0) > 0, 'догрузка ничего не дала');
    check(dupes.isEmpty, 'догрузка вернула уже показанные треки');
  } else {
    print('loadMoreTracks: продолжения нет (вкладка Songs не ответила)');
  }

  // ---- Artist: full lists, bio, similar ----
  final artistId = found.artists.first.id;
  final page = await provider.getArtist(artistId);
  print(
    'getArtist ${page?.artist.name}: ${page?.topTracks.length} популярных, '
    '${page?.tracks.length} треков, ${page?.albums.length} релизов, '
    '${page?.similarArtists.length} похожих',
  );
  check((page?.topTracks.length ?? 0) > 0, 'у артиста нет популярных треков');
  check(
    (page?.tracks.length ?? 0) > (page?.topTracks.length ?? 0),
    'полный список песен не длиннее шапки — сломалась кнопка «ещё»',
  );
  check((page?.albums.length ?? 0) > 0, 'у артиста нет релизов');

  // ---- Album: the artist in rows, the count ----
  if (page != null && page.albums.isNotEmpty) {
    final album = await provider.getAlbum(page.albums.first.id);
    print(
      'getAlbum ${album?.playlist.title}: ${album?.tracks.length} треков, '
      'год ${album?.playlist.year}',
    );
    check((album?.tracks.length ?? 0) > 0, 'альбом без треков');
    check(
      album?.tracks.every((t) => t.artist.isNotEmpty) ?? false,
      'в строках альбома пустой исполнитель',
    );
    check((album?.playlist.cover ?? '').isNotEmpty, 'у альбома нет обложки');
  }

  // ---- Playlist ----
  if (found.playlists.isNotEmpty) {
    final pl = await provider.getPlaylist(found.playlists.first.id);
    print('getPlaylist ${pl?.playlist.title}: ${pl?.tracks.length} треков');
    check((pl?.tracks.length ?? 0) > 0, 'плейлист без треков');
  }
  // Only official playlists have a track count, but where it exists it must
  // make sense.
  final counted = found.playlists.where((p) => p.trackCount != null);
  print('плейлистов со счётчиком: ${counted.length}');
  check(counted.every((p) => p.trackCount! > 0), 'счётчик треков нулевой');
  check(
    found.albums.every((a) => a.trackCount == null || a.trackCount! > 0),
    'у альбома счётчик нулём',
  );

  // ---- Links ----
  final videoId = parseYtmTrackId(track.id)!;
  final byWatch = await provider.resolveUrl(
    'https://music.youtube.com/watch?v=$videoId',
  );
  check(byWatch is ResolvedTrack, 'ссылка watch?v= не дала трек');

  final browseId = parseYtmArtistId(artistId)!;
  final byChannel = await provider.resolveUrl(
    'https://www.youtube.com/channel/$browseId',
  );
  check(byChannel is ResolvedArtist, 'ссылка на канал не дала артиста');

  if (page != null && page.albums.isNotEmpty) {
    final byBrowse = await provider.resolveUrl(
      'https://music.youtube.com/browse/${parseYtmAlbumId(page.albums.first.id)}',
    );
    check(
      byBrowse is ResolvedSet && byBrowse.playlist.isAlbum,
      'ссылка /browse/MPRE не дала альбом',
    );
  }

  // A foreign link goes on through the registry, with no request to YouTube.
  check(
    await provider.resolveUrl('https://soundcloud.com/x/y') == null,
    'YTM взялся резолвить чужую ссылку',
  );

  // ---- Stream: the link is playable and really gives bytes ----
  final stream = await provider.resolveStream(track);
  print('resolveStream: ${stream?.url.substring(0, 60)}…');
  check(stream != null && stream.url.startsWith('http'), 'нет ссылки на поток');
  if (stream != null) {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(stream.url));
    req.headers.set('Range', 'bytes=0-4095');
    final resp = await req.close();
    final bytes = await resp.fold<int>(0, (n, chunk) => n + chunk.length);
    print('байт получено: $bytes (HTTP ${resp.statusCode})');
    check(
      resp.statusCode == 206 || resp.statusCode == 200,
      'CDN не отдал байты',
    );
    check(bytes > 0, 'поток пуст');
    client.close();
  }

  // ---- Re-resolving a track by id (for recents after a restart) ----
  final again = await provider.resolveTrackById(track.id);
  print('resolveTrackById: ${again?.name}');
  check(again != null && again.name.isNotEmpty, 'трек по id не восстановился');

  print(failed == 0 ? '\nВСЁ ОК' : '\nПРОВАЛОВ: $failed');
  exit(failed == 0 ? 0 : 1);
}
