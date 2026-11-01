/// «Дизлайки в волне» — порт `DislikesModal.tsx`. На телефоне это шторка, а не
/// отдельный экран: список короткий и живёт ровно одним действием — снять
/// метку.
///
/// Дизлайк у нас один на все площадки (см. `wave_store`), поэтому и списка
/// здесь один, без десктопного склеивания «библиотечные + гостевые».
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
    // Новые сверху, как на ПК.
    final tracks = ref.watch(waveStoreProvider).dislikes;

    return SheetShell(
      scrolls: false,
      header: SheetTitle(
        context.l.waveDislikesTitle,
        subtitle: context.l.tracksCount(tracks.length),
        right: 12,
        bottom: 12,
        trailing: CircleIconButton(
          icon: Bi.trashBinTrash,
          iconSize: 20,
          onTap: tracks.isEmpty
              ? null
              : () => ref.read(waveStoreProvider.notifier).clearDislikes(),
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
    leading: Cover(url: track.cover, size: 44),
    gap: 12,
    label: track.name,
    subtitle: track.artist,
    color: context.bloom.text,
    // Off the list, the track can be picked again.
    trailing: CircleIconButton(
      icon: Bi.close,
      iconSize: 18,
      onTap: () => ref.read(waveStoreProvider.notifier).undislike(track.id),
    ),
  );
}
