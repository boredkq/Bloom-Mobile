/// Pulls a playlist's tracks from its sources. There may be several, from
/// different platforms ([UserPlaylist.sources]); each goes by collection id on
/// its platform ([fetchSource]), with no link parsing.
///
/// Contents are NOT replaced: new tracks land on top and what was added by hand
/// stays. Otherwise tying someone's collection to your playlist would wipe it
/// on the first update.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';
import '../../core/l10n/l10n.dart';
import '../../shared/ui/bloom_toast.dart';
import 'import_url.dart';
import 'pl_auto_store.dart';

/// Updates a playlist from all its [UserPlaylist.sources]. Returns how many
/// tracks were added; `null` if there's nowhere to update from or NO source
/// answered. A failed source doesn't cancel the rest, and partial success
/// counts: a tied collection may have been deleted on the platform.
Future<int?> refreshPlaylistFromSource(
  ProviderRegistry registry,
  LibraryController library,
  UserPlaylist playlist,
) async {
  if (playlist.sources.isEmpty) return null;

  // Sources are pulled in turn: there are usually few, and parallel only
  // strains the platforms.
  final fresh = <Track>[];
  for (final source in playlist.sources) {
    try {
      fresh.addAll(await fetchSource(registry, source) ?? const []);
    } catch (_) {
      // One unavailable source mustn't stop the rest.
    }
  }
  // An empty answer counts as an error, not as nothing left in the sources.
  if (fresh.isEmpty) return null;

  // The store sorts out duplicates and order: contents may have changed during
  // the network trip.
  return library.addTracksToPlaylist(playlist.id, fresh);
}

/// Refresh tracks for one playlist, from a button in its header. A toast shows
/// the result. A messenger rather than `BuildContext`: from a sheet the item
/// runs after it closes, too late to look up ancestors.
Future<void> refreshOnePlaylist(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WidgetRef ref,
  UserPlaylist playlist,
) async {
  final toast = messenger.busyToast(l.rpBusy(playlist.name));
  final added = await refreshPlaylistFromSource(
    ref.read(registryProvider),
    ref.read(libraryProvider.notifier),
    playlist,
  );
  ref.read(plAutoProvider.notifier).record(playlist.id, added);
  if (added == null) {
    toast.finish(l.rpNoAnswer, kind: ToastKind.warn);
    return;
  }
  toast.finish(
    added == 0 ? l.paNoNewTracks : l.rpNewTracks(added),
    kind: added == 0 ? ToastKind.info : ToastKind.success,
  );
}
