/// Playback queue, a sheet over the player. Its own shell: this is a long list,
/// not a dozen items, so a solid theme background, rows just as in playlists
/// (`TrackRow`), and the sheet reaches the top of the screen.
///
/// A header with a count and clear, a flat list with drag by the cover, and a
/// swipe that removes a track; settings choose what swipes do.
///
/// Two views. Normal is flat; extended splits it into Played, Now playing and
/// Next. In extended each section is ITS OWN `SliverReorderableList`, so a
/// track can't physically move between them, and the playing one stands between
/// as a pinned row. Headers are separate slivers and stay out of reordering.
///
/// Row numbers within a section are its OWN, while everything else (start,
/// menu, swipes, remove from queue) works by QUEUE index: a section knows its
/// offset and converts. Without that the second section would hit others' rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/entities/entities.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../features/wave/wave_actions.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/ui/track_swipes.dart';
import '../player_controller.dart';
import '../player_view_store.dart';
import '../../../shared/ui/subpage_header.dart';

/// Section header height in extended view. A number rather than built from
/// margins: the sheet computes where to scroll on open from it.
const double kQueueSectionLabel = 34;

/// Where to scroll on opening the sheet. Normal view: the playing track with
/// two rows of room above. Extended: the Now playing HEADER on top, taking the
/// whole Played section off the edge, or it's unclear which section the first
/// visible row belongs to.
double queueScrollOffset({required int index, required bool extended}) {
  if (index <= 0) return 0;
  if (!extended) return index > 2 ? (index - 2) * kTrackRowHeight : 0;
  return index * kTrackRowHeight + kQueueSectionLabel;
}

void showQueueSheet(BuildContext context) {
  // The root navigator and dimming glass, as for all my sheets, or the tab bar
  // and mini player stay over the dimming.
  showBloomModal<void>(context: context, builder: (_) => const _QueueSheet());
}

class _QueueSheet extends ConsumerStatefulWidget {
  const _QueueSheet();

  @override
  ConsumerState<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends ConsumerState<_QueueSheet> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Opens on the playing track rather than the queue's start: with a hundred
    // tracks it's otherwise unclear where you are.
    final index = ref.read(playbackProvider).index;
    _scroll = ScrollController(
      initialScrollOffset: queueScrollOffset(
        index: index,
        extended: ref.read(queueViewProvider).isExtended,
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Row keys. A track can be queued twice, and `ReorderableListView` crashes
  /// on duplicates, so the id gets its occurrence number.
  List<Widget> _slivers({
    required List<Track> queue,
    required List<Key> keys,
    required int current,
    required bool extended,
    required PlaybackController ctrl,
  }) {
    // No playing track in the queue (empty, or a stray index), so nothing to
    // split: a flat list, since an empty Now playing section would lie.
    final split = extended && current >= 0 && current < queue.length;
    if (!split) {
      return [
        _section(
          queue: queue,
          keys: keys,
          current: current,
          ctrl: ctrl,
          offset: 0,
          count: queue.length,
        ),
      ];
    }

    final l = context.l;
    return [
      if (current > 0) ...[
        _label(l.queueSecPlayed),
        _section(
          queue: queue,
          keys: keys,
          current: current,
          ctrl: ctrl,
          offset: 0,
          count: current,
        ),
      ],
      _label(l.queueSecNow),
      // The playing track is a static row, pinned and out of reordering.
      // `dragIndex` isn't set, so the menu returns to a long press across the
      // row (see `TrackRowShell`).
      SliverToBoxAdapter(
        child: _swipeRow(
          queue: queue,
          keys: keys,
          global: current,
          drag: null,
          current: true,
        ),
      ),
      if (current < queue.length - 1) ...[
        _label(l.queueSecNext),
        _section(
          queue: queue,
          keys: keys,
          current: current,
          ctrl: ctrl,
          offset: current + 1,
          count: queue.length - current - 1,
        ),
      ],
    ];
  }

  /// Section header.
  Widget _label(String text) => SliverToBoxAdapter(
    child: SizedBox(
      height: kQueueSectionLabel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SettingsCaption(text),
        ),
      ),
    ),
  );

