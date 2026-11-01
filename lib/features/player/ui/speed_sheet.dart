/// Пикер скорости — шторка по кнопке-спидометру в ряду инструментов плеера.
///
/// Порт десктопного `SpeedPicker.tsx`: три карточки-пресета (0.75× / 1× /
/// 1.25×), полоса произвольной скорости с засечками каждые 0.25× и тумблер
/// «Nightcore» (питч едет за темпом). На ПК это всплывашка у кнопки; на телефоне
/// — шторка снизу, по выбору пользователя, и фон у неё СПЛОШНОЙ (не размытая
/// обложка, как у меню трека) — он попросил именно так.
///
/// Значения уходят в `speed_store`, на плеер их ставит `PlaybackController`.
/// Шторка не закрывается ни по пресету, ни по тумблеру: скорость подбирают на
/// слух, и каждый раз открывать её заново незачем.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../speed_store.dart';

void showSpeedSheet(BuildContext context) {
  // Корневой навигатор и стекло затемнения — общие у всех наших шторок
  // (`showBloomModal`): иначе таб-бар и миниплеер остаются поверх затемнения.
  showBloomModal<void>(context: context, builder: (_) => const _SpeedSheet());
}

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final l = context.l;
    final speed = ref.watch(speedProvider);
    final ctrl = ref.read(speedProvider.notifier);

    return SheetShell(
      header: SheetTitle(l.playerSpeed, bottom: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final preset in kSpeedPresets) ...[
                  if (preset != kSpeedPresets.first) const SizedBox(width: 10),
                  Expanded(
                    child: _PresetCard(
                      value: preset,
                      active: speed.rate == preset,
                      onTap: () => ctrl.setRate(preset),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.playerSpeedCustom, style: theme.bodySmall),
                ),
                Semantics(
                  button: true,
                  label: context.l.playerSpeedReset,
                  child: BloomTag(
                    text: speedLabel(speed.rate),
                    active: speed.rate != 1,
                    onTap: ctrl.reset,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                SheetSlider(
                  value: speed.rate.clamp(kSpeedMin, kSpeedMax),
                  min: kSpeedMin,
                  max: kSpeedMax,
                  divisions: kSpeedDivisions,
                  label: speedLabel(speed.rate),
                  onChanged: ctrl.setRate,
                ),
                const _Ticks(),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(speedLabel(kSpeedMin), style: theme.bodySmall),
                    Text(speedLabel(kSpeedMax), style: theme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            thickness: 1,
            color: t.ovlLine2,
            indent: 20,
            endIndent: 20,
          ),
          SheetSwitchRow(
            label: l.playerSpeedNightcore,
            subtitle: l.playerSpeedNightcoreSub,
            value: speed.nightcore,
            onChanged: ctrl.setNightcore,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ],
      ),
    );
  }
}

/// Карточка-пресет: залита акцентом, когда стоит именно она.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.value,
    required this.active,
    required this.onTap,
  });

  final double value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OptionTile(
    active: active,
    onTap: onTap,
    height: 52,
    builder: (ink) => Text(
      speedLabel(value),
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: ink,
      ),
    ),
  );
}

/// Засечки под полосой — каждые 0.25×, совпавшие с пресетами крупнее.
///
/// Полоса поджата с краёв на пол-бегунка (так Slider считает дорожку), поэтому
/// и засечки живут в тех же границах: иначе крайние риски не сойдутся с
/// центром бегунка в упоре.
class _Ticks extends StatelessWidget {
  const _Ticks();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      height: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSheetSliderThumb),
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              for (final tick in kSpeedTicks)
                Positioned(
                  left:
                      (tick - kSpeedMin) /
                          (kSpeedMax - kSpeedMin) *
                          box.maxWidth -
                      0.5,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    height: kSpeedPresets.contains(tick) ? 8 : 5,
                    color: t.text.withValues(
                      alpha: kSpeedPresets.contains(tick) ? 0.3 : 0.16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
