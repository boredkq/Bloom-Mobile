/// The library: a header (view and sort on the left, auto-refresh and create on
/// the right), big tabs (all, playlists, artists) and the cards as rows or a
/// grid. "All" stacks a section per kind; in the grid each is a row of cards
/// that scrolls sideways, its title leading to the kind's tab.
///
/// Long press opens a card's menu; with the default sort, pulling it moves it
/// among its kind (the pinned among the pinned).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/big_tabs.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/pressable.dart';
import '../../detail/detail_nav.dart';
import '../../offline/offline_actions.dart';
import '../../offline/offline_store.dart';
import '../lib_order_store.dart';
import '../pl_auto_store.dart';
import 'create_playlist_sheet.dart';
import 'list_hero.dart';
import 'pl_auto_sheet.dart';
import 'tracklist_screen.dart';

const double _kGap = 12;
const double _kSide = 16;
const double _kRowCover = 62;

/// What a card adds under its square: a title and a line, and one more line
/// for the built-in lists.
const double _kCaption = 48;
const double _kLine = 17;

double _captionOf(List<_Entry> entries) =>
    entries.any((e) => e.system != null) ? _kCaption + _kLine : _kCaption;

/// Cards stand three to the screen, in a row and in a grid alike.
double _cardWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width - 2 * _kSide - 2 * _kGap) / 3;

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final order = ref.watch(libOrderProvider);
    final l = context.l;

    final system = [_Entry.system('all'), _Entry.system('fav')];
    final playlists = order
        .arrangePlaylists(lib.playlists)
        .map(_Entry.playlist)
        .toList();
    final artists = order
        .arrange(
          lib.follows,
          name: (f) => f.artist.name,
          sidePos: (f) => f.sidePos,
          pinned: (f) => f.pinned,
        )
        .map(_Entry.artist)
        .toList();

    // A tab that emptied falls back to "all".
    final tab = order.tab == LibTab.artists && artists.isEmpty
        ? LibTab.all
        : order.tab;
    void go(LibTab t) => ref.read(libOrderProvider.notifier).setTab(t);

    final draggable = order.sort == LibSort.manual;
    List<Widget> kind(List<_Entry> entries) => order.grid
        ? [_GridSliver(entries: entries, draggable: draggable)]
        : [_RowsSliver(entries: entries, draggable: draggable)];
    Widget row(List<_Entry> entries) => SliverToBoxAdapter(
      child: _CardRow(entries: entries, draggable: draggable),
    );

    final slivers = switch (tab) {
      LibTab.all => [
        SliverToBoxAdapter(child: SectionLabel(l.libSystem)),
        order.grid ? row(system) : _RowsSliver(entries: system),
        if (playlists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionLabel(
              l.commonPlaylists,
              onTap: () => go(LibTab.playlists),
            ),
          ),
          order.grid
              ? row(playlists)
              : _RowsSliver(entries: playlists, draggable: draggable),
        ],
        if (artists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionLabel(
              l.libTabArtists,
              onTap: () => go(LibTab.artists),
            ),
          ),
          order.grid
              ? row(artists)
              : _RowsSliver(entries: artists, draggable: draggable),
        ],
      ],
      LibTab.playlists => [
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        ...kind([...system, ...playlists]),
      ],
      LibTab.artists => [
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        ...kind(artists),
      ],
    };

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const _TopBar(),
          BigTabs<LibTab>(
            tabs: [
              for (final t in LibTab.values)
                BigTab(
                  t,
                  t.label(l),
                  has: t != LibTab.artists || artists.isNotEmpty,
                ),
            ],
            current: tab,
            onPick: go,
          ),
          Expanded(
            child: _FadeSwap(
              value: (tab, order.grid),
              child: CustomScrollView(
                slivers: [
                  ...slivers,
                  const SliverBottomBarsInset(extra: _kSide),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// View and sort in one capsule on the left; auto-refresh and create on the
/// right. A button is in the accent while its setting is on.
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final order = ref.watch(libOrderProvider);
    final autoOn = ref.watch(plAutoProvider).enabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kSide, 10, _kSide, 14),
      child: Row(
        children: [
          GlassBox(
            borderRadius: BorderRadius.circular(999),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CapsuleButton(
                  icon: order.grid ? Bi.list : Bi.widget2,
                  onTap: () =>
                      ref.read(libOrderProvider.notifier).setGrid(!order.grid),
                ),
                _CapsuleButton(
                  icon: Bi.sort,
                  color: order.sort != LibSort.manual ? t.accent : null,
                  onTap: () => _showSortSheet(context, ref),
                ),
              ],
            ),
          ),
          const Spacer(),
          CircleIconButton(
            icon: Bi.clockCircle,
            color: autoOn ? t.accent : null,
            tooltip: context.l.libAutoRefreshTooltip,
            onTap: () => showPlAutoSheet(context, ref),
          ),
          const SizedBox(width: 10),
          CircleIconButton(
            icon: Bi.add,
            tooltip: context.l.commonCreatePlaylist,
            onTap: () => showCreatePlaylistSheet(context, ref),
          ),
        ],
      ),
    );
  }
}

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({required this.icon, required this.onTap, this.color});

  final BloomGlyph icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: SizedBox(
      width: kHeaderControl - 4,
      height: kHeaderControl,
      child: BloomIcon(icon, size: 22, color: color ?? context.bloom.iconFg),
    ),
  );
}

