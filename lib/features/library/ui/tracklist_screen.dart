/// Track list of a library section: built-in all tracks and favourites and user
/// playlists, one screen for all. A full-width hero cover with title and count
/// over it, a Play, shuffle and edit row, and the track list below. The pencil
/// enters edit mode: [ListEditor] replaces the whole page.
///
/// Built-in sections have no cover, so it's a 2×2 collage of first tracks, or
/// if too few, a flat section tint with its coloured icon.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../core/store/play_stats.dart';
import '../../../core/store/text_files.dart';
import '../../../features/offline/file_download.dart';
import '../../../features/offline/offline_actions.dart';
import '../../../features/offline/offline_store.dart';
import '../../../features/player/play_source.dart';
import '../../../features/player/player_controller.dart';
import '../../../features/settings/data_transfer.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/detail_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/sticky_hero.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/ui/track_swipes.dart';
import '../dups.dart';
import '../local_tracks.dart';
import '../refresh_playlist.dart';
import 'convert_screen.dart';
import 'dups_view.dart';
import 'list_edit.dart';
import 'list_meta.dart';
import 'merge_sheet.dart';
import 'list_hero.dart';
import 'now_playing_jump.dart';

/// Top padding of the track list under the header. The Now playing pill
/// computes rows from it, so it must match `SliverPadding`.
const double _listPadTop = 10;

/// Track list sort, plus Downloaded: not a sort but a filter leaving what's on
/// the device. A second tap inverts it, leaving what's NOT downloaded.
///
/// Value order is the sheet's item order: sorts first, then Default and
/// Downloaded below a line.
enum TrackSort {
  name(Bi.sort),
  artist(Bi.user),
  duration(Bi.clockCircle),
  date(Bi.calendar),
  plays(Bi.play),
  album(Bi.album),
  manual(Bi.repeat),
  downloaded(Bi.downloadMinimalistic);

  const TrackSort(this.icon);
  final BloomGlyph icon;

  /// [desc] on Downloaded means the inverted filter, Not downloaded.
  String label(AppLocalizations l, {bool desc = false}) => switch (this) {
    TrackSort.manual => l.tlSortManual,
    TrackSort.name => l.tlSortName,
    TrackSort.artist => l.tlSortArtist,
    TrackSort.album => l.tlSortAlbum,
    TrackSort.duration => l.tlSortDuration,
    TrackSort.date => l.tlSortDate,
    TrackSort.plays => l.tlSortPlays,
    TrackSort.downloaded => desc ? l.tlSortNotDownloaded : l.tlSortDownloaded,
  };

  /// A second tap reverses the order, except for modes with no order of their
  /// own: In order gives the list as is, Downloaded only filters.
  bool get directional =>
      this != TrackSort.manual && this != TrackSort.downloaded;

  /// A second tap changes something: order for directional modes, the filter
  /// itself for Downloaded.
  bool get flips => directional || this == TrackSort.downloaded;

  /// Which end a mode starts from: date and plays show newest and most frequent
  /// on top.
  bool get descFirst => this == TrackSort.date || this == TrackSort.plays;
}

class TracklistScreen extends ConsumerStatefulWidget {
  const TracklistScreen({super.key, required this.listId, this.flight});

  /// `all`, `fav` or a user playlist's id.
  final String listId;

  /// Cover of the library tile this came from, flying into the header. `null`
  /// if the tile had no cover (a collage or tint in the header) or the list
  /// wasn't opened from a tile.
  final CoverFlight? flight;

  @override
  ConsumerState<TracklistScreen> createState() => _TracklistScreenState();
}

class _TracklistScreenState extends ConsumerState<TracklistScreen> {
  TrackSort _sort = TrackSort.manual;

  /// Order reversed, opposite of the mode's start.
  bool _desc = false;

  bool _searchOpen = false;
  String _query = '';

  /// The screen is given to [ListEditor]: the list is being edited, not
  /// browsed.
  bool _editing = false;

  /// Duplicates mode on for THIS list, a snapshot from the last frame. Needed
  /// in [dispose], where nothing can be asked: `ref` throws after the widget is
  /// gone, which would kill `dispose` and leave the mode on. The value comes
  /// from `build`, where the provider is watched anyway.
  bool _dupsHere = false;

