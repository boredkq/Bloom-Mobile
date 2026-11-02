/// Sleep timer sheet, from the moon button in the player's tool row: presets,
/// until the end of the track, a custom time bar, +5 minutes on a running timer
/// and a fade switch. A solid background; it doesn't close on each tap, since
/// time isn't picked on the first try.
///
/// It only calls `sleep_timer_store`; `PlaybackController` handles pause and
/// volume.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
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
    final t = context.bloom;
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
                    child: _PresetCard(
                      minutes: preset.inMinutes,
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
            child: _EndOfTrackCard(
              active: sleep.mode == SleepMode.endOfTrack,
              onTap: () => sleep.mode == SleepMode.endOfTrack
                  ? ctrl.cancel()
                  : ctrl.untilTrackEnd(),
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
                      child: BloomButton(
                        label: l.playerSleepExtend,
                        icon: Bi.alarmAdd,
                        tone: ButtonTone.plate,
                        overlay: true,
                        height: 44,
                        onTap: ctrl.extend,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: BloomButton(
                      label: l.playerSleepCancel,
                      icon: Bi.alarmTurnOff,
                      tone: ButtonTone.plate,
                      overlay: true,
                      height: 44,
                      onTap: ctrl.cancel,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Divider(
            height: 1,
            thickness: 1,
            color: t.ovlLine2,
            indent: 20,
            endIndent: 20,
          ),
          SheetSwitchRow(
            label: l.playerSleepFade,
            subtitle: l.playerSleepFadeSub,
            value: sleep.fade,
            onChanged: ctrl.setFade,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ],
      ),
    );
  }
}

/// Preset: a large number with min under it, accent-filled when the timer runs
/// on this time.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.minutes,
    required this.active,
    required this.onTap,
  });

  final int minutes;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OptionTile(
    active: active,
    onTap: onTap,
    height: 56,
    builder: (ink) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$minutes',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.1,
            color: ink,
          ),
        ),
        Text(
          context.l.playerSleepMin,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            height: 1.2,
            color: ink.withValues(alpha: active ? 0.75 : 0.55),
          ),
        ),
      ],
    ),
  );
}

/// Until the end of the track, a wide plate under the presets.
class _EndOfTrackCard extends StatelessWidget {
  const _EndOfTrackCard({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OptionTile(
    active: active,
    onTap: onTap,
    height: 52,
    scale: 0.98,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    alignment: Alignment.centerLeft,
    builder: (ink) => Row(
      children: [
        BloomIcon(Bi.musicNote, size: 20, color: ink),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.l.playerSleepEndOfTrack,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: ink,
            ),
          ),
        ),
      ],
    ),
  );
}
