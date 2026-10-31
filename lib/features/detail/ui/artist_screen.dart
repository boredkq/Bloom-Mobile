/// Страница артиста площадки: шапка с баннером и секции — «Популярные»,
/// «Альбомы», «Репосты», «Похожие исполнители», «Треки».
///
/// Состав секций взят с десктопа (`features/search/ui/DetailView.tsx`,
/// `ArtistBody`), раскладка — из референса: не вкладки, а одна прокрутка.
/// Плейлисты артиста провайдер отдаёт, но своей секции у них нет и на ПК.
///
/// Всё содержимое приходит одним `getArtist` (провайдер собирает его из шести
/// эндпоинтов параллельно); докручиваются только треки и репосты — курсорами.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/store/library_store.dart';
import '../../../features/customization/ui/app_background.dart';
import '../../../features/player/play_source.dart';
import '../../../features/player/player_controller.dart';
import '../../../features/wave/wave_actions.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/detail_hero.dart';
import '../../../shared/ui/entity_tiles.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({
    super.key,
    required this.artistId,
    this.initial,
    this.flight,
  });

  /// Сквозной id артиста («sc_artist_123»).
  final String artistId;

  /// Артист из карточки, с которой пришли: шапка рисуется до ответа сети.
  final Artist? initial;

  /// Аватарка карточки, с которой пришли: она перелетает в шапку.
  final CoverFlight? flight;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  ArtistPageData? _data;
  String? _error;
  bool _loading = true;

  /// Треки живут в состоянии экрана, а не в [_data]: их докручивают курсором,
  /// и список растёт.
  List<Track> _tracks = const [];
  String? _tracksCursor;

  /// Сколько треков у артиста всего по данным площадки — см.
  /// [ArtistPageData.tracksTotal].
  int? _tracksTotal;

  /// Треки догружаются сейчас — чтобы не жать кнопку дважды.
  bool _loadingMore = false;

  /// Прокрутка всей страницы: в неё зона треков отдаёт перелёт за свой край.
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = ref.read(registryProvider).forEntity(widget.artistId);
    if (provider == null) {
      setState(() {
        _loading = false;
        _error = context.l.artistSourceNotConnected;
      });
      return;
    }
    try {
      final data = await provider.getArtist(widget.artistId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (data == null) {
          _error = context.l.artistNotFound;
          return;
        }
        _data = data;
        _tracks = data.tracks;
        _tracksCursor = data.tracksCursor;
        _tracksTotal = data.tracksTotal;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _moreTracks() async {
    final cursor = _tracksCursor;
    if (cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    final provider = ref.read(registryProvider).forEntity(widget.artistId);
    TrackPage? page;
    try {
      page = await provider?.getArtistTracksPage(cursor);
    } catch (_) {
      page = null;
    }
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (page == null) {
        // Не вышло — курсор гасим, иначе кнопка «Загрузить ещё» будет вечной.
        _tracksCursor = null;
        return;
      }
      _tracks = [..._tracks, ...page.tracks];
      _tracksCursor = page.cursor;
    });
  }

  /// Что играет кнопка «Воспроизвести»: сначала «популярные», их у SoundCloud
  /// отдаёт отдельный эндпоинт и они точнее представляют артиста.
  List<Track> get _playQueue {
    final top = _data?.topTracks ?? const <Track>[];
    return top.isNotEmpty ? top : _tracks;
  }

  /// Источник для пилюли плеера — сама страница: с неё играют и «популярные»,
  /// и полный список треков. Артист мог ещё не загрузиться
  /// (страницу открыли по одному id) — тогда источника нет.
  PlaySource? get _source {
    final artist = _data?.artist ?? widget.initial;
    return artist == null ? null : ArtistSource(artist);
  }

  /// Из чего волна берёт сиды: популярные и загруженные треки вместе. Больше
  /// охват — точнее подбор; лишнее отсеет сам `queueSeeds`.
  List<Track> get _waveSeeds => [...?_data?.topTracks, ..._tracks];

  void _play() {
    final queue = _playQueue;
    if (queue.isEmpty) return;
    ref.read(playbackProvider.notifier).playQueue(queue, 0, source: _source);
  }

  void _shuffle() {
    final queue = _playQueue;
    if (queue.isEmpty) return;
    ref
        .read(playbackProvider.notifier)
        .playQueueShuffled(queue, source: _source);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final artist = _data?.artist ?? widget.initial;
    final queue = _playQueue;

    return Scaffold(
      // Под страницей может лежать картинка фона — тогда своей заливки нет.
      backgroundColor: ref.watch(backgroundOnProvider)
          ? Colors.transparent
          : t.bg,
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          DetailHero(
            image: artist?.avatar,
            title: artist?.name ?? context.l.commonArtist,
            subtitle: _subtitle(artist),
            flight: widget.flight,
            onMenu: artist == null ? null : () => _menu(artist),
            actions: HeroActions(
              sourceId: _source?.id,
              onPlay: queue.isEmpty ? null : _play,
              trailing: [
                GlassIconButton(
                  icon: Bi.shuffle,
                  size: 46,
                  onTap: queue.isEmpty ? null : _shuffle,
                ),
                if (artist != null) _FollowButton(artist: artist),
              ],
            ),
          ),
          if (_loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
            )
          else if (_error case final message?)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: t.danger),
                ),
              ),
            )
          else
            SliverList.list(children: _sections()),
          // Просвет в конце — плюс бары каркаса: они плавают над содержимым.
          const SliverBottomBarsInset(extra: 16),
        ],
      ),
    );
  }

  /// Подпись под именем: сколько треков. Пока треки приходят
  /// порциями, счётчик берём у площадки (у Яндекса это `pager.total`) — иначе
  /// в шапке стояло бы «50 треков» у артиста с тремя сотнями.
  String _subtitle(Artist? artist) {
    final total = _tracksTotal ?? 0;
    final count = _tracksCursor != null && total > _tracks.length
        ? total
        : _tracks.length;
    return count > 0 ? context.l.tracksCount(count) : '';
  }

  List<Widget> _sections() {
    final data = _data;
    if (data == null) return const [];

    final top = data.topTracks;
    final albums = data.albums;
    final similar = data.similarArtists;

    return [
      if (top.isNotEmpty) ...[
        SectionTitle(context.l.artistPopular, side: 8),
        EntityCarousel(
          height: 194,
          itemCount: top.length,
          builder: (i) =>
              TrackCard(track: top[i], queue: top, index: i, source: _source),
        ),
      ],
      if (albums.isNotEmpty) ...[
        SectionTitle(context.l.commonAlbums, side: 8),
        EntityCarousel(
          height: 194,
          itemCount: albums.length,
          builder: (i) => SetCard(set: albums[i]),
        ),
      ],
      if (similar.isNotEmpty) ...[
        SectionTitle(context.l.artistSimilar, side: 8),
        EntityCarousel(
          height: 168,
          itemCount: similar.length,
          builder: (i) => ArtistCard(artist: similar[i], centerLabel: true),
        ),
      ],
      if (_tracks.isNotEmpty) ...[
        SectionTitle(context.l.commonTracks, side: 8),
        _tracksZone(),
      ],
      if (top.isEmpty && albums.isEmpty && _tracks.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              context.l.artistNoTracks,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.bloom.muted),
            ),
          ),
        ),
    ];
  }

  /// «Треки» листаются в своей зоне, а не растягивают страницу: у артиста их
  /// бывают сотни. Зона не выше [_tracksZoneShare] экрана; короткий список
  /// занимает ровно свою высоту. Упёрлись в край зоны — докручиваем страницу,
  /// иначе палец на зоне, закрывшей экран, не сдвинул бы её никуда.
  Widget _tracksZone() {
    final more = _tracksCursor != null;
    final count = _tracks.length + (more ? 1 : 0);
    final full =
        _tracks.length * kTrackRowHeight + (more ? _moreButtonHeight : 0);
    final cap = MediaQuery.sizeOf(context).height * _tracksZoneShare;
    return SizedBox(
      height: full < cap ? full : cap,
      child: NotificationListener<OverscrollNotification>(
        onNotification: (n) {
          if (n.dragDetails == null || !_scroll.hasClients) return false;
          final outer = _scroll.position;
          final to = (outer.pixels + n.overscroll).clamp(
            outer.minScrollExtent,
            outer.maxScrollExtent,
          );
          if (to != outer.pixels) outer.jumpTo(to);
          return true;
        },
        child: ListView.builder(
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          itemCount: count,
          itemBuilder: (context, i) => i < _tracks.length
              ? TrackRow(
                  track: _tracks[i],
                  queue: _tracks,
                  index: i,
                  source: _source,
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                  child: BloomButton(
                    label: context.l.commonLoadMore,
                    tone: ButtonTone.plate,
                    height: 44,
                    busy: _loadingMore,
                    onTap: _moreTracks,
                  ),
                ),
        ),
      ),
    );
  }

  /// Доля высоты экрана, выше которой зона треков не растёт.
  static const double _tracksZoneShare = 0.6;

  /// Высота «Загрузить ещё» с её полями — чтобы короткий список с кнопкой
  /// не обрезался.
  static const double _moreButtonHeight = 64;

  Future<void> _menu(Artist artist) async {
    final queue = _playQueue;
    final following = ref.read(libraryProvider).isFollowing(artist.id);
    // Импортируем то, что уже загружено: догружать всю дискографию ради
    // импорта — минуты ожидания на популярном артисте.
    final forImport = _tracks.isNotEmpty ? _tracks : queue;

    await showBloomSheet(
      context: context,
      backdrop: artist.avatar,
      header: SheetLineHeader(
        cover: artist.avatar,
        title: artist.name,
        subtitle: _subtitle(artist),
        circle: true,
      ),
      groups: [
        [
          SheetAction(
            icon: Bi.playBold,
            label: context.l.commonPlay,
            onTap: queue.isEmpty ? null : _play,
          ),
          SheetAction(
            icon: Bi.shuffle,
            label: context.l.commonShuffle,
            onTap: queue.isEmpty ? null : _shuffle,
          ),
          // Волна по артисту: у Яндекса это его станция, у остальных — подбор
          // по тем трекам, что страница уже загрузила.
          if (canStartWaveFromArtist(ref, artist, _waveSeeds))
            SheetAction(
              icon: Bi.soundwave,
              label: context.l.waveFromArtist,
              onTap: () => startWaveFromArtist(
                context,
                ref,
                artist,
                seedTracks: _waveSeeds,
              ),
            ),
        ],
        [
          SheetAction(
            icon: following ? Bi.check : Bi.user,
            label: following
                ? context.l.commonUnfollow
                : context.l.commonFollow,
            onTap: () {
              final on = ref
                  .read(libraryProvider.notifier)
                  .toggleFollow(artist);
              _toast(
                on
                    ? context.l.followedToast(artist.name)
                    : context.l.unfollowedToast,
              );
            },
          ),
          SheetAction(
            icon: Bi.import,
            label: context.l.artistTracksToNewPlaylist,
            onTap: forImport.isEmpty
                ? null
                : () {
                    ref
                        .read(libraryProvider.notifier)
                        .createPlaylist(
                          artist.name,
                          tracks: forImport,
                          cover: artist.avatar,
                        );
                    _toast(
                      context.l.addedToast(
                        artist.name,
                        context.l.tracksCount(forImport.length),
                      ),
                      ToastKind.success,
                    );
                  },
          ),
        ],
      ],
    );
  }

  void _toast(String message, [ToastKind kind = ToastKind.info]) {
    if (!mounted) return;
    showToast(context, message, kind: kind);
  }
}

/// Подписка на артиста — та же, что в библиотеке: активная кнопка заливается
/// акцентом, как чип-фильтр.
class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final following = ref.watch(libraryProvider).isFollowing(artist.id);
    return GlassIconButton(
      icon: following ? Bi.check : Bi.user,
      size: 46,
      background: following ? t.accent : null,
      color: following ? t.accentText : null,
      onTap: () {
        final on = ref.read(libraryProvider.notifier).toggleFollow(artist);
        showToast(
          context,
          on ? context.l.followedToast(artist.name) : context.l.unfollowedToast,
        );
      },
    );
  }
}
