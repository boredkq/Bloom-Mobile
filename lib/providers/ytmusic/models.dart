/// Типы выдачи YouTube Music — зеркало структур из десктопного `ytm.rs`
/// (там они сериализуются в camelCase для фронта; здесь это просто поля).
library;

/// Ошибка YouTube Music. `code` — ключ из набора `ytm.err.*`, который переводит
/// UI, либо готовый текст причины от самой площадки (`playabilityStatus.reason`
/// приходит на языке запроса и переводу не подлежит).
class YtmException implements Exception {
  final String code;
  const YtmException(this.code);
  @override
  String toString() => code;
}

/// Дефолты полей — те же слова, что у Яндекса (на десктопе YTM переиспользует
/// его ключи `ym.fallback.*`). Дублируются, а не импортируются из соседнего
/// провайдера: площадки друг о друге не знают.
const String kYtmUntitled = 'Без названия';
const String kYtmUnknownArtist = 'Неизвестен';
const String kYtmAlbumFallback = 'Альбом';
const String kYtmPlaylistFallback = 'Плейлист';

class YtmRawTrack {
  /// videoId YouTube.
  final String id;
  final String title;
  final String artist;

  /// browseId артиста (`UC…`) для перехода на его страницу; пусто, если нет.
  final String artistId;
  final String cover;
  final Duration duration;

  const YtmRawTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.cover,
    required this.duration,
  });

  /// Строки альбома донашивают обложку и артиста со страницы — см. `album()`.
  YtmRawTrack copyWith({String? artist, String? cover}) => YtmRawTrack(
    id: id,
    title: title,
    artist: artist ?? this.artist,
    artistId: artistId,
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

  /// Число треков, если YTM его дал (см. `rowTrackCount`). Именно nullable:
  /// «неизвестно» и «ноль треков» — разные вещи.
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

  /// Есть ли токен следующей страницы треков. На десктопе это знание живёт в
  /// Rust и наружу не отдаётся (там «Загрузить ещё» показывается всегда), здесь
  /// общий UI спрашивает флаг у выдачи — см. `SearchResults.tracksHasMore`.
  final bool tracksHasMore;

  const YtmSearchRaw({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
    this.tracksHasMore = false,
  });
}

/// Порция догрузки поиска (см. `searchMore`).
class YtmSearchMore {
  final List<YtmRawTrack> tracks;
  final bool hasMore;
  const YtmSearchMore({this.tracks = const [], this.hasMore = false});
}

/// Страница сущности (альбом/артист/плейлист): шапка + треки + (артист)
/// релизы. Зеркало `YmEntity`.
class YtmEntity {
  final String title;
  final String subtitle;
  final String cover;
  final List<YtmRawTrack> tracks;

  /// Только для артиста: «Популярные» (top songs shelf).
  final List<YtmRawTrack> popularTracks;
  final List<YtmRawAlbum> albums;

  /// Только для артиста: похожие исполнители («Fans might also like»).
  final List<YtmRawArtist> similarArtists;

  /// Год выпуска (4-значный run в subtitle шапки). У артиста пусто.
  final String year;

  /// Аватар артиста/владельца из шапки (`straplineThumbnail`).
  final String ownerAvatar;

  /// Только для артиста: биография из шапки. Пусто, если YTM её не даёт.
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

/// Что открывает вставленная ссылка: [kind] — `track`/`album`/`playlist`/
/// `artist`, [id] — videoId либо browseId соответствующей страницы.
class YtmResolved {
  final String kind;
  final String id;
  const YtmResolved(this.kind, this.id);
}
