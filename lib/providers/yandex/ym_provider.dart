/// Яндекс.Музыка как [MusicProvider]: тонкий слой поверх порта API
/// (`yandex.dart`), который приводит `YmRaw*` к общим сущностям.
///
/// Вся сетевая логика и её гочи живут этажом ниже — здесь только маппинг и
/// сборка страниц. Зеркало `sc_provider.dart`.
library;

import 'dart:async';

import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import 'models.dart';
import 'yandex.dart' as ym;

/// Сквозные id с префиксом источника — те же, что на ПК:
///   трек     → `ym:<id>`
///   артист   → `ym:artist:<id>`
///   альбом   → `ym:album:<id>`
///   плейлист → `ym:pl:<owner>~<kind>` (owner+kind нужны запросу плейлиста)
///   публичный плейлист нового формата → `ym:plu:<uuid>`
String ymTrackId(String id) => 'ym:$id';
String ymArtistId(String id) => 'ym:artist:$id';
String ymAlbumId(String id) => 'ym:album:$id';
String ymPlaylistId(String owner, String kind) => 'ym:pl:$owner~$kind';
String ymPlaylistUuidId(String uuid) => 'ym:plu:$uuid';

/// Разобрать `ym:pl:<owner>~<kind>` обратно (по ПОСЛЕДНЕМУ `~`: в логине
/// владельца тильда встречается, в kind — нет).
({String owner, String kind})? parseYmPlaylistId(String id) {
  if (!id.startsWith('ym:pl:')) return null;
  final body = id.substring('ym:pl:'.length);
  final i = body.lastIndexOf('~');
  if (i < 0) return null;
  return (owner: body.substring(0, i), kind: body.substring(i + 1));
}

/// Разобрать `ym:plu:<uuid>` обратно в uuid (новый формат).
String? parseYmPlaylistUuidId(String id) =>
    id.startsWith('ym:plu:') ? id.substring('ym:plu:'.length) : null;

/// Числовой id из сквозного (`ym:123`, `ym:artist:123`, `ym:album:123`).
/// Пустая строка — id не разобрался, провайдер тогда просто ничего не найдёт.
String ymNumericId(String entityId) {
  final last = entityId.split(':').last;
  return RegExp(r'^\d+$').hasMatch(last) ? last : '';
}

String? _blankToNull(String s) => s.isEmpty ? null : s;

Track trackFromYm(YmRawTrack t) => Track(
  id: ymTrackId(t.id),
  name: t.title,
  artist: t.artist,
  duration: t.duration,
  cover: _blankToNull(t.cover),
  source: MusicSource.yandex,
  year: _blankToNull(t.year),
  releaseDate: _blankToNull(t.releaseDate),
  artistId: t.artistId.isEmpty ? null : ymArtistId(t.artistId),
  artists: [
    for (final a in t.artists)
      (name: a.name, id: a.id.isEmpty ? null : ymArtistId(a.id)),
  ],
  // Стрим резолвится по id трека, поэтому сырьё площадки нужно ровно для
  // одного: не гонять запрос за треком, который Яндекс сам пометил
  // недоступным.
  sourceData: {'available': t.available},
  // Чартовые поля есть только у ответа чарта; у прочих запросов места нет — и
  // интерфейс не рисует ни цифры, ни стрелки.
  chartPos: t.chartPos > 0 ? t.chartPos : null,
  chartShift: t.chartShift,
  chartNew: t.chartNew,
);

Artist artistFromYm(YmRawArtist a) => Artist(
  id: ymArtistId(a.id),
  name: a.name,
  avatar: _blankToNull(a.cover),
  source: MusicSource.yandex,
);