/// One card of the library: a built-in list ("all" / "fav"), a playlist or a
/// followed artist.
class _Entry {
  _Entry.system(String this.system) : playlist = null, follow = null;
  _Entry.playlist(UserPlaylist this.playlist) : system = null, follow = null;
  _Entry.artist(FollowedArtist this.follow) : system = null, playlist = null;

  final String? system;
  final UserPlaylist? playlist;
  final FollowedArtist? follow;

  String get key => switch (this) {
    _Entry(:final String system) => system,
    _Entry(:final UserPlaylist playlist) => libKeyOfPlaylist(playlist.id),
    _ => libKeyOfArtist(follow!.artist.id),
  };

  bool get pinned => playlist?.pinned ?? follow?.pinned ?? false;

  /// The built-in lists keep their places.
  bool get movable => system == null;
}

/// Moves a card and writes its kind's new order whole.
void _move(WidgetRef ref, List<_Entry> entries, int from, int to) {
  final moved = [...entries];
  moved.insert(to, moved.removeAt(from));
  ref.read(libraryProvider.notifier).reorderCards([
    for (final e in moved)
      if (e.movable) e.key,
  ]);
}

/// Wraps the card at [i] of [entries] for the menu and dragging.
Widget _cell(
  BuildContext context,
  WidgetRef ref,
  List<_Entry> entries,
  int i, {
  required bool draggable,
  required double width,
  required Widget child,
}) {
  final e = entries[i];
  final playlist = e.playlist;
  final follow = e.follow;
  return _DragCell(
    key: ValueKey(e.key),
    index: i,
    width: width,
    enabled: draggable && e.movable,
    accepts: (from) =>
        entries[from].movable && entries[from].pinned == e.pinned,
    onMove: (from, to) => _move(ref, entries, from, to),
    onMenu: playlist != null
        ? () => showPlaylistMenu(
            context,
            ref,
            playlist,
            ref.read(libraryProvider).tracksOf(playlist),
          )
        : follow != null
        ? () => _showArtistMenu(context, ref, follow)
        : null,
    child: child,
  );
}

class _RowsSliver extends ConsumerWidget {
  const _RowsSliver({required this.entries, this.draggable = false});

  final List<_Entry> entries;
  final bool draggable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    return SliverList.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) => _cell(
        context,
        ref,
        entries,
        i,
        draggable: draggable,
        width: width,
        child: _LibRow(entry: entries[i]),
      ),
    );
  }
}

/// A kind in "all" with the grid on: one row of cards scrolling sideways.
class _CardRow extends ConsumerWidget {
  const _CardRow({required this.entries, required this.draggable});

