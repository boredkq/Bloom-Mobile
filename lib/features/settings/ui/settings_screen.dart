/// Настройки.
///
/// Состав разделов — ПОРТ десктопного `SettingsNav.tsx` (`GROUPS`), названия
/// групп и пунктов взяты из `dict.ts` дословно. Из макета сюда пришла только
/// раскладка: капсовые заголовки групп и тёмные контейнеры со строками
/// «иконка — текст — шеврон».
///
/// Не перенесены разделы, которых на телефоне физически не бывает: «Оверлей»
/// (окно поверх других окон), «Горячие клавиши» (глобальные, на уровне ОС),
/// «Discord RPC», «Эффективность», «Страницы» и «Вкладки». Вместо них в
/// «Приложение» добавлены «Свайпы» — жесты есть только на телефоне. Иконки — те
/// же Solar, что на десктопе; исключение «Система»: там монитор, здесь
/// смартфон.
///
/// Заглушек в «Приложении» и «Интерфейсе» больше нет: работают «Система»,
/// «Аудио», «Хранилище», «Свайпы», «Внешний вид», «Плеер», «Мини плеер»,
/// кастомизация, все три площадки и «Last.fm».
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
import '../../../shared/ui/pressable.dart';
import '../../lastfm/lastfm_store.dart';
import '../../pc/pc_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/language_card.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/subpage_header.dart';
import '../about_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        // Заголовка экрана нет: вкладка и так подписана иконкой в таб-баре,
        // а первая группа начинается со своего капсового заголовка. Снизу к
        // полю добавлены бары каркаса — они плавают над списком.
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
              // Язык и версия — в конце группы, как на макете. Язык переехал
              // сюда из «Внешнего вида»: он не про оформление, а про само
              // приложение.
              const LanguageSettingsRow(),
              const VersionSettingsRow(),
            ],
          ),
          // Всё про вид приложения — одной группой «Интерфейс», включая обе
          // страницы кастомизации: своей группой они стояли отдельной от
          // «Оформления» плашкой, хотя настраивают ровно то же самое (так
          // решил пользователь, показав макет).
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
              // Тот же значок, каким мини-плеер помечен как поверхность в
              // «Смене трека»: строка и там и тут про одну карточку.
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

/// «Интеграции»: знак в фирменных цветах, только если интеграция готова к
/// работе, иначе он серый — статус видно, не заходя в раздел.
///
/// SoundCloud и YouTube Music работают без входа (ключ SoundCloud подбирается
/// сам), поэтому они всегда цветные. Яндекс.Музыка — по сохранённому токену,
/// Last.fm — по ключу сессии.
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
        // Bloom на ПК — пара раздела «Интеграции → Телефон» там.
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

  /// Строки группы — [SettingsRow] или обёртка над ней («Язык», «Версия»:
  /// им нужно своё состояние).
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
        // 14 паддинга + 24 иконки + 14 зазора: линия начинается ровно под
        // текстом строки.
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
    this.onTap,
    this.value,
    this.trailing,
  });

  final BloomGlyph? icon;
  final Widget? leading;
  final String title;
  final VoidCallback? onTap;

  /// Что показать справа от названия, перед шевроном (номер версии).
  final String? value;

  /// Чем заменить шеврон (флаг у языка): строка и так открывает шторку, а
  /// стрелка рядом с флагом читалась бы вторым значком.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final ready = onTap != null;
    return Pressable(
      onTap: onTap ?? () => _showStub(context, title),
      scale: 0.98,
      child: Padding(
        // 22 по вертикали + 20 строки текста = 64 на строку.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child:
                  leading ??
                  BloomIcon(icon, size: 20, color: ready ? t.iconFg : t.muted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: ready
                    ? theme.titleMedium
                    : theme.titleMedium?.copyWith(color: t.text2),
              ),
            ),
            if (value case final text?) ...[
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.bodyMedium?.copyWith(color: t.text2),
              ),
              const SizedBox(width: 10),
            ],
            trailing ?? BloomIcon(Bi.altArrowRight, size: 16, color: t.text2),
          ],
        ),
      ),
    );
  }
}

/// Строка «Язык»: справа флаг того языка, на котором приложение сейчас
/// говорит, тап — шторка со списком.
///
/// Флаг вместо шеврона — как на макете: он и показывает выбранное, и говорит,
/// что строка про язык, без второго значка справа.
class LanguageSettingsRow extends ConsumerWidget {
  const LanguageSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Язык не выбран руками — показываем тот, на котором приложение говорит
    // сейчас (системный), иначе флаг не соответствовал бы тексту вокруг.
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

/// Шторка выбора языка: флаг, название на самом языке, галочка у выбранного.
/// Закрывается от выбора — выбирать в ней больше нечего.
///
/// Шапки нет: строка, из которой сюда пришли, осталась видна над шторкой, и
/// подписывать список флагов словом «Язык» второй раз незачем (та же причина,
/// что у шторок «Плеера»).
Future<void> _pickLanguage(
  BuildContext context,
  WidgetRef ref,
  String current,
) async {
  final picked = await showBloomSheetChild<Locale>(
    context: context,
    // Закрывать шторку надо ЕЁ контекстом: она живёт в корневом навигаторе, а
    // «Настройки» — во вложенном, и `pop` со страничным закрыл бы вкладку.
    child: Builder(
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final locale in kLocales)
            _LanguageTile(
              locale: locale,
              active: locale.languageCode == current,
              onTap: () => Navigator.of(sheetContext).pop(locale),
            ),
        ],
      ),
    ),
  );
  if (picked != null) ref.read(settingsProvider.notifier).setLocale(picked);
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.locale,
    required this.active,
    required this.onTap,
  });

  final Locale locale;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final name = switch (locale.languageCode) {
      'ru' => context.l.apLanguageRu,
      _ => context.l.apLanguageEn,
    };
    return SheetPanel(
      // Строки стоят вплотную — как в шторках «Плеера»: полный просвет блока
      // рвал бы короткий список на отдельные плашки.
      gap: 3,
      children: [
        Pressable(
          onTap: onTap,
          scale: 0.98,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 17, 18, 17),
            child: Row(
              children: [
                LanguageFlag(code: locale.languageCode, width: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (active) BloomIcon(Bi.check, size: 20, color: t.accent),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Строка «Версия»: справа номер установленной сборки, тап — страница проверки
/// обновлений с заметками к новой версии.
class VersionSettingsRow extends ConsumerStatefulWidget {
  const VersionSettingsRow({super.key});

  @override
  ConsumerState<VersionSettingsRow> createState() => _VersionSettingsRowState();
}

class _VersionSettingsRowState extends ConsumerState<VersionSettingsRow> {
  @override
  void initState() {
    super.initState();
    // Версию спрашиваем у платформы один раз за сеанс: ответ не меняется до
    // переустановки. Не в `build` — там правка состояния пришлась бы на фазу
    // построения кадра.
    Future.microtask(() => ref.read(aboutProvider.notifier).loadVersion());
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(aboutProvider.select((s) => s.version));
    return SettingsRow(
      icon: Bi.infoCircle,
      title: context.l.aboutVersion,
      // Платформа не ответила (так бывает в тестах и на десктопе) — прочерк
      // честнее нуля.
      value: version.isEmpty ? '—' : 'v$version',
      onTap: () => context.go('/settings/version'),
    );
  }
}

void _showStub(BuildContext context, String title) =>
    showToast(context, context.l.setStub(title), kind: ToastKind.warn);