Playlist albumFromYm(YmRawAlbum a) => Playlist(
  id: ymAlbumId(a.id),
  title: a.title,
  cover: _blankToNull(a.cover),
  // У Яндекса отсутствующий счётчик приходит нулём — «0 треков» под альбомом с
  // четырнадцатью хуже, чем ничего.
  trackCount: a.trackCount > 0 ? a.trackCount : null,
  ownerName: _blankToNull(a.artist),
  ownerAvatar: _blankToNull(a.artistCover),
  ownerId: a.artistId.isEmpty ? null : ymArtistId(a.artistId),
  year: _blankToNull(a.year),
  releaseDate: _blankToNull(a.releaseDate),
  albumType: _blankToNull(a.albumType),
  sourceUrl: 'https://music.yandex.ru/album/${a.id}',
  isAlbum: true,
  source: MusicSource.yandex,
);

Playlist playlistFromYm(YmRawPlaylist p) => Playlist(
  id: ymPlaylistId(p.owner, p.kind),
  title: p.title,
  cover: _blankToNull(p.cover),
  trackCount: p.trackCount > 0 ? p.trackCount : null,
  ownerName: _blankToNull(p.owner),
  sourceUrl: 'https://music.yandex.ru/users/${p.owner}/playlists/${p.kind}',
  source: MusicSource.yandex,
);

/// Внутренний пейджер поиска: страницы Яндекса 0-индексные, ~24 трека в
/// каждой, а общий стор считает `offset` шагами под SoundCloud — маппинг
/// offset→page разъехался бы. Порт `_pager` с десктопа.
String? _pagerQuery;
int _pagerPage = 0;

/// Станция → batch-id её последней порции: отзыв идёт с ним.
final Map<String, String> _batches = {};

class YandexProvider extends MusicProvider {
  const YandexProvider();

  @override
  MusicSource get source => MusicSource.yandex;

