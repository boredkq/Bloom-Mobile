/// Find duplicates: one track in a list twice. Grouped by normalized title and
/// artist, with one-track groups dropped. Within a group the one worth keeping
/// comes first: has a cover, then played more, then added earlier. The rest are
/// extra copies.
///
/// The mode lives in a store, not screen state: a sheet turns it on and the
/// list shows it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';

/// The key by which tracks count as one: case and extra spaces don't matter.
/// Rough on purpose: this searches within one list, not across platforms, which
/// is the matcher's job.
String dupKey(Track track) => '${_norm(track.name)}|||${_norm(track.artist)}';

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Duplicate groups in [pool], each from keep to extras. Groups go in order of
/// a track's first appearance, standing where the user saw them.
///
/// [plays] is the play count (`PlayStats.playCount`). [addedAt] is when a track
/// entered the library (`LibraryState.inLib`): all else equal, the earlier copy
/// stays.
List<List<Track>> dupGroups(
  List<Track> pool, {
  int Function(String id)? plays,
  Map<String, int> addedAt = const {},
}) {
  final byKey = <String, List<Track>>{};
  for (final track in pool) {
    byKey.putIfAbsent(dupKey(track), () => <Track>[]).add(track);
  }
  return [
    for (final group in byKey.values)
      if (group.length > 1) sortDupGroup(group, plays: plays, addedAt: addedAt),
  ];
}

/// Order in a group: has a cover, more plays, added earlier. The first stays.
List<Track> sortDupGroup(
  List<Track> group, {
  int Function(String id)? plays,
  Map<String, int> addedAt = const {},
}) {
  final sorted = [...group];
  sorted.sort((a, b) {
    final coverA = (a.cover ?? '').isNotEmpty;
    final coverB = (b.cover ?? '').isNotEmpty;
    if (coverA != coverB) return coverA ? -1 : 1;
    final playsA = plays?.call(a.id) ?? 0;
    final playsB = plays?.call(b.id) ?? 0;
    if (playsA != playsB) return playsB - playsA;
    return (addedAt[a.id] ?? 0).compareTo(addedAt[b.id] ?? 0);
  });
  return sorted;
}

/// Extra copies: all but the first in each group.
List<Track> extraDups(List<List<Track>> groups) => [
  for (final group in groups) ...group.skip(1),
];

/// Which list has duplicates mode on; `null` for none.
final dupsProvider = NotifierProvider<DupsController, String?>(
  DupsController.new,
);

class DupsController extends Notifier<String?> {
  @override
  String? build() => null;

  void enter(String listId) => state = listId;

  void exit() => state = null;
}
