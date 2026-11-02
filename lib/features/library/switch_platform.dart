/// Change platform: replaces a library entry with the same track from another
/// platform. It searches by title and artist, takes the matcher's best result
/// and moves ALL references: library, likes, playlists, queue and plays in the
/// log (with them history, stats and Wrapped). Playlists and order don't move,
/// only what the track plays from.
///
/// A downloaded copy under the old id gets deleted: no track points at it any
/// more, and junk that can't be removed shouldn't stay. The user can download
/// again from the new platform.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/source_label.dart';
import '../../core/log/bloom_log.dart';
import '../../core/providers/match.dart';
import '../../core/store/library_store.dart';
import '../../core/store/play_log.dart';
import '../../shared/ui/bloom_toast.dart';
import '../offline/offline_store.dart';
import '../player/player_controller.dart';

/// Where a track can move: all platforms but local and its current one.
/// Disabled ones (Yandex with no login) aren't hidden, as in the search picker;
/// the provider itself says it can't.
List<MusicSource> switchTargets(WidgetRef ref, Track track) => [
  for (final provider in ref.read(registryProvider).all)
    if (provider.source != MusicSource.local && provider.source != track.source)
      provider.source,
];

/// Whether this track's platform can change at all: for a local file that would
/// mean changing the file itself, and a search result has no library entry
/// behind it.
bool canSwitchPlatform(LibraryState lib, WidgetRef ref, Track track) =>
    track.source != MusicSource.local &&
    lib.tracks.containsKey(track.id) &&
    switchTargets(ref, track).isNotEmpty;

/// Finds the track on [target] and replaces the library entry with it.
Future<void> switchTrackPlatform(
  AppLocalizations l10n,
  WidgetRef ref,
  Track track,
  MusicSource target,
) async {
  if (track.source == target) return;
  final provider = ref.read(registryProvider).byId(target.id);
  if (provider == null) {
    toaster.show(l10n.spUnavailable, kind: ToastKind.warn);
    return;
  }

  // Search takes seconds, so I say so at once, or a press looks like nothing
  // happened.
  toaster.show(l10n.spSearching(target.label10n(l10n)));

  List<Track> found;
  try {
    final results = await provider.search(
      '${track.name} ${track.artist}'.trim(),
    );
    found = results.tracks;
  } catch (e) {
    logWarn('library', 'platform switch: search on ${target.id} failed: $e');
    toaster.show(l10n.spFailed, kind: ToastKind.error);
    return;
  }

  // A platform's results may include other platforms' tracks, so I take only
  // the target's.
  final best = rankMatches(
    [
      for (final t in found)
        if (t.source == target) t,
    ],
    track,
    limit: 1,
    min: kMinMatchScore,
  ).firstOrNull;
  if (best == null) {
    toaster.show(l10n.spNotFound(target.label10n(l10n)), kind: ToastKind.warn);
    return;
  }

  // References move in the database itself: list places, the like and plays
  // (with them history, stats and Wrapped). It's one track, and its count can't
  // be split between two ids. The log gets re-read afterwards.
  ref.read(libraryProvider.notifier).replaceTrack(track.id, best.track);
  ref.read(playLogProvider.notifier).reload();
  ref.read(playbackProvider.notifier).replaceInQueue(track.id, best.track);
  // The downloaded copy is from the old platform: it plays a different file
  // than the track now has, and nothing can refer to it.
  await ref.read(offlineProvider.notifier).remove(track.id);

  toaster.show(l10n.spNow(target.label10n(l10n)), kind: ToastKind.success);
}
