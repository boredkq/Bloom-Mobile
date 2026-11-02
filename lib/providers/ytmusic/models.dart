/// YouTube Music result types.
library;

/// A YouTube Music error. `code` is a key from `ytm.err.*`, translated by the
/// UI, or the platform's ready reason text (`playabilityStatus.reason` comes in
/// the request's language and isn't translated).
class YtmException implements Exception {
  final String code;
  const YtmException(this.code);
  @override
  String toString() => code;
}

class YtmRawTrack {
  /// videoId YouTube.
  final String id;
  final String title;
  final String artist;

  /// Artist's browseId (`UC…`), to go to their page; empty if none.
  final String artistId;

  /// Every artist with a page, for the artist links.
  final List<({String id, String name})> artists;
  final String cover;
  final Duration duration;

  const YtmRawTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.cover,
    required this.duration,
    this.artists = const [],
  });

  /// Album rows take cover and artist from the page; see `album()`.
  YtmRawTrack copyWith({String? artist, String? cover}) => YtmRawTrack(
    id: id,
    title: title,
    artist: artist ?? this.artist,
    artistId: artistId,
    artists: artists,
    cover: cover ?? this.cover,
    duration: duration,
  );
}

class YtmRawArtist {
  /// browseId (`UC…`).
  final String id;
  final String name;
  final String cover;

  const YtmRawArtist({
    required this.id,
    required this.name,
    required this.cover,
  });
}

class YtmRawAlbum {
  /// browseId (`MPRE…`).
  final String id;
  final String title;
  final String artist;
  final String cover;
  final String year;

  /// The release's type from the caption's opening label: single, ep; null
  /// for an album.
  final String? kind;

  const YtmRawAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.cover,
    required this.year,
    this.kind,
  });
}

class YtmRawPlaylist {
  /// browseId (`VL…`/playlistId).
  final String id;
  final String title;
  final String cover;
  final String ownerName;

  /// Track count, if YTM gave it (see `rowTrackCount`). Nullable: unknown and
  /// zero tracks are different things.
  final int? trackCount;

  const YtmRawPlaylist({
    required this.id,
    required this.title,
    required this.cover,
    required this.ownerName,
    this.trackCount,
  });
}

class YtmSearchRaw {
  final List<YtmRawTrack> tracks;
  final List<YtmRawArtist> artists;
  final List<YtmRawAlbum> albums;
  final List<YtmRawPlaylist> playlists;

  /// Whether there's a next page token. The shared UI asks the results for this
  /// flag; see `SearchResults.tracksHasMore`.
  final bool tracksHasMore;

  const YtmSearchRaw({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
    this.tracksHasMore = false,
  });
}

/// A batch of search loading (see `searchMore`).
class YtmSearchMore {
  final List<YtmRawTrack> tracks;
  final bool hasMore;
  const YtmSearchMore({this.tracks = const [], this.hasMore = false});
}

/// An entity page (album, artist, playlist): a header, tracks and, for an
/// artist, releases.
class YtmEntity {
  final String title;
  final String subtitle;
  final String cover;
  final List<YtmRawTrack> tracks;

  /// Artist only: popular, the top songs shelf.
  final List<YtmRawTrack> popularTracks;
  final List<YtmRawAlbum> albums;

  /// Artist only: similar artists (Fans might also like).
  final List<YtmRawArtist> similarArtists;

  /// Release year, a 4-digit run in the header's subtitle. Empty for an artist.
  final String year;

  /// Artist's or owner's avatar from the header (`straplineThumbnail`).
  final String ownerAvatar;

  /// Artist only: bio from the header. Empty if YTM gives none.
  final String description;

  const YtmEntity({
    this.title = '',
    this.subtitle = '',
    this.cover = '',
    this.tracks = const [],
    this.popularTracks = const [],
    this.albums = const [],
    this.similarArtists = const [],
    this.year = '',
    this.ownerAvatar = '',
    this.description = '',
  });
}

/// What a pasted link opens: [kind] is `track`, `album`, `playlist` or
/// `artist`, [id] a videoId or the page's browseId.
class YtmResolved {
  final String kind;
  final String id;
  const YtmResolved(this.kind, this.id);
}
