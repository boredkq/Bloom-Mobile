/// Speed picker sheet, from the speedometer button in the player's tool row:
/// three preset tiles (0.75×, 1×, 1.25×), a custom speed bar with marks every
/// 0.25× and a wide Nightcore tile (pitch follows tempo). A solid background.
///
/// Values go to `speed_store`, and `PlaybackController` applies them. The sheet
/// doesn't close on a preset or switch: speed gets picked by ear.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../speed_store.dart';

void showSpeedSheet(BuildContext context) {
  // The root navigator and dimming glass, as for all my sheets, or the tab bar
  // and mini player stay over the dimming.
  showBloomModal<void>(context: context, builder: (_) => const _SpeedSheet());
}

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    child: OptionTile.label(
                      speedLabel(preset),
                      size: 16,
                      height: 50,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: OptionTile.label(
                l.playerSpeedNightcore,
                scale: 0.98,
                active: speed.nightcore,
                onTap: () => ctrl.setNightcore(!speed.nightcore),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks under the bar every 0.25×, those matching presets larger. The bar is
/// inset by half a knob (how Slider computes its track), so the marks live in
/// the same bounds, or the outer ones miss the knob's centre at the stops.
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
