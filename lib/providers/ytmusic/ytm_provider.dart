/// YouTube Music as a [MusicProvider]: a thin layer over InnerTube, mapping
/// `YtmRaw*` to shared entities. All network logic and its gotchas live a floor
/// below; here it's mapping and building pages.
///
/// No `isEnabled`: public search and stream need no auth, so the platform
/// always shows, unlike Yandex with its token.
library;

import 'dart:io';

import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import 'models.dart';
import 'ytmusic.dart' as ytm;

/// Global ids with a source prefix: a track is `ytm:<videoId>`, an artist
/// `ytm:artist:<browseId>`, an album `ytm:album:<browseId>`, a playlist
/// `ytm:pl:<browseId>`.
String ytmTrackId(String videoId) => 'ytm:$videoId';
String ytmArtistId(String browseId) => 'ytm:artist:$browseId';
String ytmAlbumId(String browseId) => 'ytm:album:$browseId';
String ytmPlaylistId(String browseId) => 'ytm:pl:$browseId';

/// Parses a global id back. A track's prefix is shared with the rest, so longer
/// ones go first, or `ytm:album:MPRE…` parses as videoId `album:MPRE…`.
String? parseYtmTrackId(String id) =>
    id.startsWith('ytm:') &&
        !id.startsWith('ytm:artist:') &&
        !id.startsWith('ytm:album:') &&
        !id.startsWith('ytm:pl:')
    ? id.substring('ytm:'.length)
    : null;
String? parseYtmArtistId(String id) =>
    id.startsWith('ytm:artist:') ? id.substring('ytm:artist:'.length) : null;
String? parseYtmAlbumId(String id) =>
    id.startsWith('ytm:album:') ? id.substring('ytm:album:'.length) : null;
String? parseYtmPlaylistId(String id) =>
    id.startsWith('ytm:pl:') ? id.substring('ytm:pl:'.length) : null;

String? _blankToNull(String s) => s.isEmpty ? null : s;

Track trackFromYtm(YtmRawTrack t) => Track(
  id: ytmTrackId(t.id),
  name: t.title.isEmpty ? kYtmUntitled : t.title,
  artist: t.artist.isEmpty ? kYtmUnknownArtist : t.artist,
  duration: t.duration,
  cover: _blankToNull(t.cover),
  source: MusicSource.ytmusic,
  artistId: t.artistId.isEmpty ? null : ytmArtistId(t.artistId),
  artists: [
    for (final a in t.artists)
      (name: a.name, id: a.id.isEmpty ? null : ytmArtistId(a.id)),
  ],
  url: 'https://music.youtube.com/watch?v=${t.id}',
  // The stream resolves by the videoId in the global id, with no raw platform
  // data needed.
);

Artist artistFromYtm(YtmRawArtist a) => Artist(
  id: ytmArtistId(a.id),
  name: a.name.isEmpty ? kYtmUnknownArtist : a.name,
  avatar: _blankToNull(a.cover),
  source: MusicSource.ytmusic,
);

Playlist albumFromYtm(YtmRawAlbum a) => Playlist(
  id: ytmAlbumId(a.id),
  title: a.title.isEmpty ? kYtmAlbumFallback : a.title,
  cover: _blankToNull(a.cover),
  ownerName: _blankToNull(a.artist),
  year: _blankToNull(a.year),
  albumType: a.kind,
  sourceUrl: 'https://music.youtube.com/browse/${a.id}',
  isAlbum: true,
  source: MusicSource.ytmusic,
);

Playlist playlistFromYtm(YtmRawPlaylist p) => Playlist(
  id: ytmPlaylistId(p.id),
  title: p.title.isEmpty ? kYtmPlaylistFallback : p.title,
  cover: _blankToNull(p.cover),
  // The count isn't filled with zero: YTM gives it only on its own playlists,
  // and 0 for unknown looks like an empty playlist.
  trackCount: p.trackCount,
  ownerName: _blankToNull(p.ownerName),
  sourceUrl: 'https://music.youtube.com/playlist?list=${_bare(p.id)}',
  source: MusicSource.ytmusic,
);

