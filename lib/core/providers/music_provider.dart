/// The contract of a music provider, the only thing a platform implements. It
/// maps its results to shared [Track], [Artist] and [Playlist]; the whole UX
/// knows nothing of the platform.
///
/// Dart has no optional methods, so not supported means `null` from the base
/// implementation: callers check the result.
library;

import '../entities/entities.dart';

enum SearchSort {
  /// By relevance, the default.
  relevance,

  /// Newest first; on SoundCloud, `&sort=created_at`.
  newest,
}

/// Normalized search results, so search UI is one for all. Albums are the same
/// [Playlist] with the same card.
class SearchResults {
  final List<Artist> artists;
  final List<Playlist> playlists;
  final List<Playlist> albums;
  final List<Track> tracks;

  /// Whether more tracks exist.
  final bool tracksHasMore;

  const SearchResults({
    this.artists = const [],
    this.playlists = const [],
    this.albums = const [],
    this.tracks = const [],
    this.tracksHasMore = false,
  });

  static const empty = SearchResults();

  bool get isEmpty =>
      artists.isEmpty && playlists.isEmpty && albums.isEmpty && tracks.isEmpty;
}

/// Result of resolving a pasted link.
sealed class ResolvedUrl {
  const ResolvedUrl();
}

class ResolvedTrack extends ResolvedUrl {
  final Track track;
  const ResolvedTrack(this.track);
}

class ResolvedArtist extends ResolvedUrl {
  final Artist artist;
  const ResolvedArtist(this.artist);
}

class ResolvedSet extends ResolvedUrl {
  final Playlist playlist;
  const ResolvedSet(this.playlist);
}

/// A platform's new releases. Fresh albums on Yandex and YTM, New & Hot tracks
/// on SoundCloud, which has no global album feed. So a union: the block decides
/// how to draw it.
sealed class NewReleases {
  const NewReleases();
}

class NewAlbums extends NewReleases {
  final List<Playlist> albums;
  const NewAlbums(this.albums);
}

class NewTracks extends NewReleases {
  final List<Track> tracks;
  const NewTracks(this.tracks);
}

/// Artist page content.
class ArtistPageData {
  /// The artist enriched with description, website and bannerUrl.
  final Artist artist;

  /// Popular section.
  final List<Track> topTracks;

  /// All of the artist's tracks.
  final List<Track> tracks;
  final List<Playlist> albums;

  /// A listener's playlists (a profile has no albums).
  final List<Playlist> playlists;

  /// A listener's likes as a collection: set, the page is a profile and
  /// [tracks] are these likes.
  final Playlist? likes;

  /// Similar artists; empty on platforms that don't give them.
  final List<Artist> similarArtists;

  /// Opaque cursor of the next track page; null if no more.
  final String? tracksCursor;

  /// The artist's total tracks per the platform, for the header count until all
  /// are loaded. `null`: the platform doesn't know, so I count what's loaded.
  final int? tracksTotal;

  const ArtistPageData({
    required this.artist,
    this.topTracks = const [],
    this.tracks = const [],
    this.albums = const [],
    this.playlists = const [],
    this.likes,
    this.similarArtists = const [],
    this.tracksCursor,
    this.tracksTotal,
  });
}

/// A batch of tracks with a cursor or more flag.
class TrackPage {
  final List<Track> tracks;
  final bool hasMore;

  /// Opaque cursor, if the platform pages by it rather than an offset.
  final String? cursor;

  const TrackPage({this.tracks = const [], this.hasMore = false, this.cursor});
}

/// Album or playlist content.
class SetContent {
  final Playlist playlist;
  final List<Track> tracks;
  const SetContent({required this.playlist, this.tracks = const []});
}

/// A playable track stream.
class PlayableStream {
  final String url;

  /// HLS needs different handling by the player than a progressive file.
  final bool isHls;

  /// Headers the CDN needs to serve the bytes (SoundCloud needs none).
  final Map<String, String> headers;

  const PlayableStream({
    required this.url,
    this.isHls = false,
    this.headers = const {},
  });
}

/// A batch of a platform's radio. [cursor] leads to the next; empty means the
/// radio ended and next time starts over.
class StationPage {
  final List<Track> tracks;
  final String cursor;

  const StationPage({this.tracks = const [], this.cursor = ''});
}

abstract class MusicProvider {
  const MusicProvider();

  MusicSource get source;

  /// Source id; a separate getter so the registry doesn't depend on the enum.
  String get id => source.id;

  String get label => source.label;

  /// Whether the provider is on right now (Yandex only after login).
  bool get isEnabled => true;

  /// Search. Returns all results; missing sections are just empty.
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  });

  /// Artists by name, with no other results. For when only one field is wanted,
  /// like an artist's avatar in the stats top.
  ///
  /// By default comes from general search; a platform with its own endpoint
  /// (SoundCloud's `/search/users`) overrides it.
  Future<List<Artist>> searchArtists(String query, {int limit = 3}) async =>
      (await search(query)).artists.take(limit).toList();

  /// Loads more tracks. `offset` is how many are shown; `null` means no paging.
  Future<TrackPage?> loadMoreTracks(
    String query,
    int offset, {
    SearchSort sort = SearchSort.relevance,
  }) async => null;

  /// Resolves a pasted link of this source.
  Future<ResolvedUrl?> resolveUrl(String url) async => null;

  /// Resolves one track by global id, to play a recent item after a restart,
  /// when it's no longer in memory.
  Future<Track?> resolveTrackById(String id) async => null;

  Future<ArtistPageData?> getArtist(String id) async => null;

  Future<SetContent?> getAlbum(String id) async => null;

  Future<SetContent?> getPlaylist(String id) async => null;

  /// Loads an artist's tracks by the cursor from [ArtistPageData.tracksCursor].
  Future<TrackPage?> getArtistTracksPage(String cursor) async => null;

  /// Home shelf: the platform's chart. `null` means it doesn't take part.
  Future<List<Track>?> getCharts() async => null;

  Future<NewReleases?> getNewReleases() async => null;

  /// Similar to a track, for home shelves. The seed is a global id: it comes
  /// from the play log, with no [Track] to hand.
  ///
  /// `null`: the platform gives no similar tracks. A foreign or non-track id
  /// gives an empty list with no network call.
  Future<List<Track>?> getSimilarTracks(String seedId) async => null;

  /// Radio the wave starts from for this platform's track (`track:<id>`).
  /// Empty: no radio here.
  String trackStation(Track track) => '';

  /// A batch of radio [station] (`track:<id>`, on Yandex also
  /// `user:onyourwave`, `artist:<id>`) from [cursor]; an empty cursor starts
  /// over. A failure is an empty batch: the wave polls seeds in a batch, and
  /// one failing mustn't bring down the rest.
  Future<StationPage> station(String station, String cursor) async =>
      const StationPage();

  /// Feedback to a self-learning radio (Yandex): `radioStarted`,
  /// `trackStarted`, `trackFinished`, `skip`; [played] is in seconds.
  void stationFeedback(
    String station,
    String event, {
    Track? track,
    double played = 0,
  }) {}

  /// Playable URL of this platform's track.
  Future<PlayableStream?> resolveStream(Track track) async => null;

  /// Whether the platform can serve the track as a FILE. Separate from
  /// [resolveStream]: HLS plays but can't be saved.
  bool canDownload(Track track) => false;

  /// File link for an offline copy. Unlike [resolveStream] it must be a whole
  /// file (progressive), not a playlist of chunks; throws if the track has
  /// none.
  Future<PlayableStream?> resolveDownload(Track track) async => null;
}
