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
import 'package:bloom/core/providers/provider_text.dart';
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
    'visitorData: ${visitor.isEmpty ? "EMPTY" : "${visitor.length} chars"}',
  );
  check(visitor.isNotEmpty, 'no visitorData received');

  // ---- Search: sections don't mix ----
  final found = await provider.search(query);
  print(
    'search "$query": ${found.tracks.length} tracks, '
    '${found.artists.length} artists, ${found.albums.length} albums, '
    '${found.playlists.length} playlists',
  );
  check(found.tracks.isNotEmpty, 'no tracks');
  check(found.artists.isNotEmpty, 'no artists');
  check(
    found.tracks.every((t) => t.duration > Duration.zero),
    'a track has zero duration',
  );
  check(
    found.tracks.every((t) => t.artist != providerText.unknownArtist),
    'a track with no artist (the type label ate it)',
  );
  // What I search for must land in its own section (catches mixed-up results).
  check(
    found.artists.any(
      (a) => a.name.toLowerCase().contains(query.toLowerCase()),
    ),
    'the searched artist is not among the artists',
  );

  final track = found.tracks.first;
  print('first track: ${track.artist} — ${track.name} (${track.duration})');

  // ---- Paging: pages without duplicates ----
  if (found.tracksHasMore) {
    final more = await provider.loadMoreTracks(query, found.tracks.length);
    final ids = found.tracks.map((t) => t.id).toSet();
    final dupes = (more?.tracks ?? const []).where((t) => ids.contains(t.id));
    print(
      'loadMoreTracks: +${more?.tracks.length} tracks, ${dupes.length} duplicates',
    );
    check((more?.tracks.length ?? 0) > 0, 'loading more gave nothing');
    check(dupes.isEmpty, 'loading more returned tracks already shown');
  } else {
    print('loadMoreTracks: no continuation (the Songs tab did not answer)');
  }

  // ---- Artist: full lists, bio, similar ----
  final artistId = found.artists.first.id;
  final page = await provider.getArtist(artistId);
  print(
    'getArtist ${page?.artist.name}: ${page?.topTracks.length} popular, '
    '${page?.tracks.length} tracks, ${page?.albums.length} releases, '
    '${page?.similarArtists.length} similar',
  );
  check((page?.topTracks.length ?? 0) > 0, 'the artist has no popular tracks');
  check(
    (page?.tracks.length ?? 0) > (page?.topTracks.length ?? 0),
    'the full song list is no longer than the header: the more button broke',
  );
  check((page?.albums.length ?? 0) > 0, 'the artist has no releases');

  // ---- Album: the artist in rows, the count ----
  if (page != null && page.albums.isNotEmpty) {
    final album = await provider.getAlbum(page.albums.first.id);
    print(
      'getAlbum ${album?.playlist.title}: ${album?.tracks.length} tracks, '
      'year ${album?.playlist.year}',
    );
    check((album?.tracks.length ?? 0) > 0, 'an album with no tracks');
    check(
      album?.tracks.every((t) => t.artist.isNotEmpty) ?? false,
      'album rows have an empty artist',
    );
    check((album?.playlist.cover ?? '').isNotEmpty, 'the album has no cover');
  }

  // ---- Playlist ----
  if (found.playlists.isNotEmpty) {
    final pl = await provider.getPlaylist(found.playlists.first.id);
    print('getPlaylist ${pl?.playlist.title}: ${pl?.tracks.length} tracks');
    check((pl?.tracks.length ?? 0) > 0, 'a playlist with no tracks');
  }
  // Only official playlists have a track count, but where it exists it must
  // make sense.
  final counted = found.playlists.where((p) => p.trackCount != null);
  print('playlists with a count: ${counted.length}');
  check(counted.every((p) => p.trackCount! > 0), 'the track count is zero');
  check(
    found.albums.every((a) => a.trackCount == null || a.trackCount! > 0),
    'an album has a zero count',
  );

  // ---- Links ----
  final videoId = parseYtmTrackId(track.id)!;
  final byWatch = await provider.resolveUrl(
    'https://music.youtube.com/watch?v=$videoId',
  );
  check(byWatch is ResolvedTrack, 'a watch?v= link gave no track');

  final browseId = parseYtmArtistId(artistId)!;
  final byChannel = await provider.resolveUrl(
    'https://www.youtube.com/channel/$browseId',
  );
  check(byChannel is ResolvedArtist, 'a channel link gave no artist');

  if (page != null && page.albums.isNotEmpty) {
    final byBrowse = await provider.resolveUrl(
      'https://music.youtube.com/browse/${parseYtmAlbumId(page.albums.first.id)}',
    );
    check(
      byBrowse is ResolvedSet && byBrowse.playlist.isAlbum,
      'a /browse/MPRE link gave no album',
    );
  }

  // A foreign link goes on through the registry, with no request to YouTube.
  check(
    await provider.resolveUrl('https://soundcloud.com/x/y') == null,
    'YouTube Music tried to resolve a foreign link',
  );

  // ---- Stream: the link is playable and really gives bytes ----
  final stream = await provider.resolveStream(track);
  print('resolveStream: ${stream?.url.substring(0, 60)}…');
  check(stream != null && stream.url.startsWith('http'), 'no stream link');
  if (stream != null) {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(stream.url));
    req.headers.set('Range', 'bytes=0-4095');
    final resp = await req.close();
    final bytes = await resp.fold<int>(0, (n, chunk) => n + chunk.length);
    print('bytes received: $bytes (HTTP ${resp.statusCode})');
    check(
      resp.statusCode == 206 || resp.statusCode == 200,
      'the CDN gave no bytes',
    );
    check(bytes > 0, 'the stream is empty');
    client.close();
  }

  // ---- Re-resolving a track by id (for recents after a restart) ----
  final again = await provider.resolveTrackById(track.id);
  print('resolveTrackById: ${again?.name}');
  check(
    again != null && again.name.isNotEmpty,
    'the track did not come back by id',
  );

  print(failed == 0 ? '\nALL OK' : '\nFAILED: $failed');
  exit(failed == 0 ? 0 : 1);
}
