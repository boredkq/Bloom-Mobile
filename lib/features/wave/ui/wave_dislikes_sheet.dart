/// Wave dislikes, a sheet: the list is short and has one action, removing a
/// mark. A dislike is one across all platforms, so there's one list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../wave_store.dart';

void showWaveDislikesSheet(BuildContext context) => showBloomModal<void>(
  context: context,
  builder: (_) => const _DislikesSheet(),
);

class _DislikesSheet extends ConsumerWidget {
  const _DislikesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Newest on top.
    final tracks = ref.watch(waveStoreProvider).dislikes;

    return SheetShell(
      scrolls: false,
      header: SheetTitle(
        context.l.waveDislikesTitle,
        right: 12,
        bottom: 12,
        trailing: tracks.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SheetCountPill('${tracks.length}'),
                  const SizedBox(width: 8),
                  // Months of marks go at once, so it asks with a second press.
                  SecondTap(
                    onConfirm: ref
                        .read(waveStoreProvider.notifier)
                        .clearDislikes,
                    builder: (armed, tap) => CircleIconButton(
                      icon: Bi.trashBinTrash,
                      iconSize: 20,
                      label: context.l.commonClear,
                      background: armed
                          ? context.bloom.danger.withValues(alpha: 0.14)
                          : Colors.transparent,
                      color: armed ? context.bloom.danger : null,
                      onTap: tap,
                    ),
                  ),
                ],
              ),
      ),
      child: tracks.isEmpty
          ? CenterNote(
              context.l.waveNoDislikes,
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 46),
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 10),
              itemCount: tracks.length,
              itemBuilder: (context, i) => _Row(track: tracks[i]),
            ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SheetRow(
    leading: Cover(url: track.cover, size: 40),
    gap: 12,
    label: track.name,
    subtitle: track.artist,
    color: context.bloom.text,
    // Off the list, the track can be picked again.
    trailing: CircleIconButton(
      icon: Bi.close,
      size: 40,
      iconSize: 18,
      background: Colors.transparent,
      color: context.bloom.muted,
      onTap: () => ref.read(waveStoreProvider.notifier).undislike(track.id),
    ),
  );
}
