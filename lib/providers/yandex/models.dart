/// Типы выдачи Яндекс.Музыки — зеркало структур из десктопного `yandex.rs`
/// (там они сериализуются в camelCase для фронта; здесь это просто поля).
library;

/// Ошибка Яндекса. `code` — ключ из набора `ym.err.*`, который UI переводит
/// сам (см. `describeYmFailure` в экране настроек), либо текст от площадки.
class YmException implements Exception {
  final String code;
  const YmException(this.code);
  @override
  String toString() => code;
}

/// Дефолты полей — порт `yandex.rs`: подставляются, только когда площадка не
/// отдала поле вовсе. В UI попадают настолько редко, что заводить под них
/// ключи перевода не стали (то же решение, что с `Unknown` у SoundCloud).
const String kYmUntitled = 'Без названия';
const String kYmUnknownArtist = 'Неизвестен';
const String kYmDash = '—';

class YmRawTrack {
  final String id;
  final String title;
  final String artist;

  /// id первого артиста (для перехода на страницу артиста).
  final String artistId;

  /// Every artist with their id, for the artist links.
  final List<({String id, String name})> artists;

  /// Полный https-URL обложки 400x400 (или пусто).
  final String cover;
  final Duration duration;

  /// Год релиза (из первого альбома трека) или пусто.
  final String year;

  /// Полная дата релиза альбома («2024-05-13T00:00:00+03:00»), если она в
  /// выдаче есть: у Яндекса рядом с `year` часто лежит и `releaseDate`.
  final String releaseDate;
  final bool available;

  /// Место в чарте (1-based); 0 — трек пришёл не из чарта.
  final int chartPos;

  /// Сдвиг места за сутки: >0 — поднялся, <0 — опустился, 0 — без изменений.
  final int chartShift;

  /// Новичок чарта (`progress: "new"`) — вместо стрелки «нов.».
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

  /// Тот же трек с местом в чарте: чартовые поля лежат не в самом треке, а в
  /// обёртке элемента чарта, и проставляются поверх разобранного.
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

  /// Полная дата релиза — см. [YmRawTrack.releaseDate].
  final String releaseDate;
  final int trackCount;

  /// id первого артиста — переход на его страницу с карточки релиза.
  final String artistId;

  /// Фото первого артиста 1000×1000 — крупный круг карточки релиза. Крупнее
  /// обложек: круг почти во всю ширину карточки, и 400×400 там мылит.
  final String artistCover;

  /// Тип релиза от Яндекса: `single` | `compilation` | `podcast` | …; пусто —
  /// обычный альбом.
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

/// Страница сущности (альбом/артист/плейлист): шапка + треки + (для артиста)
/// его альбомы и похожие исполнители.
class YmEntity {
  final String title;
  final String subtitle;
  final String cover;

  /// Основной список треков (альбом/плейлист — все; артист — дискография из
  /// `/artists/{id}/tracks`, секция «Треки»).
  final List<YmRawTrack> tracks;

  /// Только у артиста: «Популярные» из brief-info.
  final List<YmRawTrack> popularTracks;
  final List<YmRawAlbum> albums;

  /// Год выпуска (альбом). У артиста/плейлиста пусто.
  final String year;

  /// Полная дата релиза альбома — см. [YmRawTrack.releaseDate].
  final String releaseDate;

  /// Аватар владельца/артиста для строки владельца в шапке
  /// (альбом → `artists[0]`).
  final String ownerAvatar;

  /// Только у артиста: похожие исполнители из brief-info.
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

  /// Только у артиста: номер следующей страницы «Треков»; `null` — дискография
  /// уместилась в первую.
  final int? tracksNextPage;

  /// Только у артиста: всего треков в «Треках» (`pager.total`) — счётчик в
  /// шапке, пока догружено не всё.
  final int? tracksTotal;
}

/// Страница «Треков» артиста (догрузка по «Загрузить ещё»).
class YmTracksPage {
  const YmTracksPage({this.tracks = const [], this.nextPage, this.total});

  final List<YmRawTrack> tracks;

  /// Номер следующей страницы; `null` — это была последняя.
  final int? nextPage;

  /// Всего треков у артиста; `null` — Яндекс не отдал pager.
  final int? total;
}

/// Результат поиска по всем категориям.
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

/// Результат резолва ссылки music.yandex.ru — порт `YmResolved` (tag `kind`).
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

/// Батч rotor-станции: сами треки и id пачки, который потом уходит обратно в
/// фидбек — по нему станция сопоставляет событие с тем, что она предложила.
class YmWaveBatch {
  final List<YmRawTrack> tracks;
  final String batchId;

  const YmWaveBatch({this.tracks = const [], this.batchId = ''});
}

/// Код устройства OAuth device-flow (шаг 1).
class YmDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;

  /// Пауза между опросами токена.
  final Duration interval;

  /// Сколько живёт код.
  final Duration expiresIn;

  const YmDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresIn,
  });
}

/// Исход одного опроса токена: либо ещё ждём подтверждения, либо токен готов.
class YmPollOutcome {
  /// null — пользователь ещё не подтвердил, опросить позже.
  final String? token;
  const YmPollOutcome.pending() : token = null;
  const YmPollOutcome.token(String this.token);

  bool get isPending => token == null;
}
