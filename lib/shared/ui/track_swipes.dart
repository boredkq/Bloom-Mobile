/// Track swipes: what happens when a list row or the player card is pulled
/// aside. One place for all four [SwipeZone]s; a library row, a queue row, the
/// mini player and the player differ only in where the track comes from and
/// what delete means. [SwipeRow] and `TrackFlick` draw the gesture.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/store/library_store.dart';
import '../../features/library/local_tracks.dart';
import '../../features/offline/offline_actions.dart';
import '../../features/offline/offline_store.dart';
import '../../features/player/player_controller.dart';
import '../../features/player/track_swap_dir.dart';
import '../../features/settings/swipe_store.dart';
import 'bloom_icon.dart';
import 'bloom_toast.dart';
import 'swipe_row.dart';

/// Action icon, shared by settings, the picker and the plate.
BloomGlyph swipeActionIcon(SwipeAction action) => switch (action) {
  SwipeAction.none => Bi.forbiddenCircle,
  SwipeAction.like => Bi.heart,
  SwipeAction.queue => Bi.addCircle,
  SwipeAction.playNext => Bi.skipNext,
  SwipeAction.next => Bi.skipNext,
  SwipeAction.prev => Bi.skipPrevious,
  SwipeAction.download => Bi.diskette,
  SwipeAction.delete => Bi.trashBinTrash,
};

String swipeActionLabel(AppLocalizations l, SwipeAction action) =>
    switch (action) {
      SwipeAction.none => l.swActNone,
      SwipeAction.like => l.swActLike,
      SwipeAction.queue => l.swActQueue,
      SwipeAction.playNext => l.swActPlayNext,
      SwipeAction.next => l.swActNext,
      SwipeAction.prev => l.swActPrev,
      SwipeAction.download => l.swActDownload,
      SwipeAction.delete => l.swActDelete,
    };

String swipeZoneLabel(AppLocalizations l, SwipeZone zone) => switch (zone) {
  SwipeZone.library => l.swZoneLibrary,
  SwipeZone.queue => l.swZoneQueue,
  SwipeZone.mini => l.swZoneMini,
  SwipeZone.player => l.swZonePlayer,
};

/// List row with swipes from settings. [listId] is the library section (`all`,
/// `fav`, `history` or a playlist id), so delete knows where from. [queueIndex]
/// is the queue position: there a track leaves the queue itself.
class TrackSwipe extends ConsumerWidget {
  const TrackSwipe({
    super.key,
    required this.zone,
    required this.track,
    required this.child,
    this.listId,
    this.queueIndex,
  });

  final SwipeZone zone;
  final Track track;
  final String? listId;
  final int? queueIndex;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = ref.watch(swipeProvider).of(zone);
    return SwipeRow(
      left: _panel(context, ref, pair.right),
      right: _panel(context, ref, pair.left),
      child: child,
    );
  }

  /// Plate of one direction; `null` means no action and the row doesn't move
  /// that way.
  SwipePanel? _panel(BuildContext context, WidgetRef ref, SwipeAction action) {
    if (action == SwipeAction.none) return null;
    // Nothing leaves history, so the row doesn't move that way.
    if (action == SwipeAction.delete && listId == 'history') return null;
    // Delete is the only action after which the row is gone; the others return
    // it.
    final removes =
        action == SwipeAction.delete && (queueIndex != null || listId != null);
    return SwipePanel(
      icon: swipeActionIcon(action),
      danger: action == SwipeAction.delete,
      dismiss: removes,
      onFire: () => runSwipeAction(
        context,
        ref,
        action,
        track: track,
        listId: listId,
        queueIndex: queueIndex,
      ),
    );
  }
}

/// Runs what the gesture is set to.
void runSwipeAction(
  BuildContext context,
  WidgetRef ref,
  SwipeAction action, {
  required Track track,
  String? listId,
  int? queueIndex,
  bool fromFlick = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l;
  final player = ref.read(playbackProvider.notifier);

  switch (action) {
    case SwipeAction.none:
      return;
    case SwipeAction.like:
      final on = ref.read(libraryProvider.notifier).toggleFav(track);
      messenger.toast(on ? l.swLiked : l.swUnliked);
    case SwipeAction.queue:
      messenger.toast(
        player.addToQueue(track) ? l.swAddedToQueue : l.swAlreadyInQueue,
      );
    case SwipeAction.playNext:
      player.playNext(track);
      messenger.toast(l.swPlaysNext);
    // `TrackSwap` doesn't animate a change under the finger: the gesture
    // already carried the content off (see `markSwapSilent`). The flag is
    // one-shot, so I set it only on actions that will surely change the track.
    case SwipeAction.next:
      if (fromFlick) markSwapSilent();
      unawaited(player.next());
    case SwipeAction.prev:
      if (fromFlick) markSwapSilent();
      unawaited(player.prev());
    case SwipeAction.download:
      unawaited(toggleTrackOffline(messenger, l, ref, track));
    case SwipeAction.delete:
      if (queueIndex != null) {
        unawaited(player.removeAt(queueIndex));
        return;
      }
      if (listId != null) {
        removeTrackFromList(messenger, l, ref, listId, track);
        return;
      }
      // The player and mini player have no list behind them, so a track can
      // only leave the queue.
      final index = ref.read(playbackProvider).index;
      if (index >= 0) unawaited(player.removeAt(index));
  }
}

/// Removes a track from a library section with the same handles as edit mode,
/// and Undo in the toast. From all tracks it goes throughout (see
/// [LibraryController.deleteTrack]), so Undo restores a snapshot of the whole
/// library. The offline copy goes only when it's too late to undo.
///
/// Shared with the actions sheet: its Remove from playlist must behave just
/// like a swipe.
void removeTrackFromList(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  String listId,
  Track track,
) {
  // History shows the log as it is; nothing leaves it.
  if (listId == 'history') return;

  final lib = ref.read(libraryProvider.notifier);
  final state = ref.read(libraryProvider);
  final before = lib.snapshot();

  switch (listId) {
    case 'all':
      lib.deleteTrack(track.id);
    case 'fav':
      lib.setFavTracks([
        for (final t in state.favTracks)
          if (t.id != track.id) t.id,
      ]);
    default:
      lib.removeTrackFromPlaylist(listId, track.id);
  }

  final offline = ref.read(offlineProvider.notifier);
  messenger.toast(
    l.swRemoved,
    action: ToastAction(
      fn: () => lib.restoreSnapshot(before),
      // Files go only when it's too late to undo: Undo restores the library
      // snapshot, but not a deleted copy of a local track.
      onExpire: listId == 'all'
          ? () {
              unawaited(offline.remove(track.id));
              unawaited(forgetLocalTracks([track]));
            }
          : null,
    ),
  );
}
