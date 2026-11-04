/// Settings: the groups and their rows. Sections that make no sense on a phone
/// aren't here; swipes are only here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../providers/yandex/ym_auth.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../lastfm/lastfm_store.dart';
import '../../pc/pc_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/language_flag.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/subpage_header.dart';
import '../about_store.dart';
import 'settings_rows.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        // No title: the tab's icon says it, and the first group has its header.
        // The bars float over the list: the bottom counts from them.
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottomBarsInset(context)),
        children: [
          SettingsGroup(
            title: context.l.setGroupApp,
            rows: [
              SettingsRow(
                icon: Bi.smartphone,
                title: context.l.setSystem,
                onTap: () => context.go('/settings/system'),
              ),
              SettingsRow(
                icon: Bi.eq,
                title: context.l.setAudio,
                onTap: () => context.go('/settings/audio'),
              ),
              SettingsRow(
                icon: Bi.database,
                title: context.l.setStorage,
                onTap: () => context.go('/settings/storage'),
              ),
              SettingsRow(
                icon: Bi.transferHorizontal,
                title: context.l.setSwipes,
                onTap: () => context.go('/settings/swipes'),
              ),
              // Not about looks but the app itself.
              const LanguageSettingsRow(),
              const VersionSettingsRow(),
            ],
          ),
          // All about how the app looks, in one group.
          SettingsGroup(
            title: context.l.setGroupInterface,
            rows: [
              SettingsRow(
                icon: Bi.sidebarMinimalistic,
                title: context.l.setAppearance,
                onTap: () => context.go('/settings/appearance'),
              ),
              SettingsRow(
                icon: Bi.musicNote,
                title: context.l.setPlayer,
                onTap: () => context.go('/settings/player'),
              ),
              SettingsRow(
                icon: Bi.widget,
                title: context.l.setMiniPlayer,
                onTap: () => context.go('/settings/miniplayer'),
              ),
              SettingsRow(
                icon: Bi.album,
                title: context.l.stCustom,
                onTap: () => context.go('/settings/customization'),
              ),
            ],
          ),
          const _IntegrationsGroup(),
        ],
      ),
    );
  }
}

/// A logo in its colours only if the integration is ready, grey otherwise: the
/// status shows without going in.
///
/// SoundCloud and YouTube Music work without signing in, so they're always
/// coloured; Yandex goes by its token, Last.fm by its session.
class _IntegrationsGroup extends ConsumerWidget {
  const _IntegrationsGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final off = context.bloom.muted;
    final ymOn = ref.watch(ymAuthProvider.select((s) => s.authed));
    final lfmOn = ref.watch(lastfmProvider.select((s) => s.connected));
    final pcName = ref.watch(pcProvider.select((s) => s.link?.name));
    return SettingsGroup(
      title: context.l.setGroupIntegrations,
      rows: [
        SettingsRow(
          title: 'SoundCloud',
          leading: const PlatformLogo(MusicSource.soundcloud, size: 20),
          onTap: () => context.go('/settings/soundcloud'),
        ),
        SettingsRow(
          title: context.l.sourceYandex,
          leading: PlatformLogo(
            MusicSource.yandex,
            size: 20,
            color: ymOn ? null : off,
          ),
          onTap: () => context.go('/settings/yandex'),
        ),
        SettingsRow(
          title: 'YouTube Music',
          leading: const PlatformLogo(MusicSource.ytmusic, size: 20),
          onTap: () => context.go('/settings/ytmusic'),
        ),
        SettingsRow(
          title: 'Last.fm',
          leading: ServiceLogo(
            Service.lastfm,
            size: 20,
            color: lfmOn ? null : off,
          ),
          onTap: () => context.go('/settings/lastfm'),
        ),
        SettingsRow(
          icon: Bi.monitor,
          title: context.l.setPc,
          value: pcName,
          onTap: () => context.go('/settings/pc'),
        ),
      ],
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.rows});

  final String title;

  /// [SettingsRow] or a wrapper over it: "Language" and "Version" need state.
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
          child: SettingsCaption(title),
        ),
        // Padding, icon, gap: the line starts under the row's text.
        SettingsGroupCard(rows: rows, dividerInset: 52),
      ],
    );
  }
}

/// The flag of the language in use; a tap opens the list. In place of the
/// chevron: it shows the choice and what the row is about.
class LanguageSettingsRow extends ConsumerWidget {
  const LanguageSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Not chosen by hand: the one in use, the system's, or the flag won't match
    // the text around it.
    final code =
        (ref.watch(settingsProvider.select((s) => s.locale)) ??
                Localizations.localeOf(context))
            .languageCode;
    return SettingsRow(
      icon: Bi.global,
      title: context.l.setLanguage,
      trailing: LanguageFlag(code: code),
      onTap: () => _pickLanguage(context, ref, code),
    );
  }
}

/// A flag, the name in that language, a check on the chosen. Closes on
/// choosing. No header: the row it came from stays visible above.
Future<void> _pickLanguage(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final picked = await showBloomSheetChild<Locale>(
    context: context,
    // With the sheet's own context: it lives in the root navigator, the page's
    // would close the tab.
    child: Builder(
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final locale in kLocales)
            SheetOptionTile(
              leading: LanguageFlag(code: locale.languageCode, width: 32),
              label: switch (locale.languageCode) {
                'ru' => sheetContext.l.apLanguageRu,
                _ => sheetContext.l.apLanguageEn,
              },
              active: locale.languageCode == current,
              onTap: () => Navigator.of(sheetContext).pop(locale),
            ),
        ],
      ),
    ),
  );
  if (picked != null) ref.read(settingsProvider.notifier).setLocale(picked);
}

/// The installed version on the right; a tap opens the update check with its
/// notes.
class VersionSettingsRow extends ConsumerStatefulWidget {
  const VersionSettingsRow({super.key});

  @override
  ConsumerState<VersionSettingsRow> createState() => _VersionSettingsRowState();
}

class _VersionSettingsRowState extends ConsumerState<VersionSettingsRow> {
  @override
  void initState() {
    super.initState();
    // Asked once a session, the answer holds until reinstalling. Not in
    // `build`: that would change state during the frame's build.
    Future.microtask(() => ref.read(aboutProvider.notifier).loadVersion());
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(aboutProvider.select((s) => s.version));
    return SettingsRow(
      icon: Bi.infoCircle,
      title: context.l.aboutVersion,
      // No answer from the platform: a dash is more honest than a zero.
      value: version.isEmpty ? '—' : 'v$version',
      onTap: () => context.go('/settings/version'),
    );
  }
}