  final List<_Entry> entries;
  final bool draggable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = _cardWidth(context);
    return SizedBox(
      height: width + _captionOf(entries),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kSide),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: _kGap),
        itemBuilder: (context, i) => SizedBox(
          width: width,
          child: _cell(
            context,
            ref,
            entries,
            i,
            draggable: draggable,
            width: width,
            child: _LibCard(entry: entries[i]),
          ),
        ),
      ),
    );
  }
}

/// A kind's tab with the grid on: three columns.
class _GridSliver extends ConsumerWidget {
  const _GridSliver({required this.entries, required this.draggable});

  final List<_Entry> entries;
  final bool draggable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cell = _cardWidth(context);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _kSide),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: _kGap,
          mainAxisSpacing: 14,
          mainAxisExtent: cell + _captionOf(entries),
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _cell(
            context,
            ref,
            entries,
            i,
            draggable: draggable,
            width: cell,
            child: _LibCard(entry: entries[i]),
          ),
          childCount: entries.length,
        ),
      ),
    );
  }
}

/// Where a card leads, and what flies into the page's header.
void _open(BuildContext context, _Entry e, CoverFlight? flight) {
  final system = e.system;
  final playlist = e.playlist;
  if (system != null) {
    context.go('/library/list/$system');
  } else if (playlist != null) {
    context.go('/library/list/${playlist.id}', extra: flight);
  } else {
    final artist = e.follow!.artist;
    openArtist(context, artist.id, initial: artist, flight: flight);
  }
}

CoverFlight? _flightOf(_Entry e, Object tag) {
  final image = e.playlist?.cover ?? e.follow?.artist.avatar;
  return image == null || image.isEmpty
      ? null
      : CoverFlight(tag: tag, image: image);
}

/// A card's square: the built-in list's tint, a playlist's cover (or the
/// collage of its tracks), an artist's round avatar.
Widget _art(
  BuildContext context,
  LibraryState lib,
  _Entry e,
  double size,
  CoverFlight? flight,
) {
  final system = e.system;
  final playlist = e.playlist;
  if (system != null) return _SystemArt(id: system, size: size);
  if (playlist != null) {
    return Cover(
      url: playlist.cover,
      size: size,
      flight: flight,
      overlay: SetEqualizer(setId: playlist.id),
      covers: lib.tracksOf(playlist).map((track) => track.cover),
    );
  }
  return Cover(
    url: e.follow!.artist.avatar,
    size: size,
    circle: true,
    flight: flight,
  );
}

/// The title: the pin after it, and before it the arrow of a playlist kept
/// offline whole.
Widget _title(
  BuildContext context,
  _Entry e,
  TextStyle? style, {
  bool kept = false,
}) {
  final t = context.bloom;
  final name = switch (e.system) {
    'all' => context.l.commonAllTracks,
    'fav' => context.l.commonFavorites,
    _ => e.playlist?.name ?? e.follow!.artist.name,
  };
  return Row(
    children: [
      if (kept) ...[
        BloomIcon(Bi.downloadMinimalistic, size: 13, color: t.text2),
        const SizedBox(width: 4),
      ],
      Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
      if (e.pinned) ...[
        const SizedBox(width: 4),
        BloomIcon(Bi.pin, size: 13, color: t.text2),
      ],
    ],
  );
}

/// The lines under the title. The built-in lists say what they are, then the
/// count; a playlist only its count, with how much of it is kept offline when
/// that's only part of it. [kept]: all of it is.
({bool kept, List<String> lines}) _lines(
  BuildContext context,
  WidgetRef ref,
  _Entry e,
) {
  final l = context.l;
  if (e.follow != null) return (kept: false, lines: const <String>[]);
  final lib = ref.watch(libraryProvider);
  String count(int n) => n > 0 ? l.tracksCount(n) : l.libNoTracks;
  final playlist = e.playlist;
  if (playlist == null) {
    final fav = e.system == 'fav';
    return (
      kept: false,
      lines: [
        fav ? l.libLikedSub : l.libAllTracksSub,
        count(fav ? lib.favs.length : lib.inLib.length),
      ],
    );
  }
  final off = listOfflineState(
    ref.watch(offlineProvider),
    ref.read(offlineProvider.notifier),
    lib.tracksOf(playlist),
  );
  final n = count(playlist.trackIds.length);
  return (
    kept: off.all,
    lines: [off.any && !off.all ? '$n · ${off.cached}/${off.total}' : n],
  );
}

