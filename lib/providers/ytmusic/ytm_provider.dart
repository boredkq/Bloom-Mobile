/// YouTube Music как [MusicProvider]: тонкий слой поверх порта InnerTube
/// (`ytmusic.dart`), который приводит `YtmRaw*` к общим сущностям.
///
/// Вся сетевая логика и её гочи живут этажом ниже — здесь только маппинг и
/// сборка страниц. Зеркало `ym_provider.dart` / `sc_provider.dart`.
///
/// Без `isEnabled`: публичный поиск и стрим работают без авторизации, площадка
/// всегда в выдаче (в отличие от Яндекса, которому нужен токен).
library;

import 'dart:io';

import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import 'models.dart';
import 'ytmusic.dart' as ytm;

/// Сквозные id с префиксом источника — те же, что на ПК:
///   трек     → `ytm:<videoId>`
///   артист   → `ytm:artist:<browseId>`
///   альбом   → `ytm:album:<browseId>`
///   плейлист → `ytm:pl:<browseId>`
String ytmTrackId(String videoId) => 'ytm:$videoId';
String ytmArtistId(String browseId) => 'ytm:artist:$browseId';
String ytmAlbumId(String browseId) => 'ytm:album:$browseId';
String ytmPlaylistId(String browseId) => 'ytm:pl:$browseId';

/// Обратный разбор сквозного id. У трека префикс общий с остальными, поэтому
/// сначала отсекаем более длинные — иначе `ytm:album:MPRE…` разобрался бы как
/// videoId `album:MPRE…`.
String? parseYtmTrackId(String id) =>
    id.startsWith('ytm:') &&
        !id.startsWith('ytm:artist:') &&
        !id.startsWith('ytm:album:') &&
        !id.startsWith('ytm:pl:')
    ? id.substring('ytm:'.length)
    : null;
String? parseYtmArtistId(String id) =>
    id.startsWith('ytm:artist:') ? id.substring('ytm:artist:'.length) : null;
String? parseYtmAlbumId(String id) =>
    id.startsWith('ytm:album:') ? id.substring('ytm:album:'.length) : null;
String? parseYtmPlaylistId(String id) =>
    id.startsWith('ytm:pl:') ? id.substring('ytm:pl:'.length) : null;

String? _blankToNull(String s) => s.isEmpty ? null : s;

Track trackFromYtm(YtmRawTrack t) => Track(
  id: ytmTrackId(t.id),
  name: t.title.isEmpty ? kYtmUntitled : t.title,
  artist: t.artist.isEmpty ? kYtmUnknownArtist : t.artist,
  duration: t.duration,
  cover: _blankToNull(t.cover),
  source: MusicSource.ytmusic,
  artistId: t.artistId.isEmpty ? null : ytmArtistId(t.artistId),
  url: 'https://music.youtube.com/watch?v=${t.id}',
  // Стрим резолвится по videoId из сквозного id, сырьё площадки не нужно.
);

Artist artistFromYtm(YtmRawArtist a) => Artist(
  id: ytmArtistId(a.id),
  name: a.name.isEmpty ? kYtmUnknownArtist : a.name,
  avatar: _blankToNull(a.cover),
  source: MusicSource.ytmusic,
);

Playlist albumFromYtm(YtmRawAlbum a) => Playlist(
  id: ytmAlbumId(a.id),
  title: a.title.isEmpty ? kYtmAlbumFallback : a.title,
  cover: _blankToNull(a.cover),
  ownerName: _blankToNull(a.artist),
  year: _blankToNull(a.year),
  albumType: a.kind,
  sourceUrl: 'https://music.youtube.com/browse/${a.id}',
  isAlbum: true,
  source: MusicSource.ytmusic,
);

Playlist playlistFromYtm(YtmRawPlaylist p) => Playlist(
  id: ytmPlaylistId(p.id),
  title: p.title.isEmpty ? kYtmPlaylistFallback : p.title,
  cover: _blankToNull(p.cover),
  // Счётчик не подставляем нулём: YTM даёт его только у своих плейлистов, и
  // «0 тр.» вместо «неизвестно» выглядит как пустой плейлист.
  trackCount: p.trackCount,
  ownerName: _blankToNull(p.ownerName),
  sourceUrl: 'https://music.youtube.com/playlist?list=${_bare(p.id)}',
  source: MusicSource.ytmusic,
);

