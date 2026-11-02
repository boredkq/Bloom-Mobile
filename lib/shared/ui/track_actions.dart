/// Track actions: like, add to playlist, go to artist. A bottom sheet, from a
/// long press on a row or the buttons on the player's cover.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/source_label.dart';
import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../features/detail/artists_sheet.dart';
import '../../features/library/import_url.dart';
import '../../features/library/local_tracks.dart';
import '../../features/library/switch_platform.dart';
import '../../features/offline/file_download.dart';
import '../../features/lyrics/lyrics_store.dart';
import '../../features/offline/offline_actions.dart';
import '../../features/offline/offline_store.dart';
import '../../features/player/play_source.dart';
import '../../features/player/player_controller.dart';
import '../../features/wave/wave_actions.dart';
import '../../features/wave/wave_store.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'bloom_sheet.dart';
import 'bloom_toast.dart';
import 'platform_logo.dart';
import 'track_info_sheet.dart';
import 'track_swipes.dart';

/// [listId] is the library section the row was opened from (`all`, `fav`,
/// `history` or a playlist id); Remove from playlist depends on it.
/// [queueIndex] is the row's queue position: there a track leaves the queue
/// itself, and it may stand there twice.
Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  String? listId,
  int? queueIndex,
}) async {
  final lib = ref.read(libraryProvider);
  final isFav = lib.isFav(track.id);
  final inLib = lib.isInLib(track.id);
  // Shown only if the platform serves this track as a file at all.
  final canOffline = ref.read(offlineProvider.notifier).canDownload(track);
  final hasCover = track.cover?.isNotEmpty ?? false;
  final isDisliked = ref.read(waveStoreProvider).isDisliked(track.id);
  // Queue position: from the queue itself it's passed explicitly (a track may
  // stand there twice, ids can't tell them apart); elsewhere I look up the id.
  final queue = ref.read(playbackProvider).queue;
  final inQueueAt = queueIndex ?? queue.indexWhere((t) => t.id == track.id);
  // Remove from playlist only for user playlists: in all tracks, favourites and
  // history the same item would be a different action.
  final fromPlaylist = lib.playlists.any((p) => p.id == listId) ? listId : null;
  final player = ref.read(playbackProvider.notifier);
  // I take the messenger here: the sheet closes before the handler runs, and by
  // the time of the snack bar its context has left the tree.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

  await showBloomSheet(
    context: context,
    header: SheetHero(
      cover: track.cover,
      title: track.name,
      subtitle: track.artist,
      // When it came into the library; a track from search has no such date.
      meta: sheetDateMeta(context, l10n.commonAddedOn, lib.inLib[track.id]),
    ),
    bar: [
      SheetAction(
        icon: isFav ? Bi.heartBold : Bi.heart,
        label: isFav
            ? context.l.taRemoveFromFavorites
            : context.l.taAddToFavorites,
        onTap: () => ref.read(libraryProvider.notifier).toggleFav(track),
      ),
      SheetAction(
        icon: Bi.plus,
        label: context.l.taAddToPlaylist,
        onTap: () => showAddToPlaylistSheet(context, ref, track),
      ),
      SheetAction(
        icon: Bi.inboxIn,
        label: context.l.taToQueue,
        onTap: () => messenger.toast(
          player.addToQueue(track)
              ? l10n.swAddedToQueue
              : l10n.swAlreadyInQueue,
        ),
      ),
      // Two kinds of download live in their own sheet. A local track has only
      // the cover from its tags to save, and the sheet opens for that alone.
      if (canOffline || (canSaveFiles && hasCover))
        SheetAction(
          icon: Bi.downloadMinimalistic,
          label: context.l.taDownload,
          onTap: () =>
              _showDownloadSheet(context, ref, track, canOffline: canOffline),
        ),
    ],
    groups: [
      [
        SheetAction(
          icon: Bi.skipNext,
          label: context.l.taPlayNext,
          subtitle: context.l.taPlayNextHint,
          onTap: () {
            player.playNext(track);
            messenger.toast(l10n.swPlaysNext);
          },
        ),
        // Only platforms with radio: elsewhere it would open just to refuse.
        if (canStartWaveFrom(ref, track))
          SheetAction(
            icon: Bi.soundwave,
            label: context.l.waveFromTrack,
            subtitle: context.l.waveFromTrackHint,
            onTap: () => startWaveFromTrack(context, ref, track),
          ),
        if (canOpenTrackArtist(track))
          SheetAction(
            icon: Bi.user,
            label: context.l.taGoToArtist,
            subtitle: track.artist,
            onTap: () => openTrackArtist(context, ref, track),
          ),
        // About the library's record, so not for search results or own files.
        if (canSwitchPlatform(lib, ref, track))
          SheetAction(
            icon: Bi.refreshSquare,
            label: context.l.spSwitch,
            subtitle: track.source.label10n(context.l),
            onTap: () => _showSwitchPlatformSheet(context, ref, track),
          ),
        SheetAction(
          icon: Bi.lyrics,
          label: context.l.pvGroupLyrics,
          onTap: () {
            ref.read(lyricsOpenProvider.notifier).state = true;
            ref.read(lyricsProvider.notifier).load(track);
          },
        ),
        SheetAction(
          icon: Bi.infoCircle,
          label: context.l.tiTitle,
          subtitle: context.l.tiHint,
          onTap: () =>
              showTrackInfoSheet(context, track, addedAt: lib.inLib[track.id]),
        ),
        SheetAction(
          icon: isDisliked ? Bi.dislikeBold : Bi.dislike,
          label: isDisliked ? context.l.waveUndislike : context.l.waveDislike,
          subtitle: isDisliked
              ? context.l.waveUndislikeHint
              : context.l.waveDislikeHint,
          onTap: () => toggleWaveDislike(context, ref, track),
        ),
      ],
      [
        // Red too: after these the row leaves its place.
        if (fromPlaylist case final playlistId?)
          SheetAction(
            icon: Bi.close,
            label: context.l.taRemoveFromPlaylist,
            danger: true,
            onTap: () =>
                removeTrackFromList(messenger, l10n, ref, playlistId, track),
          ),
        if (inQueueAt >= 0)
          SheetAction(
            icon: Bi.close,
            label: context.l.taRemoveFromQueue,
            danger: true,
            onTap: () => unawaited(player.removeAt(inQueueAt)),
          ),
        // Only a library track has anything to delete: the rest came from search.
        if (inLib)
          SheetAction(
            icon: Bi.trashBinTrash,
            label: context.l.taDeleteTrack,
            danger: true,
            onTap: () => _deleteTrack(messenger, l10n, ref, track),
          ),
      ],
    ],
  );
}

