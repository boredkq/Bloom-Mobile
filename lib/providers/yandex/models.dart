/// Yandex Music result types.
library;

/// A Yandex error. `code` is a key from `ym.err.*`, translated by the UI (see
/// `describeYmFailure`), or the platform's text.
class YmException implements Exception {
  final String code;
  const YmException(this.code);
  @override
  String toString() => code;
}

/// Field defaults, used only when the platform gave no field at all. They reach
/// the UI so rarely that they get no translation keys.
const String kYmUntitled = 'Без названия';
const String kYmUnknownArtist = 'Неизвестен';
const String kYmDash = '—';

class YmRawTrack {
  final String id;
  final String title;
  final String artist;

  /// First artist's id, to go to their page.
  final String artistId;

  /// Every artist with their id, for the artist links.
  final List<({String id, String name})> artists;

  /// Full https URL of a 400x400 cover, or empty.
  final String cover;
  final Duration duration;

  /// Release year from the track's first album, or empty.
  final String year;

  /// Album's full release date (2024-05-13T00:00:00+03:00), if in the results:
  /// Yandex often has `releaseDate` beside `year`.
  final String releaseDate;
  final bool available;

  /// Chart position (1-based); 0 if the track isn't from a chart.
  final int chartPos;

  /// Daily position change: >0 rose, <0 fell, 0 none.
  final int chartShift;

  /// New in the chart (`progress: "new"`): shows new instead of an arrow.
  final bool chartNew;

  const YmRawTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.cover,
    required this.duration,
    required this.year,
    required this.available,
    this.artists = const [],
    this.releaseDate = '',
    this.chartPos = 0,
    this.chartShift = 0,
    this.chartNew = false,
  });

  /// The same track with a chart position: chart fields lie in the chart item's
  /// wrapper, not the track, and go on top of the parsed result.
  YmRawTrack withChart({
    required int pos,
    required int shift,
    required bool isNew,
  }) => YmRawTrack(
    id: id,
    title: title,
    artist: artist,
    artistId: artistId,
    artists: artists,
    cover: cover,
    duration: duration,
    year: year,
    available: available,
    releaseDate: releaseDate,
    chartPos: pos,
    chartShift: shift,
    chartNew: isNew,
  );
}

class YmRawArtist {
  final String id;
  final String name;
  final String cover;

  const YmRawArtist({
    required this.id,
    required this.name,
    required this.cover,
  });
}

class YmRawAlbum {
  final String id;
  final String title;
  final String artist;
  final String cover;
  final String year;

  /// Full release date; see [YmRawTrack.releaseDate].
  final String releaseDate;
  final int trackCount;

  /// First artist's id, to go to their page from a release card.
  final String artistId;

  /// First artist's 1000×1000 photo for a release card's large circle. Larger
  /// than covers: the circle is nearly the card's width, and 400×400 is soft
  /// there.
  final String artistCover;

  /// Yandex's release type: `single`, `compilation`, `podcast`…; empty is a
  /// usual album.
  final String albumType;

  const YmRawAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.cover,
    required this.year,
    required this.trackCount,
    this.releaseDate = '',
    this.artistId = '',
    this.artistCover = '',
    this.albumType = '',
  });
}

class YmRawPlaylist {
  final String kind;
  final String owner;
  final String title;
  final String cover;
  final int trackCount;

  const YmRawPlaylist({
    required this.kind,
    required this.owner,
    required this.title,
    required this.cover,
    required this.trackCount,
  });
}

/// An entity page (album, artist, playlist): a header, tracks and, for an
/// artist, albums and similar artists.
class YmEntity {
  final String title;
  final String subtitle;
  final String cover;

  /// Main track list: all for an album or playlist; for an artist the
  /// discography from `/artists/{id}/tracks`.
  final List<YmRawTrack> tracks;

  /// Artist only: popular tracks from brief-info.
  final List<YmRawTrack> popularTracks;
  final List<YmRawAlbum> albums;

  /// Release year (album); empty for an artist or playlist.
  final String year;

  /// Album's full release date; see [YmRawTrack.releaseDate].
  final String releaseDate;

  /// Owner's or artist's avatar for the header's owner row (an album takes
  /// `artists[0]`).
  final String ownerAvatar;

  /// Artist only: similar artists from brief-info.
  final List<YmRawArtist> similarArtists;

  const YmEntity({
    required this.title,
    required this.subtitle,
    required this.cover,
    this.tracks = const [],
    this.popularTracks = const [],
    this.albums = const [],
    this.year = '',
    this.releaseDate = '',
    this.ownerAvatar = '',
    this.similarArtists = const [],
    this.tracksNextPage,
    this.tracksTotal,
  });

  /// Artist only: next tracks page number; `null` if the discography fit the
  /// first.
  final int? tracksNextPage;

  /// Artist only: total tracks (`pager.total`), for the header's count until
  /// all are loaded.
  final int? tracksTotal;
}

/// A page of an artist's tracks, loaded by Load more.
class YmTracksPage {
  const YmTracksPage({this.tracks = const [], this.nextPage, this.total});

  final List<YmRawTrack> tracks;

  /// Next page number; `null` if this was the last.
  final int? nextPage;

  /// The artist's total tracks; `null` if Yandex gave no pager.
  final int? total;
}

/// Search result across all categories.
class YmSearch {
  final List<YmRawTrack> tracks;
  final List<YmRawArtist> artists;
  final List<YmRawAlbum> albums;
  final List<YmRawPlaylist> playlists;

  const YmSearch({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
  });
}

/// Result of resolving a music.yandex.ru link (tag `kind`).
class YmResolved {
  /// `track` | `album` | `artist` | `playlist`.
  final String kind;
  final YmRawTrack? track;
  final YmEntity? entity;

  const YmResolved.track(YmRawTrack this.track) : kind = 'track', entity = null;
  const YmResolved.album(YmEntity this.entity) : kind = 'album', track = null;
  const YmResolved.artist(YmEntity this.entity) : kind = 'artist', track = null;
  const YmResolved.playlist(YmEntity this.entity)
    : kind = 'playlist',
      track = null;
}

/// A rotor station batch: the tracks and a batch id that goes back in feedback,
/// by which the station matches an event to what it offered.
class YmWaveBatch {
  final List<YmRawTrack> tracks;
  final String batchId;

  const YmWaveBatch({this.tracks = const [], this.batchId = ''});
}

/// OAuth device-flow device code (step 1).
class YmDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;

  /// Pause between token polls.
  final Duration interval;

  /// Code lifetime.
  final Duration expiresIn;

  const YmDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresIn,
  });
}

/// One token poll's outcome: still waiting for confirmation, or the token is
/// ready.
class YmPollOutcome {
  /// null: the user hasn't confirmed, poll later.
  final String? token;
  const YmPollOutcome.pending() : token = null;
  const YmPollOutcome.token(String this.token);

  bool get isPending => token == null;
}
