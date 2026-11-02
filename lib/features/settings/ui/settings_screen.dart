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
import '../../telegram/telegram_store.dart';
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
    final tg = ref.watch(telegramAuthProvider);
    final pcName = ref.watch(pcProvider.select((s) => s.link?.name));
    return SettingsGroup(
      title: context.l.setGroupIntegrations,
      rows: [
        SettingsRow(
          title: 'Telegram',
          leading: const BloomIcon(Bi.send, size: 20, color: Color(0xFF2AABEE)),
          value: tg.authed ? (tg.user?.displayName ?? 'Подключен') : null,
          onTap: () => _openTelegramSettings(context, ref),
        ),
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

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    required this.onTap,
    this.value,
    this.trailing,
  });

  final BloomGlyph? icon;
  final Widget? leading;
  final String title;
  final VoidCallback onTap;

  /// Right of the title, before the chevron: the version number.
  final String? value;

  /// Replaces the chevron: an arrow beside the flag would read as a second
  /// icon.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final text = value;
    return SettingsRowShell(
      icon: icon,
      leading: leading,
      title: title,
      // Makes 64 a row with the text line.
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text != null) ...[
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.text2),
            ),
            const SizedBox(width: 10),
          ],
          trailing ?? BloomIcon(Bi.altArrowRight, size: 16, color: t.text2),
        ],
      ),
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

Future<void> _openTelegramSettings(BuildContext context, WidgetRef ref) async {
  final tg = ref.read(telegramAuthProvider);
  final t = context.bloom;

  if (tg.authed) {
    await showBloomSheetChild<void>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2AABEE).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const BloomIcon(
                    Bi.send,
                    size: 20,
                    color: Color(0xFF2AABEE),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tg.user?.displayName ?? 'Telegram',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (tg.user?.handle case final handle?)
                        Text(
                          handle,
                          style: TextStyle(color: t.text2, fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: t.text,
                side: BorderSide(color: t.accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: BloomIcon(Bi.refresh, size: 18, color: t.accent),
              label: const Text('Синхронизировать с облаком'),
              onPressed: () async {
                final ok = await ref.read(telegramAuthProvider.notifier).pushBackup();
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Медиатека, уровень и плейлисты сохранены в облаке!'
                          : 'Ошибка сохранения в облако'),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: t.text2,
                side: BorderSide(color: t.ovlLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: BloomIcon(Bi.downloadMinimalistic, size: 18, color: t.text2),
              label: const Text('Восстановить из облака'),
              onPressed: () async {
                final ok = await ref.read(telegramAuthProvider.notifier).pullBackup();
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Данные успешно восстановлены из облака!'
                          : 'Облачная копия не найдена'),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: t.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                ref.read(telegramAuthProvider.notifier).logout();
                Navigator.of(context).pop();
              },
              child: const Text('Отключить Telegram'),
            ),
          ],
        ),
      ),
    );
    return;
  }

  final vercelCtrl = TextEditingController(
    text: 'https://bloom-auth.vercel.app',
  );

  await showBloomSheetChild<void>(
    context: context,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2AABEE).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const BloomIcon(
                  Bi.send,
                  size: 20,
                  color: Color(0xFF2AABEE),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Подключение Telegram',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Адрес Vercel-бэкенда с Telegram Login Widget:',
            style: TextStyle(fontSize: 13, color: t.text2),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: vercelCtrl,
            decoration: InputDecoration(
              hintText: 'https://your-bloom.vercel.app',
              filled: true,
              fillColor: t.ovlBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.ovlLine),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2AABEE),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            onPressed: () {
              final url = vercelCtrl.text.trim();
              if (url.isNotEmpty) {
                ref.read(telegramAuthProvider.notifier).startWebLogin(url);
                Navigator.of(context).pop();
              }
            },
            child: const Text(
              'Открыть Telegram Login Widget',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