/// Deletes throughout with no second question: the track leaves favourites and
/// playlists too; the item is red, so the tap is the decision. Its history
/// entry stays: that's a log of what was played, and only the user clears it.
void _deleteTrack(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  WidgetRef ref,
  Track track,
) {
  // The offline copy goes with the track, or the file would be garbage nothing
  // points at. For a local track too: the copy in the app goes, the user's file
  // stays.
  unawaited(ref.read(offlineProvider.notifier).remove(track.id));
  unawaited(forgetLocalTracks([track]));
  ref.read(libraryProvider.notifier).deleteTrack(track.id);
  messenger.toast(l10n.taTrackDeleted);
}

/// Download sheet: a copy inside the app, or a file outside. Offline state is
/// read afresh here: a batch download may have changed it since the menu
/// opened.
Future<void> _showDownloadSheet(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  required bool canOffline,
}) async {
  final isOffline = ref.read(offlineProvider).has(track.id);
  final hasCover = track.cover?.isNotEmpty ?? false;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

  // Order: track, cover, offline.
  final rows = <Widget>[
    if (canOffline && canSaveFiles)
      Builder(
        builder: (sheetContext) => SheetRow(
          icon: Bi.musicNote,
          label: l10n.fdDownloadFile,
          color: context.bloom.text,
          onTap: () {
            Navigator.of(sheetContext).pop();
            unawaited(saveTrackFile(messenger, l10n, ref, track));
          },
        ),
      ),
    if (canSaveFiles && hasCover)
      Builder(
        builder: (sheetContext) => SheetRow(
          icon: Bi.gallery,
          label: l10n.fdDownloadCover,
          color: context.bloom.text,
          onTap: () {
            Navigator.of(sheetContext).pop();
            unawaited(saveCoverFile(messenger, l10n, track));
          },
        ),
      ),
    if (canOffline)
      Builder(
        builder: (sheetContext) => SheetRow(
          icon: isOffline ? Bi.trashBinTrash : Bi.downloadMinimalistic,
          label: isOffline ? l10n.taRemoveOffline : l10n.taListenOffline,
          color: isOffline ? context.bloom.accent : context.bloom.text,
          onTap: () {
            Navigator.of(sheetContext).pop();
            unawaited(toggleTrackOffline(messenger, l10n, ref, track));
          },
        ),
      ),
  ];

  await showBloomSheetChild<void>(
    context: context,
    header: SheetHero(
      cover: track.cover,
      title: context.l.taDownload,
      subtitle: track.name,
    ),
    child: Builder(builder: (sheetContext) => SheetPanel(children: rows)),
  );
}

