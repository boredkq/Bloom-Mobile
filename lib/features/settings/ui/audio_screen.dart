/// Settings → Audio: what happens to the last session on launch, and the queue
/// going on with similar tracks. The output device is the system's business
/// here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../features/audio_dsp/audio_dsp_models.dart';
import '../../../features/audio_dsp/audio_dsp_store.dart';
import '../../../features/audio_dsp/ui/equalizer_sheet.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
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
            SettingsRowShell(
              icon: Bi.eq,
              title: l.eqTitle,
              subtitle: l.eqSubtitle,
              onTap: () => showEqualizerSheet(context),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    eqStatus,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.bloom.text2,
                        ),
                  ),
                  const SizedBox(width: 8),
                  BloomIcon(
                    Bi.altArrowRight,
                    size: 16,
                    color: context.bloom.text2,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.eqCrossfadeTitle),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsRowShell(
              icon: Bi.speed,
              title: l.eqCrossfadeTitle,
              subtitle: l.eqCrossfadeSub,
              onTap: () => _pickCrossfade(
                context,
                ref,
                dspState.crossfadeSeconds,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dspState.crossfadeSeconds > 0
                        ? '${dspState.crossfadeSeconds} с'
                        : l.eqDisabled,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.bloom.text2,
                        ),
                  ),
                  const SizedBox(width: 8),
                  BloomIcon(
                    Bi.altArrowRight,
                    size: 16,
                    color: context.bloom.text2,
                  ),
                ],
              ),
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

String _formatCrossfadeSeconds(BuildContext context, int sec) {
  if (sec == 0) return context.l.eqDisabled;
  final isRu = Localizations.localeOf(context).languageCode == 'ru';
  if (isRu) {
    final mod10 = sec % 10;
    final mod100 = sec % 100;
    final unit = (mod10 == 1 && mod100 != 11)
        ? 'секунда'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20))
            ? 'секунды'
            : 'секунд';
    return '$sec $unit';
  }
  return '$sec ${sec == 1 ? "second" : "seconds"}';
}

Future<void> _pickCrossfade(
  BuildContext context,
  WidgetRef ref,
  int currentSeconds,
) async {
  final l = context.l;
  final isRu = Localizations.localeOf(context).languageCode == 'ru';
  const options = [0, 1, 2, 3, 4, 5, 7, 10, 12];

  final picked = await showBloomSheetChild<int>(
    context: context,
    header: SheetTitle(
      l.eqCrossfadeTitle,
      subtitle: l.eqCrossfadeSub,
    ),
    child: Builder(
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final sec in options)
            SheetOptionTile(
              icon: sec == 0 ? Bi.close : Bi.speed,
              label: _formatCrossfadeSeconds(sheetContext, sec),
              sub: sec == 3
                  ? (isRu
                      ? 'Рекомендуемое значение для мягкого перехода'
                      : 'Recommended duration for seamless transition')
                  : null,
              active: sec == currentSeconds,
              onTap: () => Navigator.of(sheetContext).pop(sec),
            ),
        ],
      ),
    ),
  );
  if (picked != null) {
    ref.read(audioDspProvider.notifier).setCrossfadeSeconds(picked);
  }
}