/// A playlist's browseId with no service prefix `VL`, which is extra in a
/// `?list=` link.
String _bare(String browseId) =>
    browseId.startsWith('VL') ? browseId.substring(2) : browseId;

class YtmusicProvider extends MusicProvider {
  const YtmusicProvider();

  @override
  MusicSource get source => MusicSource.ytmusic;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    // YTM search has no sort: the parameter comes from the shared UI, with
    // nothing to affect here.
    final d = await ytm.search(query);
    return SearchResults(
      tracks: d.tracks.map(trackFromYtm).toList(),
      artists: d.artists.map(artistFromYtm).toList(),
      albums: d.albums.map(albumFromYtm).toList(),
      playlists: d.playlists.map(playlistFromYtm).toList(),
      tracksHasMore: d.tracksHasMore,
    );
  }

  /// One Artists tab rather than all results: an artist's avatar doesn't need
  /// five search requests. General search treats the same tab as the truth on
  /// artists, with the wanted one first.
  @override
  Future<List<Artist>> searchArtists(String query, {int limit = 3}) async {
    final v = await ytm.searchRaw(query, ytm.kParamsArtists);
    final rows = ytm.filteredRows(
      v,
      (it) => ytm.pageType(it) == 'MUSIC_PAGE_TYPE_ARTIST',
      ytm.parseArtist,
      limit,
      (a) => a.id,
    );
    return rows.map(artistFromYtm).toList();
  }

  /// Loads results (20 at a time). `offset` is ignored: InnerTube pages by an
  /// opaque token rather than an offset, tied to the query and living in the
  /// network layer.
  @override
  Future<TrackPage?> loadMoreTracks(
    String query,
    int offset, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    final d = await ytm.searchMore(query);
    return TrackPage(
      tracks: d.tracks.map(trackFromYtm).toList(),
      hasMore: d.hasMore,
    );
  }

  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    // A foreign link goes on through the registry with no request spent.
    if (!RegExp(
      r'youtube\.com|youtu\.be',
      caseSensitive: false,
    ).hasMatch(url)) {
      return null;
    }
    final r = await ytm.resolve(url);
    switch (r.kind) {
      case 'track':
        return ResolvedTrack(trackFromYtm(await ytm.track(r.id)));
      case 'artist':
        final e = await ytm.artist(r.id);
        return ResolvedArtist(
          Artist(
            id: ytmArtistId(r.id),
            name: e.title.isEmpty ? kYtmUnknownArtist : e.title,
            avatar: _blankToNull(e.cover),
            source: MusicSource.ytmusic,
          ),
        );
      case 'album':
        final c = await getAlbum(ytmAlbumId(r.id));
        return c == null ? null : ResolvedSet(c.playlist);
      case 'playlist':
        final c = await getPlaylist(ytmPlaylistId(r.id));
        return c == null ? null : ResolvedSet(c.playlist);
      default:
        return null;
    }
  }

  @override
  Future<Track?> resolveTrackById(String id) async {
    final videoId = parseYtmTrackId(id);
    if (videoId == null) return null;
    return trackFromYtm(await ytm.track(videoId));
  }

  @override
  Future<ArtistPageData?> getArtist(String id) async {
    final browseId = parseYtmArtistId(id);
    if (browseId == null) return null;
    final e = await ytm.artist(browseId);
    return ArtistPageData(
      artist: Artist(
        id: id,
        name: e.title.isEmpty ? kYtmUnknownArtist : e.title,
        avatar: _blankToNull(e.cover),
        description: _blankToNull(e.description),
        source: MusicSource.ytmusic,
      ),
      topTracks: e.popularTracks.map(trackFromYtm).toList(),
      tracks: e.tracks.map(trackFromYtm).toList(),
      albums: e.albums.map(albumFromYtm).toList(),
      similarArtists: e.similarArtists.map(artistFromYtm).toList(),
    );
  }

  @override
  Future<SetContent?> getAlbum(String id) async {
    final browseId = parseYtmAlbumId(id);
    if (browseId == null) return null;
    final e = await ytm.album(browseId);
    final tracks = e.tracks.map(trackFromYtm).toList();
    return SetContent(
      playlist: Playlist(
        id: id,
        title: e.title.isEmpty ? kYtmAlbumFallback : e.title,
        cover: _blankToNull(e.cover),
        ownerName: _blankToNull(e.subtitle),
        ownerAvatar: _blankToNull(e.ownerAvatar),
        year: _blankToNull(e.year),
        trackCount: tracks.isEmpty ? null : tracks.length,
        isAlbum: true,
        sourceUrl: 'https://music.youtube.com/browse/$browseId',
        source: MusicSource.ytmusic,
      ),
      tracks: tracks,
    );
  }

  @override
  Future<SetContent?> getPlaylist(String id) async {
    final browseId = parseYtmPlaylistId(id);
    if (browseId == null) return null;
    final e = await ytm.playlist(browseId);
    final tracks = e.tracks.map(trackFromYtm).toList();
    return SetContent(
      playlist: Playlist(
        id: id,
        title: e.title.isEmpty ? kYtmPlaylistFallback : e.title,
        cover: _blankToNull(e.cover),
        ownerName: _blankToNull(e.subtitle),
        ownerAvatar: _blankToNull(e.ownerAvatar),
        trackCount: tracks.isEmpty ? null : tracks.length,
        sourceUrl: 'https://music.youtube.com/playlist?list=${_bare(browseId)}',
        source: MusicSource.ytmusic,
      ),
      tracks: tracks,
    );
  }

  @override
  String trackStation(Track track) {
    final vid = track.source == MusicSource.ytmusic
        ? parseYtmTrackId(track.id)
        : null;
    return vid == null || vid.isEmpty ? '' : 'track:$vid';
  }

  /// YouTube Music has no separate similar: it's the start of a track's radio.
  @override
  Future<List<Track>?> getSimilarTracks(String seedId) async {
    final vid = parseYtmTrackId(seedId);
    if (vid == null || vid.isEmpty) return const [];
    final page = await station('track:$vid', '');
    return [
      for (final t in page.tracks)
        if (t.id != seedId) t,
    ];
  }

  @override
  Future<StationPage> station(String station, String cursor) async {
    if (!station.startsWith('track:')) return const StationPage();
    try {
      final r = await ytm.radio(station.substring(6), cursor: cursor);
      return StationPage(
        tracks: r.tracks.map(trackFromYtm).toList(),
        cursor: r.cursor,
      );
    } catch (_) {
      return const StationPage();
    }
  }

  /// A direct `googlevideo` link, fetched by the player itself.
  ///
  /// On iOS it's an HLS playlist instead: the direct link leads to fragmented
  /// mp4, and outside HLS AVPlayer counts its duration as double the real one
  /// (see `_hlsAudioUrl`).
  @override
  Future<PlayableStream?> resolveStream(Track track) async =>
      PlayableStream(url: await _streamUrl(track, hls: Platform.isIOS));

  /// What downloads is just what plays: `adaptiveFormats` is a whole file (itag
  /// 140, m4a), not a playlist of chunks.
  @override
  bool canDownload(Track track) => true;

  /// Downloads always take the direct link, even on iOS, which plays through a
  /// playlist: an offline copy must be one file, not a set of segments.
  @override
  Future<PlayableStream?> resolveDownload(Track track) async =>
      PlayableStream(url: await _streamUrl(track));

  /// A signed googlevideo link lives minutes, so a 4 minute cache: otherwise a
  /// pause and play would need a new resolve.
  Future<String> _streamUrl(Track track, {bool hls = false}) async {
    final videoId = parseYtmTrackId(track.id);
    if (videoId == null) throw const YtmException('ytm.err.trackNotFound');
    // Player and download take DIFFERENT links for one track: a shared key
    // would give a download the playlist, or the reverse, by who asked first.
    final key = hls ? '$videoId#hls' : videoId;
    final cached = _streamCache[key];
    if (cached != null && DateTime.now().difference(cached.at) < _streamTtl) {
      return cached.url;
    }
    final url = await ytm.streamUrl(videoId, hls: hls);
    _streamCache[key] = (url: url, at: DateTime.now());
    return url;
  }
}

const Duration _streamTtl = Duration(minutes: 4);
final Map<String, ({String url, DateTime at})> _streamCache = {};
