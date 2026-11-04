/// Sleep timer sheet, from the moon button in the player's tool row: presets,
/// until the end of the track, a custom time bar, +5 minutes on a running timer
/// and a fade tile. A solid background; it doesn't close on each tap, since time
/// isn't picked on the first try.
///
/// It only calls `sleep_timer_store`; `PlaybackController` handles pause and
/// volume.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../sleep_timer_store.dart';

void showSleepSheet(BuildContext context) {
  showBloomModal<void>(context: context, builder: (_) => const _SleepSheet());
}

class _SleepSheet extends ConsumerWidget {
  const _SleepSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context).textTheme;
    final l = context.l;
    final sleep = ref.watch(sleepTimerProvider);
    final ctrl = ref.read(sleepTimerProvider.notifier);
    final running = sleep.mode == SleepMode.timer;

    return SheetShell(
      header: SheetTitle(
        l.playerSleep,
        bottom: 14,
        trailing: running
            ? BloomTag(text: l.playerSleepLeft(sleepLabel(sleep.remaining)))
            : sleep.mode == SleepMode.endOfTrack
            ? BloomTag(text: l.playerSleepEndOfTrack)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final preset in kSleepPresets) ...[
                  if (preset != kSleepPresets.first) const SizedBox(width: 8),
                  Expanded(
                    child: OptionTile.label(
                      l.playerSleepMinutes(preset.inMinutes),
                      size: 13,
                      height: 50,
                      active: running && sleep.choice == preset,
                      // A tap on the selected preset clears the timer: no need
                      // to look for a cancel button.
                      onTap: () => running && sleep.choice == preset
                          ? ctrl.cancel()
                          : ctrl.start(preset),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: OptionTile.label(
                l.playerSleepEndOfTrack,
                scale: 0.98,
                active: sleep.mode == SleepMode.endOfTrack,
                onTap: () => sleep.mode == SleepMode.endOfTrack
                    ? ctrl.cancel()
                    : ctrl.untilTrackEnd(),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.playerSleepCustom, style: theme.bodySmall),
                ),
                BloomTag(
                  text: l.playerSleepMinutes(sleep.choice.inMinutes),
                  active: running,
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
                  value: clampSleepMinutes(sleep.choice.inMinutes).toDouble(),
                  min: kSleepMinMinutes.toDouble(),
                  max: kSleepMaxMinutes.toDouble(),
                  divisions: kSleepDivisions,
                  label: l.playerSleepMinutes(sleep.choice.inMinutes),
                  // It moves the time right away: the sheet has no start
                  // button, so what's under the finger must be real.
                  onChanged: (v) => ctrl.start(Duration(minutes: v.round())),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l.playerSleepMinutes(kSleepMinMinutes),
                      style: theme.bodySmall,
                    ),
                    Text(
                      l.playerSleepMinutes(kSleepMaxMinutes),
                      style: theme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (sleep.active) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // +5 minutes makes sense only for running time: until the end
                  // of the track has nothing to extend.
                  if (running) ...[
                    Expanded(
                      child: SheetButton(
                        label: l.playerSleepExtend,
                        icon: Bi.alarmAdd,
                        onTap: ctrl.extend,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SheetButton(
                      label: l.playerSleepCancel,
                      icon: Bi.alarmTurnOff,
                      onTap: ctrl.cancel,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: OptionTile.label(
                l.playerSleepFade,
                scale: 0.98,
                active: sleep.fade,
                onTap: () => ctrl.setFade(!sleep.fade),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
