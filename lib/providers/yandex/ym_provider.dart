/// Yandex Music as a [MusicProvider]: a thin layer over the API, mapping
/// `YmRaw*` to shared entities. All network logic and its gotchas live a floor
/// below; here it's mapping and building pages.
library;

import 'dart:async';

import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import 'models.dart';
import 'yandex.dart' as ym;

/// Global ids with a source prefix: a track is `ym:<id>`, an artist
/// `ym:artist:<id>`, an album `ym:album:<id>`, a playlist
/// `ym:pl:<owner>~<kind>` (the playlist request needs owner and kind), and a
/// new format public playlist `ym:plu:<uuid>`.
String ymTrackId(String id) => 'ym:$id';
String ymArtistId(String id) => 'ym:artist:$id';
String ymAlbumId(String id) => 'ym:album:$id';
String ymPlaylistId(String owner, String kind) => 'ym:pl:$owner~$kind';
String ymPlaylistUuidId(String uuid) => 'ym:plu:$uuid';

/// Parses `ym:pl:<owner>~<kind>` back, by the LAST `~`: a tilde occurs in an
/// owner's login, not in kind.
({String owner, String kind})? parseYmPlaylistId(String id) {
  if (!id.startsWith('ym:pl:')) return null;
  final body = id.substring('ym:pl:'.length);
  final i = body.lastIndexOf('~');
  if (i < 0) return null;
  return (owner: body.substring(0, i), kind: body.substring(i + 1));
}

/// Parses `ym:plu:<uuid>` back to a uuid (new format).
String? parseYmPlaylistUuidId(String id) =>
    id.startsWith('ym:plu:') ? id.substring('ym:plu:'.length) : null;

/// Numeric id from a global one (`ym:123`, `ym:artist:123`, `ym:album:123`).
/// Empty means unparsed, and the provider then finds nothing.
String ymNumericId(String entityId) {
  final last = entityId.split(':').last;
  return RegExp(r'^\d+$').hasMatch(last) ? last : '';
}

String? _blankToNull(String s) => s.isEmpty ? null : s;

Track trackFromYm(YmRawTrack t) => Track(
  id: ymTrackId(t.id),
  name: t.title,
  artist: t.artist,
  duration: t.duration,
  cover: _blankToNull(t.cover),
  source: MusicSource.yandex,
  year: _blankToNull(t.year),
  releaseDate: _blankToNull(t.releaseDate),
  artistId: t.artistId.isEmpty ? null : ymArtistId(t.artistId),
  artists: [
    for (final a in t.artists)
      (name: a.name, id: a.id.isEmpty ? null : ymArtistId(a.id)),
  ],
  // The stream resolves by track id, so the platform's raw data is for one
  // thing: not requesting a track Yandex marked unavailable.
  sourceData: {'available': t.available},
  // Chart fields exist only in a chart's answer; elsewhere there's no position,
  // and the UI draws no number or arrow.
  chartPos: t.chartPos > 0 ? t.chartPos : null,
  chartShift: t.chartShift,
  chartNew: t.chartNew,
);

Artist artistFromYm(YmRawArtist a) => Artist(
  id: ymArtistId(a.id),
  name: a.name,
  avatar: _blankToNull(a.cover),
  source: MusicSource.yandex,
);

Playlist albumFromYm(YmRawAlbum a) => Playlist(
  id: ymAlbumId(a.id),
  title: a.title,
  cover: _blankToNull(a.cover),
  // A missing count arrives as zero: 0 tracks under a 14-track album is worse
  // than nothing.
  trackCount: a.trackCount > 0 ? a.trackCount : null,
  ownerName: _blankToNull(a.artist),
  ownerAvatar: _blankToNull(a.artistCover),
  ownerId: a.artistId.isEmpty ? null : ymArtistId(a.artistId),
  year: _blankToNull(a.year),
  releaseDate: _blankToNull(a.releaseDate),
  albumType: _blankToNull(a.albumType),
  sourceUrl: 'https://music.yandex.ru/album/${a.id}',
  isAlbum: true,
  source: MusicSource.yandex,
);

Playlist playlistFromYm(YmRawPlaylist p) => Playlist(
  id: ymPlaylistId(p.owner, p.kind),
  title: p.title,
  cover: _blankToNull(p.cover),
  trackCount: p.trackCount > 0 ? p.trackCount : null,
  ownerName: _blankToNull(p.owner),
  sourceUrl: 'https://music.yandex.ru/users/${p.owner}/playlists/${p.kind}',
  source: MusicSource.yandex,
);

/// Search's inner pager: Yandex's pages are 0-indexed with ~24 tracks each,
/// while the shared store counts `offset` in SoundCloud steps, and offset to
/// page mapping would drift.
String? _pagerQuery;
int _pagerPage = 0;

/// Station to its last batch's id, sent with feedback.
final Map<String, String> _batches = {};

