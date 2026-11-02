/// Merge with sheet: picks playlists to build a new one from. A name (filled in
/// until touched), multi-select of other playlists, Remove duplicates (on by
/// default), Delete sources (off by default), and a line counting the result.
///
/// The sheet creates nothing: it returns a decision and the caller builds the
/// playlist, since navigation lives outside the sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../merge.dart';

/// What the user picked in the sheet.
class _MergePlan {
  const _MergePlan({
    required this.name,
    required this.ids,
    required this.dedup,
    required this.deleteSources,
  });

  final String name;

  /// Playlists mixed into the source, in pick order.
  final List<String> ids;

  final bool dedup;
  final bool deleteSources;
}

/// Opens the sheet and builds the playlist from its result.
Future<void> showMergeSheet(
  BuildContext context,
  WidgetRef ref,
  UserPlaylist source,
) async {
  final l10n = context.l;
  // Nothing to merge with: I say so at once rather than an empty sheet.
  final others = _mergeable(ref.read(libraryProvider), source);
  if (others.isEmpty) {
    toaster.show(l10n.mgNothingToMerge, kind: ToastKind.info);
    return;
  }

  final plan = await showBloomSheetChild<_MergePlan>(
    context: context,
    header: SheetHero(
      cover: source.cover,
      title: source.name,
      subtitle: l10n.mgTitle,
    ),
    child: _MergeBody(source: source),
  );
  if (plan == null) return;

  final lib = ref.read(libraryProvider);
  final library = ref.read(libraryProvider.notifier);
  final picked = [
    for (final id in plan.ids)
      ...lib.playlists.where((p) => p.id == id).map(lib.tracksOf),
  ];
  final tracks = mergeTracks([
    lib.tracksOf(source),
    ...picked,
  ], dedup: plan.dedup);

  final created = library.createPlaylist(plan.name, tracks: tracks);
  if (plan.deleteSources) {
    library.deletePlaylist(source.id);
    for (final id in plan.ids) {
      library.deletePlaylist(id);
    }
  }
  if (context.mounted) context.go('/library/list/${created.id}');
  toaster.show(
    l10n.mgMerged(created.name, l10n.tracksCount(tracks.length)),
    kind: ToastKind.success,
  );
}

/// What can be merged: all playlists but the source itself. Imported albums
/// stay: unlike adding a track, an album here is read, not edited.
List<UserPlaylist> _mergeable(LibraryState lib, UserPlaylist source) => [
  for (final pl in lib.playlists)
    if (pl.id != source.id) pl,
];

class _MergeBody extends ConsumerStatefulWidget {
  const _MergeBody({required this.source});

  final UserPlaylist source;

  @override
  ConsumerState<_MergeBody> createState() => _MergeBodyState();
}

class _MergeBodyState extends ConsumerState<_MergeBody> {
  late final TextEditingController _name = TextEditingController(
    // Default name, the source's plus a sign. Until touched it stays a hint
    // rather than the user's choice.
    text: '${widget.source.name} +',
  );

  /// Picked playlists in press order, which is also the merge order.
  final List<String> _picked = [];

  bool _dedup = true;
  bool _deleteSources = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    // Silently doing nothing won't do: the tick was pressed, so the user
    // expects a result, and I say what's missing.
    if (_picked.isEmpty) {
      toaster.show(context.l.mgPickHint, kind: ToastKind.warn);
      return;
    }
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _MergePlan(
        name: name,
        ids: [..._picked],
        dedup: _dedup,
        deleteSources: _deleteSources,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final lib = ref.watch(libraryProvider);
    final others = _mergeable(lib, widget.source);
    final lists = [
      lib.tracksOf(widget.source),
      for (final id in _picked)
        ...lib.playlists.where((p) => p.id == id).map(lib.tracksOf),
    ];
    final total = mergeTracks(lists, dedup: _dedup).length;
    final dups = mergeDupCount(lists);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetField(
          controller: _name,
          hint: context.l.mgNameHint,
          onChanged: (_) => setState(() {}),
          onSubmit: _submit,
        ),
        // The result's count right under the name: it changes with each mark,
        // and should show where you mark.
        SheetCaption(
          _picked.isEmpty
              ? context.l.mgPickHint
              : context.l.mgResult(context.l.tracksCount(total)),
          padding: const EdgeInsets.fromLTRB(kSheetEdge, 2, kSheetEdge, 8),
          trailing: _dedup && dups > 0
              ? Text(
                  context.l.mgDupsDropped(dups),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: t.accent),
                )
              : null,
        ),
        SheetPanel(
          children: [
            for (final other in others)
              _PlaylistRow(
                playlist: other,
                tracks: lib.tracksOf(other).length,
                covers: lib.tracksOf(other).map((track) => track.cover),
                // The number says in what order the tracks land in the new
                // playlist, which a tick wouldn't.
                order: _picked.indexOf(other.id),
                onTap: () => setState(() {
                  if (!_picked.remove(other.id)) _picked.add(other.id);
                }),
              ),
          ],
        ),
        SheetPanel(
          children: [
            SheetSwitchRow(
              icon: Bi.copy,
              label: context.l.mgDedup,
              value: _dedup,
              onChanged: (v) => setState(() => _dedup = v),
              padding: const EdgeInsets.all(16),
            ),
            SheetSwitchRow(
              icon: Bi.trashBinTrash,
              label: context.l.mgDeleteSources,
              value: _deleteSources,
              danger: true,
              onChanged: (v) => setState(() => _deleteSources = v),
              padding: const EdgeInsets.all(16),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.tracks,
    required this.covers,
    required this.order,
    required this.onTap,
  });

  final UserPlaylist playlist;
  final int tracks;
  final Iterable<String?> covers;

  /// Number in merge order; `-1` if not picked.
  final int order;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final picked = order >= 0;

    return SheetRow(
      leading: Cover(url: playlist.cover, size: 40, covers: covers),
      gap: 12,
      label: playlist.name,
      subtitle: context.l.tracksCount(tracks),
      color: picked ? t.accent : t.text,
      trailing: picked ? CountBadge(order + 2, height: 24, size: 12) : null,
      onTap: onTap,
    );
  }
}
