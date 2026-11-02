/// SoundCloud as a [MusicProvider]: a thin layer over api-v2, mapping `ScRaw*`
/// to shared entities. All network logic and its gotchas live a floor below;
/// here it's mapping and building pages.
library;

import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import '../../core/providers/provider_text.dart';
import 'models.dart';
import 'sc_sources.dart' show similarTracks, waveRelated, waveStation;
import 'soundcloud.dart' as sc;

/// Global ids: `sc:123`, `sc:artist:123`, `sc:set:123`. An album and a playlist
/// are one set on SoundCloud, told apart by [Playlist.isAlbum].
String scTrackId(int id) => 'sc:$id';
String scArtistId(int id) => 'sc:artist:$id';
String scSetId(int id) => 'sc:set:$id';

/// Numeric id back from a global one. Unsafe values give 0: the provider then
/// finds nothing rather than crashing.
int scNumericId(String entityId) => int.tryParse(entityId.split(':').last) ?? 0;

String? _blankToNull(String s) => s.isEmpty ? null : s;

Track trackFromSc(ScRawTrack t) => Track(
  id: scTrackId(t.id),
  name: t.title,
  artist: t.artist,
  duration: Duration(milliseconds: t.duration),
  cover: t.artwork,
  source: MusicSource.soundcloud,
  album: _blankToNull(t.album),
  year: _blankToNull(t.year),
  releaseDate: _blankToNull(t.releaseDate),
  publisher: _blankToNull(t.publisher),
  description: _blankToNull(t.description),
  explicit: t.explicit,
  genres: t.genre == null ? const [] : [t.genre!.toLowerCase()],
  url: t.permalink,
  artistId: t.artistScId == null ? null : scArtistId(t.artistScId!),
  artistAvatar: t.artistAvatar,
  artistVerified: t.artistVerified,
  creditedArtist: _blankToNull(t.creditedArtist),
  // The stream resolves from `media.transcodings`, so I keep the raw data with
  // the track.
  sourceData: t.media,
);

Artist artistFromSc(ScRawArtist a) => Artist(
  id: scArtistId(a.id),
  // Here `title` is the username and `artist` the full_name.
  name: a.title,
  fullName: _blankToNull(a.artist),
  avatar: a.artwork,
  permalink: a.permalink,
  profile: a.trackCount == 0,
  source: MusicSource.soundcloud,
);

/// A set's release type in [Playlist.albumType]'s words; a plain album is null.
String? _setKind(String setType) =>
    const {'single', 'ep', 'compilation'}.contains(setType) ? setType : null;

Playlist setFromSc(ScRawPlaylist p, {required bool isAlbum}) => Playlist(
  id: scSetId(p.id),
  title: p.title,
  cover: p.artwork,
  // A missing count arrives as zero: 0 tracks under a 14-track album is worse
  // than nothing.
  trackCount: p.trackCount > 0 ? p.trackCount : null,
  ownerName: _blankToNull(p.artist),
  ownerAvatar: p.artistAvatar,
  year: _blankToNull(p.year),
  releaseDate: _blankToNull(p.releaseDate),
  albumType: _setKind(p.setType),
  duration: p.duration > 0 ? Duration(milliseconds: p.duration) : null,
  sourceUrl: p.permalink,
  isAlbum: isAlbum,
  source: MusicSource.soundcloud,
);

/// A listener's likes as a collection (`sc:likes:<id>`): what's imported and
/// linked as a source, named in the language of the moment.
Playlist scLikesOf(Artist account) => Playlist(
  id: 'sc:likes:${scNumericId(account.id)}',
  title: providerText.likesOf(account.name),
  cover: account.avatar,
  ownerName: account.name,
  ownerAvatar: account.avatar,
  ownerId: account.id,
  sourceUrl: account.permalink == null ? null : '${account.permalink}/likes',
  source: MusicSource.soundcloud,
);

Artist _artistFromUser(ScRawUser u) => Artist(
  id: scArtistId(u.id),
  name: u.username,
  fullName: _blankToNull(u.fullName),
  avatar: u.avatar,
  bannerUrl: u.banner,
  permalink: u.permalink,
  description: _blankToNull(u.description),
  website: u.website,
  source: MusicSource.soundcloud,
);

class SoundCloudProvider extends MusicProvider {
  const SoundCloudProvider();

  @override
  MusicSource get source => MusicSource.soundcloud;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    final sortParam = sort == SearchSort.newest ? 'new' : 'relevance';
    // Four endpoints in parallel; a failed section just adds nothing.
    final results = await Future.wait([
      sc
          .searchTracks(query, limit: 30, sort: sortParam)
          .then<Object?>((v) => v, onError: (_) => null),
      sc
          .searchArtists(query, limit: 12)
          .then<Object?>((v) => v, onError: (_) => null),
      sc
          .searchAlbums(query, limit: 12)
          .then<Object?>((v) => v, onError: (_) => null),
      sc
          .searchPlaylists(query, limit: 12)
          .then<Object?>((v) => v, onError: (_) => null),
    ]);

