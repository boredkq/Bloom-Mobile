/// Tuning the wave (a long press on its stage): the platform and the way into
/// the dislikes.
///
/// The platform switch ALWAYS shows, not only after Yandex login: hidden whole,
/// it looks as if there's no choice. So with no login the Yandex tile dims and
/// says on tap where to go.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../providers/yandex/ym_auth.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';
import '../wave_store.dart';
import 'wave_dislikes_sheet.dart';

/// A sheet with no cover and a solid background: the wave has no picture.
void showWaveTuneSheet(BuildContext context) =>
    showBloomModal<void>(context: context, builder: (_) => const _TuneSheet());

class _TuneSheet extends ConsumerWidget {
  const _TuneSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final source = ref.watch(waveStoreProvider).source;
    final dislikes = ref.watch(waveStoreProvider).dislikes.length;
    // Through the provider, not `ym.activeToken()`: module state isn't
    // reactive, and after login the sheet would keep a dimmed tile.
    final ymAuthed = ref.watch(ymAuthProvider).authed;

    return SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tiles lie right on the sheet with no plate or caption: the logos
          // say it's a platform choice.
          Padding(
            // Side margin as on the dislikes block below, or tiles pass its
            // edges.
            padding: const EdgeInsets.fromLTRB(kSheetEdge, 12, kSheetEdge, 10),
            child: Row(
              children: [
                for (final s in kWaveSources) ...[
                  if (s != kWaveSources.first) const SizedBox(width: 10),
                  Expanded(
                    child: _SourceTile(
                      source: s,
                      label: s.label10n(context.l),
                      selected:
                          source == s && (s != MusicSource.yandex || ymAuthed),
                      enabled: s != MusicSource.yandex || ymAuthed,
                      // With no Yandex account there's nothing to choose, but
                      // silence won't do: I say where to log in.
                      onTap: s == MusicSource.yandex && !ymAuthed
                          ? () => toaster.show(
                              context.l.waveToastYmNoAuth,
                              kind: ToastKind.warn,
                            )
                          : () => _pick(ref, s),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SheetPanel(
            children: [
              SheetRow(
                icon: Bi.dislike,
                label: context.l.waveDislikes,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$dislikes',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: t.muted),
                    ),
                    const SizedBox(width: 6),
                    BloomIcon(Bi.altArrowRight, size: 18, color: t.muted),
                  ],
                ),
                onTap: () => openNextSheet(
                  context,
                  () => showWaveDislikesSheet(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _pick(WidgetRef ref, MusicSource source) =>
      ref.read(waveStoreProvider.notifier).setSource(source);
}

/// Platform tile: a logo and OUTLINE in its brand colour, not the theme's
/// accent. No fill: the selected one's frame burns at full strength, others
/// barely show the same colour.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final MusicSource source;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The platform is available. A disabled one dims but catches taps, to
  /// explain why.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final tile = Pressable(
      onTap: onTap,
      child: Material(
        // The chosen one stands on a film, the others on nothing.
        color: selected ? t.text.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(t.radius * 0.8),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              PlatformLogo(source, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? t.text : t.text2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return enabled ? tile : Opacity(opacity: 0.45, child: tile);
  }
}