  /// The store itself, also ahead of time: it outlives the widget, and can turn
  /// the mode off after removal.
  late final DupsController _dups = ref.read(dupsProvider.notifier);

  /// Own scroll controller: through it the Now playing pill knows whether the
  /// playing row shows, and returns the list to it.
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _dups; // take the store while `ref` still lives
  }

  @override
  void dispose() {
    // Leaving a list turns duplicates mode off: it's about THIS playlist.
    if (_dupsHere) _dups.exit();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    // Duplicates mode is on for this list: repeat groups replace rows. Read at
    // the very start, before any early return: [dispose] needs the snapshot
    // too, see [_dupsHere].
    final dups = _dupsHere = ref.watch(dupsProvider) == widget.listId;

    // Playlist ids have no prefix, so I always search; built-in `all` and `fav`
    // just won't be found.
    UserPlaylist? playlist;
    for (final p in lib.playlists) {
      if (p.id == widget.listId) {
        playlist = p;
        break;
      }
    }

    final (String title, List<Track> source) = switch (widget.listId) {
      'all' => (context.l.commonAllTracks, lib.allTracks),
      'fav' => (context.l.commonFavorites, lib.favTracks),
      _ => (
        playlist?.name ?? context.l.commonPlaylist,
        playlist == null ? <Track>[] : lib.tracksOf(playlist),
      ),
    };

    if (_editing) {
      return ListEditor(
        listId: widget.listId,
        title: title,
        playlist: playlist,
        // The WHOLE list is edited in its own order: sort and search reset on
        // entering.
        tracks: source,
        onClose: () => setState(() => _editing = false),
      );
    }

    // Offline contents are asked only when they affect the screen: the index
    // changes on every percent of a batch download, and subscribing for a list
    // not showing it means rebuilding for nothing.
    final offline = _sort == TrackSort.downloaded
        ? ref.watch(offlineProvider)
        : null;
    // Stats too, only when they affect the screen: they recount on every
    // counted play.
    final stats = _sort == TrackSort.plays
        ? ref.watch(playStatsProvider)
        : null;
    final tracks = _apply(source, lib, offline, stats);
    // Keys aren't only for dragging: a row can be swiped, the list isn't
    // animated, and with no key the gesture state goes to the neighbour taking
    // its place.
    final keys = trackRowKeys(tracks);
    final width = MediaQuery.of(context).size.width;

    // Geometry for the Now playing pill: how much of the list's top the stuck
    // header covers, and where the first row lies in scroll coordinates. The
    // playing row may not be in the tree, so its place comes from the model.
    final barHeight = _searchOpen ? kHeaderControl * 2 + 10 : kHeaderControl;
    final collapsed = StickyHero.collapsedHeight(context, barHeight);
    final heroExtent = math.max(width * 0.62 + 76, collapsed);

    double? rowTopOf(String id) {
      // Duplicates mode replaces the whole list, with no track rows.
      if (dups) return null;
      final i = tracks.indexWhere((t) => t.id == id);
      return i < 0 ? null : heroExtent + _listPadTop + i * kTrackRowHeight;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomScrollView(
          controller: _scroll,
          slivers: [
            _Hero(
              listId: widget.listId,
              title: title,
              playlist: playlist,
              tracks: source,
              visible: tracks,
              // A flight only to an own cover: a 2×2 collage is built from
              // other pictures, with no place for the tile's.
              flight: playlist?.cover == null ? null : widget.flight,
              height: width * 0.62 + 76,
              sort: _sort,
              desc: _desc,
              onSort: _pickSort,
              searchOpen: _searchOpen,
              query: _query,
              onToggleSearch: () => setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) _query = '';
              }),
              onQuery: (q) => setState(() => _query = q),
              onEdit: () => setState(() {
                _editing = true;
                _searchOpen = false;
                _query = '';
                _sort = TrackSort.manual;
                _desc = false;
              }),
            ),
            // Batch download progress lives in a toast (`BatchToastBody`),
            // visible from any screen.
            //
            // Find duplicates replaces ONLY the list: the header stays. The
            // search pool is the whole list, not the visible part: looking for
            // repeats in a filtered list means not finding them.
            if (dups)
              DupsSliver(listId: widget.listId, tracks: source)
            else if (tracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CenterNote(
                    _query.isNotEmpty
                        ? context.l.tlNothingFound
                        // The list isn't empty, just nothing to show under the
                        // filter: I say so, or playlist empty on a full
                        // playlist looks broken.
                        : _sort == TrackSort.downloaded
                        ? (_desc
                              ? context.l.tlNothingNotDownloaded
                              : context.l.tlNothingDownloaded)
                        : switch (widget.listId) {
                            'fav' => context.l.tlEmptyFav,
                            'all' => context.l.tlEmptyAll,
                            _ => context.l.tlEmptyPlaylist,
                          },
                    padding: const EdgeInsets.symmetric(vertical: 60),
                  ),
                ),
              )
            // The list's own order: rows can be dragged by holding the cover,
            // as in the queue.
            else if (_canReorder)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, _listPadTop, 8, 12),
                sliver: SliverReorderableList(
                  itemCount: tracks.length,
                  onReorder: (from, to) => _reorder(source, from, to),
                  proxyDecorator: (child, _, _) =>
                      trackRowDragged(context, child),
                  itemBuilder: (context, i) => TrackSwipe(
                    key: keys[i],
                    zone: SwipeZone.library,
                    track: tracks[i],
                    listId: widget.listId,
                    child: TrackRow(
                      track: tracks[i],
                      queue: tracks,
                      index: i,
                      source: LibSource(widget.listId),
                      dragIndex: i,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, _listPadTop, 8, 12),
                sliver: SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => TrackSwipe(
                    key: keys[i],
                    zone: SwipeZone.library,
                    track: tracks[i],
                    listId: widget.listId,
                    child: TrackRow(
                      track: tracks[i],
                      queue: tracks,
                      index: i,
                      source: LibSource(widget.listId),
                    ),
                  ),
                ),
              ),
            // Room for the shell's bars, shared by all branches above: they
            // float over the list, and otherwise the last row can't clear the
            // mini player.
            const SliverBottomBarsInset(),
          ],
        ),
        // The Now playing pill lies OUTSIDE the scroll and so stays in place,
        // on the right above the mini player.
        Positioned(
          right: 16,
          bottom: bottomBarsInset(context) + 12,
          child: NowPlayingJump(
            controller: _scroll,
            rowTopOf: rowTopOf,
            topInset: collapsed,
          ),
        ),
      ],
    );
  }

  /// A pick in the sort sheet. A second tap on the current mode reverses the
  /// order.
  void _pickSort(TrackSort next) {
    setState(() {
      if (next == _sort && next.flips) {
        _desc = !_desc;
      } else {
        _sort = next;
        _desc = next.descFirst;
      }
    });
  }

  /// Rows can be dragged only with the list's own order on screen: under sort
  /// or search a move would land in the wrong place.
  bool get _canReorder => _sort == TrackSort.manual && _query.isEmpty;

  /// Row keys: a track can be in a list twice, and `ReorderableList` crashes on
  /// duplicates, so I add the occurrence number.
  void _reorder(List<Track> source, int from, int to) {
    // The insertion index counts BEFORE the row is removed, and all below is
    // already shifted.
    if (to > from) to--;
    final next = [...source];
    next.insert(to, next.removeAt(from));
    final ids = [for (final track in next) track.id];
    final lib = ref.read(libraryProvider.notifier);
    switch (widget.listId) {
      case 'all':
        lib.setLibraryTracks(ids);
      case 'fav':
        lib.setFavTracks(ids);
      default:
        lib.setPlaylistTracks(widget.listId, ids);
    }
  }

  /// Search, filter and sort apply to a copy: the playlist's order must stay,
  /// so In order can bring it back.
  ///
  /// [offline] comes only in Downloaded mode, [stats] only in By plays.
  List<Track> _apply(
    List<Track> source,
    LibraryState lib,
    OfflineState? offline,
    PlayStats? stats,
  ) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? [...source]
        : source
              .where(
                (t) =>
                    t.name.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q),
              )
              .toList();

    if (_sort == TrackSort.downloaded) {
      // Order stays its own: the mode only drops what's not on the device.
      // Tracks downloading now don't count: no file yet. Local tracks are phone
      // files with no offline index entry, and without them the downloaded list
      // would lie about the user's own music. The inverted filter ([_desc])
      // leaves exactly the rest: what won't play offline, including those
      // downloading.
      list.removeWhere((t) {
        final onDevice =
            t.source == MusicSource.local || offline?.has(t.id) == true;
        return _desc ? onDevice : !onDevice;
      });
      return list;
    }
    if (!_sort.directional) return list;

    // Add time comes from the section on screen: in favourites it's the like's
    // time.
    int addedAt(Track t) => switch (widget.listId) {
      'fav' => lib.favs[t.id] ?? 0,
      _ => lib.inLib[t.id] ?? 0,
    };

    // Plays are the listener's own, from the log.
    final int dir = _desc ? -1 : 1;
    list.sort((a, b) {
      final c = switch (_sort) {
        TrackSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        TrackSort.artist => a.artist.toLowerCase().compareTo(
          b.artist.toLowerCase(),
        ),
        TrackSort.album => (a.album ?? '').toLowerCase().compareTo(
          (b.album ?? '').toLowerCase(),
        ),
        TrackSort.duration => a.duration.compareTo(b.duration),
        TrackSort.date => addedAt(a).compareTo(addedAt(b)),
        TrackSort.plays => (stats?.playCount(a.id) ?? 0).compareTo(
          stats?.playCount(b.id) ?? 0,
        ),
        TrackSort.manual || TrackSort.downloaded => 0,
      };
      return dir * c;
    });
    return list;
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.listId,
    required this.title,
    required this.playlist,
    required this.tracks,
    required this.visible,
    required this.flight,
    required this.height,
    required this.sort,
    required this.desc,
    required this.onSort,
    required this.searchOpen,
    required this.query,
    required this.onToggleSearch,
    required this.onQuery,
    required this.onEdit,
  });

  final String listId;
  final String title;
  final UserPlaylist? playlist;

  /// Full contents, for the count and for starting playback.
  final List<Track> tracks;

  /// What's really shown, after search and sort.
  final List<Track> visible;

  /// Cover of the source tile, the flight's target.
  final CoverFlight? flight;

  /// Full header height, with the title strip and action row under the cover.
  /// Computed outside: the Now playing pill learns from it where the list
  /// starts.
  final double height;
  final TrackSort sort;
  final bool desc;
  final ValueChanged<TrackSort> onSort;
  final bool searchOpen;
  final String query;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQuery;

  /// Enters edit mode, the pencil in the action row.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return StickyHero(
      height: height,
      flying: flight != null,
      // The cover fills the header with the action row: its rounded bottom edge
      // is the border with the list.
      background: HeroCover(
        child: CoverHero(
          tag: flight?.tag,
          shape: BorderRadius.vertical(bottom: Radius.circular(t.radius * 1.5)),
          child: ListHeroBackground(
            listId: listId,
            cover: playlist?.cover,
            tracks: tracks,
          ),
        ),
      ),
      // Open search rides with the buttons: searching a list while looking at
      // it matters most when scrolled.
      barHeight: searchOpen ? kHeaderControl * 2 + 10 : kHeaderControl,
      bar: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlassIconButton(
                icon: Bi.arrowLeft,
                onTap: () => context.go('/library'),
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: Bi.sort,
                background: sort != TrackSort.manual ? t.accent : null,
                color: sort != TrackSort.manual ? t.accentText : null,
                onTap: () => showSortSheet(context, sort, desc, onSort),
              ),
              const Spacer(),
              // The plus only in all tracks: favourites' contents aren't own,
              // and a track joins a playlist from its own sheet.
              if (listId == 'all') ...[
                const _AddLocalButton(),
                const SizedBox(width: 8),
              ],
              GlassIconButton(
                icon: searchOpen ? Bi.close : Bi.magnifier,
                onTap: onToggleSearch,
              ),
              if (playlist != null) ...[
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: Bi.kebab,
                  onTap: () =>
                      showPlaylistMenu(context, ref, playlist!, tracks),
                ),
              ],
            ],
          ),
          if (searchOpen) ...[
            const SizedBox(height: 10),
            _InlineSearch(query: query, onQuery: onQuery),
          ],
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.headlineSmall?.copyWith(fontSize: 30),
          ),
          const SizedBox(height: 4),
          // Count, offline tag and total time.
          ListMeta(
            tracks: tracks,
            style: theme.bodyMedium,
            showOffline: playlist != null,
          ),
          const SizedBox(height: 14),
          _Actions(
            listId: listId,
            tracks: visible.isEmpty ? tracks : visible,
            onEdit: onEdit,
          ),
        ],
      ),
    );
  }
}