Widget _line(String text, TextStyle? style) =>
    Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

/// "All tracks" and liked, with the bars while one is the queue.
class _SystemArt extends StatelessWidget {
  const _SystemArt({required this.id, required this.size});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final radius = BorderRadius.circular(Cover.defaultRadius(t));
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          OutlineArt(
            icon: systemListGlyph(id)!,
            iconSize: (size * 0.3).roundToDouble(),
            borderRadius: radius,
          ),
          ClipRRect(
            borderRadius: radius,
            child: SetEqualizer(setId: id),
          ),
        ],
      ),
    );
  }
}

class _LibRow extends ConsumerStatefulWidget {
  const _LibRow({required this.entry});

  final _Entry entry;

  @override
  ConsumerState<_LibRow> createState() => _LibRowState();
}

class _LibRowState extends ConsumerState<_LibRow> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final theme = Theme.of(context).textTheme;
    final flight = _flightOf(e, _tag);
    final sub = theme.bodySmall?.copyWith(fontSize: 13);
    final (:kept, :lines) = _lines(context, ref, e);
    return InkWell(
      onTap: () => _open(context, e, flight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kSide, vertical: 8),
        child: Row(
          children: [
            _art(context, ref.watch(libraryProvider), e, _kRowCover, flight),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(
                    context,
                    e,
                    theme.titleMedium?.copyWith(fontSize: 16),
                    kept: kept,
                  ),
                  const SizedBox(height: 2),
                  if (e.follow != null)
                    _line(context.l.commonArtist, sub)
                  else
                    for (final line in lines) _line(line, sub),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibCard extends ConsumerStatefulWidget {
  const _LibCard({required this.entry});

  final _Entry entry;

  @override
  ConsumerState<_LibCard> createState() => _LibCardState();
}

class _LibCardState extends ConsumerState<_LibCard> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final follow = e.follow;
    if (follow != null) {
      return ArtistCard(
        artist: follow.artist,
        size: null,
        centerLabel: true,
        pinned: follow.pinned,
      );
    }
    final theme = Theme.of(context).textTheme;
    final flight = _flightOf(e, _tag);
    final (:kept, :lines) = _lines(context, ref, e);
    return LayoutBuilder(
      builder: (context, box) => Pressable(
        onTap: () => _open(context, e, flight),
        scale: 0.97,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _art(context, ref.watch(libraryProvider), e, box.maxWidth, flight),
            const SizedBox(height: 8),
            _title(
              context,
              e,
              theme.titleSmall?.copyWith(fontSize: 14),
              kept: kept,
            ),
            const SizedBox(height: 2),
            for (final line in lines) _line(line, theme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Swaps the content without a shift: the old fades out, only then the new
/// fades in, so their covers never show through each other.
class _FadeSwap extends StatefulWidget {
  const _FadeSwap({required this.value, required this.child});

  /// What counts as new content; while it holds, the child updates in place.
  final Object value;

  final Widget child;

  static const Duration half = Duration(milliseconds: 90);

  @override
  State<_FadeSwap> createState() => _FadeSwapState();
}

class _FadeSwapState extends State<_FadeSwap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: _FadeSwap.half,
    value: 1,
  );

  late Widget _shown = widget.child;

  /// What replaces [_shown] once the old has faded.
  Widget? _pending;

  @override
  void initState() {
    super.initState();
    _fade.addStatusListener((status) {
      if (status != AnimationStatus.dismissed || _pending == null) return;
      setState(() {
        _shown = _pending!;
        _pending = null;
      });
      _fade.forward();
    });
  }

  @override
  void didUpdateWidget(_FadeSwap old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) {
      if (_pending == null) {
        _shown = widget.child;
      } else {
        _pending = widget.child;
      }
      return;
    }
    _pending = widget.child;
    // A second switch in a row: nothing is left to fade out.
    if (_fade.isDismissed) {
      _shown = widget.child;
      _pending = null;
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: _shown);
}

/// A card that can be picked up and dropped on another's place. A long press
/// held still opens the menu instead, since the long press is all a card has.
class _DragCell extends StatefulWidget {
  const _DragCell({
    super.key,
    required this.index,
    required this.width,
    required this.enabled,
    required this.accepts,
    required this.onMove,
    required this.onMenu,
    required this.child,
  });

  final int index;

  /// The picture under the finger has no cell to size it.
  final double width;
  final bool enabled;
  final bool Function(int from) accepts;
  final void Function(int from, int to) onMove;
  final VoidCallback? onMenu;
  final Widget child;

  @override
  State<_DragCell> createState() => _DragCellState();
}

class _DragCellState extends State<_DragCell> {
  /// How far the finger went; under [_slop] it was a hold, not a move.
  double _travel = 0;

  static const double _slop = 12;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return GestureDetector(
        onLongPress: widget.onMenu,
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      );
    }
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) =>
          d.data != widget.index && widget.accepts(d.data),
      onAcceptWithDetails: (d) => widget.onMove(d.data, widget.index),
      builder: (context, candidate, _) {
        final hovered = candidate.isNotEmpty;
        return LongPressDraggable<int>(
          data: widget.index,
          onDragStarted: () {
            _travel = 0;
            HapticFeedback.selectionClick();
          },
          onDragUpdate: (d) => _travel += d.delta.distance,
          onDragEnd: (d) {
            if (!d.wasAccepted && _travel < _slop) widget.onMenu?.call();
          },
          feedback: Material(
            type: MaterialType.transparency,
            child: Opacity(
              opacity: 0.9,
              child: SizedBox(width: widget.width, child: widget.child),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: widget.child),
          // The target only shrinks: a frame read as a foreign element.
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            scale: hovered ? 0.94 : 1,
            child: widget.child,
          ),
        );
      },
    );
  }
}