class YandexProvider extends MusicProvider {
  const YandexProvider();

  @override
  MusicSource get source => MusicSource.yandex;

  /// Before login Yandex doesn't show in the platform picker or all sources:
  /// with no token the API answers 401 to everything.
  @override
  bool get isEnabled => ym.activeToken() != null;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    // Resets the pager: the next loadMoreTracks starts from page 1.
    _pagerQuery = query;
    _pagerPage = 0;
    // Yandex search has no sort: the parameter comes from the shared UI, with
    // nothing to affect here.
    final d = await ym.search(query);
    return SearchResults(
      tracks: d.tracks.map(trackFromYm).toList(),
      artists: d.artists.map(artistFromYm).toList(),
      albums: d.albums.map(albumFromYm).toList(),
      playlists: d.playlists.map(playlistFromYm).toList(),
      // A Yandex page has ~24 tracks; a full one means there's more.
      tracksHasMore: d.tracks.length >= 20,
    );
  }

  @override
  Future<TrackPage?> loadMoreTracks(
    String query,
    int offset, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    // `offset` is ignored (it's SoundCloud-sized), with a page counter of my
    // own. On a query mismatch it starts over.
    if (_pagerQuery != query) {
      _pagerQuery = query;
      _pagerPage = 0;
    }
    _pagerPage += 1;
    final d = await ym.search(query, page: _pagerPage);
    return TrackPage(
      tracks: d.tracks.map(trackFromYm).toList(),
      hasMore: d.tracks.length >= 20,
    );
  }

  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    // A foreign link goes on through the registry with no request spent.
    if (!RegExp(r'music\.yandex\.[a-z]+', caseSensitive: false).hasMatch(url)) {
      return null;
    }
    final r = await ym.resolve(url);
    switch (r.kind) {
      case 'track':
        return ResolvedTrack(trackFromYm(r.track!));
      // The entity comes with tracks but no id of its own: I take it from the
      // link, so the page can load (getAlbum, getPlaylist).
      case 'album':
        final id = ym.reAlbum.firstMatch(url)?.group(1);
        if (id == null) return null;
        return ResolvedSet(_setFromEntity(r.entity!, ymAlbumId(id), true, url));
      case 'artist':
        final id = ym.reArtist.firstMatch(url)?.group(1);
        if (id == null) return null;
        return ResolvedArtist(
          Artist(
            id: ymArtistId(id),
            name: r.entity!.title,
            avatar: _blankToNull(r.entity!.cover),
            source: MusicSource.yandex,
          ),
        );
      case 'playlist':
        final m = ym.reUserPlaylist.firstMatch(url);
        final uuid = m == null
            ? ym.rePublicPlaylist.firstMatch(url)?.group(1)
            : null;
        if (m == null && uuid == null) return null;
        final id = m != null
            ? ymPlaylistId(m.group(1)!, m.group(2)!)
            : ymPlaylistUuidId(uuid!);
        return ResolvedSet(_setFromEntity(r.entity!, id, false, url));
      default:
        return null;
    }
  }

  Playlist _setFromEntity(
    YmEntity e,
    String id,
    bool isAlbum,
    String sourceUrl,
  ) => Playlist(
    id: id,
    title: e.title,
    cover: _blankToNull(e.cover),
    ownerName: _blankToNull(e.subtitle),
    ownerAvatar: _blankToNull(e.ownerAvatar),
    year: _blankToNull(e.year),
    releaseDate: _blankToNull(e.releaseDate),
    trackCount: e.tracks.isEmpty ? null : e.tracks.length,
    isAlbum: isAlbum,
    sourceUrl: sourceUrl,
    source: MusicSource.yandex,
  );

  @override
  Future<Track?> resolveTrackById(String id) async {
    final numeric = ymNumericId(id);
    if (numeric.isEmpty) return null;
    return trackFromYm(await ym.trackOne(numeric));
  }

  /// Similar for home shelves. Artists, albums and playlists also live under
  /// the `ym:` prefix, with no similar and no network trip.
  @override
  Future<List<Track>?> getSimilarTracks(String seedId) async {
    if (!RegExp(r'^ym:\d+$').hasMatch(seedId)) return const [];
    return (await ym.similarTracks(
      seedId.substring('ym:'.length),
    )).map(trackFromYm).toList();
  }

  @override
  String trackStation(Track track) {
    final id = track.source == MusicSource.yandex ? ymNumericId(track.id) : '';
    return id.isNotEmpty && isEnabled ? 'track:$id' : '';
  }

  /// A rotor station: it goes on from the last track it gave.
  @override
  Future<StationPage> station(String station, String cursor) async {
    try {
      final batch = await ym.waveTracks(station, lastId: cursor);
      if (batch.batchId.isNotEmpty) _batches[station] = batch.batchId;
      return StationPage(
        tracks: batch.tracks.map(trackFromYm).toList(),
        cursor: batch.tracks.isEmpty ? '' : batch.tracks.last.id,
      );
    } catch (_) {
      return const StationPage();
    }
  }

  /// Best effort: lost feedback just teaches the station a bit less.
  @override
  void stationFeedback(
    String station,
    String event, {
    Track? track,
    double played = 0,
  }) {
    final id = track == null ? '' : ymNumericId(track.id);
    unawaited(
      ym.waveFeedback(
        station: station,
        event: event,
        trackId: id,
        batchId: _batches[station] ?? '',
        played: played,
      ),
    );
  }

  @override
  Future<ArtistPageData?> getArtist(String id) async {
    final numeric = ymNumericId(id);
    if (numeric.isEmpty) return null;
    final e = await ym.artist(numeric);
    return ArtistPageData(
      artist: Artist(
        id: id,
        name: e.title,
        avatar: _blankToNull(e.cover),
        source: MusicSource.yandex,
      ),
      // Popular from brief-info; tracks are the discography's first page, with
      // more through Load more ([getArtistTracksPage]).
      topTracks: e.popularTracks.map(trackFromYm).toList(),
      tracks: e.tracks.map(trackFromYm).toList(),
      albums: e.albums.map(albumFromYm).toList(),
      similarArtists: e.similarArtists.map(artistFromYm).toList(),
      tracksCursor: e.tracksNextPage == null
          ? null
          : '$numeric:${e.tracksNextPage}',
      tracksTotal: e.tracksTotal,
    );
  }

  /// Loads an artist's tracks. The cursor is `<artist id>:<page number>` (see
  /// [getArtist]).
  @override
  Future<TrackPage?> getArtistTracksPage(String cursor) async {
    final m = RegExp(r'^(\d+):(\d+)$').firstMatch(cursor);
    if (m == null) return null;
    final id = m.group(1)!;
    final page = await ym.artistTracksPage(id, int.parse(m.group(2)!));
    final next = page.nextPage;
    return TrackPage(
      tracks: page.tracks.map(trackFromYm).toList(),
      hasMore: next != null,
      cursor: next == null ? null : '$id:$next',
    );
  }

  @override
  Future<SetContent?> getAlbum(String id) async {
    final numeric = ymNumericId(id);
    if (numeric.isEmpty) return null;
    final e = await ym.album(numeric);
    final tracks = e.tracks.map(trackFromYm).toList();
    return SetContent(
      playlist: _setFromEntity(
        e,
        id,
        true,
        'https://music.yandex.ru/album/$numeric',
      ),
      tracks: tracks,
    );
  }

  @override
  Future<SetContent?> getPlaylist(String id) async {
    final uuid = parseYmPlaylistUuidId(id);
    final parsed = uuid == null ? parseYmPlaylistId(id) : null;
    if (uuid == null && parsed == null) return null;
    final e = uuid != null
        ? await ym.playlistByUuid(uuid)
        : await ym.playlist(parsed!.owner, parsed.kind);
    return SetContent(
      playlist: _setFromEntity(
        e,
        id,
        false,
        uuid != null
            ? 'https://music.yandex.ru/playlists/$uuid'
            : 'https://music.yandex.ru/users/${parsed!.owner}/playlists/${parsed.kind}',
      ),
      tracks: e.tracks.map(trackFromYm).toList(),
    );
  }

  @override
  Future<List<Track>?> getCharts() async =>
      (await ym.chart()).map(trackFromYm).toList();

  @override
  Future<NewReleases?> getNewReleases() async =>
      NewAlbums((await ym.newReleases()).map(albumFromYm).toList());

  @override
  Future<PlayableStream?> resolveStream(Track track) async =>
      PlayableStream(url: await _streamUrl(track));

  /// What downloads is just what plays: on Yandex it's a whole mp3, not a
  /// playlist of chunks.
  @override
  bool canDownload(Track track) => track.sourceData?['available'] != false;

  @override
  Future<PlayableStream?> resolveDownload(Track track) async =>
      PlayableStream(url: await _streamUrl(track));

  /// A signed link lives minutes, so a 4 minute cache: otherwise a pause and
  /// play would need a new resolve.
  Future<String> _streamUrl(Track track) async {
    final id = ymNumericId(track.id);
    if (id.isEmpty) throw const YmException('ym.err.trackNotFound');
    final cached = _streamCache[id];
    if (cached != null && DateTime.now().difference(cached.at) < _streamTtl) {
      return cached.url;
    }
    final url = await ym.streamUrl(id);
    _streamCache[id] = (url: url, at: DateTime.now());
    return url;
  }
}

const Duration _streamTtl = Duration(minutes: 4);
final Map<String, ({String url, DateTime at})> _streamCache = {};

/// Forgets signed links: on logout they'd expire anyway, with no reason to hold
/// them in memory.
void clearYmStreamCache() => _streamCache.clear();
