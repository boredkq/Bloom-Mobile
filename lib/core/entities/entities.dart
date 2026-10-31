/// Общие сущности всех площадок — порт `src/entities/{track,artist,playlist}`
/// из десктопного Bloom.
///
/// Смысл: провайдер приводит свою выдачу К ЭТИМ типам, и весь UI (поиск,
/// страницы, плеер) о площадке ничего не знает. Добавить площадку = написать
/// провайдер, экраны не трогаем.
///
/// Отличия от десктопа, сделанные осознанно:
/// - `duration` здесь [Duration], а не строка «m:ss». На десктопе это поле
///   названо `dur` и хранит уже отформатированную строку — там же в
///   комментарии помечено как историческое. Форматируем при отрисовке.
/// - вместо плоских флагов `_sc`/`_ym`/`_ytm` и россыпи полей вроде `scMedia`
///   — [Track.source] и непрозрачный [Track.sourceData]: сырьё площадки,
///   которое нужно ей самой (у SoundCloud там `media.transcodings` для
///   резолва стрима).
library;

enum MusicSource {
  local('local', 'local', 'Локальные', 'lf:'),
  soundcloud('soundcloud', 'sc', 'SoundCloud', 'sc:'),
  ytmusic('ytmusic', 'ytm', 'YouTube Music', 'ytm:'),
  yandex('yandex', 'ym', 'Яндекс.Музыка', 'ym:');

  const MusicSource(this.id, this.code, this.label, this.prefix);

  /// Технический id источника. В UI не показывается.
  final String id;

  /// Площадка так, как её пишет база (`tracks.provider`) — те же коды, что на ПК.
  final String code;

  static MusicSource fromCode(String code) => MusicSource.values.firstWhere(
    (s) => s.code == code,
    orElse: () => MusicSource.local,
  );

  /// Человекочитаемая метка. Для площадок это бренд и перевода не требует;
  /// переводятся только «Локальные» и «Яндекс.Музыка» — см. `label10n` в
  /// `core/l10n/source_label.dart`, где нужен язык.
  final String label;

  /// Префикс сквозных id сущностей этой площадки — как на ПК: `sc:123`,
  /// `sc:artist:123`, `ytm:<videoId>`, `ym:<id>`, `lf:<хеш>`.
  final String prefix;

  /// Площадка по ПРЕФИКСУ сквозного id — там, где источник не сохранён
  /// отдельным полем.
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
  /// Сквозной id с префиксом источника («sc:123»).
  final String id;

  /// Заголовок трека.
  final String name;

  /// Отображаемое имя артиста (может быть «Artist A, Artist B»).
  final String artist;
  final Duration duration;
  final String? cover;
  final MusicSource source;

  final String? album;
  final String? year;

  /// Полная дата релиза («2024-05-13T00:00:00Z»), если площадка отдала её
  /// целиком, а не одним годом. Год из неё уже вынут в [year] — рядом лежит
  /// именно сырьё, разбирает его `releaseDateLabel` из `shared/util/format.dart`.
  final String? releaseDate;
  final String? publisher;
  final String? description;
  final bool explicit;
  final List<String> genres;

  /// Ссылка на трек у площадки (permalink).
  final String? url;

  /// Сквозной id артиста — чтобы открыть его страницу по клику на имя, минуя
  /// резолв по имени.
  final String? artistId;
  final String? artistAvatar;
  final bool artistVerified;

  /// Артист из `publisher_metadata` — иногда точнее имени аккаунта.
  final String? creditedArtist;

  /// Every artist with their page, as the platform lists them; empty when it
  /// gives only the line.
  final List<ArtistLink> artists;

  /// Tags edited by hand: the platform's ids may be someone else's now.
  final bool edited;

  /// Сырьё площадки для [MusicProvider.resolveStream] и скачивания.
  final Map<String, dynamic>? sourceData;

  /// Место в чарте площадки (1-based) — только у треков из `getCharts()`
  /// (витрина на главной и страница «Чарт»), у остальных `null`.
  ///
  /// В [toJson] не пишется намеренно: место меняется каждые сутки, и трек,
  /// сохранённый из чарта в библиотеку, носил бы вчерашнее место вечно.
  final int? chartPos;

  /// Сдвиг места за сутки: >0 — поднялся, <0 — опустился.
  final int chartShift;

  /// Новичок чарта — вместо стрелки «нов.».
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

  /// Трек так, как его держит ПК (`Track::toMap`): строка таблицы `tracks`, он
  /// же — трек в файле переноса и в кешах. Формат один на обе стороны, поэтому
  /// синхронизации и файлу нечего переводить.
  ///
  /// Своё у площадки — в `extra` под ключами ПК: `scId`/`videoId`/`ymId`,
  /// `artistId` (голый id площадки), `media` (транскодинги SoundCloud, из них
  /// резолвится стрим), `available` у Яндекса. Чего ПК не знает (`releaseDate`,
  /// `creditedArtist`…), лежит там же: чужие ключи ему не мешают, а база при
  /// записи сливает `extra` со старым, так что ключи ПК (`edited`, `artists`)
  /// у нас тоже не теряются.
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
        // Свой файл: ключ дедупа и где он лежит — на ПК таких нет, это наше.
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

  /// Ссылка на трек у площадки, когда своей в `extra` нет: у YouTube Music она
  /// собирается из id (на ПК так же — `trackLink`).
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
  /// "Profile", as on the PC.
  final bool profile;

  // Поля страницы артиста — заполняются провайдером в getArtist.

  /// Полное имя — подзаголовок профиля.
  final String? fullName;
  final String? description;
  final String? website;
  final List<String> genres;

  /// Баннер для фона hero.
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

/// Плейлист И альбом — одна сущность: рисуются одной карточкой, различаются
/// флагом [isAlbum].
class Playlist {
  final String id;
  final String title;
  final String? cover;

  /// Число треков. Именно nullable: у части площадок его нет вовсе, и «0» вместо
  /// «неизвестно» показывало «0 треков» у альбома с четырнадцатью.
  final int? trackCount;
  final String? ownerName;
  final String? ownerAvatar;

  /// Сквозной id артиста-владельца (альбом) — переход на его страницу с
  /// карточки релиза.
  final String? ownerId;

  /// Год выпуска (у альбомов; у плейлистов чаще пусто).
  final String? year;

  /// Полная дата релиза, если площадка знает её точнее года — см.
  /// [Track.releaseDate].
  final String? releaseDate;

  /// Тип релиза от площадки: `single` | `compilation` | `podcast` | …;
  /// `null` — обычный альбом.
  final String? albumType;
  final MusicSource source;
  final bool isAlbum;

  /// Длительность целиком, если площадка её отдаёт.
  final Duration? duration;

  /// URL/permalink для повторной загрузки из источника.
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
