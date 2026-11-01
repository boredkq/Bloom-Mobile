/// Settings → Audio: what happens to the last session on launch, and the queue
/// going on with similar tracks. The output device is the system's business
/// here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
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

    return SubPage(
      title: l.setAudio,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.sysStartup.toUpperCase()),
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
        SettingsCaption(l.audQueue.toUpperCase()),
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
