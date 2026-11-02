/// The History list, a view over the play log with no store of its own. Nothing
/// is removed from it, whole or one by one: it shows the log as it is.
///
/// A row's track comes from the library, or else the database snapshot, kept
/// for every track ever played, so an old row survives the track's being gone
/// everywhere.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entities/entities.dart';
import 'library_store.dart';
import 'play_stats.dart';

/// History rows with no tracks, for those needing only id and time (the wave).
final historyRowsProvider = Provider<List<HistoryRow>>(
  (ref) => ref.watch(playStatsProvider).historyRows(),
);

/// A history row with the track to show and play it.
@immutable
class HistoryItem {
  const HistoryItem(this.row, this.track);

  final HistoryRow row;
  final Track track;
}

/// History rows, newest first.
final historyProvider = Provider<List<HistoryItem>>((ref) {
  final stats = ref.watch(playStatsProvider);
  final lib = ref.watch(libraryProvider);
  return [
    for (final row in ref.watch(historyRowsProvider))
      if (resolveHistoryTrack(row.id, lib, stats) case final track?)
        HistoryItem(row, track),
  ];
});

/// A history row's track: library, then database snapshot.
Track? resolveHistoryTrack(String id, LibraryState lib, PlayStats stats) =>
    lib.tracks[id] ?? stats.tracks[id];