  /// One draggable section. [offset] is the queue row it starts from: numbers
  /// inside are its own, and queue numbers go out.
  Widget _section({
    required List<Track> queue,
    required List<Key> keys,
    required int current,
    required PlaybackController ctrl,
    required int offset,
    required int count,
  }) => SliverReorderableList(
    itemCount: count,
    // Reordering inside a section doesn't cross the playing track, so its index
    // holds by itself: the controller gets an ordinary queue reorder in queue
    // numbers.
    onReorder: (from, to) => ctrl.reorder(from + offset, to + offset),
    proxyDecorator: (child, _, _) =>
        Material(color: Colors.white.withValues(alpha: 0.06), child: child),
    itemBuilder: (context, i) => _swipeRow(
      queue: queue,
      keys: keys,
      global: offset + i,
      // The drag handle needs the number IN THE SECTION:
      // `SliverReorderableList` counts its rows from zero, and with a queue
      // number the second section would grab someone else's row.
      drag: i,
      current: offset + i == current,
    ),
  );

  /// Queue row with swipes. Its key is shared by both views: by it
  /// `SliverReorderableList` knows the row while reordering.
  Widget _swipeRow({
    required List<Track> queue,
    required List<Key> keys,
    required int global,
    required int? drag,
    required bool current,
  }) => TrackSwipe(
    key: keys[global],
    zone: SwipeZone.queue,
    track: queue[global],
    queueIndex: global,
    child: _QueueRow(
      track: queue[global],
      index: global,
      dragIndex: drag,
      current: current,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final ctrl = ref.read(playbackProvider.notifier);
    final queue = state.queue;
    final keys = trackRowKeys(queue);

    // The last track was swiped, so the queue is empty with nothing to show.
    // The player below closes by itself, but the sheet should go first: the
    // action happened in it.
    ref.listen(playbackProvider, (_, next) {
      if (next.queue.isNotEmpty) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
    });

    return SheetShell(
      scrolls: false,
      header: SheetTitle(
        context.l.playerQueue,
        right: 12,
        bottom: 12,
        line: Row(
          children: [
            Text(
              context.l.tracksCount(queue.length),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (state.shuffle) ...[
              const SizedBox(width: 8),
              BloomIcon(Bi.shuffle, size: 14, color: context.bloom.accent),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // It carries the queue on with a pick. The sheet closes: the list
            // under it is about to change whole.
            CircleIconButton(
              icon: Bi.soundwave,
              iconSize: 20,
              onTap: queue.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      startWaveFromQueue(context, ref, queue);
                    },
            ),
            const SizedBox(width: 8),
            CircleIconButton(
              icon: Bi.trashBinTrash,
              iconSize: 20,
              onTap: queue.length > 1 ? ctrl.clearExceptCurrent : null,
            ),
          ],
        ),
      ),
      child: CustomScrollView(
        controller: _scroll,
        shrinkWrap: true,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            sliver: SliverMainAxisGroup(
              slivers: _slivers(
                queue: queue,
                keys: keys,
                current: state.index,
                extended: ref.watch(queueViewProvider).isExtended,
                ctrl: ctrl,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({
    required this.track,
    required this.index,
    required this.current,
    required this.dragIndex,
  });

  final Track track;

  /// Row number IN THE QUEUE: it starts playback, and the track sheet removes
  /// the row by it.
  final int index;

  final bool current;

  /// Row number IN ITS SECTION, for the cover's drag handle. `null` for the
  /// playing track, which is pinned.
  final int? dragIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: TrackRowShell(
        track: track,
        // Not by id: a track may be queued twice, and the one at the current
        // position is what plays.
        active: current,
        onTap: () => ref.read(playbackProvider.notifier).jumpTo(index),
        // A row number rather than an id search: a track may be queued twice,
        // and Remove from queue must remove this row.
        onMenu: () => showTrackActions(context, ref, track, queueIndex: index),
        dragIndex: dragIndex,
      ),
    );
  }
}