/// Change platform sheet: platforms the track can move to. The current one
/// isn't listed.
Future<void> _showSwitchPlatformSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final targets = switchTargets(ref, track);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

  await showBloomSheetChild<void>(
    context: context,
    header: SheetHero(
      cover: track.cover,
      title: context.l.spSwitch,
      subtitle: track.name,
    ),
    // The sheet must close through its own navigator: from outside
    // `Navigator.of` finds the tab's and closes the page instead.
    child: Builder(
      builder: (sheetContext) => SheetPanel(
        children: [
          for (final target in targets)
            PlatformRow(
              source: target,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  switchTrackPlatform(messenger, l10n, ref, track, target),
                );
              },
            ),
        ],
      ),
    ),
  );
}

/// Platform row of a sheet: its logo and name.
class PlatformRow extends StatelessWidget {
  const PlatformRow({super.key, required this.source, required this.onTap});

  final MusicSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SheetRow(
      leading: PlatformLogo(source, size: 22),
      label: source.label10n(context.l),
      onTap: onTap,
    );
  }
}

/// Add to sheet: the library first, then playlists.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) => showAddTracksToPlaylistSheet(context, ref, [track]);

/// The same sheet for a batch of tracks, from a list's edit mode. [newName]
/// fills in New playlist: a track's title for one, the source list's name for a
/// batch.
Future<void> showAddTracksToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  String? newName,
}) async {
  if (tracks.isEmpty) return;
  final one = tracks.length == 1 ? tracks.first : null;
  final cover = tracks.first.cover;

  await showBloomSheetChild(
    context: context,
    header: SheetHero(
      cover: cover,
      title: context.l.taAddToPlaylist,
      subtitle: one?.name ?? context.l.tracksCount(tracks.length),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final t = context.bloom;
        final lib = ref.watch(libraryProvider);
        final playlists = lib.playlists;
        final outside = [
          for (final track in tracks)
            if (!lib.isInLib(track.id)) track,
        ];

        return SheetPanel(
          children: [
            // This item doesn't concern what's already in the library; it hides
            // when there's nothing to add. A track only leaves via Delete track
            // in the actions sheet, throughout.
            if (outside.isNotEmpty) ...[
              SheetRow(
                icon: Bi.downloadMinimalistic,
                label: context.l.commonAddToLibrary,
                color: t.accent,
                onTap: () {
                  // I take the messenger before pop: after it the sheet's
                  // context has left the tree and can't reach the Scaffold.
                  final messenger = ScaffoldMessenger.of(context);
                  final l10n = context.l;
                  ref.read(libraryProvider.notifier).addToLibrary(outside);
                  Navigator.of(context).pop();
                  messenger.toast(
                    l10n.taAddedToLibrary,
                    kind: ToastKind.success,
                  );
                },
              ),
            ],
            SheetRow(
              icon: Bi.plus,
              label: context.l.commonNewPlaylist,
              color: t.accent,
              onTap: () {
                ref
                    .read(libraryProvider.notifier)
                    .createPlaylist(newName ?? one?.name ?? '', tracks: tracks);
                Navigator.of(context).pop();
              },
            ),
            for (final pl in playlists)
              _PlaylistRow(playlist: pl, tracks: tracks),
          ],
        );
      },
    ),
  );
}