Future<void> _showSortSheet(BuildContext context, WidgetRef ref) {
  final t = context.bloom;
  final active = ref.read(libOrderProvider).sort;
  return showBloomSheet(
    context: context,
    groups: [
      [
        for (final sort in LibSort.values)
          SheetAction(
            icon: sort.icon,
            label: sort.label(context.l),
            onTap: () => ref.read(libOrderProvider.notifier).setSort(sort),
            trailing: sort == active
                ? BloomIcon(Bi.checkCircleBold, size: 18, color: t.accent)
                : null,
          ),
      ],
    ],
  );
}

Future<void> _showArtistMenu(
  BuildContext context,
  WidgetRef ref,
  FollowedArtist followed,
) {
  final artist = followed.artist;
  final pinned = followed.pinned;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

  return showBloomSheet(
    context: context,
    header: SheetHero(
      cover: artist.avatar,
      title: artist.name,
      subtitle: context.l.commonArtist,
    ),
    groups: [
      [
        SheetAction(
          icon: Bi.pin,
          label: pinned ? context.l.commonUnpin : context.l.commonPin,
          subtitle: pinned ? null : context.l.commonPinHint,
          onTap: () => ref
              .read(libraryProvider.notifier)
              .setPinned(libKeyOfArtist(artist.id), !pinned),
        ),
      ],
      [
        SheetAction(
          icon: Bi.userCheckRoundedBold,
          label: context.l.commonUnfollow,
          danger: true,
          onTap: () {
            ref.read(libraryProvider.notifier).toggleFollow(artist);
            messenger.toast(l10n.unfollowedToast);
          },
        ),
      ],
    ],
  );
}
