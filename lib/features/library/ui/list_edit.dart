/// A library list's edit mode: checkboxes on rows, dragging, a bottom action
/// bar over the selection, editing a playlist's name and cover.
///
/// What changes the list ITSELF (contents, order, name, cover, refresh sources)
/// gathers in a draft and writes at once on ✓; ✕ throws out the whole draft. To
/// playlist and to favourites write to OTHER lists, which ✕ couldn't undo, so
/// they apply at once.
///
/// Remove depends on the list: from a playlist the track just leaves, from
/// favourites the like goes, and from all tracks it's deleted THROUGHOUT, so
/// that asks again before writing.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../features/offline/offline_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/sticky_hero.dart';
import '../../../shared/ui/track_actions.dart';
import '../local_tracks.dart';
import 'list_hero.dart';
import 'pl_sources_editor.dart';

class ListEditor extends ConsumerStatefulWidget {
  const ListEditor({
    super.key,
    required this.listId,
    required this.title,
    required this.playlist,
    required this.tracks,
    required this.onClose,
  });

  /// `all`, `fav` or a user playlist's id.
  final String listId;

  final String title;

  /// `null` for a built-in section: its name and cover can't be edited.
  final UserPlaylist? playlist;

  /// Source contents in its own order, with NO search or sort: editing half a
  /// list, and in the wrong order, makes no sense.
  final List<Track> tracks;

  /// Leaves edit mode, by ✓ and by ✕.
  final VoidCallback onClose;

