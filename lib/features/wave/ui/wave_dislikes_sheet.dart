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

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SheetSurface(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              _Header(count: tracks.length),
              if (tracks.isEmpty)
                const _Empty()
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    itemCount: tracks.length,
                    itemBuilder: (context, i) => _Row(track: tracks[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l.waveDislikesTitle, style: theme.titleLarge),
                const SizedBox(height: 2),
                Text(context.l.tracksCount(count), style: theme.bodyMedium),
              ],
            ),
          ),
          // Снять все метки разом. Пустой список чистить нечего — кнопка гаснет.
          CircleIconButton(
            icon: Bi.trashBinTrash,
            iconSize: 20,
            onTap: count == 0
                ? null
                : () => ref.read(waveStoreProvider.notifier).clearDislikes(),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 30, 24, 46),
    child: Text(
      context.l.waveNoDislikes,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.bloom.muted),
    ),
  );
}

class _Row extends ConsumerWidget {
  const _Row({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Cover(url: track.cover, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Снять метку — трек снова может попасть в подбор.
          CircleIconButton(
            icon: Bi.close,
            iconSize: 18,
            onTap: () =>
                ref.read(waveStoreProvider.notifier).undislike(track.id),
          ),
        ],
      ),
    );
  }
}