  /// До входа в аккаунт Яндекс не появляется ни в переключателе площадок, ни в
  /// «Все источники»: без токена API отвечает 401 вообще на всё.
  @override
  bool get isEnabled => ym.activeToken() != null;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    // Сбрасываем пейджер: следующий loadMoreTracks начнёт со страницы 1.
    _pagerQuery = query;
    _pagerPage = 0;
    // Сортировки у поиска Яндекса нет — параметр приходит от общего UI и здесь
    // просто не на что влиять.
    final d = await ym.search(query);
    return SearchResults(
      tracks: d.tracks.map(trackFromYm).toList(),
      artists: d.artists.map(artistFromYm).toList(),
      albums: d.albums.map(albumFromYm).toList(),
      playlists: d.playlists.map(playlistFromYm).toList(),
      // Страница у Яндекса ~24 трека; пришла полная — значит есть ещё.
      tracksHasMore: d.tracks.length >= 20,
    );
  }

  @override
  Future<TrackPage?> loadMoreTracks(
    String query,
    int offset, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    // `offset` игнорируем (он SC-калибра) и ведём свой счётчик страниц.
    // Рассинхрон запроса — начинаем заново.
    if (_pagerQuery != query) {
      _pagerQuery = query;
      _pagerPage = 0;
    }
    _pagerPage += 1;
    final d = await ym.search(query, page: _pagerPage);
    return TrackPage(
      tracks: d.tracks.map(trackFromYm).toList(),
      hasMore: d.tracks.length >= 20,
    );
  }

  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    // Чужую ссылку отдаём дальше по реестру, не тратя на неё запрос.
    if (!RegExp(r'music\.yandex\.[a-z]+', caseSensitive: false).hasMatch(url)) {
      return null;
    }
    final r = await ym.resolve(url);
    switch (r.kind) {
      case 'track':
        return ResolvedTrack(trackFromYm(r.track!));
      // Сущность приходит с треками, но без своего id — id берём из самой
      // ссылки, чтобы страницу можно было дозагрузить (getAlbum/getPlaylist).
      case 'album':
        final id = ym.reAlbum.firstMatch(url)?.group(1);
        if (id == null) return null;
        return ResolvedSet(_setFromEntity(r.entity!, ymAlbumId(id), true, url));
      case 'artist':
        final id = ym.reArtist.firstMatch(url)?.group(1);
        if (id == null) return null;
        return ResolvedArtist(
          Artist(
            id: ymArtistId(id),
            name: r.entity!.title,
            avatar: _blankToNull(r.entity!.cover),
            source: MusicSource.yandex,
          ),
        );
      case 'playlist':
        final m = ym.reUserPlaylist.firstMatch(url);
        final uuid = m == null
            ? ym.rePublicPlaylist.firstMatch(url)?.group(1)
            : null;
        if (m == null && uuid == null) return null;
        final id = m != null
            ? ymPlaylistId(m.group(1)!, m.group(2)!)
            : ymPlaylistUuidId(uuid!);
        return ResolvedSet(_setFromEntity(r.entity!, id, false, url));
      default:
        return null;
    }
  }

  Playlist _setFromEntity(
    YmEntity e,
    String id,
    bool isAlbum,
    String sourceUrl,
  ) => Playlist(
    id: id,
    title: e.title,
    cover: _blankToNull(e.cover),
    ownerName: _blankToNull(e.subtitle),
    ownerAvatar: _blankToNull(e.ownerAvatar),
    year: _blankToNull(e.year),
    releaseDate: _blankToNull(e.releaseDate),
    trackCount: e.tracks.isEmpty ? null : e.tracks.length,
    isAlbum: isAlbum,
    sourceUrl: sourceUrl,
    source: MusicSource.yandex,
  );

  @override
  Future<Track?> resolveTrackById(String id) async {
    final numeric = ymNumericId(id);
    if (numeric.isEmpty) return null;
    return trackFromYm(await ym.trackOne(numeric));
  }

  /// Похожие для витрин главной. Под префиксом `ym:` живут и артисты, альбомы,
  /// плейлисты — похожих у них нет, в сеть за ними не ходим.
  @override
  Future<List<Track>?> getSimilarTracks(String seedId) async {
    if (!RegExp(r'^ym:\d+$').hasMatch(seedId)) return const [];
    return (await ym.similarTracks(
      seedId.substring('ym:'.length),
    )).map(trackFromYm).toList();
  }

  @override
  String trackStation(Track track) {
    final id = track.source == MusicSource.yandex ? ymNumericId(track.id) : '';
    return id.isNotEmpty && isEnabled ? 'track:$id' : '';
  }

  /// Станция rotor: идёт дальше от последнего трека, который отдала.
  @override
  Future<StationPage> station(String station, String cursor) async {
    try {
      final batch = await ym.waveTracks(station, lastId: cursor);
      if (batch.batchId.isNotEmpty) _batches[station] = batch.batchId;
      return StationPage(
        tracks: batch.tracks.map(trackFromYm).toList(),
        cursor: batch.tracks.isEmpty ? '' : batch.tracks.last.id,
      );
    } catch (_) {
      return const StationPage();
    }
  }

  /// Как получится: потерянный отзыв лишь чуть меньше научит станцию.
  @override
  void stationFeedback(
    String station,
    String event, {
    Track? track,
    double played = 0,
  }) {
    final id = track == null ? '' : ymNumericId(track.id);
    unawaited(
      ym.waveFeedback(
        station: station,
        event: event,
        trackId: id,
        batchId: _batches[station] ?? '',
        played: played,
      ),
    );
  }

  @override
  Future<ArtistPageData?> getArtist(String id) async {
    final numeric = ymNumericId(id);
    if (numeric.isEmpty) return null;
    final e = await ym.artist(numeric);
    return ArtistPageData(
      artist: Artist(
        id: id,
        name: e.title,
        avatar: _blankToNull(e.cover),
        source: MusicSource.yandex,
      ),
      // «Популярные» — из brief-info; «Треки» — первая страница дискографии,
      // остальное — «Загрузить ещё» через [getArtistTracksPage]. Раскладка
      // страницы артиста у SoundCloud.
      topTracks: e.popularTracks.map(trackFromYm).toList(),
      tracks: e.tracks.map(trackFromYm).toList(),
      albums: e.albums.map(albumFromYm).toList(),
      similarArtists: e.similarArtists.map(artistFromYm).toList(),
      tracksCursor: e.tracksNextPage == null
          ? null
          : '$numeric:${e.tracksNextPage}',
      tracksTotal: e.tracksTotal,
    );
  }

  /// Догрузка «Треков» артиста. Курсор — `<id артиста>:<номер страницы>`
  /// (см. [getArtist]).
  @override
  Future<TrackPage?> getArtistTracksPage(String cursor) async {
    final m = RegExp(r'^(\d+):(\d+)$').firstMatch(cursor);
    if (m == null) return null;
    final id = m.group(1)!;
    final page = await ym.artistTracksPage(id, int.parse(m.group(2)!));
    final next = page.nextPage;
    return TrackPage(
      tracks: page.tracks.map(trackFromYm).toList(),
      hasMore: next != null,
      cursor: next == null ? null : '$id:$next',
    );
  }

  @override
  Future<SetContent?> getAlbum(String id) async {
    final numeric = ymNumericId(id);
    if (numeric.isEmpty) return null;
    final e = await ym.album(numeric);
    final tracks = e.tracks.map(trackFromYm).toList();
    return SetContent(
      playlist: _setFromEntity(
        e,
        id,
        true,
        'https://music.yandex.ru/album/$numeric',
      ),
      tracks: tracks,
    );
  }

  @override
  Future<SetContent?> getPlaylist(String id) async {
    final uuid = parseYmPlaylistUuidId(id);
    final parsed = uuid == null ? parseYmPlaylistId(id) : null;
    if (uuid == null && parsed == null) return null;
    final e = uuid != null
        ? await ym.playlistByUuid(uuid)
        : await ym.playlist(parsed!.owner, parsed.kind);
    return SetContent(
      playlist: _setFromEntity(
        e,
        id,
        false,
        uuid != null
            ? 'https://music.yandex.ru/playlists/$uuid'
            : 'https://music.yandex.ru/users/${parsed!.owner}/playlists/${parsed.kind}',
      ),
      tracks: e.tracks.map(trackFromYm).toList(),
    );
  }

  @override
  Future<List<Track>?> getCharts() async =>
      (await ym.chart()).map(trackFromYm).toList();

  @override
  Future<NewReleases?> getNewReleases() async =>
      NewAlbums((await ym.newReleases()).map(albumFromYm).toList());

  @override
  Future<PlayableStream?> resolveStream(Track track) async =>
      PlayableStream(url: await _streamUrl(track));

  /// Скачивается ровно то же, что играет: у Яндекса это цельный mp3, а не
  /// плейлист кусков.
  @override
  bool canDownload(Track track) => track.sourceData?['available'] != false;

  @override
  Future<PlayableStream?> resolveDownload(Track track) async =>
      PlayableStream(url: await _streamUrl(track));

  /// Подписанная ссылка живёт минуты — держим кеш 4, как на десктопе: иначе
  /// пауза с последующим play уже требовала бы нового резолва.
  Future<String> _streamUrl(Track track) async {
    final id = ymNumericId(track.id);
    if (id.isEmpty) throw const YmException('ym.err.trackNotFound');
    final cached = _streamCache[id];
    if (cached != null && DateTime.now().difference(cached.at) < _streamTtl) {
      return cached.url;
    }
    final url = await ym.streamUrl(id);
    _streamCache[id] = (url: url, at: DateTime.now());
    return url;
  }
}

const Duration _streamTtl = Duration(minutes: 4);
final Map<String, ({String url, DateTime at})> _streamCache = {};

/// Забыть подписанные ссылки — при выходе из аккаунта они всё равно
/// протухнут, но держать их в памяти после logout незачем.
void clearYmStreamCache() => _streamCache.clear();