/// The plus in the all tracks header: system audio picker, adding files to the
/// library as local tracks. During the dialog and parsing it shows a ring:
/// copying a large file and reading tags take time, and a second tap would open
/// a second dialog (the native side refuses such a request).
class _AddLocalButton extends ConsumerStatefulWidget {
  const _AddLocalButton();

  @override
  ConsumerState<_AddLocalButton> createState() => _AddLocalButtonState();
}

class _AddLocalButtonState extends ConsumerState<_AddLocalButton> {
  bool _busy = false;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Messenger and translations come before the dialog: it's the system's, the
    // screen may leave meanwhile, and `context` won't do after await.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l;
    final result = await importLocalTracks(ref, l10n);
    if (mounted) setState(() => _busy = false);
    switch (result.status) {
      case LocalImportStatus.cancelled:
        break; // the dialog was just closed, so quietly
      case LocalImportStatus.nothing:
        messenger.toast(l10n.ltNothingAdded);
      case LocalImportStatus.added:
        messenger.toast(l10n.ltAdded(result.added), kind: ToastKind.success);
      case LocalImportStatus.failed:
        messenger.toast(l10n.ltImportFailed, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) => GlassIconButton(
    icon: Bi.add,
    onTap: _add,
    child: _busy
        ? const Center(child: BloomSpinner(size: 18, color: Colors.white))
        : null,
  );
}

/// List sort choice, a bottom sheet like a track's rather than a popup: a hand
/// reaches the screen's bottom on a phone, not the header's corner. A second
/// tap on the current mode reverses the order, with an arrow on the right
/// showing which end leads.
Future<void> showSortSheet(
  BuildContext context,
  TrackSort sort,
  bool desc,
  ValueChanged<TrackSort> onSort,
) {
  final t = context.bloom;
  SheetAction item(TrackSort s) => SheetAction(
    icon: s.icon,
    label: s.label(context.l, desc: s == sort && desc),
    onTap: () => onSort(s),
    trailing: s != sort
        ? null
        : BloomIcon(
            switch (s) {
              _ when s.directional =>
                desc ? Bi.altArrowDownBold : Bi.altArrowUpBold,
              // The inverted Downloaded filter is Not downloaded: a tick would
              // read as downloaded, so a cross.
              TrackSort.downloaded when desc => Bi.close,
              _ => Bi.check,
            },
            size: 18,
            color: t.accent,
          ),
  );
  // The line separates sorts from Default and the filter.
  return showBloomSheet(
    context: context,
    groups: [
      [
        for (final s in TrackSort.values)
          if (s.directional) item(s),
      ],
      [
        for (final s in TrackSort.values)
          if (!s.directional) item(s),
      ],
    ],
  );
}

class _InlineSearch extends StatelessWidget {
  const _InlineSearch({required this.query, required this.onQuery});

  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) => HeaderSearchField(
    hint: context.l.tlSearchHint,
    overPicture: true,
    onChanged: onQuery,
  );
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.listId,
    required this.tracks,
    required this.onEdit,
  });

  /// `all`, `fav` or a playlist id, also the queue's source.
  final String listId;

  final List<Track> tracks;

  /// Every library list has a pencil. Built-in sections edit contents and
  /// order, with no own name or cover.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = tracks.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: HeroPlayButton(
            sourceId: listId,
            onPlay: enabled
                ? () => ref
                      .read(playbackProvider.notifier)
                      .playQueue(tracks, 0, source: LibSource(listId))
                : null,
          ),
        ),
        const SizedBox(width: 10),
        GlassIconButton(
          icon: Bi.shuffle,
          size: 46,
          onTap: enabled
              ? () => ref
                    .read(playbackProvider.notifier)
                    .playQueueShuffled(tracks, source: LibSource(listId))
              : null,
        ),
        const SizedBox(width: 10),
        GlassIconButton(icon: Bi.pen, size: 46, onTap: onEdit),
      ],
    );
  }
}