/// browseId плейлиста без служебного префикса `VL` — в ссылке `?list=` он
/// лишний.
String _bare(String browseId) =>
    browseId.startsWith('VL') ? browseId.substring(2) : browseId;

class YtmusicProvider extends MusicProvider {
  const YtmusicProvider();

  @override
  MusicSource get source => MusicSource.ytmusic;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    // Сортировки у поиска YTM нет — параметр приходит от общего UI и здесь
    // просто не на что влиять.
    final d = await ytm.search(query);
    return SearchResults(
      tracks: d.tracks.map(trackFromYtm).toList(),
      artists: d.artists.map(artistFromYtm).toList(),
      albums: d.albums.map(albumFromYtm).toList(),
      playlists: d.playlists.map(playlistFromYtm).toList(),
      tracksHasMore: d.tracksHasMore,
    );
  }

  /// Одна вкладка «Artists» вместо всей выдачи: за аватаром исполнителя незачем
  /// гонять пять запросов поиска. Ту же вкладку общий поиск считает источником
  /// истины по артистам — искомый в ней первый.
  @override
  Future<List<Artist>> searchArtists(String query, {int limit = 3}) async {
    final v = await ytm.searchRaw(query, ytm.kParamsArtists);
    final rows = ytm.filteredRows(
      v,
      (it) => ytm.pageType(it) == 'MUSIC_PAGE_TYPE_ARTIST',
      ytm.parseArtist,
      limit,
      (a) => a.id,
    );
    return rows.map(artistFromYtm).toList();
  }

  /// Догрузка выдачи (по 20). `offset` игнорируем: InnerTube листает
  /// непрозрачным токеном, а не смещением, — токен привязан к строке запроса и
  /// живёт в сетевом слое.
  @override
  Future<TrackPage?> loadMoreTracks(
    String query,
    int offset, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    final d = await ytm.searchMore(query);
    return TrackPage(
      tracks: d.tracks.map(trackFromYtm).toList(),
      hasMore: d.hasMore,
    );
  }

  @override
  Future<ResolvedUrl?> resolveUrl(String url) async {
    // Чужую ссылку отдаём дальше по реестру, не тратя на неё запрос.
    if (!RegExp(
      r'youtube\.com|youtu\.be',
      caseSensitive: false,
    ).hasMatch(url)) {
      return null;
    }
    final r = await ytm.resolve(url);
    switch (r.kind) {
      case 'track':
        return ResolvedTrack(trackFromYtm(await ytm.track(r.id)));
      case 'artist':
        final e = await ytm.artist(r.id);
        return ResolvedArtist(
          Artist(
            id: ytmArtistId(r.id),
            name: e.title.isEmpty ? kYtmUnknownArtist : e.title,
            avatar: _blankToNull(e.cover),
            source: MusicSource.ytmusic,
          ),
        );
      case 'album':
        final c = await getAlbum(ytmAlbumId(r.id));
        return c == null ? null : ResolvedSet(c.playlist);
      case 'playlist':
        final c = await getPlaylist(ytmPlaylistId(r.id));
        return c == null ? null : ResolvedSet(c.playlist);
      default:
        return null;
    }
  }

  @override
  Future<Track?> resolveTrackById(String id) async {
    final videoId = parseYtmTrackId(id);
    if (videoId == null) return null;
    return trackFromYtm(await ytm.track(videoId));
  }

  @override
  Future<ArtistPageData?> getArtist(String id) async {
    final browseId = parseYtmArtistId(id);
    if (browseId == null) return null;
    final e = await ytm.artist(browseId);
    return ArtistPageData(
      artist: Artist(
        id: id,
        name: e.title.isEmpty ? kYtmUnknownArtist : e.title,
        avatar: _blankToNull(e.cover),
        description: _blankToNull(e.description),
        source: MusicSource.ytmusic,
      ),
      topTracks: e.popularTracks.map(trackFromYtm).toList(),
      tracks: e.tracks.map(trackFromYtm).toList(),
      albums: e.albums.map(albumFromYtm).toList(),
      similarArtists: e.similarArtists.map(artistFromYtm).toList(),
    );
  }

  @override
  Future<SetContent?> getAlbum(String id) async {
    final browseId = parseYtmAlbumId(id);
    if (browseId == null) return null;
    final e = await ytm.album(browseId);
    final tracks = e.tracks.map(trackFromYtm).toList();
    return SetContent(
      playlist: Playlist(
        id: id,
        title: e.title.isEmpty ? kYtmAlbumFallback : e.title,
        cover: _blankToNull(e.cover),
        ownerName: _blankToNull(e.subtitle),
        ownerAvatar: _blankToNull(e.ownerAvatar),
        year: _blankToNull(e.year),
        trackCount: tracks.isEmpty ? null : tracks.length,
        isAlbum: true,
        sourceUrl: 'https://music.youtube.com/browse/$browseId',
        source: MusicSource.ytmusic,
      ),
      tracks: tracks,
    );
  }

  @override
  Future<SetContent?> getPlaylist(String id) async {
    final browseId = parseYtmPlaylistId(id);
    if (browseId == null) return null;
    final e = await ytm.playlist(browseId);
    final tracks = e.tracks.map(trackFromYtm).toList();
    return SetContent(
      playlist: Playlist(
        id: id,
        title: e.title.isEmpty ? kYtmPlaylistFallback : e.title,
        cover: _blankToNull(e.cover),
        ownerName: _blankToNull(e.subtitle),
        ownerAvatar: _blankToNull(e.ownerAvatar),
        trackCount: tracks.isEmpty ? null : tracks.length,
        sourceUrl: 'https://music.youtube.com/playlist?list=${_bare(browseId)}',
        source: MusicSource.ytmusic,
      ),
      tracks: tracks,
    );
  }

  @override
  String trackStation(Track track) {
    final vid = track.source == MusicSource.ytmusic
        ? parseYtmTrackId(track.id)
        : null;
    return vid == null || vid.isEmpty ? '' : 'track:$vid';
  }

  /// Похожих отдельно YouTube Music не отдаёт — это начало радио трека.
  @override
  Future<List<Track>?> getSimilarTracks(String seedId) async {
    final vid = parseYtmTrackId(seedId);
    if (vid == null || vid.isEmpty) return const [];
    final page = await station('track:$vid', '');
    return [
      for (final t in page.tracks)
        if (t.id != seedId) t,
    ];
  }

  @override
  Future<StationPage> station(String station, String cursor) async {
    if (!station.startsWith('track:')) return const StationPage();
    try {
      final r = await ytm.radio(station.substring(6), cursor: cursor);
      return StationPage(
        tracks: r.tracks.map(trackFromYtm).toList(),
        cursor: r.cursor,
      );
    } catch (_) {
      return const StationPage();
    }
  }

  /// Прямая ссылка `googlevideo` — плеер тянет её сам. Локального прокси, как на
  /// десктопе, здесь нет: он там нужен из-за CORS и range-запросов WebView2.
  ///
  /// На iOS вместо неё идёт HLS-плейлист: прямая ведёт на фрагментированный
  /// mp4, а AVPlayer вне HLS считает его длительность вдвое больше настоящей
  /// (подробности — у `_hlsAudioUrl` в `ytmusic.dart`).
  @override
  Future<PlayableStream?> resolveStream(Track track) async =>
      PlayableStream(url: await _streamUrl(track, hls: Platform.isIOS));

  /// Скачивается ровно то, что играет: `adaptiveFormats` — цельный файл
  /// (itag 140, m4a), а не плейлист кусков.
  @override
  bool canDownload(Track track) => true;

  /// Качаем всегда прямую ссылку — даже на iOS, где играем через плейлист:
  /// офлайн-копия должна быть одним файлом, а не набором сегментов.
  @override
  Future<PlayableStream?> resolveDownload(Track track) async =>
      PlayableStream(url: await _streamUrl(track));

  /// Подписанная ссылка googlevideo живёт минуты — держим кеш 4, как на
  /// десктопе: иначе пауза с последующим play требовала бы нового резолва.
  Future<String> _streamUrl(Track track, {bool hls = false}) async {
    final videoId = parseYtmTrackId(track.id);
    if (videoId == null) throw const YtmException('ytm.err.trackNotFound');
    // Плеер и скачивание берут у одного трека РАЗНЫЕ ссылки — общий ключ отдал
    // бы скачиванию плейлист (или наоборот), смотря кто попросил первым.
    final key = hls ? '$videoId#hls' : videoId;
    final cached = _streamCache[key];
    if (cached != null && DateTime.now().difference(cached.at) < _streamTtl) {
      return cached.url;
    }
    final url = await ytm.streamUrl(videoId, hls: hls);
    _streamCache[key] = (url: url, at: DateTime.now());
    return url;
  }
}

const Duration _streamTtl = Duration(minutes: 4);
final Map<String, ({String url, DateTime at})> _streamCache = {};
