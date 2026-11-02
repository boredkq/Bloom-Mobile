/// Entities shared by all platforms. A provider maps its results TO these
/// types, and the whole UI knows nothing about the platform: adding one means
/// writing a provider, with no screen changes.
///
/// `duration` is a [Duration], formatted when drawn. [Track.source] and the
/// opaque [Track.sourceData] hold what the platform itself needs (for
/// SoundCloud, `media.transcodings` to resolve a stream).
library;

enum MusicSource {
  local('local', 'local', 'Local', 'lf:'),
  soundcloud('soundcloud', 'sc', 'SoundCloud', 'sc:'),
  ytmusic('ytmusic', 'ytm', 'YouTube Music', 'ytm:'),
  yandex('yandex', 'ym', 'Yandex Music', 'ym:');

  const MusicSource(this.id, this.code, this.label, this.prefix);

  /// Source id; not shown in the UI.
  final String id;

  /// Platform as the database writes it (`tracks.provider`).
  final String code;

  static MusicSource fromCode(String code) => MusicSource.values.firstWhere(
    (s) => s.code == code,
    orElse: () => MusicSource.local,
  );

  /// Readable label. Platforms are brands and stay untranslated; only Local and
  /// Yandex Music are translated, via `label10n`.
  final String label;

  /// Prefix of this platform's global ids: `sc:123`, `sc:artist:123`,
  /// `ytm:<videoId>`, `ym:<id>`, `lf:<hash>`.
  final String prefix;

  /// Platform by a global id's PREFIX, where the source isn't stored
  /// separately.
  static MusicSource fromId(String id) {
    for (final s in [
      MusicSource.ytmusic,
      MusicSource.yandex,
      MusicSource.soundcloud,
    ]) {
      if (id.startsWith(s.prefix)) return s;
    }
    return MusicSource.local;
  }
}

/// An artist's name and their page, if it is known.
typedef ArtistLink = ({String name, String? id});

class Track {
  /// Global id with the source prefix (sc:123).
  final String id;

  final String name;

  /// Display name of the artist (may be "Artist A, Artist B").
  final String artist;
  final Duration duration;
  final String? cover;
  final MusicSource source;

  final String? album;
  final String? year;

  /// Full release date (2024-05-13T00:00:00Z) when the platform gave all of it.
  /// The year is already in [year]; this is the raw form for
  /// `releaseDateLabel`.
  final String? releaseDate;
  final String? publisher;
  final String? description;
  final bool explicit;
  final List<String> genres;

  /// Track link on the platform.
  final String? url;

  /// Artist's global id, to open the page from the name with no lookup.
  final String? artistId;
  final String? artistAvatar;
  final bool artistVerified;

  /// Artist from `publisher_metadata`, sometimes more accurate than the account
  /// name.
  final String? creditedArtist;

  /// Every artist with their page, as the platform lists them; empty when it
  /// gives only the line.
  final List<ArtistLink> artists;

  /// Tags edited by hand: the platform's ids may be someone else's now.
  final bool edited;

  /// Platform raw data for [MusicProvider.resolveStream] and downloads.
  final Map<String, dynamic>? sourceData;

  /// Chart position (1-based), only on tracks from `getCharts()`, else `null`.
  ///
  /// [toJson] leaves it out on purpose: it changes daily, and a saved track
  /// would carry yesterday's forever.
  final int? chartPos;

  /// Daily position change: >0 rose, <0 fell.
  final int chartShift;

  /// New in the chart: shows new instead of an arrow.
  final bool chartNew;

  const Track({
    required this.id,
    required this.name,
    required this.artist,
    required this.duration,
    required this.source,
    this.cover,
    this.album,
    this.year,
    this.releaseDate,
    this.publisher,
    this.description,
    this.explicit = false,
    this.genres = const [],
    this.url,
    this.artistId,
    this.artistAvatar,
    this.artistVerified = false,
    this.creditedArtist,
    this.artists = const [],
    this.edited = false,
    this.sourceData,
    this.chartPos,
    this.chartShift = 0,
    this.chartNew = false,
  });