/// "To the queue" and "Play next" for a whole list: a track's two items, for
/// all of [tracks].
List<SheetAction> queueSheetActions(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  PlaySource? source,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;
  final player = ref.read(playbackProvider.notifier);
  return [
    SheetAction(
      icon: Bi.inboxIn,
      label: l10n.tlToQueue,
      onTap: tracks.isEmpty
          ? null
          : () {
              final added = player.queueTracks(tracks, source: source);
              messenger.toast(
                added > 0 ? l10n.tlQueuedTracks(added) : l10n.swAlreadyInQueue,
              );
            },
    ),
    SheetAction(
      icon: Bi.skipNext,
      label: l10n.tlPlayNext,
      onTap: tracks.isEmpty
          ? null
          : () {
              final moved = player.queueTracksNext(tracks, source: source);
              if (moved > 0) messenger.toast(l10n.tlQueuedNext(moved));
            },
    ),
  ];
}

/// Where a page's whole list goes: a new playlist named as the page, all
/// tracks, liked, or one of the playlists.
Future<ImportTarget?> pickImportTarget(
  BuildContext context, {
  required String title,
  String? cover,
}) => showBloomSheetChild<ImportTarget>(
  context: context,
  header: SheetHero(
    cover: cover,
    title: context.l.artistImport,
    subtitle: title,
  ),
  child: Consumer(
    builder: (context, ref, _) {
      final t = context.bloom;
      void pick(ImportTarget target) => Navigator.of(context).pop(target);
      return SheetPanel(
        children: [
          SheetRow(
            icon: Bi.plus,
            label: context.l.commonCreatePlaylist,
            color: t.accent,
            onTap: () => pick(const ImportTarget.create()),
          ),
          SheetRow(
            icon: Bi.musicNote,
            label: context.l.commonAllTracks,
            color: t.text,
            onTap: () => pick(const ImportTarget(ImportTargetKind.library)),
          ),
          SheetRow(
            icon: Bi.heartBold,
            label: context.l.commonFavorites,
            color: t.text,
            onTap: () => pick(const ImportTarget(ImportTargetKind.favorites)),
          ),
          for (final pl in ref.watch(libraryProvider).playlists)
            _PlaylistRow(
              playlist: pl,
              tracks: const [],
              onTap: () => pick(
                ImportTarget(ImportTargetKind.playlist, playlistId: pl.id),
              ),
            ),
        ],
      );
    },
  ),
);

class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.tracks,
    this.onTap,
  });

  final UserPlaylist playlist;
  final List<Track> tracks;

  /// Instead of adding [tracks] here.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    // A tick means all of it is here already: with half of a batch in the
    // playlist there's still something to add.
    final ids = playlist.trackIds.toSet();
    final has =
        tracks.isNotEmpty && tracks.every((track) => ids.contains(track.id));

    return SheetRow(
      leading: Cover(
        url: playlist.cover,
        size: 40,
        covers: playlist.trackIds.map((id) => lib.tracks[id]?.cover),
      ),
      gap: 12,
      label: playlist.name,
      trailing: has ? const SheetTick() : null,
      onTap:
          onTap ??
          () {
            ref
                .read(libraryProvider.notifier)
                .addTracksToPlaylist(playlist.id, tracks);
            Navigator.of(context).pop();
          },
    );
  }
}
