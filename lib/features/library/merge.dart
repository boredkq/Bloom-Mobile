/// Merge with: builds one new playlist from several. The source goes first,
/// then the picked ones in pick order; repeats collapse by id unless turned
/// off. Sources don't change: the result is ALWAYS a new playlist, and deleting
/// them is a separate checkbox.
library;

import '../../core/entities/entities.dart';

/// The new playlist's contents. [lists] are the source lists in order. Repeats
/// count by id: one track from different platforms is two library entries and
/// can't collapse here; Find duplicates compares titles for that.
List<Track> mergeTracks(List<List<Track>> lists, {required bool dedup}) {
  final out = <Track>[];
  final seen = <String>{};
  for (final list in lists) {
    for (final track in list) {
      if (dedup && !seen.add(track.id)) continue;
      out.add(track);
    }
  }
  return out;
}

/// How many repeats a merge removes, for the sheet's count line.
int mergeDupCount(List<List<Track>> lists) {
  final total = lists.fold<int>(0, (sum, list) => sum + list.length);
  return total - mergeTracks(lists, dedup: true).length;
}