  /// The track as the `tracks` row, also used in transfer files and caches. One
  /// format on all sides, so sync and files have nothing to translate.
  ///
  /// Platform specifics live in `extra`: `scId`, `videoId`, `ymId`, `artistId`
  /// (the bare platform id), `media` (SoundCloud transcodings for resolving a
  /// stream), `available` on Yandex. Keys only this app knows (`releaseDate`,
  /// `creditedArtist`…) sit there too: foreign keys harm nothing, and the
  /// database merges `extra` on write, so nothing gets lost.
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': name,
    'artist': artist,
    'album': album ?? '',
    'cover': cover ?? '',
    'duration': duration.inMilliseconds / 1000,
    'provider': source.code,
    'extra': _extra(),
  };

  Map<String, dynamic> _extra() {
    final bare = id.startsWith(source.prefix)
        ? id.substring(source.prefix.length)
        : id;
    final page = '${source.prefix}artist:';
    String? raw(String? id) => id == null
        ? null
        : id.startsWith(page)
        ? id.substring(page.length)
        : id;
    final rawArtist = raw(artistId);
    return {
      ...switch (source) {
        MusicSource.soundcloud => {
          'scId': int.tryParse(bare) ?? bare,
          if (url != null) 'permalink': url,
          if (rawArtist != null)
            'artistId': int.tryParse(rawArtist) ?? rawArtist,
          if (sourceData != null) 'media': sourceData,
        },
        MusicSource.ytmusic => {'videoId': bare, 'artistId': ?rawArtist},
        MusicSource.yandex => {
          'ymId': bare,
          'artistId': ?rawArtist,
          if (sourceData?['available'] == false) 'available': false,
        },
        // A local file: its dedupe key and where it lies.
        MusicSource.local => {...?sourceData},
      },
      if (year != null) 'year': year,
      if (genres.isNotEmpty) 'genres': genres,
      if (publisher != null) 'publisher': publisher,
      if (releaseDate != null) 'releaseDate': releaseDate,
      if (description != null) 'description': description,
      if (explicit) 'explicit': true,
      if (artistAvatar != null) 'artistAvatar': artistAvatar,
      if (artistVerified) 'verified': true,
      if (creditedArtist != null) 'creditedArtist': creditedArtist,
      if (artists.isNotEmpty)
        'artists': [
          for (final a in artists) {'id': raw(a.id) ?? '', 'name': a.name},
        ],
      if (edited) 'edited': true,
    };
  }

  static Track? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final provider = json['provider'];
    final source = provider is String && provider.isNotEmpty
        ? MusicSource.fromCode(provider)
        : MusicSource.fromId(id);
    final x = (json['extra'] as Map?)?.cast<String, dynamic>() ?? const {};
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    String? page(Object? raw) => source == MusicSource.local
        ? null
        : switch (raw) {
            final num n when n > 0 => '${source.prefix}artist:${n.toInt()}',
            final String s when s.isNotEmpty && s != '0' =>
              '${source.prefix}artist:$s',
            _ => null,
          };
    final genre = text(x['genre']);
    return Track(
      id: id,
      name: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      duration: Duration(
        milliseconds: (((json['duration'] as num?) ?? 0) * 1000).round(),
      ),
      source: source,
      cover: text(json['cover']),
      album: text(json['album']),
      year: text(x['year']),
      releaseDate: text(x['releaseDate']),
      publisher: text(x['publisher']),
      description: text(x['description']),
      explicit: x['explicit'] == true,
      genres:
          (x['genres'] as List?)?.whereType<String>().toList() ??
          (genre == null ? const [] : [genre.toLowerCase()]),
      url: text(x['permalink']) ?? _linkOf(source, id),
      artistId: page(x['artistId']),
      artistAvatar: text(x['artistAvatar']),
      artistVerified: x['verified'] == true,
      creditedArtist: text(x['creditedArtist']),
      artists: [
        for (final a in (x['artists'] as List?) ?? const [])
          if (a is Map)
            if (text(a['name']) case final name?)
              (name: name, id: page(a['id'])),
      ],
      edited: x['edited'] == true,
      sourceData: switch (source) {
        MusicSource.soundcloud => (x['media'] as Map?)?.cast<String, dynamic>(),
        MusicSource.yandex => {'available': x['available'] != false},
        MusicSource.ytmusic => null,
        MusicSource.local => x.isEmpty ? null : x,
      },
    );
  }

  /// Track link when `extra` has none: for YouTube Music it's built from the
  /// id.
  static String? _linkOf(MusicSource source, String id) =>
      source == MusicSource.ytmusic
      ? 'https://music.youtube.com/watch?v=${id.substring(source.prefix.length)}'
      : null;
}