  @override
  ConsumerState<ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends ConsumerState<ListEditor> {
  late final List<String> _idsWas = [for (final t in widget.tracks) t.id];

  late final List<Track> _tracks = [...widget.tracks];
  late String _name = widget.title;
  late String? _cover = widget.playlist?.cover;
  late List<PlSourceRef> _sources = widget.playlist?.sources ?? const [];

  final Set<String> _selected = {};

  /// The title is being edited: the bottom bar becomes an input for now.
  bool _renaming = false;

  /// ✕ on a draft asks with a second press: the app has no modals for this.
  bool _armedCancel = false;

  /// ✓ asks the same way, only in all tracks and only if something was removed:
  /// there it's a delete throughout.
  bool _armedPurge = false;

  /// The track being dragged right now; `null` if none.
  String? _dragId;

  UserPlaylist? get _playlist => widget.playlist;

  List<String> get _ids => [for (final t in _tracks) t.id];

  List<Track> get _selectedTracks => [
    for (final t in _tracks)
      if (_selected.contains(t.id)) t,
  ];

  bool get _allSelected =>
      _tracks.isNotEmpty && _selected.length == _tracks.length;

  /// How many rows this drag moves: a selected row carries the whole block, any
  /// other just itself.
  int get _dragGroup {
    final id = _dragId;
    return id != null && _selected.contains(id) ? _selected.length : 1;
  }

  /// The row moves with the block, but the list has one proxy, and this row
  /// isn't under the finger.
  bool _movingWithDrag(String id) =>
      _dragGroup > 1 && id != _dragId && _selected.contains(id);

  /// ALL selected are liked: the bar's heart is filled and the next press
  /// removes the like. That's why I listen to the library: a like bypasses the
  /// draft and goes straight to favourites.
  bool get _selectedAllFav {
    final lib = ref.watch(libraryProvider);
    return _selected.isNotEmpty &&
        _selectedTracks.every((t) => lib.isFav(t.id));
  }

  bool get _dirty =>
      _name != widget.title ||
      _cover != _playlist?.cover ||
      !listEquals(_ids, _idsWas) ||
      _sourcesChanged;

  /// Sources compare by collection id: a platform may give another title, with
  /// the tie unchanged.
  bool get _sourcesChanged => !listEquals(
    [for (final s in _sources) s.id],
    [for (final s in _playlist?.sources ?? const <PlSourceRef>[]) s.id],
  );

  // ── Editing ───────────────────────────────────────────────────────────────

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  void _toggleAll() => setState(() {
    final all = _allSelected;
    _selected.clear();
    if (!all) _selected.addAll(_ids);
  });

  /// Dragging a selected row moves the whole selection as one block: otherwise
  /// tracks gathered across the list go one by one.
  ///
  /// Counted by an anchor rather than indices, the first row below the drop
  /// point, which doesn't move: removing a block shifts indices around it, and
  /// a `to--` correction can't help.
  void _reorder(int from, int to) => setState(() {
    final dragged = _tracks[from];
    final group = _selected.contains(dragged.id) && _selected.length > 1
        ? {..._selected}
        : {dragged.id};
    String? anchor;
    for (var i = to; i < _tracks.length; i++) {
      if (!group.contains(_tracks[i].id)) {
        anchor = _tracks[i].id;
        break;
      }
    }
    final moving = [
      for (final t in _tracks)
        if (group.contains(t.id)) t,
    ];
    _tracks.removeWhere((t) => group.contains(t.id));
    // No anchor: dropped below all remaining rows, and the block goes to the
    // end.
    _tracks.insertAll(
      anchor == null
          ? _tracks.length
          : _tracks.indexWhere((t) => t.id == anchor),
      moving,
    );
  });

  void _removeSelected() => setState(() {
    _tracks.removeWhere((t) => _selected.contains(t.id));
    _selected.clear();
  });

  /// Likes the selection at once, not in the draft: favourites is another list.
  /// A toggle: while any selected track has no like the rest catch up, and once
  /// all have it the same press removes it. The selection stays, or there'd be
  /// nothing to undo with.
  void _favSelected() {
    final lib = ref.read(libraryProvider.notifier);
    final was = ref.read(libraryProvider);
    final batch = _selectedTracks;
    if (batch.isEmpty) return;
    final off = batch.every((t) => was.isFav(t.id));
    var n = 0;
    for (final track in batch) {
      if (was.isFav(track.id) != off) continue;
      lib.toggleFav(track);
      n++;
    }
    final tracks = context.l.tracksCount(n);
    toaster.show(
      off
          ? context.l.leRemovedFromFavorites(tracks)
          : context.l.leAddedToFavorites(tracks),
      kind: off ? ToastKind.warn : ToastKind.success,
    );
  }

  /// Sources open as a sheet from the header: on the page the section stood
  /// between cover and tracks and read as part of the list's first row.
  void _openSources() {
    unawaited(
      showPlSourcesSheet(
        context,
        sources: _sources,
        onChanged: (next) => setState(() => _sources = next),
      ),
    );
  }

  Future<void> _addSelectedToPlaylist() async {
    final batch = _selectedTracks;
    await showAddTracksToPlaylistSheet(context, ref, batch, newName: _name);
    if (!mounted) return;
    setState(_selected.clear);
  }

  /// A new cover saves to a file at once, so the previous PICK (not the
  /// playlist's original cover) gets cleaned up here: nobody needs it.
  Future<void> _pickCover() async {
    final picked = await pickCover();
    if (picked == null || !mounted) return;
    final stale = _cover != _playlist?.cover ? _cover : null;
    setState(() => _cover = picked);
    unawaited(deleteCover(stale));
  }

  /// Removes the cover: the playlist returns to a mosaic of track covers. Its
  /// own picture still lives: only ✓ deletes the file, or ✕ would return a
  /// cover no longer on disk. A file just picked and unwritten goes right away,
  /// as in [_pickCover].
  void _removeCover() {
    final stale = _cover != _playlist?.cover ? _cover : null;
    setState(() => _cover = null);
    unawaited(deleteCover(stale));
  }

  // ── Leaving ───────────────────────────────────────────────────────────────

  void _commit() {
    final lib = ref.read(libraryProvider.notifier);
    final left = _ids.toSet();
    final gone = [
      for (final id in _idsWas)
        if (!left.contains(id)) id,
    ];

    switch (widget.listId) {
      case 'all':
        // This deletes THROUGHOUT, so ✓ asks with a second press.
        if (gone.isNotEmpty && !_armedPurge) {
          setState(() => _armedPurge = true);
          toaster.show(
            context.l.leDeleteArm(context.l.tracksCount(gone.length)),
            kind: ToastKind.warn,
          );
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _armedPurge = false);
          });
          return;
        }
        // Offline copies of deleted tracks are junk nothing will refer to.
        final offline = ref.read(offlineProvider.notifier);
        for (final id in gone) {
          unawaited(offline.remove(id));
        }
        // The same for local files, and BEFORE editing the list: afterwards the
        // tracks are gone from the store, with no way to know which had a copy.
        unawaited(
          forgetLocalTracks(localTracksOf(ref.read(libraryProvider), gone)),
        );
        lib.setLibraryTracks(_ids);
      case 'fav':
        lib.setFavTracks(_ids);
      default:
        final pl = _playlist;
        if (pl != null) {
          lib.setPlaylistTracks(pl.id, _ids);
          if (_name.trim().isNotEmpty) lib.renamePlaylist(pl.id, _name);
          if (_sourcesChanged) lib.setPlaylistSources(pl.id, _sources);
          if (_cover != pl.cover) {
            lib.setPlaylistCover(pl.id, _cover);
            // The old own picture is a file in the app's directory.
            unawaited(deleteCover(pl.cover));
          }
        }
    }
    widget.onClose();
  }

  void _cancel() {
    // An empty draft has nothing to discard, so ✕ leaves at once.
    if (_dirty && !_armedCancel) {
      setState(() => _armedCancel = true);
      toaster.show(context.l.leDiscardArm, kind: ToastKind.warn);
      // Cools down by itself, or it waits for a stray second tap.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armedCancel = false);
      });
      return;
    }
    // A picked but unwritten cover is a file nothing refers to now.
    if (_cover != _playlist?.cover) unawaited(deleteCover(_cover));
    widget.onClose();
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // The edit bar floats over the list, with the mini player and tab bar under
    // it: it clears their height from above, the list from below.
    final inset = bottomBarsInset(context);

    return PopScope(
      // System Back in edit mode is ✕, not leaving the page.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _EditHero(
                listId: widget.listId,
                name: _name,
                cover: _cover,
                tracks: _tracks,
                // Only a playlist has its own cover and name.
                editable: _playlist != null,
                height: width * 0.62,
                cancelArmed: _armedCancel,
                doneArmed: _armedPurge,
                onCancel: _cancel,
                onDone: _commit,
                onCover: _pickCover,
                // Nothing to remove with no cover: a list with no picture has a
                // track mosaic in the header anyway.
                onCoverRemove: (_cover?.isEmpty ?? true) ? null : _removeCover,
                onRename: () => setState(() => _renaming = true),
                // Only a playlist has sources: built-in sections have nowhere
                // to pull from.
                sources: _playlist == null ? null : _sources.length,
                onSources: _openSources,
              ),
              SliverPadding(
                // Room below for the floating bar and shell bars: the last row
                // shouldn't stay under them.
                padding: EdgeInsets.fromLTRB(8, 10, 8, 92 + inset),
                sliver: SliverReorderableList(
                  itemCount: _tracks.length,
                  onReorder: _reorder,
                  // Only I know what's moving: the list drags one row and knows
                  // nothing of selection.
                  onReorderStart: (i) =>
                      setState(() => _dragId = _tracks[i].id),
                  onReorderEnd: (_) => setState(() => _dragId = null),
                  proxyDecorator: (child, _, _) {
                    final card = trackRowDragged(context, child);
                    final n = _dragGroup;
                    return n < 2 ? card : _DragDeck(count: n, child: card);
                  },
                  itemBuilder: (context, i) {
                    final track = _tracks[i];
                    return _EditRow(
                      key: ValueKey(track.id),
                      index: i,
                      track: track,
                      selected: _selected.contains(track.id),
                      // It moves with the block but isn't under the finger, so
                      // it dims to show it's in hand.
                      ghost: _movingWithDrag(track.id),
                      onTap: () => _toggle(track.id),
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + inset,
            child: _renaming
                ? _RenameBar(
                    initial: _name,
                    onCancel: () => setState(() => _renaming = false),
                    onDone: (value) => setState(() {
                      final name = value.trim();
                      if (name.isNotEmpty) _name = name;
                      _renaming = false;
                    }),
                  )
                : _EditBar(
                    count: _selected.length,
                    total: _tracks.length,
                    allSelected: _allSelected,
                    // In favourites every row is liked already, so a bin takes
                    // its place, which also removes the like.
                    canFav: widget.listId != 'fav',
                    favOn: _selectedAllFav,
                    onToggleAll: _tracks.isEmpty ? null : _toggleAll,
                    onAdd: _addSelectedToPlaylist,
                    onFav: _favSelected,
                    onRemove: _removeSelected,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Edit mode's header: the same cover, with ✕ and ✓ instead of back, sort and
/// search, a picture button in the centre and a pencil by the title. No Play
/// row, but the same height as usual, so entering edit doesn't jolt it. Title
/// and caption just drop to the cover's bottom edge.
///
/// A sliver, like the usual list header: the ✕/✓ row stays at the top.
class _EditHero extends StatelessWidget {
  const _EditHero({
    required this.listId,
    required this.name,
    required this.cover,
    required this.tracks,
    required this.editable,
    required this.height,
    required this.cancelArmed,
    required this.doneArmed,
    required this.onCancel,
    required this.onDone,
    required this.onCover,
    required this.onCoverRemove,
    required this.onRename,
    required this.sources,
    required this.onSources,
  });

  final String listId;
  final String name;
  final String? cover;
  final List<Track> tracks;

  /// Whether name and cover can be edited (a playlist only).
  final bool editable;

  final double height;

  /// ✕ is armed: the next tap discards the draft.
  final bool cancelArmed;

  /// ✓ is armed: the next tap deletes removed tracks throughout.
  final bool doneArmed;

  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onCover;

  /// Removes the cover; `null` if the list has no own picture.
  final VoidCallback? onCoverRemove;

  final VoidCallback onRename;

  /// Sources tied. `null` for a built-in section, which has no sources button.
  final int? sources;

  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return StickyHero(
      // The same `+ 76` as the usual list header's Play row: both heights come
      // from one [height].
      height: height + 76,
      background: Stack(
        fit: StackFit.expand,
        children: [
          HeroCover(
            child: ListHeroBackground(
              listId: listId,
              cover: cover,
              tracks: tracks,
            ),
          ),
          if (editable)
            Center(
              // A bin beside it rather than a cross on the button: a nail-sized
              // target on a cover gets missed more than hit.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassIconButton(
                    icon: Bi.gallery,
                    size: 66,
                    iconSize: 28,
                    onTap: onCover,
                  ),
                  if (onCoverRemove case final remove?) ...[
                    const SizedBox(width: 14),
                    GlassIconButton(
                      icon: Bi.trashBinTrash,
                      size: 52,
                      iconSize: 23,
                      onTap: remove,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
      // ✕ and ✓ stay on top: otherwise finishing a long list's edit means
      // scrolling back.
      barHeight: kHeaderControl,
      // An armed button is red, like the bin in the edit bar: with no modal
      // it's all that shows what a second tap does.
      bar: Row(
        children: [
          _BarButton(icon: Bi.close, armed: cancelArmed, onTap: onCancel),
          const Spacer(),
          _BarButton(icon: Bi.check, armed: doneArmed, onTap: onDone),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.headlineSmall?.copyWith(fontSize: 30),
                ),
              ),
              if (editable) ...[
                const SizedBox(width: 8),
                // A pencil right by the title with no plate: part of the
                // heading, not another header button.
                Pressable(
                  onTap: onRename,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: BloomIcon(
                      Bi.pen,
                      size: 21,
                      color: context.bloom.text,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(context.l.tracksCount(tracks.length), style: theme.bodyMedium),
          if (sources case final count?) ...[
            const SizedBox(height: 10),
            _SourcesButton(count: count, onTap: onSources),
          ],
        ],
      ),
    );
  }
}

/// Sources button in the edit header: a glass pill with a tie count. Glass
/// rather than a theme plate: it stands on the cover, like the header's
/// buttons, in the same ink.
class _SourcesButton extends StatelessWidget {
  const _SourcesButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final ink = context.bloom.text;

    return Pressable(
      onTap: onTap,
      child: GlassSurface(
        shape: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BloomIcon(Bi.link, size: 18, color: ink),
              const SizedBox(width: 9),
              Text(
                context.l.psTitle,
                style: theme.titleMedium?.copyWith(fontSize: 14, color: ink),
              ),
              // Zero isn't shown: an empty count on the very button that makes
              // the first tie just confuses.
              if (count > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: theme.bodySmall?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              BloomIcon(
                Bi.altArrowRight,
                size: 20,
                color: ink.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edit header button. Armed it's red: the next tap loses something.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.armed,
    required this.onTap,
  });

  final BloomGlyph icon;
  final bool armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GlassIconButton(
      icon: icon,
      color: armed ? t.danger : null,
      background: armed ? t.danger.withValues(alpha: 0.16) : null,
      onTap: onTap,
    );
  }
}

/// List row in edit mode: checkbox, cover, title and duration. A tap selects it
/// rather than starting a track. The cover is the drag handle, as in the usual
/// list and queue.
class _EditRow extends StatelessWidget {
  const _EditRow({
    super.key,
    required this.index,
    required this.track,
    required this.selected,
    required this.ghost,
    required this.onTap,
  });

  /// Row number for dragging. `null` where the order isn't mine, leaving
  /// nowhere to drag.
  final int? index;
  final Track track;
  final bool selected;

  /// A row in hand with the selected block: while dragged it dims in its old
  /// place.
  final bool ghost;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final drag = index;
    final Widget cover = Cover(url: track.cover, size: 52);

    return AnimatedOpacity(
      opacity: ghost ? 0.3 : 1,
      duration: const Duration(milliseconds: 120),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius * 0.85),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              BloomCheck(on: selected),
              const SizedBox(width: 12),
              if (drag == null)
                cover
              else
                ReorderableDelayedDragStartListener(index: drag, child: cover),
              const SizedBox(width: 12),
              Expanded(
                child: TwoLines(
                  track.name,
                  track.artist,
                  subStyle: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: t.text2),
                ),
              ),
              const SizedBox(width: 10),
              DurationPill(track: track, active: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drag card when a whole selected block moves: more plates peek out under it,
/// with a count in the corner. `SliverReorderableList` has one proxy, so one
/// row is always under the finger, and with no deck a block's move looks like
/// one track's.
class _DragDeck extends StatelessWidget {
  const _DragDeck({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final shape = BorderRadius.circular(t.radius * 0.85);

    // A plate the card's height, shifted down by [inset], so exactly that shift
    // shows. A row-sized proxy won't clip it: the overlay clips only at the
    // screen's edge.
    Widget sheet(double inset, Color color) => Positioned(
      left: inset,
      right: inset,
      top: inset,
      bottom: -inset,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: shape),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The far plate only if the block really has more than two rows.
        if (count > 2) sheet(13, Color.lerp(t.pill, t.bg, 0.55)!),
        sheet(6.5, Color.lerp(t.pill, t.bg, 0.28)!),
        child,
        Positioned(
          top: -9,
          right: -4,
          child: Material(
            type: MaterialType.transparency,
            elevation: 6,
            shadowColor: Colors.black,
            borderRadius: BorderRadius.circular(999),
            child: CountBadge(count, height: 24, size: 13, side: 9),
          ),
        ),
      ],
    );
  }
}

/// Edit mode's floating bar: select all with a selection count on the left,
/// actions on the right. With nothing selected there are no actions, and it
/// just shows the row count.
class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.count,
    required this.total,
    required this.allSelected,
    required this.canFav,
    required this.favOn,
    required this.onToggleAll,
    required this.onAdd,
    required this.onFav,
    required this.onRemove,
  });

  final int count;
  final int total;
  final bool allSelected;
  final bool canFav;

  /// All selected are liked: the heart is filled and removes the like.
  final bool favOn;

  final VoidCallback? onToggleAll;
  final VoidCallback onAdd;
  final VoidCallback onFav;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final some = count > 0;

    return _BarShell(
      child: Row(
        children: [
          // The count presses along with the tick: the two read as one control.
          Semantics(
            checked: allSelected,
            enabled: onToggleAll != null,
            child: Pressable(
              onTap: onToggleAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Opacity(
                      opacity: onToggleAll == null ? 0.35 : 1,
                      child: BloomCheck(on: allSelected),
                    ),
                    const SizedBox(width: 12),
                    // The denominator is muted: selected is what's counted, and
                    // the total only measures how near that is to all.
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$count',
                            style: TextStyle(color: some ? t.text : t.text2),
                          ),
                          TextSpan(
                            text: '/$total',
                            style: TextStyle(color: t.text2),
                          ),
                        ],
                      ),
                      style: theme.titleLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          if (some) ...[
            CircleIconButton(
              icon: Bi.add,
              size: 44,
              background: Colors.transparent,
              color: t.text,
              onTap: onAdd,
            ),
            if (canFav)
              CircleIconButton(
                size: 44,
                background: Colors.transparent,
                icon: favOn ? Bi.heartBold : Bi.heart,
                color: favOn ? t.sysFavIco : t.text,
                onTap: onFav,
              ),
            const SizedBox(width: 4),
            CircleIconButton(
              size: 44,
              background: t.danger.withValues(alpha: 0.16),
              icon: Bi.trashBinTrash,
              color: t.danger,
              onTap: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

/// The same bar as an input: ✕ drops the title edit, ✓ accepts it.
class _RenameBar extends StatefulWidget {
  const _RenameBar({
    required this.initial,
    required this.onCancel,
    required this.onDone,
  });

  final String initial;
  final VoidCallback onCancel;
  final ValueChanged<String> onDone;

  @override
  State<_RenameBar> createState() => _RenameBarState();
}

class _RenameBarState extends State<_RenameBar> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BarShell(
      child: Row(
        children: [
          CircleIconButton(
            icon: Bi.close,
            size: 44,
            background: Colors.transparent,
            color: context.bloom.text,
            onTap: widget.onCancel,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: BloomField(
              controller: _controller,
              autofocus: true,
              action: TextInputAction.done,
              onSubmitted: widget.onDone,
            ),
          ),
          const SizedBox(width: 8),
          CircleIconButton(
            size: 44,
            background: Colors.transparent,
            icon: Bi.check,
            color: context.bloom.text,
            onTap: () => widget.onDone(_controller.text),
          ),
        ],
      ),
    );
  }
}

/// The pill both bottom bars live in.
class _BarShell extends StatelessWidget {
  const _BarShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      // The chrome's solid base, like the header's buttons: the bar hangs over
      // the list, and rows showing through would be mush.
      color: t.pill,
      elevation: 8,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    );
  }
}
