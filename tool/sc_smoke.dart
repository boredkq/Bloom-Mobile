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

/// The first item [play] works for: some results are DRM-only and give no
/// stream, which says nothing about the code.
Future<(T, R)> firstPlayable<T, R>(
  Iterable<T> items,
  Future<R> Function(T) play,
) async {
  for (final item in items) {
    try {
      return (item, await play(item));
    } catch (e) {
      print('skipped: $e');
    }
  }
  stderr.writeln('FAIL: nothing playable in the results');
  exit(1);
}

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
  check(page.items.isNotEmpty, 'empty search results');
  // Resolving the stream from media.transcodings.
  final (t, stream) = await firstPlayable(
    page.items,
    (t) => streamUrl(t.media),
  );
  check(t.id > 0 && t.title.isNotEmpty, 'a track with no id or title');
  print(
    'track: ${t.artist} — ${t.title} (id ${t.id}, media: ${t.media != null})',
  );
  print('client_id: ${activeClientId()}');
  check(stream.url.startsWith('http'), 'the stream is not a url');
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
  print('cdn: status ${resp.statusCode}, $bytes bytes');
  client.close();

  // Artist: search, then profile.
  final arts = await searchArtists('skrillex', limit: 3);
  check(arts.items.isNotEmpty, 'empty artist results');
  final a = arts.items.first;
  final user = await getUser('${a.id}');
  check(user != null && user.id == a.id, 'get_user does not match');
  print('artist: ${user?.username}');

  // Top tracks and artist data.
  final top = await artistTopTracks('${a.id}', artistName: a.title);
  print('top tracks: ${top.length}');
  final data = await artistData('${a.id}', artistName: a.title);
  print(
    'artist data: ${data.tracks.length} tracks, ${data.albums.length} albums',
  );
  final rel = await relatedArtists('${a.id}');
  print('related: ${rel.length}');

  // Resolving a track's permalink.
  final resolved = await resolveUrl(t.permalink!);
  check(resolved?.kind == 'track', 'resolve did not recognize the track');
  print('resolve ok');

  // ── The provider contract on top of it ───────────────────────────
  print('\n— provider —');
  final registry = ProviderRegistry()..register(const SoundCloudProvider());

  final results = await registry.searchAll('daft punk');
  check(results.tracks.isNotEmpty, 'empty results through the registry');
  print(
    'searchAll: ${results.tracks.length} tracks, ${results.artists.length} artists, '
    '${results.albums.length} albums, ${results.playlists.length} playlists',
  );

  // This is how the player goes: a provider by id prefix, then the stream.
  final provider = registry.forEntity(results.tracks.first.id);
  if (provider == null) {
    stderr.writeln('FAIL: the registry found no provider by track id');
    exit(1);
  }
  final (entity, (playable, downloadable)) = await firstPlayable(
    results.tracks,
    (t) async =>
        (await provider.resolveStream(t), await provider.resolveDownload(t)),
  );
  check(entity.id.startsWith('sc:'), 'id with no source prefix: ${entity.id}');
  check(entity.duration > Duration.zero, 'zero duration');
  check(
    playable != null && playable.url.startsWith('http'),
    'the stream does not resolve',
  );
  print('resolveStream: hls=${playable?.isHls}');

  // An offline copy: the same chain, but the link must point to a whole file
  // and bytes must really flow, or offline listening silently fails.
  check(
    provider.canDownload(entity),
    'a platform track does not count as downloadable',
  );
  check(
    downloadable != null && !downloadable.isHls,
    'the download gave a stream, not a file',
  );
  final dlClient = HttpClient();
  final dlResp = await (await dlClient.getUrl(
    Uri.parse(downloadable!.url),
  )).close();
  check(dlResp.statusCode == 200, 'file: CDN status ${dlResp.statusCode}');
  final first = await dlResp.first;
  // The magic bytes the offline store picks an extension by: `ftyp` from the
  // fourth byte is m4a, else mp3.
  final isM4a =
      first.length > 8 && String.fromCharCodes(first.sublist(4, 8)) == 'ftyp';
  check(first.isNotEmpty, 'file: empty body');
  print(
    'resolveDownload: status ${dlResp.statusCode}, '
    '${dlResp.contentLength} bytes, format ${isM4a ? 'm4a' : 'mp3'}',
  );
  dlClient.close(force: true);

  // The artist page: six endpoints in parallel.
  final artistEntity = results.artists.isNotEmpty
      ? results.artists.first
      : (await registry.searchAll('skrillex')).artists.first;
  final artistPage = await provider.getArtist(artistEntity.id);
  check(artistPage != null, 'the artist page did not come together');
  print(
    'getArtist ${artistPage?.artist.name}: top ${artistPage?.topTracks.length}, '
    'tracks ${artistPage?.tracks.length}, albums ${artistPage?.albums.length}, '
    'playlists ${artistPage?.playlists.length}, '
    'similar ${artistPage?.similarArtists.length}',
  );
  check(
    (artistPage?.topTracks.length ?? 0) > 0,
    'the artist has no popular tracks',
  );

  // An artist's album opens by its composite id.
  final albums = artistPage?.albums ?? const [];
  final album = albums.isEmpty
      ? null
      : await provider.getAlbum(albums.first.id);
  if (album != null) {
    print('getAlbum ${album.playlist.title}: ${album.tracks.length} tracks');
    check(album.tracks.isNotEmpty, 'an album with no tracks');
  }

  // An account link opens the account's page.
  final handle = artistPage?.artist.permalink ?? artistEntity.permalink;
  if (handle != null) {
    final hit = await registry.resolveUrlAny(handle);
    check(hit?.resolved is ResolvedArtist, 'an account link gave no artist');
    if (hit?.resolved case ResolvedArtist(:final artist)) {
      print('account resolve ${artist.name}');
    }
  }

  // A foreign link mustn't go to `/resolve`: the provider passes it on.
  check(
    await provider.resolveUrl('https://music.yandex.ru/album/1') == null,
    'SoundCloud tried to resolve a foreign link',
  );

  print(failed == 0 ? '\nALL OK' : '\nFAILED: $failed');
  exit(failed == 0 ? 0 : 1);
}
