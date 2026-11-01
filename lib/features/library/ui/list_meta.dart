/// A list's caption under its title: track count, offline count and total time.
/// One widget because of width: on a library tile the full line won't fit and
/// the count shortens to a bare number. Header, tile and sheet deciding apart
/// would be three clippings of one line.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../features/offline/offline_actions.dart';
import '../../../features/offline/offline_store.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/util/format.dart';

class ListMeta extends ConsumerWidget {
  const ListMeta({
    super.key,
    required this.tracks,
    this.count,
    this.style,
    this.showCount = true,
    this.showOffline = true,
    this.showDuration = true,
  });

  /// List contents, for the offline tag and total time.
  final List<Track> tracks;

  /// Track count when not from [tracks]: a tile counts the playlist's contents
  /// even before the tracks come up from the library.
  final int? count;

  /// Caption style. The list header's `bodyMedium` by default; smaller on
  /// tiles, and its own colour in a sheet.
  final TextStyle? style;

  final bool showCount;

  /// How many of the list are on the device, for own playlists only.
  final bool showOffline;

  final bool showDuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = this.style ?? Theme.of(context).textTheme.bodyMedium;
    final l = context.l;

    final status = showOffline
        ? listOfflineState(
            ref.watch(offlineProvider),
            ref.read(offlineProvider.notifier),
            tracks,
          )
        : null;
    // Offline indicator: all downloaded shows offline, some shows N/M, none
    // shows no tag.
    final offline = status == null || !status.any
        ? null
        : status.all
        ? l.commonOfflineBadge
        : '${status.cached}/${status.total}';

    final sum = !showDuration
        ? Duration.zero
        : tracks.fold<Duration>(Duration.zero, (acc, x) => acc + x.duration);
    final duration = sum > Duration.zero ? totalDur(l, sum) : null;

    final iconSize = style?.fontSize ?? 13;
    const iconGap = 3.0;

    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        double width(String text) => (TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout()).width;

        String? counter;
        if (showCount) {
          final n = count ?? tracks.length;
          // The tail (tag and time) isn't cut: the count shrinks for it. With
          // unknown width (an infinite Row) the full form. The icon doesn't
          // scale with text (`applyTextScaling` is off by default on `Icon`),
          // so its width is exactly `iconSize`.
          final tail =
              (offline == null
                  ? 0
                  : width(' · ') + iconSize + iconGap + width(offline)) +
              (duration == null ? 0 : width(' · $duration'));
          final full = l.tracksCount(n);
          counter = !box.maxWidth.isFinite || width(full) + tail <= box.maxWidth
              ? full
              : '$n';
        }

        final parts = <Widget>[];
        void separator() {
          if (parts.isNotEmpty) parts.add(Text(' · ', style: style));
        }

        if (counter != null) {
          // Even a bare number ellipsizes if the tile is very narrow.
          parts.add(
            Flexible(
              child: Text(
                counter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          );
        }
        if (offline != null) {
          separator();
          parts.addAll([
            // The diskette, as in a track row.
            BloomIcon(Bi.diskette, size: iconSize, color: style?.color),
            const SizedBox(width: iconGap),
            Text(offline, style: style),
          ]);
        }
        if (duration != null) {
          separator();
          parts.add(Text(duration, style: style));
        }

        // With nothing to show the line still takes its height: it's set from
        // outside in the list header, and a dropped caption would stretch the
        // gap to the action row.
        if (parts.isEmpty) return Text(' ', style: style);
        return Row(mainAxisSize: MainAxisSize.min, children: parts);
      },
    );
  }
}
