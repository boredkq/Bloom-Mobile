/// Importing playlists from a `.bloomplaylist` file, a shared flow for the
/// library's plus and settings. Parsing lives elsewhere; here it's the system
/// dialog, the library and a toast. The toast shows right here: there are four
/// outcomes, and each entry point handling them would drift in wording.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/log/bloom_log.dart';
import '../../core/store/library_store.dart';
import '../../core/store/text_files.dart';
import '../../shared/ui/bloom_toast.dart';
import '../settings/data_transfer.dart';

/// Picks a file and creates playlists from it. Returns counts, or `null` if no
/// import happened (dialog closed, foreign file, no playlists); for all but a
/// cancel, a toast already told the caller.
Future<ImportResult?> importPlaylistFile(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  AppLocalizations l,
) async {
  final content = await openTextFile();
  if (content == null) return null; // the dialog was closed, so silently
  final result = await importPlaylistBundle(
    content,
    ref.read(libraryProvider),
    ref.read(libraryProvider.notifier),
  );
  if (result.failure case final failure?) {
    messenger.toast(switch (failure) {
      ImportFailure.bad => l.sysImportInvalid,
      ImportFailure.oldFormat => l.sysImportOld,
      ImportFailure.newer => l.sysImportNewer,
    }, kind: ToastKind.error);
    return null;
  }
  if (result.playlists == 0) {
    messenger.toast(l.sysImportNoPlaylists, kind: ToastKind.warn);
    return null;
  }
  logInfo(
    'transfer',
    'import: ${result.playlists} playlists, ${result.tracks} tracks',
  );
  messenger.toast(
    result.tracks > 0
        ? l.sysImportedFull(result.playlists, result.tracks)
        : l.sysImportedPlaylists(result.playlists),
    kind: ToastKind.success,
  );
  return result;
}
