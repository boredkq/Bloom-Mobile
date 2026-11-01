/// Tuning the wave (a long press on its stage), as `WaveMenu` on the PC: the
/// platform and the way into the dislikes.
///
/// Заголовка строкой нет: шторку открывают жестом с самой волны, и подписывать
/// её нечем — плитки и «Дизлайки» говорят за себя.
///
/// Отличие от ПК: переключатель площадки показывается ВСЕГДА, а не только
/// после входа в Яндекс. Спрятанный целиком, он выглядит так, будто выбора
/// нет вовсе — на десктопе рядом стоят настройки интеграций и это заметно, а
/// здесь единственная строка «Дизлайки» ничего не объясняет. Поэтому плитка
/// Яндекса без входа просто гаснет и по тапу говорит, куда идти.
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

/// Шторка без обложки — как пикер скорости: сплошной фон, ручка и заголовок
/// строкой. Меню трека с размытой обложкой здесь не подходит, картинки у волны
/// нет.
void showWaveTuneSheet(BuildContext context) =>
    showBloomModal<void>(context: context, builder: (_) => const _TuneSheet());

class _TuneSheet extends ConsumerWidget {
  const _TuneSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final source = ref.watch(waveStoreProvider).source;
    final dislikes = ref.watch(waveStoreProvider).dislikes.length;
    // Именно через провайдер, а не `ym.activeToken()`: модульное состояние не
    // реактивно, и после входа шторка осталась бы с погашенной плиткой.
    final ymAuthed = ref.watch(ymAuthProvider).authed;

    return SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Плитки лежат прямо на шторке, без подложки и подписи: что это
          // выбор площадки, видно по самим логотипам.
          Padding(
            // Боковой край — как у блока «Дизлайки» ниже, иначе плитки
            // вылезают за его границы.
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
                      // Без аккаунта Яндекса выбирать нечего, но и молчать
                      // нельзя — говорим, куда идти за входом.
                      onTap: s == MusicSource.yandex && !ymAuthed
                          ? () => showToast(
                              context,
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
                onTap: () {
                  Navigator.of(context).pop();
                  showWaveDislikesSheet(context);
                },
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

/// Плитка площадки: логотип и ОБВОДКА в её фирменном цвете, а не в акценте
/// темы. Заливки нет — выбранная отличается тем, что рамка горит в полную силу,
/// а у остальных тот же цвет еле виден.
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

  /// Площадка доступна. Выключенная гаснет, но тап ловит — чтобы объяснить,
  /// почему она недоступна.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final brand = platformColor[source] ?? t.accent;
    final tile = Pressable(
      onTap: onTap,
      child: Material(
        // Заливки нет ни у выбранной, ни у остальных: фирменный цвет здесь
        // только в обводке и логотипе.
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(t.radius * 0.8),
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radius * 0.8),
            border: Border.all(
              color: brand.withValues(alpha: selected ? 1 : 0.28),
              width: selected ? 1.5 : 1,
            ),
          ),
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