/// A playlist's three-dot sheet, shared by its page and its library tile.
Future<void> showPlaylistMenu(
  BuildContext context,
  WidgetRef ref,
  UserPlaylist playlist,
  List<Track> tracks,
) async {
  void play({bool shuffle = false}) {
    if (tracks.isEmpty) return;
    final ctrl = ref.read(playbackProvider.notifier);
    if (shuffle) {
      ctrl.playQueueShuffled(tracks, source: LibSource(playlist.id));
    } else {
      ctrl.playQueue(tracks, 0, source: LibSource(playlist.id));
    }
  }

  // With no own cover the first track plays that role, as in the screen's hero.
  final cover = playlist.cover ?? (tracks.isEmpty ? null : tracks.first.cover);

  // Offline contents are counted before the sheet opens: `watch` isn't
  // available in its handlers, and `read` in an item would give the state at
  // press time.
  final offlineStatus = listOfflineState(
    ref.read(offlineProvider),
    ref.read(offlineProvider.notifier),
    tracks,
  );
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

  await showBloomSheet(
    context: context,
    header: SheetHero(
      cover: cover,
      title: playlist.name,
      // The same line as on the library's card.
      subtitleWidget: ListMeta(
        tracks: tracks,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
      ),
      meta: sheetDateMeta(context, l10n.commonCreatedOn, playlist.createdAt),
    ),
    bar: [
      SheetAction(
        icon: Bi.playBold,
        label: context.l.commonPlay,
        onTap: tracks.isEmpty ? null : play,
      ),
      SheetAction(
        icon: Bi.shuffle,
        label: context.l.commonShuffle,
        onTap: tracks.isEmpty ? null : () => play(shuffle: true),
      ),
      ...queueSheetActions(
        context,
        ref,
        tracks,
        source: LibSource(playlist.id),
      ),
    ],
    groups: [
      [
        // THIS playlist's batch is downloading now: the only fitting thing is
        // stopping it. Another batch doesn't change the items: stopping it from
        // here would surprise, and `downloadAll` itself says it's busy with
        // another list.
        if (ref.read(offlineProvider).batch?.sourceId == playlist.id)
          SheetAction(
            icon: Bi.close,
            label: context.l.tlStopSaving,
            onTap: () => ref.read(offlineProvider.notifier).cancelBatch(),
          )
        // Download all makes sense while unsaved tracks remain; when all are on
        // the device it becomes remove.
        else if (offlineStatus.total > 0) ...[
          SheetAction(
            icon: offlineStatus.all
                ? Bi.trashBinTrash
                : Bi.downloadMinimalistic,
            label: offlineStatus.all
                ? context.l.tlRemoveOffline
                : context.l.tlListenOffline(
                    offlineStatus.total - offlineStatus.cached,
                  ),
            subtitle: offlineStatus.all ? null : context.l.tlOfflineHint,
            onTap: () => offlineStatus.all
                ? removeListOffline(messenger, l10n, ref, tracks)
                : downloadListOffline(
                    messenger,
                    l10n,
                    ref,
                    playlist.id,
                    tracks,
                  ),
          ),
          if (canSaveFiles)
            SheetAction(
              icon: Bi.downloadMinimalistic,
              label: context.l.tlDownloadFiles(offlineStatus.total),
              subtitle: context.l.tlFilesHint,
              onTap: () =>
                  saveListFiles(messenger, l10n, ref, playlist.id, tracks),
            ),
        ],
        // The same Refresh tracks as the header button: the sheet also opens
        // from a library tile, which has no header.
        if (playlist.sources.isNotEmpty)
          SheetAction(
            icon: Bi.refresh,
            label: context.l.tlRefreshTracks,
            subtitle: context.l.tlRefreshHint,
            onTap: () => refreshOnePlaylist(messenger, l10n, ref, playlist),
          ),
        SheetAction(
          icon: Bi.pin,
          label: playlist.pinned ? context.l.commonUnpin : context.l.commonPin,
          subtitle: playlist.pinned ? null : context.l.commonPinHint,
          onTap: () => ref
              .read(libraryProvider.notifier)
              .setPinned(libKeyOfPlaylist(playlist.id), !playlist.pinned),
        ),
        SheetAction(
          icon: Bi.import,
          label: context.l.tlMergeWith,
          subtitle: context.l.tlMergeHint,
          onTap: () => showMergeSheet(context, ref, playlist),
        ),
        // Transfer is a copy with another platform's tracks. An empty playlist
        // has nothing to transfer.
        if (tracks.isNotEmpty)
          SheetAction(
            icon: Bi.arrowRight,
            label: context.l.tlConvert,
            subtitle: context.l.tlConvertHint,
            onTap: () => showConvertSheet(context, ref, playlist, tracks),
          ),
        // Duplicate search runs right in the list, so I open the playlist
        // first, or the mode turns on where it can't be seen.
        if (tracks.isNotEmpty)
          SheetAction(
            icon: Bi.copy,
            label: context.l.tlFindDups,
            subtitle: context.l.tlFindDupsHint,
            onTap: () {
              context.go('/library/list/${playlist.id}');
              ref.read(dupsProvider.notifier).enter(playlist.id);
            },
          ),
        // A transfer file for one playlist, in the settings export format, so
        // the same import reads it.
        SheetAction(
          icon: Bi.export,
          label: context.l.tlExportPlaylist,
          subtitle: context.l.tlExportHint,
          onTap: () => _exportPlaylist(messenger, l10n, ref, playlist),
        ),
        // Name and cover edit only in edit mode: they show at once on the
        // header there, and the same ✕ undoes them.
      ],
      [
        SheetAction(
          icon: Bi.trashBinTrash,
          label: context.l.tlDeletePlaylist,
          danger: true,
          onTap: () {
            // Deletes at once with Undo in the toast: a playlist is just a list
            // of ids, cheap to bring back, and the tracks stay in the library.
            final lib = ref.read(libraryProvider.notifier);
            lib.deletePlaylist(playlist.id);
            context.go('/library');
            messenger.toast(
              l10n.tlPlaylistDeleted(playlist.name),
              action: ToastAction(
                fn: () => lib.restorePlaylist(playlist),
                // An own cover is a file in the app's directory, deleted only
                // when there's nothing left to undo, or a restored playlist
                // would have no picture.
                onExpire: () => deleteCover(playlist.cover),
              ),
            );
          },
        ),
        // With tracks is a separate item, not a question after the first:
        // removing a list and erasing music differ too much to hide behind the
        // same words.
        if (tracks.isNotEmpty)
          SheetAction(
            icon: Bi.trashBinTrash,
            label: context.l.tlDeletePlaylistWithTracks,
            danger: true,
            onTap: () {
              context.go('/library');
              _deletePlaylistWithTracks(messenger, l10n, ref, playlist, tracks);
            },
          ),
      ],
    ],
  );
}

