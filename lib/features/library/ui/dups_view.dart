/// Inline Find duplicates mode: the list's tracks grouped by repeats. The
/// list's header stays, since it's still that playlist. A strip on top has the
/// count and Remove all duplicates, with groups below: the first in each is
/// marked keep, and extras go one by one or by group.
///
/// The mode removes only from a PLAYLIST: a track leaves the list and stays in
/// the library. All tracks deletes throughout, so the mode doesn't go there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../core/store/play_stats.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../dups.dart';
import '../../../shared/ui/glass.dart';

/// A sliver with the strip and groups, living in the track list's
/// `CustomScrollView`.
class DupsSliver extends ConsumerWidget {
  const DupsSliver({super.key, required this.listId, required this.tracks});

  /// The playlist being searched, also what gets removed from.
  final String listId;

  /// Search pool: the list's contents in its own order.
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final plays = ref.watch(playStatsProvider).playCount;
    // Counted from fresh contents: remove a copy and the group rebuilds, with
    // empty ones gone by themselves.
    final groups = dupGroups(tracks, plays: plays, addedAt: lib.inLib);
    final extra = extraDups(groups);

    return SliverList.list(
      children: [
        _Bar(
          groups: groups.length,
          extra: extra.length,
          checked: tracks.length,
          onDeleteAll: extra.isEmpty
              ? null
              : () => removeDups(context, ref, listId, extra),
          onExit: () => ref.read(dupsProvider.notifier).exit(),
        ),
        for (final group in groups)
          _Group(
            group: group,
            plays: plays,
            onDelete: () =>
                removeDups(context, ref, listId, group.skip(1).toList()),
            onDeleteOne: (track) => removeDups(context, ref, listId, [track]),
          ),
        if (groups.isEmpty) _Empty(checked: tracks.length),
      ],
    );
  }
}

/// Removes copies from the playlist, with Undo like any list removal: the
/// library snapshot restores contents and order at once.
void removeDups(
  BuildContext context,
  WidgetRef ref,
  String listId,
  List<Track> extra,
) {
  if (extra.isEmpty) return;
  final l = context.l;
  final lib = ref.read(libraryProvider.notifier);
  final before = lib.snapshot();

  for (final track in extra) {
    lib.removeTrackFromPlaylist(listId, track.id);
  }
  toaster.show(
    l.dupsRemoved(extra.length),
    action: ToastAction(fn: () => lib.restoreSnapshot(before)),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.groups,
    required this.extra,
    required this.checked,
    required this.onDeleteAll,
    required this.onExit,
  });

  final int groups;
  final int extra;
  final int checked;
  final VoidCallback? onDeleteAll;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 4),
      child: Row(
        children: [
          BloomIcon(Bi.copy, size: 18, color: t.accent),
          const SizedBox(width: 10),
          Expanded(
            child: TwoLines(
              context.l.dupsTitle,
              groups > 0
                  ? context.l.dupsFound(groups, extra)
                  : context.l.dupsChecked(checked),
            ),
          ),
          if (onDeleteAll != null)
            BloomButton(
              label: context.l.dupsDelAll,
              color: context.bloom.danger,
              height: 32,
              onTap: onDeleteAll,
            ),
          CircleIconButton(
            icon: Bi.close,
            size: 48,
            iconSize: 22,
            background: Colors.transparent,
            color: t.text2,
            onTap: onExit,
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.plays,
    required this.onDelete,
    required this.onDeleteOne,
  });

  final List<Track> group;

  /// The track's own plays, from the log.
  final int Function(String id) plays;
  final VoidCallback onDelete;
  final ValueChanged<Track> onDeleteOne;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: GlassBox(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l.dupsCopies(group.length),
                      style: theme.bodySmall,
                    ),
                  ),
                  BloomButton(
                    label: context.l.dupsDelGroup,
                    color: context.bloom.danger,
                    height: 32,
                    onTap: onDelete,
                  ),
                ],
              ),
            ),
            for (var i = 0; i < group.length; i++)
              _Row(
                track: group[i],
                plays: plays(group[i].id),
                keep: i == 0,
                onDelete: () => onDeleteOne(group[i]),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.track,
    required this.plays,
    required this.keep,
    required this.onDelete,
  });

  final Track track;
  final int plays;

  /// The one suggested to keep, first in its group.
  final bool keep;

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          Cover(url: track.cover, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: TwoLines(
              track.name,
              plays > 0
                  ? '${track.artist} · ${context.l.dupsPlays(plays)}'
                  : track.artist,
              titleStyle: keep
                  ? theme.titleSmall?.copyWith(color: t.accent)
                  : theme.titleSmall,
            ),
          ),
          const SizedBox(width: 8),
          if (keep)
            Text(
              context.l.dupsKeep,
              style: theme.bodySmall?.copyWith(color: t.accent),
            )
          else
            CircleIconButton(
              icon: Bi.close,
              size: 48,
              iconSize: 20,
              background: Colors.transparent,
              color: t.danger,
              onTap: onDelete,
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.checked});

  final int checked;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      child: Column(
        children: [
          BloomIcon(Bi.checkCircle, size: 30, color: t.accent),
          const SizedBox(height: 10),
          Text(context.l.dupsNone, style: theme.titleMedium),
          const SizedBox(height: 4),
          Text(context.l.dupsChecked(checked), style: theme.bodySmall),
        ],
      ),
    );
  }
}
