/// An artist's page: the header, then "About", the popular tracks (the first
/// five; "Show all" opens all of their tracks as a page of its own), the albums
/// and the similar artists. A listener's (a profile) is "About", their
/// playlists and their likes as the rows.
///
/// Everything comes in one `getArtist`; only the rows page on, by a cursor.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/store/library_store.dart';
import '../../../features/library/import_url.dart';
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
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/util/format.dart';
import '../detail_nav.dart';
import 'detail_parts.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({
    super.key,
    required this.artistId,
    this.initial,
    this.flight,
    this.seed,
  });

  /// The artist's id across platforms ("sc:artist:123").
  final String artistId;

  /// The card's artist: the header shows before the network answers.
  final Artist? initial;

  /// The card's avatar, flying into the header.
  final CoverFlight? flight;

  /// Set, this is all of the artist's tracks, opened from their page with what
  /// it had loaded: no network again.
  final ArtistPageData? seed;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  ArtistPageData? _data;
  String? _error;
  bool _loading = true;

  // The rows grow page by page, so they live here and not in [_data].
  List<Track> _tracks = const [];
  String? _cursor;
  Future<void>? _pulling;

  /// The last page failed: no more loading on its own, only by hand.
  bool _failed = false;

  /// The page and the list of all tracks scroll the same way: the next page
  /// loads while the end is still a screen or two away.
  final ScrollController _scroll = ScrollController();

  static const int _popularRows = 5;

  bool get _tracksView => widget.seed != null;
  bool get _profile => _data?.likes != null;

  /// Below the header: all of the artist's tracks, or a profile's likes.
  bool get _rows => _tracksView || _profile;

  List<Track> get _top => _data?.topTracks ?? const [];

  /// The popular ones; their tracks when the platform has none.
  List<Track> get _popular => _top.isNotEmpty ? _top : _tracks;

  bool get _hasMore => _top.isNotEmpty
      ? _tracks.isNotEmpty || _cursor != null
      : _tracks.length > _popularRows || _cursor != null;

  /// What the page plays: their tracks, the popular ones when that's all.
  List<Track> get _main => _tracks.isEmpty ? _top : _tracks;

  Artist? get _artist => _data?.artist ?? widget.initial;

  /// Artist may not be loaded yet (opened by an id alone): then no source.
  PlaySource? get _source => _artist == null ? null : ArtistSource(_artist!);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    if (widget.seed case final seed?) {
      _take(seed);
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _take(ArtistPageData data) {
    _data = data;
    _tracks = data.tracks;
    _cursor = data.tracksCursor;
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
        } else {
          _take(data);
        }
      });
      _later();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// The next page of the rows; the one in flight when there is one.
  Future<void> _more() => _pulling ??= _pull().whenComplete(() {
    _pulling = null;
    _later();
  });

  Future<void> _pull() async {
    final cursor = _cursor;
    if (cursor == null) return;
    setState(() => _failed = false);
    final provider = ref.read(registryProvider).forEntity(widget.artistId);
    TrackPage? page;
    try {
      page = await provider?.getArtistTracksPage(cursor);
    } catch (_) {
      page = null;
    }
    if (!mounted) return;
    setState(() {
      if (page == null) {
        // The cursor stays: "more" tries it again.
        _failed = true;
        return;
      }
      final seen = {for (final t in _tracks) t.id};
      final fresh = [
        for (final t in page.tracks)
          if (seen.add(t.id)) t,
      ];
      _tracks = [..._tracks, ...fresh];
      // A page of nothing new ends it: a dangling cursor would loop.
      _cursor = fresh.isEmpty ? null : page.cursor;
    });
  }

  void _later() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _check();
  });

  void _check() {
    if (!_rows || _cursor == null || _failed || _pulling != null) return;
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.extentAfter < p.viewportDimension * 2) _more();
  }

  void _play() {
    final queue = _main;
    if (queue.isEmpty) return;
    ref.read(playbackProvider.notifier).playQueue(queue, 0, source: _source);
  }

  void _shuffle() {
    final queue = _main;
    if (queue.isEmpty) return;
    ref
        .read(playbackProvider.notifier)
        .playQueueShuffled(queue, source: _source);
  }

  void _showAll() {
    final data = _data;
    if (data == null) return;
    openArtistTracks(
      context,
      ArtistPageData(
        artist: data.artist,
        topTracks: data.topTracks,
        tracks: _tracks,
        tracksCursor: _cursor,
        tracksTotal: data.tracksTotal,
      ),
    );
  }

  /// The header's numbers: "120 tracks, 5 h 3 min". While pages are left, the
  /// count is the platform's and the length an estimate.
  String _stats() {
    if (_data == null) return '';
    final l = context.l;
    final known = _tracks.fold(Duration.zero, (sum, t) => sum + t.duration);
    final withLength = _tracks.where((t) => t.duration > Duration.zero).length;
    var count = _tracks.length;
    var length = known;
    final total = _data?.tracksTotal ?? 0;
    final approx = _cursor != null && total > 0;
    if (_cursor != null) count = math.max(total, count);
    if (approx) {
      length = withLength == 0 ? Duration.zero : known * (count / withLength);
    }
    return [
      _profile ? l.likesCount(count) : l.tracksCount(count),
      if (length.inMinutes > 0) '${approx ? '≈ ' : ''}${totalDur(l, length)}',
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final artist = _artist;
    final canPlay = _main.isNotEmpty;

    final rows = [
      SliverList.builder(
        itemCount: _tracks.length,
        itemBuilder: (context, i) => DetailRow(track: _tracks[i]),
      ),
      SliverToBoxAdapter(child: _footer()),
      // The bars float over the page: the end clears them.
      const SliverBottomBarsInset(extra: 16),
    ];

    return BloomPage(
      body: _tracksView
          ? _allTracks(rows)
          : CustomScrollView(
              controller: _scroll,
              slivers: [
                DetailHero(
                  image: artist?.avatar,
                  title: artist?.name ?? context.l.commonArtist,
                  subtitle: _stats(),
                  flight: widget.flight,
                  onMenu: artist == null || _data == null
                      ? null
                      : () => _menu(artist),
                  actions: HeroActions(
                    sourceId: _source?.id,
                    onPlay: canPlay ? _play : null,
                    trailing: [
                      GlassIconButton(
                        icon: Bi.shuffle,
                        size: 46,
                        onTap: canPlay ? _shuffle : null,
                      ),
                      if (artist != null && !_profile)
                        _FollowButton(artist: artist),
                    ],
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(child: DetailSkeleton(artist: true))
                else if (_error case final message?)
                  SliverToBoxAdapter(
                    child: CenterNote(
                      message,
                      color: context.bloom.danger,
                      padding: const EdgeInsets.all(24),
                    ),
                  )
                else ...[
                  SliverList.list(children: _sections()),
                  if (_profile) ...rows,
                ],
                if (_loading || _error != null || !_profile)
                  const SliverBottomBarsInset(extra: 16),
              ],
            ),
    );
  }

  /// All of the artist's tracks: no header, only "back" and the title over
  /// the rows.
  Widget _allTracks(List<Widget> rows) => SubPage(
    title: context.l.commonTracks,
    onBack: () => Navigator.of(context).maybePop(),
    child: CustomScrollView(controller: _scroll, slivers: rows),
  );

  List<Widget> _sections() {
    final data = _data;
    if (data == null) return const [];
    final l = context.l;
    final popular = _popular;
    final about = data.artist.description;

    return [
      if (about != null && about.isNotEmpty) ...[
        SectionTitle(_profile ? l.artistAboutProfile : l.artistAbout, side: 8),
        DetailAbout(about),
      ],
      if (!_profile && popular.isNotEmpty) ...[
        SectionTitle(
          l.artistPopular,
          side: 8,
          actionLabel: _hasMore ? l.artistShowAll : null,
          onAction: _showAll,
        ),
        for (final track in popular.take(_popularRows)) DetailRow(track: track),
      ],
      if (data.albums.isNotEmpty) ...[
        SectionTitle(l.commonAlbums, side: 8),
        EntityCarousel(
          height: setRowHeight(data.albums),
          itemCount: data.albums.length,
          builder: (i) => SetCard(set: data.albums[i]),
        ),
      ],
      if (data.similarArtists.isNotEmpty) ...[
        SectionTitle(l.artistSimilar, side: 8),
        EntityCarousel(
          height: 168,
          itemCount: data.similarArtists.length,
          builder: (i) =>
              ArtistCard(artist: data.similarArtists[i], centerLabel: true),
        ),
      ],
      if (data.playlists.isNotEmpty) ...[
        SectionTitle(l.commonPlaylists, side: 8),
        EntityCarousel(
          height: setRowHeight(data.playlists),
          itemCount: data.playlists.length,
          builder: (i) => SetCard(set: data.playlists[i]),
        ),
      ],
      if (_profile && _tracks.isNotEmpty) SectionTitle(l.artistLikes, side: 8),
      if (!_profile && _top.isEmpty && _tracks.isEmpty && data.albums.isEmpty)
        CenterNote(l.artistNoTracks),
    ];
  }

  Widget _footer() {
    if (_cursor != null) {
      return DetailLoadMore(busy: !_failed, onTap: _more);
    }
    final bare = _tracksView || (_profile && _data!.playlists.isEmpty);
    return bare && _tracks.isEmpty
        ? CenterNote(context.l.setNoTracks)
        : const SizedBox.shrink();
  }

  Future<void> _menu(Artist artist) async {
    final canPlay = _main.isNotEmpty;
    final following = ref.read(libraryProvider).isFollowing(artist.id);
    final seeds = [..._top, ..._tracks];

    await showBloomSheet(
      context: context,
      header: SheetHero(
        cover: artist.avatar,
        title: artist.name,
        subtitle: _stats(),
      ),
      bar: [
        SheetAction(
          icon: Bi.playBold,
          label: context.l.commonPlay,
          onTap: canPlay ? _play : null,
        ),
        SheetAction(
          icon: Bi.shuffle,
          label: context.l.commonShuffle,
          onTap: canPlay ? _shuffle : null,
        ),
        ...queueSheetActions(context, ref, _main, source: _source),
      ],
      groups: [
        [
          // Yandex has the artist's own station; elsewhere I pick from the
          // tracks the page has loaded.
          if (!_profile && canStartWaveFromArtist(ref, artist, seeds))
            SheetAction(
              icon: Bi.soundwave,
              label: context.l.waveFromArtist,
              subtitle: context.l.waveFromArtistHint,
              onTap: () =>
                  startWaveFromArtist(context, ref, artist, seedTracks: seeds),
            ),
          if (!_profile)
            SheetAction(
              icon: following ? Bi.check : Bi.user,
              label: following
                  ? context.l.commonUnfollow
                  : context.l.commonFollow,
              subtitle: following ? null : context.l.commonFollowHint,
              onTap: () => toggleFollow(context, ref, artist),
            ),
          SheetAction(
            icon: Bi.import,
            label: context.l.artistImport,
            subtitle: context.l.artistImportHint,
            next: true,
            onTap: canPlay ? () => _import(artist) : null,
          ),
        ],
      ],
    );
  }

  /// All of their tracks, not just the pages shown; a listener's likes all
  /// of them too, linked as the playlist's source.
  Future<void> _import(Artist artist) async {
    final likes = _data?.likes;
    final target = await pickImportTarget(
      context,
      title: likes?.title ?? artist.name,
      cover: artist.avatar,
    );
    if (target == null || !mounted) return;
    final l10n = context.l;
    var tracks = _main;
    if (likes != null) {
      toaster.show(l10n.artistLikesLoading);
      final provider = ref.read(registryProvider).forEntity(likes.id);
      tracks = (await provider?.getPlaylist(likes.id))?.tracks ?? tracks;
    } else if (_cursor != null) {
      toaster.show(l10n.artistImportLoading);
      while (mounted && _cursor != null && !_failed) {
        await _more();
      }
      tracks = _main;
    }
    if (!mounted) return;
    try {
      final result = importTracksInto(
        ref.read(libraryProvider.notifier),
        () => ref.read(libraryProvider),
        tracks,
        target,
        title: likes?.title ?? artist.name,
        cover: artist.avatar,
        source: likes == null ? null : PlSourceRef.of(likes),
      );
      toaster.show(
        importResultText(l10n, result),
        kind: result.added == 0 ? ToastKind.info : ToastKind.success,
      );
    } on ImportException catch (e) {
      toaster.show(describeImportFailure(l10n, e.reason), kind: ToastKind.warn);
    }
  }
}

/// Following, as in the library: lit with the accent while on.
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
      onTap: () => toggleFollow(context, ref, artist),
    );
  }
}

/// Follows or unfollows, with its toast.
void toggleFollow(BuildContext context, WidgetRef ref, Artist artist) {
  final on = ref.read(libraryProvider.notifier).toggleFollow(artist);
  toaster.show(
    on ? context.l.followedToast(artist.name) : context.l.unfollowedToast,
  );
}
