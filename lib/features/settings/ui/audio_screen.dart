/// Settings → Audio: what happens to the last session on launch, and the queue
/// going on with similar tracks. The output device is the system's business
/// here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../features/audio_dsp/audio_dsp_models.dart';
import '../../../features/audio_dsp/audio_dsp_store.dart';
import '../../../features/audio_dsp/ui/equalizer_sheet.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/subpage_header.dart';
import 'settings_rows.dart';

class AudioSettingsScreen extends ConsumerWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final dspState = ref.watch(audioDspProvider);
    final dspNotifier = ref.read(audioDspProvider.notifier);

    final activePreset = AudioPresets.byId(
      dspState.presetId,
      dspState.customPresets,
    );
    final eqStatus = dspState.enabled
        ? '${activePreset.name} • ${l.eqActive}'
        : l.eqDisabled;

    return SubPage(
      title: l.setAudio,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.eqTitle),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsRow(
              icon: Bi.eq,
              title: l.eqTitle,
              value: eqStatus,
              onTap: () => showEqualizerSheet(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.eqCrossfadeTitle),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsRow(
              icon: Bi.speed,
              title: l.eqCrossfadeTitle,
              value: dspState.crossfadeSeconds > 0
                  ? '${dspState.crossfadeSeconds} сек • ${l.eqCrossfadeSub}'
                  : l.eqDisabled,
              onTap: () {
                final nextSeconds = (dspState.crossfadeSeconds + 3) % 15;
                dspNotifier.setCrossfadeSeconds(nextSeconds);
              },
            ),
            SettingsToggleRow(
              icon: Bi.album,
              title: l.eqSmartGaplessTitle,
              subtitle: l.eqSmartGaplessSub,
              value: dspState.smartGapless,
              onChanged: dspNotifier.setSmartGapless,
            ),
            SettingsToggleRow(
              icon: Bi.soundwave,
              title: l.eqNormalizationTitle,
              subtitle: l.eqNormalizationSub,
              value: dspState.normalizeVolume,
              onChanged: dspNotifier.setNormalizeVolume,
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.sysStartup),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsToggleRow(
              icon: Bi.playlistMinimalistic,
              title: l.audRestoreTitle,
              subtitle: l.audRestoreSub,
              value: settings.restoreQueue,
              onChanged: controller.setRestoreQueue,
            ),
            // Autoplay only goes on from a restored session: turning that off
            // takes it along.
            SettingsToggleRow(
              icon: Bi.play,
              title: l.audAutoplayTitle,
              subtitle: l.audAutoplaySub,
              value: settings.autoplay,
              enabled: settings.restoreQueue,
              onChanged: controller.setAutoplay,
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.audQueue),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsToggleRow(
              icon: Bi.skipNext,
              title: l.audAutoSimilarTitle,
              subtitle: l.audAutoSimilarSub,
              value: settings.autoSimilar,
              onChanged: controller.setAutoSimilar,
            ),
          ],
        ),
      ],
    );
  }
}