/// Exports one playlist as a `.bloomplaylist` file. Cancelling the system
/// dialog is quiet.
Future<void> _exportPlaylist(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  WidgetRef ref,
  UserPlaylist playlist,
) async {
  final ok = await saveTextFile(
    playlistFileName(playlist.name),
    await buildExportBundle(playlist, ref.read(libraryProvider)),
  );
  if (ok) messenger.toast(l10n.sysExported, kind: ToastKind.success);
}

/// Deletes a playlist WITH its tracks, throughout: they leave the library,
/// likes and other playlists. History entries stay.
///
/// No second question, but Undo restores a snapshot of the whole library: this
/// delete can't be rebuilt piece by piece (see [LibraryController.snapshot]).
/// Files (offline copies, local tracks, the playlist's cover) go only when it's
/// too late to undo.
void _deletePlaylistWithTracks(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  WidgetRef ref,
  UserPlaylist playlist,
  List<Track> tracks,
) {
  final lib = ref.read(libraryProvider.notifier);
  final offline = ref.read(offlineProvider.notifier);
  final before = lib.snapshot();
  final own = localTracksOf(ref.read(libraryProvider), [
    for (final track in tracks) track.id,
  ]);

  for (final track in tracks) {
    lib.deleteTrack(track.id);
  }
  lib.deletePlaylist(playlist.id);

  messenger.toast(
    l10n.tlPlaylistAndTracksDeleted(playlist.name),
    action: ToastAction(
      fn: () => lib.restoreSnapshot(before),
      onExpire: () {
        for (final track in tracks) {
          unawaited(offline.remove(track.id));
        }
        unawaited(forgetLocalTracks(own));
        unawaited(deleteCover(playlist.cover));
      },
    ),
  );
}
