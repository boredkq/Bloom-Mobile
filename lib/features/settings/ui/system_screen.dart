/// Settings → System: playlists to a file and back, the log and the danger
/// zone. Confirmations are the shared sheet with a red button
/// ([confirmDanger]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/log/bloom_log.dart';
import '../../../core/store/library_store.dart';
import '../../../core/store/text_files.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/danger_confirm.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../library/import_file.dart';
import '../data_transfer.dart';
import '../reset.dart';
import 'settings_rows.dart';

class SystemSettingsScreen extends ConsumerWidget {
  const SystemSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final t = context.bloom;

    return SubPage(
      title: l.setSystem,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.sysImportExport.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsLinkRow(
              icon: Bi.export,
              title: l.sysExportTitle,
              subtitle: l.sysExportSub,
              enabled: ref.watch(
                libraryProvider.select((lib) => lib.playlists.isNotEmpty),
              ),
              onTap: () => _exportAll(context, ref),
            ),
            SettingsLinkRow(
              icon: Bi.import,
              title: l.sysImportTitle,
              subtitle: l.sysImportSub,
              onTap: () => _import(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.sysLogs.toUpperCase()),
        const SizedBox(height: 10),
        // Subscribed: the log's page lies over this one, and after clearing
        // this page wouldn't rebuild and would keep the old number.
        ValueListenableBuilder<int>(
          valueListenable: BloomLog.instance.count,
          builder: (context, count, _) => SettingsGroupCard(
            dividerInset: 52,
            rows: [
              SettingsLinkRow(
                icon: Bi.documentText,
                title: l.sysLogTitle,
                subtitle: count == 0
                    ? l.sysLogEmptySub
                    : l.sysLogEntries(count),
                onTap: () => context.go('/settings/system/logs'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            BloomIcon(Bi.dangerTriangle, size: 13, color: t.danger),
            const SizedBox(width: 6),
            SettingsCaption(l.sysDangerZone.toUpperCase()),
          ],
        ),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsLinkRow(
              icon: Bi.restart,
              title: l.sysResetTitle,
              subtitle: l.sysResetSub,
              danger: true,
              onTap: () => _confirmReset(context, ref, hard: false),
            ),
            SettingsLinkRow(
              icon: Bi.trashBinTrash,
              title: l.sysHardResetTitle,
              subtitle: l.sysHardResetSub,
              danger: true,
              onTap: () => _confirmReset(context, ref, hard: true),
            ),
          ],
        ),
      ],
    );
  }
}

/// All playlists to a file. A cancelled dialog stays silent.
Future<void> _exportAll(BuildContext context, WidgetRef ref) async {
  final l = context.l;
  final messenger = ScaffoldMessenger.of(context);
  final lib = ref.read(libraryProvider);
  final ok = await saveTextFile(
    l.sysExportFilename,
    await buildExportAllBundle(lib),
  );
  if (!ok) return;
  logInfo('transfer', 'выгружено плейлистов: ${lib.playlists.length}');
  messenger.toast(l.sysExported, kind: ToastKind.success);
}

/// The same flow as "From file" in the library's plus.
Future<void> _import(BuildContext context, WidgetRef ref) =>
    importPlaylistFile(ref, ScaffoldMessenger.of(context), context.l);

/// [hard] is "Reset everything".
Future<void> _confirmReset(
  BuildContext context,
  WidgetRef ref, {
  required bool hard,
}) async {
  final l = context.l;
  final messenger = ScaffoldMessenger.of(context);

  final yes = await confirmDanger(
    context,
    icon: hard ? Bi.trashBinTrash : Bi.restart,
    title: hard ? l.sysHardResetTitle : l.sysResetTitle,
    body: hard ? l.sysHardResetBody : l.sysResetBody,
    button: hard ? l.sysHardResetBtn : l.sysResetBtn,
  );
  if (!yes) return;

  if (hard) {
    await hardReset(ref);
    messenger.toast(l.sysHardResetDone, kind: ToastKind.success);
  } else {
    await resetSettings(ref);
    messenger.toast(l.sysResetDone, kind: ToastKind.success);
  }
}