    final tracks = results[0] as ScPage<ScRawTrack>?;
    final artists = results[1] as ScPage<ScRawArtist>?;
    final albums = results[2] as ScPage<ScRawPlaylist>?;
    final playlists = results[3] as ScPage<ScRawPlaylist>?;

    return SearchResults(
      tracks: tracks?.items.map(trackFromSc).toList() ?? const [],
      artists: artists?.items.map(artistFromSc).toList() ?? const [],
      albums:
          albums?.items.map((p) => setFromSc(p, isAlbum: true)).toList() ??
          const [],
      playlists:
          playlists?.items.map((p) => setFromSc(p, isAlbum: false)).toList() ??
          const [],
      tracksHasMore: tracks?.hasMore ?? false,
    );
  }

  /// Narrow `/search/users` rather than all results: one artist's avatar
  /// doesn't need tracks, albums and playlists too.
  @override
  Future<List<Artist>> searchArtists(String query, {int limit = 3}) async {
    final page = await sc.searchArtists(query, limit: limit);
    return page.items.map(artistFromSc).toList();
  }

  @override
  Future<TrackPage?> loadMoreTracks(
    String query,
    int offset, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    final page = await sc.searchTracks(
      query,
      limit: 30,
      offset: offset,
      sort: sort == SearchSort.newest ? 'new' : 'relevance',
    );
    return TrackPage(
      tracks: page.items.map(trackFromSc).toList(),
      hasMore: page.hasMore,
    );
  }

  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    // A foreign link goes on through the registry with no `/resolve` call:
    // platforms are asked in turn, and an extra request means extra seconds
    // before the one that understands it.
    final u = url.trim().toLowerCase();
    if (!u.contains('soundcloud.com') && !u.contains('snd.sc')) return null;
    final r = await sc.resolveUrl(url);
    if (r == null) return null;
    switch (r.kind) {
      case 'track':
        return ResolvedTrack(trackFromSc(r.track!));
      case 'artist':
        // soundcloud.com/<user>/likes: their likes, as a playlist of their own.
        final path = Uri.tryParse(url.trim())?.pathSegments ?? const [];
        final artist = artistFromSc(r.artist!);
        if (path.length >= 2 && path[1].toLowerCase() == 'likes') {
          return ResolvedSet(scLikesOf(artist));
        }
        return ResolvedArtist(artist);
      case 'album':
        return ResolvedSet(setFromSc(r.playlist!, isAlbum: true));
      case 'playlist':
        return ResolvedSet(setFromSc(r.playlist!, isAlbum: false));
      default:
        return null;
    }
  }

  @override
  Future<Track?> resolveTrackById(String id) async {
    final raw = await sc.trackById(scNumericId(id));
    return raw == null ? null : trackFromSc(raw);
  }

  /// Similar for home shelves: related, and if few, the track's station.
  /// Through the queue and cache shared with the wave, or together they hit
  /// 429.
  @override
  Future<List<Track>?> getSimilarTracks(String seedId) async {
    final m = RegExp(r'^sc:(\d+)$').firstMatch(seedId);
    if (m == null) return const [];
    return (await similarTracks(m.group(1)!)).map(trackFromSc).toList();
  }

  @override
  String trackStation(Track track) {
    final sid = track.source == MusicSource.soundcloud
        ? scNumericId(track.id)
        : 0;
    return sid > 0 ? 'track:$sid' : '';
  }

  /// The track's station by offset and related mixed: the top of both is
  /// equally good. The cursor is the station's next offset, moving only past
  /// what came; an ended station starts over. Related doesn't page, always the
  /// same list, and the wave filters what's heard.
  @override
  Future<StationPage> station(String station, String cursor) async {
    final sid = station.startsWith('track:') ? station.substring(6) : '';
    if (int.tryParse(sid) == null) return const StationPage();
    var offset = int.tryParse(cursor) ?? 0;
    final related = waveRelated(sid);
    var run = await waveStation(sid, offset: offset);
    if (run.isEmpty && offset > 0) {
      offset = 0;
      run = await waveStation(sid);
    }
    final own = _playable(run);
    final like = _playable(await related);
    final tracks = <Track>[
      for (var i = 0; i < own.length || i < like.length; i++) ...[
        if (i < own.length) own[i],
        if (i < like.length) like[i],
      ],
    ];
    return StationPage(
      tracks: tracks,
      cursor: run.isEmpty ? '' : '${offset + 20}',
    );
  }

  @override
  Future<ArtistPageData?> getArtist(String id) async {
    final user = await sc.getUser('${scNumericId(id)}');
    if (user == null) return null;
    // One with no tracks of their own is a listener, whose page is a profile.
    if (user.trackCount == 0) return _profile(user);
    final userId = '${user.id}';
    // In parallel: the page is four endpoints, each failing into nothing.
    final parts = await Future.wait([
      sc.artistTopTracks(userId).then<Object?>((v) => v, onError: (_) => null),
      sc
          .artistData(userId, artistName: user.username)
          .then<Object?>((v) => v, onError: (_) => null),
      sc.relatedArtists(userId).then<Object?>((v) => v, onError: (_) => null),
    ]);
    final top = (parts[0] as List<ScRawTrack>?) ?? const [];
    final data = parts[1] as ScArtistData?;
    final related = (parts[2] as List<ScRawArtist>?) ?? const [];

    return ArtistPageData(
      artist: _artistFromUser(user),
      topTracks: top.map(trackFromSc).toList(),
      tracks: data?.tracks.map(trackFromSc).toList() ?? const [],
      albums:
          data?.albums.map((p) => setFromSc(p, isAlbum: true)).toList() ??
          const [],
      similarArtists: related.map(artistFromSc).toList(),
      tracksCursor: data?.tracksNext,
      tracksTotal: user.trackCount,
    );
  }

  /// A listener's page: their playlists, and their likes as the rows.
  Future<ArtistPageData> _profile(ScRawUser user) async {
    final artist = _artistFromUser(user);
    final parts = await Future.wait([
      sc.userTrackLikes(user.id).then<Object?>((v) => v, onError: (_) => null),
      sc.userPlaylists('${user.id}'),
    ]);
    final likes = parts[0] as ScTracksCursorPage?;
    final playlists = parts[1] as List<ScRawPlaylist>;
    return ArtistPageData(
      artist: artist,
      likes: scLikesOf(artist),
      tracks: likes?.tracks.map(trackFromSc).toList() ?? const [],
      playlists: playlists.map((p) => setFromSc(p, isAlbum: false)).toList(),
      tracksCursor: likes?.next,
      tracksTotal: user.likesCount,
    );
  }

  @override
  Future<SetContent?> getAlbum(String id) => _getSet(id, isAlbum: true);

  @override
  Future<SetContent?> getPlaylist(String id) => _getSet(id, isAlbum: false);

  Future<SetContent?> _getSet(String id, {required bool isAlbum}) async {
    // Account likes are a collection too, updated this way by Refresh tracks.
    if (id.startsWith('sc:likes:')) {
      final likes = await sc.userLikes(id.substring('sc:likes:'.length));
      return SetContent(
        playlist: Playlist(id: id, title: '', source: MusicSource.soundcloud),
        tracks: likes.map(trackFromSc).toList(),
      );
    }
    final full = await sc.playlistById(scNumericId(id));
    final tracks = full.tracks.map(trackFromSc).toList();
    return SetContent(
      playlist: Playlist(
        id: id,
        title: full.title,
        cover: full.cover,
        trackCount: full.trackCount > 0 ? full.trackCount : tracks.length,
        ownerName: _blankToNull(full.ownerName),
        ownerAvatar: full.ownerAvatar,
        ownerId: full.ownerId == null ? null : scArtistId(full.ownerId!),
        year: _blankToNull(full.year),
        releaseDate: _blankToNull(full.releaseDate),
        isAlbum: isAlbum,
        source: MusicSource.soundcloud,
      ),
      tracks: tracks,
    );
  }

  @override
  Future<TrackPage?> getArtistTracksPage(String cursor) async {
    final page = await sc.listPage(cursor);
    return TrackPage(
      tracks: page.tracks.map(trackFromSc).toList(),
      hasMore: page.next != null,
      cursor: page.next,
    );
  }

  @override
  Future<PlayableStream?> resolveStream(Track track) async {
    final stream = await sc.streamUrl(await _media(track));
    return PlayableStream(url: stream.url, isHls: stream.isHls);
  }

  /// Anything with a way to resolve can download: raw data with the track or an
  /// id to fetch it. Whether transcodings include progressive shows only at the
  /// resolve itself.
  @override
  bool canDownload(Track track) =>
      track.sourceData != null || scNumericId(track.id) > 0;

  @override
  Future<PlayableStream?> resolveDownload(Track track) async {
    final stream = await sc.streamUrl(
      await _media(track),
      progressiveOnly: true,
    );
    return PlayableStream(url: stream.url, isHls: stream.isHls);
  }

  /// A track's transcodings. Empty means it came from a transfer file with no
  /// raw data: I fetch it by id, the same way as recents after a restart. It
  /// doesn't go back to the library (the provider doesn't know it), so such a
  /// track costs a request per play, paid only by tracks that otherwise
  /// wouldn't play.
  Future<Map<String, dynamic>?> _media(Track track) async =>
      track.sourceData ?? (await resolveTrackById(track.id))?.sourceData;
}

/// What plays whole: Go+ previews (`SNIP`) and blocked (`BLOCK`) tracks would
/// just get skipped.
List<Track> _playable(List<ScRawTrack> raw) => [
  for (final t in raw)
    if (t.policy == null ||
        t.policy!.isEmpty ||
        t.policy == 'ALLOW' ||
        t.policy == 'MONETIZE')
      trackFromSc(t),
];