class Artist {
  final String id;
  final String name;
  final String? avatar;
  final bool verified;
  final String? permalink;
  final MusicSource source;

  /// A listener with no tracks of their own (SoundCloud): their card says
  /// "Profile".
  final bool profile;

  // Artist page fields, filled by the provider in getArtist.

  /// Full name, the profile's subtitle.
  final String? fullName;
  final String? description;
  final String? website;
  final List<String> genres;

  /// Banner for the hero background.
  final String? bannerUrl;

  const Artist({
    required this.id,
    required this.name,
    required this.source,
    this.avatar,
    this.verified = false,
    this.permalink,
    this.profile = false,
    this.fullName,
    this.description,
    this.website,
    this.genres = const [],
    this.bannerUrl,
  });

  Artist copyWith({
    String? fullName,
    String? description,
    String? website,
    String? bannerUrl,
    String? avatar,
  }) => Artist(
    id: id,
    name: name,
    source: source,
    avatar: avatar ?? this.avatar,
    verified: verified,
    permalink: permalink,
    profile: profile,
    fullName: fullName ?? this.fullName,
    description: description ?? this.description,
    website: website ?? this.website,
    genres: genres,
    bannerUrl: bannerUrl ?? this.bannerUrl,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (avatar != null) 'avatar': avatar,
    if (verified) 'verified': true,
    if (permalink != null) 'permalink': permalink,
    if (profile) 'profile': true,
    if (fullName != null) 'fullName': fullName,
  };

  static Artist? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    return Artist(
      id: id,
      name: json['name'] as String? ?? '',
      source: MusicSource.fromId(id),
      avatar: json['avatar'] as String?,
      verified: json['verified'] == true,
      permalink: json['permalink'] as String?,
      profile: json['profile'] == true,
      fullName: json['fullName'] as String?,
    );
  }
}

/// Playlist AND album are one entity: one card, told apart by [isAlbum].
class Playlist {
  final String id;
  final String title;
  final String? cover;

  /// Track count. Nullable: some platforms don't have it, and 0 for unknown
  /// showed 0 tracks on a 14-track album.
  final int? trackCount;
  final String? ownerName;
  final String? ownerAvatar;

  /// Owner artist's global id (album), to open their page from a release card.
  final String? ownerId;

  /// Release year (albums; usually empty for playlists).
  final String? year;

  /// Full release date when known beyond the year; see [Track.releaseDate].
  final String? releaseDate;

  /// Platform's release type: `single`, `compilation`, `podcast`…; `null` is a
  /// usual album.
  final String? albumType;
  final MusicSource source;
  final bool isAlbum;

  /// Total duration, if the platform gives it.
  final Duration? duration;

  /// URL for reloading from the source.
  final String? sourceUrl;

  const Playlist({
    required this.id,
    required this.title,
    required this.source,
    this.cover,
    this.trackCount,
    this.ownerName,
    this.ownerAvatar,
    this.ownerId,
    this.year,
    this.releaseDate,
    this.albumType,
    this.isAlbum = false,
    this.duration,
    this.sourceUrl,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (cover != null) 'cover': cover,
    if (trackCount != null) 'trackCount': trackCount,
    if (ownerName != null) 'ownerName': ownerName,
    if (ownerAvatar != null) 'ownerAvatar': ownerAvatar,
    if (ownerId != null) 'ownerId': ownerId,
    if (year != null) 'year': year,
    if (releaseDate != null) 'releaseDate': releaseDate,
    if (albumType != null) 'albumType': albumType,
    if (isAlbum) 'isAlbum': true,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
  };

  static Playlist? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    return Playlist(
      id: id,
      title: json['title'] as String? ?? '',
      source: MusicSource.fromId(id),
      cover: json['cover'] as String?,
      trackCount: (json['trackCount'] as num?)?.toInt(),
      ownerName: json['ownerName'] as String?,
      ownerAvatar: json['ownerAvatar'] as String?,
      ownerId: json['ownerId'] as String?,
      year: json['year'] as String?,
      releaseDate: json['releaseDate'] as String?,
      albumType: json['albumType'] as String?,
      isAlbum: json['isAlbum'] == true,
      sourceUrl: json['sourceUrl'] as String?,
    );
  }
}
