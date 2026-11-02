/// The history sheet: what was played, newest first, under a line for each
/// day ("Today", "Yesterday", "3 days ago", a date). A row says when it last
/// played and how many times; a tap plays the history from it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/store/history_store.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/track_swipes.dart';
import '../../library/history_format.dart';
import '../../player/play_source.dart';
import '../../settings/swipe_store.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/ui/atoms.dart';

/// The list can run to thousands of rows: it scrolls itself and builds lazily.
Future<void> showHistorySheet(BuildContext context) =>
    showBloomSheetChild<void>(
      context: context,
      header: const _Head(),
      scrolls: false,
      child: const _HistoryList(),
    );

/// The title and how many tracks are under it; stays put while the list scrolls.
class _Head extends ConsumerWidget {
  const _Head();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(historyProvider.select((h) => h.length));
    return SheetTitle(
      context.l.commonHistory,
      subtitle: context.l.tracksCount(count),
      bottom: 8,
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    if (history.isEmpty) {
      return CenterNote(
        context.l.historyEmpty,
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      );
    }

    // One flat list, a day's head before its first row.
    final tracks = [for (final item in history) item.track];
    final items = <Object>[];
    var last = '';
    for (var i = 0; i < history.length; i++) {
      final at = DateTime.fromMillisecondsSinceEpoch(history[i].row.at);
      final label = historyLabel(context, at);
      if (label != last) items.add(label);
      last = label;
      items.add(i);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: items.length,
      itemBuilder: (context, n) {
        final item = items[n];
        if (item is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
            child: SettingsCaption(item),
          );
        }
        final i = item as int;
        final row = history[i].row;
        final track = tracks[i];
        return TrackSwipe(
          key: ValueKey(track.id),
          zone: SwipeZone.library,
          track: track,
          listId: 'history',
          child: TrackRow(
            track: track,
            queue: tracks,
            index: i,
            source: const LibSource('history'),
            mark: HistoryMark(
              time: historyTime(
                context,
                DateTime.fromMillisecondsSinceEpoch(row.at),
              ),
              count: row.count,
            ),
          ),
        );
      },
    );
  }
}
