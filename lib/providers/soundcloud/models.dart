/// SoundCloud result types.
library;

/// A SoundCloud error. `code` is a dictionary key (`sc.err.*`, `search.err.*`)
/// or the platform's own error text.
class ScException implements Exception {
  final String code;
  const ScException(this.code);
  @override
  String toString() => code;
}

class ScRawTrack {
  final int id;
  final String title;
  final String artist;
  final int? artistScId;
  final String? artwork;
  final int duration;
  final String? permalink;

  /// Raw `media` (transcodings), for streaming and downloading.
  final Map<String, dynamic>? media;
  final String? genre;
  final List<String> tags;
  final String album;
  final String publisher;
  final String description;
  final bool explicit;
  final String creditedArtist;
  final String? artistAvatar;
  final String? artistPermalink;
  final bool artistVerified;
  final String year;

  /// The date [year] was cut from, whole (`release_date`, else `created_at`),
  /// so track info can show day and month when known.
  final String releaseDate;

  /// `policy` from api-v2 (`ALLOW`, `MONETIZE`, `BLOCK`, `SNIP`). For the wave:
  /// picks shouldn't offer what surely won't play.
  final String? policy;

  const ScRawTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistScId,
    required this.artwork,
    required this.duration,
    required this.permalink,
    required this.media,
    required this.genre,
    required this.tags,
    required this.album,
    required this.publisher,
    required this.description,
    required this.explicit,
    required this.creditedArtist,
    required this.artistAvatar,
    required this.artistPermalink,
    required this.artistVerified,
    required this.year,
    this.releaseDate = '',
    this.policy,
  });
}

class ScRawArtist {
  final int id;
  final String title;
  final String artist;
  final String? artwork;
  final String? permalink;

  /// `track_count`; null when the answer leaves it out.
  final int? trackCount;

  const ScRawArtist({
    required this.id,
    required this.title,
    required this.artist,
    required this.artwork,
    required this.permalink,
    this.trackCount,
  });
}

class ScRawPlaylist {
  final int id;
  final String title;
  final String artist;
  final String? artwork;

  /// Owner's avatar (`user.avatar_url`), for the owner row in a hero.
  final String? artistAvatar;
  final int trackCount;
  final int duration;

  /// Release year: `release_date`, else `created_at`.
  final String year;

  /// The same date whole; see [ScRawTrack.releaseDate].
  final String releaseDate;
  final String? permalink;

  /// `set_type`: album, ep, single, compilation; "" for a playlist.
  final String setType;

  const ScRawPlaylist({
    required this.id,
    required this.title,
    required this.artist,
    required this.artwork,
    required this.artistAvatar,
    required this.trackCount,
    required this.duration,
    required this.year,
    required this.permalink,
    this.releaseDate = '',
    this.setType = '',
  });
}

class ScPage<T> {
  final List<T> items;
  final bool hasMore;
  const ScPage({required this.items, required this.hasMore});
}

class ScCheckResult {
  final bool ok;
  final String? clientId;
  final String? error;
  const ScCheckResult({required this.ok, required this.clientId, this.error});
}

class ScRawUser {
  final int id;
  final String username;
  final String fullName;
  final String? avatar;
  final String? banner;

  /// `null` when the answer had no count: then I can't tell a listener.
  final int? trackCount;
  final int? likesCount;
  final String description;
  final String? website;
  final String? permalink;

  const ScRawUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatar,
    required this.banner,
    required this.trackCount,
    this.likesCount,
    required this.description,
    required this.website,
    required this.permalink,
  });
}

class ScTracksCursorPage {
  final List<ScRawTrack> tracks;
  final String? next;
  const ScTracksCursorPage({required this.tracks, required this.next});
}

class ScArtistData {
  final List<ScRawTrack> tracks;
  final String? tracksNext;
  final List<ScRawPlaylist> albums;
  const ScArtistData({
    required this.tracks,
    required this.tracksNext,
    required this.albums,
  });
}

class ScPlaylistFull {
  final List<ScRawTrack> tracks;
  final String title;
  final String? cover;
  final String ownerName;

  /// Owner's avatar, for the owner row in a hero.
  final String? ownerAvatar;
  final int? ownerId;
  final int trackCount;

  /// Release year (release_date or created_at).
  final String year;

  /// The same date whole; see [ScRawTrack.releaseDate].
  final String releaseDate;

  const ScPlaylistFull({
    required this.tracks,
    required this.title,
    required this.cover,
    required this.ownerName,
    required this.ownerAvatar,
    this.ownerId,
    required this.trackCount,
    required this.year,
    this.releaseDate = '',
  });
}

/// Result of resolving a SoundCloud link, with fields by `kind`.
class ScResolved {
  final String kind; // "track" | "artist" | "playlist" | "album"
  final ScRawTrack? track;
  final ScRawArtist? artist;
  final ScRawPlaylist? playlist;
  const ScResolved({
    required this.kind,
    this.track,
    this.artist,
    this.playlist,
  });
}

class ScStream {
  final String url;
  final bool isHls;
  const ScStream({required this.url, required this.isHls});
}
