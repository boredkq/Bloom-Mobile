/// Внешний вид: тема, акцент, прозрачность.
///
/// Тема — ровно три цвета пресета; акцент живёт отдельно и при смене темы НЕ
/// сбрасывается (то же правило, что в десктопном `themeStore.ts`).
/// Превью пресета считается теми же формулами, что и сама тема, поэтому кружки
/// в списке не могут разойтись с тем, что применится.
///
/// Радиуса тут больше нет: скругление задано одним числом на всё приложение
/// ([kBloomRadius]) — настройку он убрал сам. Убрана она ЦЕЛИКОМ: поля `radius`
/// нет ни в модели настроек, ни в `bloom.json`, и старое сохранённое число
/// (файлы с ползунком ещё ходят) больше не применяется — при первом же
/// сохранении настроек ключ из файла пропадёт.
///
/// Пресеты выбираются не сеткой на странице, а нижней шторкой: на экране
/// остаётся одна строка «Тема — Dark» с кружками превью справа.
///
/// Ручного выбора акцента нет — как и на ПК, где акцент задаётся либо темой,
/// либо тогглом авто-акцента из обложки.
///
/// Языка тут больше нет (на ПК секция «ЯЗЫК» стоит над «ТЕМА»): он строкой в
/// группе «Приложение» корневых «Настроек» — язык не про вид, а про само
/// приложение, и ищут его там.
library;

import 'dart:math' show Random, min;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/fonts.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/color_picker.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../customization/custom_store.dart';
import '../../customization/media_store.dart' show kBgBlurMax, kBgDimMax;
import '../../wrapped/wrapped_store.dart';
import '../transparency_store.dart';
import '../user_fonts.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context).textTheme;

    return SubPage(
      title: context.l.setAppearance,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(context.l.apTheme),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            _SettingsCard(
              onTap: () => _pickTheme(context, ref),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l.apThemeRow, style: theme.titleMedium),
                        const SizedBox(height: 3),
                        // У авто-темы пресетного имени нет — она режим, и
                        // называется переводом, как на ПК.
                        Text(
                          settings.autoTheme
                              ? context.l.thAutoName
                              : settings.preset.name,
                          style: theme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  _ThemeDots(preset: settings.preset),
                ],
              ),
            ),
            // Авто-акцент — тот же тоггл, что в десктопной секции «Интерфейс»:
            // ручного выбора акцента нет ни там, ни здесь. При авто-теме его
            // не показывают вовсе (так же на ПК): она красит акцент сама, и
            // выбирать между ними нечего.
            if (!settings.autoTheme)
              _SettingsCard(
                child: _SettingsRow(
                  title: context.l.apAutoAccent,
                  subtitle: context.l.apAutoAccentSub,
                  trailing: BloomSwitch(
                    value: settings.autoAccent,
                    onChanged: controller.setAutoAccent,
                  ),
                ),
              ),
            // Яркость — отдельной строкой под тогглом, ровно как на ПК: она
            // нужна, пока включён авто-акцент ИЛИ авто-тема (акцент у них
            // считается одной формулой). Ползунок не на самой странице, а в
            // шторке — тем же способом, что и ползунки прозрачности ниже:
            // строка показывает значение, крутят его в шторке.
            if (settings.autoAccent || settings.autoTheme)
              _ValueRow(
                icon: Bi.sun2,
                title: context.l.apAutoAccentLevel,
                value: '${(settings.autoAccentL * 100).round()} %',
                onTap: () => _pickIntValue(
                  context: context,
                  title: context.l.apAutoAccentLevel,
                  value: (settings.autoAccentL * 100).round(),
                  minValue: (kAutoAccentLMin * 100).round(),
                  max: (kAutoAccentLMax * 100).round(),
                  unit: ' %',
                  // Акцент считается на ходу — иначе яркость крутишь вслепую:
                  // шторка и сама покрашена в него.
                  onChanged: (v) => controller.setAutoAccentL(v / 100),
                ),
              ),
            // Бейджи стоят тут же, в блоке темы, и сразу после авто-акцента —
            // тот же порядок, что в десктопной секции «Интерфейс»: настройка
            // про акцент, а не про скругления. Тексты — из `dict.ts`
            // (`settings.interface.accentBadges`).
            _SettingsCard(
              child: _SettingsRow(
                title: context.l.apBadgesTitle,
                subtitle: context.l.apBadgesSubtitle,
                trailing: BloomSwitch(
                  value: settings.accentBadges,
                  onChanged: controller.setAccentBadges,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        ..._transparencyGroup(context, ref),
        // Шрифт — после прозрачности, как на ПК (там между ними ещё
        // «Масштаб», которого на телефоне нет).
        const SizedBox(height: 26),
        SettingsCaption(context.l.apFontCat),
        const SizedBox(height: 10),
        const SettingsGroupCard(rows: [_FontCard()]),
        const SizedBox(height: 26),
        SettingsCaption(context.l.apNavBar),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            _SettingsCard(
              onTap: () => _pickNavStyle(context, ref),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l.apNavBarRow, style: theme.titleMedium),
                        const SizedBox(height: 3),
                        Text(
                          _navStyleLabel(context.l, settings.navStyle),
                          style: theme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Тот же макет, что в шторке, только мелкий: строка
                  // показывает выбранное, как кружки темы над ней.
                  SizedBox(
                    width: 46,
                    height: 46 * 64 / 100,
                    child: CustomPaint(
                      painter: _NavStyleGlyph(
                        style: settings.navStyle,
                        indicator: settings.navIndicator,
                        labels: settings.navLabels,
                        screen: t.bg,
                        frame: t.ovlLine2,
                        ink: t.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _SettingsCard(
              onTap: () => _pickNavOrder(context, ref),
              child: _SettingsRow(
                title: context.l.apNavTabsRow,
                subtitle: [
                  for (final tab in settings.navOrder)
                    _navTabLabel(context.l, tab),
                ].join(' · '),
                trailing: BloomIcon(
                  Bi.altArrowRight,
                  size: 20,
                  color: t.iconFgSb,
                ),
              ),
            ),
            _SettingsCard(
              onTap: () => _pickNavIndicator(context, ref),
              child: _SettingsRow(
                title: context.l.apNavMarkRow,
                subtitle: _navIndicatorLabel(context.l, settings.navIndicator),
                trailing: BloomIcon(
                  Bi.altArrowRight,
                  size: 20,
                  color: t.iconFgSb,
                ),
              ),
            ),
            _SettingsCard(
              onTap: () => _pickNavLabels(context, ref),
              child: _SettingsRow(
                title: context.l.apNavLabelsRow,
                subtitle: _navLabelsLabel(context.l, settings.navLabels),
                trailing: BloomIcon(
                  Bi.altArrowRight,
                  size: 20,
                  color: t.iconFgSb,
                ),
              ),
            ),
            // Тумблером, а не пятой шторкой: выбирать нечего — либо иконка,
            // либо знак. Стоит последним в блоке, потому что настройка не про
            // саму панель, а про один её таб.
            _SettingsCard(
              child: _SettingsRow(
                title: context.l.apNavHomeLogoRow,
                subtitle: context.l.apNavHomeLogoSub,
                trailing: BloomSwitch(
                  value: settings.navHomeLogo,
                  onChanged: controller.setNavHomeLogo,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        SettingsCaption(context.l.apBgGroup),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            // «Обложка трека как фон» — десктопная настройка вкладки «Фон»
            // раздела «Кастомизация»; сюда её перенёс пользователь. Своя
            // картинка фона (её ставят в «Кастомизации») эту настройку
            // перебивает — как и на ПК.
            _SettingsCard(
              child: _SettingsRow(
                title: context.l.apCoverAsBg,
                subtitle: context.l.apCoverAsBgSub,
                trailing: BloomSwitch(
                  value: settings.coverAsBg,
                  onChanged: controller.setCoverAsBg,
                ),
              ),
            ),
            // Размытие и затемнение самой обложки — те же две ручки, что у
            // картинки библиотеки на её странице, и с теми же границами. Здесь
            // они строкой со шторкой, как ползунки «Прозрачности» ниже, и
            // скрыты, пока фон выключен: крутить их выключенными нечего.
            if (settings.coverAsBg) ..._coverAsBgRows(context, ref),
          ],
        ),
        // Тумблеры «Итогов» — только в отладочной сборке, как повтор онбординга
        // (см. `settings_screen.dart`). В релизе итоги не настраиваются, они
        // случаются: на ПК настроек нет вовсе, а расписание там снимают скрытым
        // флагом в `localStorage`.
        if (kDebugMode) ...[
          const SizedBox(height: 26),
          ..._wrappedGroup(context, ref),
        ],
      ],
    );
  }
}

/// Две ручки «Обложки трека как фон»: размытие в пикселях и затемнение в
/// процентах.
///
/// Названия и границы — общие со страницей картинки в библиотеке
/// (`custBlur`/`custDim`, [kBgBlurMax]/[kBgDimMax]): это те же самые размытие и
/// затемнение фона, только у картинки они лежат в ней самой, а у обложки трека
/// — в [coverAsBgFxProvider]. Значки те же, что у соседей по «Интерфейсу»:
/// капля — размытие, луна — затемнение.
List<Widget> _coverAsBgRows(BuildContext context, WidgetRef ref) {
  final fx = ref.watch(coverAsBgFxProvider);
  final controller = ref.read(coverAsBgFxProvider.notifier);
  final l = context.l;

  return [
    _ValueRow(
      icon: Bi.waterdrop,
      title: l.custBlur,
      value: '${fx.blur}px',
      onTap: () => _pickIntValue(
        context: context,
        title: l.custBlur,
        value: fx.blur,
        max: kBgBlurMax.round(),
        unit: 'px',
        onChanged: controller.setBlur,
      ),
    ),
    _ValueRow(
      icon: Bi.moon,
      title: l.custDim,
      value: '${fx.dim}%',
      onTap: () => _pickIntValue(
        context: context,
        title: l.custDim,
        value: fx.dim,
        max: kBgDimMax.round(),
        unit: '%',
        onChanged: controller.setDim,
      ),
    ),
  ];
}

/// Группа «ИТОГИ». На ПК тумблеров больше нет (итоги не настраиваются, они
/// случаются), и роль «показать вне расписания» там играет скрытый флаг в
/// `localStorage`; на телефоне девтулзы нет, поэтому оба тумблера остались.
///
/// «Показывать всегда» — единственный способ увидеть итоги года вне декабря, а
/// месяцем считать идущий: журнал копится только с обновления, и у прошедшего
/// месяца сплошь и рядом ноль событий.
List<Widget> _wrappedGroup(BuildContext context, WidgetRef ref) {
  final prefs = ref.watch(wrappedPrefsProvider);
  final controller = ref.read(wrappedPrefsProvider.notifier);
  final l = context.l;

  return [
    // Метку «DEBUG» несёт сама подпись — как у группы повтора онбординга.
    SettingsCaption('${l.wrSetCaption} · DEBUG'),
    const SizedBox(height: 10),
    SettingsGroupCard(
      rows: [
        _SettingsCard(
          child: _SettingsRow(
            title: l.wrSetShow,
            subtitle: l.wrSetShowSub,
            trailing: BloomSwitch(
              value: prefs.show,
              onChanged: controller.setShow,
            ),
          ),
        ),
        // Расписание настраивается, только пока вход вообще показывается.
        if (prefs.show)
          _SettingsCard(
            child: _SettingsRow(
              title: l.wrSetAlways,
              subtitle: l.wrSetAlwaysSub,
              trailing: BloomSwitch(
                value: prefs.always,
                onChanged: controller.setAlways,
              ),
            ),
          ),
      ],
    ),
  ];
}

/// Группа «ПРОЗРАЧНОСТЬ» — последняя на экране, как категория с тем же именем
/// в конце десктопной секции «Интерфейс».
///
/// Ползунков на самой странице нет (на ПК они стоят прямо в карточке): строка
/// показывает значение и открывает шторку с одним ползунком — так решил
/// пользователь, показав макет. Всё, кроме тумблера режима, скрыто, пока
/// прозрачность выключена: это подрежимы, и настраивать их в выключенном
/// состоянии нечего (десктопный `#sTrSliders` с классом `vis`).
List<Widget> _transparencyGroup(BuildContext context, WidgetRef ref) {
  final tr = ref.watch(transparencyProvider);
  final controller = ref.read(transparencyProvider.notifier);
  final l = context.l;

  return [
    SettingsCaption(l.apTrGroup),
    const SizedBox(height: 10),
    SettingsGroupCard(
      rows: [
        _SettingsCard(
          child: _SettingsRow(
            title: l.apTrTitle,
            subtitle: tr.on ? l.apTrOn(tr.transparencyPercent) : l.apTrOff,
            trailing: BloomSwitch(value: tr.on, onChanged: controller.setOn),
          ),
        ),
        if (tr.on) ...[
          _ValueRow(
            icon: Bi.eye,
            title: l.apTrLevel,
            value: '${tr.transparencyPercent}%',
            onTap: () => _pickIntValue(
              context: context,
              title: l.apTrLevel,
              value: tr.transparencyPercent,
              max: 100,
              unit: '%',
              onChanged: controller.setTransparencyPercent,
            ),
          ),
          _ValueRow(
            icon: Bi.sun2,
            title: l.apTrBrightness,
            value: '${tr.glassStr}%',
            onTap: () => _pickIntValue(
              context: context,
              title: l.apTrBrightness,
              value: tr.glassStr,
              max: 100,
              unit: '%',
              onChanged: controller.setGlassStr,
            ),
          ),
          _ValueRow(
            icon: Bi.waterdrop,
            title: l.apTrBlur,
            value: '${tr.glassBlur}px',
            onTap: () => _pickIntValue(
              context: context,
              title: l.apTrBlur,
              value: tr.glassBlur,
              max: kTrBlurMax,
              unit: 'px',
              onChanged: controller.setGlassBlur,
            ),
          ),
          _SettingsCard(
            child: _SettingsRow(
              title: l.apTrOverlays,
              subtitle: l.apTrOverlaysSub,
              trailing: BloomSwitch(
                value: tr.overlayGlass,
                onChanged: controller.setOverlayGlass,
              ),
            ),
          ),
        ],
      ],
    ),
  ];
}

/// Строка группы: название, под ним значение или пояснение, справа — тумблер
/// либо кружок со значком.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.subtitle,
    required this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.titleMedium),
              if (subtitle case final sub?) ...[
                const SizedBox(height: 3),
                // Ярче общего `bodySmall` — как выбранное в строках «Плеера».
                Text(
                  sub,
                  style: theme.bodySmall?.copyWith(color: context.bloom.text2),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        trailing,
      ],
    );
  }
}

/// Строка с ползунком за ней: значение под названием, справа кружок со
/// значком. Кружок не кнопка — нажимается вся строка, а он показывает, о чём
/// она (солнце — яркость, глаз — прозрачность, капля — размытие).
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final BloomGlyph icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return _SettingsCard(
      onTap: onTap,
      child: _SettingsRow(
        title: title,
        subtitle: value,
        trailing: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: BloomIcon(icon, size: 20, color: t.text),
        ),
      ),
    );
  }
}

/// Шторка одного ползунка: крупное значение по центру и широкая полоса под ним.
/// Значение применяется НА ХОДУ, не по закрытию, — иначе стекло не с чем
/// сравнивать, пока крутишь.
///
/// Заголовка НЕТ (его слово, с макетом): в шторке всего одна ручка, и что
/// именно крутят, уже сказано строкой, из которой её открыли. Название всё
/// равно уходит в [Semantics] — скринридеру одного числа мало.
///
/// Пуговки у ползунка тоже нет: на макете полоса просто наливается — жирная,
/// со скруглёнными концами, во всю ширину шторки.
///
/// [minValue] — левый край: у яркости акцента он не ноль, там своя вилка
/// ([kAutoAccentLMin]…[kAutoAccentLMax]).
Future<void> _pickIntValue({
  required BuildContext context,
  required String title,
  required int value,
  required int max,
  required String unit,
  required ValueChanged<int> onChanged,
  int minValue = 0,
}) async {
  var current = value;
  await showBloomSheetChild<void>(
    context: context,
    child: StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$current$unit',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 30),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: SliderComponentShape.noThumb,
                // Полоса упирается в поля шторки: без пуговки края ползунка
                // резервировать не под что.
                trackShape: const RoundedRectSliderTrackShape(),
                padding: EdgeInsets.zero,
              ),
              child: Semantics(
                label: title,
                child: Slider(
                  value: current.toDouble(),
                  min: minValue.toDouble(),
                  max: max.toDouble(),
                  divisions: max - minValue,
                  onChanged: (v) {
                    setState(() => current = v.round());
                    onChanged(current);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Вид таб-бара ───────────────────────────────────────────────────────────

String _navStyleLabel(AppLocalizations l, NavBarStyle style) => switch (style) {
  NavBarStyle.bar => l.apNavBarPlain,
  NavBarStyle.rounded => l.apNavBarRounded,
  NavBarStyle.dome => l.apNavBarDome,
  NavBarStyle.floating => l.apNavBarFloating,
  NavBarStyle.pill => l.apNavBarPill,
};

/// Шторка выбора вида таб-бара: плитки в два столбца, последняя в нечётном
/// ряду остаётся одна.
///
/// Сетка живёт в шторке, а не на самой странице: у «Интерфейса» уже есть
/// строка «Тема» с таким же поведением, и второй развёрнутый блок выбора
/// раздул бы экран вдвое. Плитки в два столбца, а не в строку из четырёх (как
/// варианты анимации в настройках плеера): там подписи в одно короткое слово,
/// а «Скруглённый» на четверти ширины телефона стал бы многоточием.
///
/// Выбор применяется и закрывает шторку: сам бар она собой и закрывает, так
/// что смотреть на результат из-под неё всё равно нечем.
Future<void> _pickNavStyle(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final picked = await _pickNavCard<NavBarStyle>(
    context: context,
    values: NavBarStyle.values,
    current: settings.navStyle,
    label: (style) => _navStyleLabel(context.l, style),
    // Плитки показывают бар целиком, вместе с уже выбранными пометкой и
    // подписями: выбирают-то форму панели, но человек сравнивает картинку со
    // своим баром, а не с абстрактным.
    paint: (style, ink) => _NavStyleGlyph(
      style: style,
      indicator: settings.navIndicator,
      labels: settings.navLabels,
      screen: context.bloom.bg,
      frame: context.bloom.ovlLine2,
      ink: ink,
    ),
  );
  if (picked != null) ref.read(settingsProvider.notifier).setNavStyle(picked);
}

/// Шторка выбора пометки активного таба.
Future<void> _pickNavIndicator(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final picked = await _pickNavCard<NavIndicator>(
    context: context,
    values: NavIndicator.values,
    current: settings.navIndicator,
    label: (value) => _navIndicatorLabel(context.l, value),
    paint: (value, ink) => _NavStyleGlyph(
      style: settings.navStyle,
      indicator: value,
      labels: settings.navLabels,
      screen: context.bloom.bg,
      frame: context.bloom.ovlLine2,
      ink: ink,
    ),
  );
  if (picked != null) {
    ref.read(settingsProvider.notifier).setNavIndicator(picked);
  }
}

/// Шторка выбора подписей под иконками.
Future<void> _pickNavLabels(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final picked = await _pickNavCard<NavLabels>(
    context: context,
    values: NavLabels.values,
    current: settings.navLabels,
    label: (value) => _navLabelsLabel(context.l, value),
    paint: (value, ink) => _NavStyleGlyph(
      style: settings.navStyle,
      indicator: settings.navIndicator,
      labels: value,
      screen: context.bloom.bg,
      frame: context.bloom.ovlLine2,
      ink: ink,
    ),
  );
  if (picked != null) ref.read(settingsProvider.notifier).setNavLabels(picked);
}

/// Общая шторка настроек бара: плитки с макетом экрана в два столбца,
/// последняя в нечётном ряду остаётся одна.
///
/// Заголовка НЕТ (его слово): что выбирают, уже сказано строкой, из которой
/// шторку открыли, — как у [_pickIntValue].
Future<T?> _pickNavCard<T>({
  required BuildContext context,
  required List<T> values,
  required T current,
  required String Function(T value) label,
  required CustomPainter Function(T value, Color ink) paint,
}) {
  final width = MediaQuery.of(context).size.width;
  // Поля шторки с двух сторон + 12 зазора между столбцами.
  final cardWidth = (width - kSheetEdge * 2 - 12) / 2;

  return showBloomSheetChild<T>(
    context: context,
    // Закрывать шторку надо ЕЁ контекстом, а не контекстом страницы: шторка
    // живёт в корневом навигаторе, а страница — во вложенном (ветка таба), и
    // `pop` со страничным контекстом закрыл бы сами «Настройки».
    child: Builder(
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(kSheetEdge, 6, kSheetEdge, 6),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final value in values)
              _NavPickCard(
                width: cardWidth,
                active: value == current,
                label: label(value),
                paint: (ink) => paint(value, ink),
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    ),
  );
}

class _NavPickCard extends StatelessWidget {
  const _NavPickCard({
    required this.paint,
    required this.label,
    required this.width,
    required this.active,
    required this.onTap,
  });

  /// Значок варианта. Цвет приходит снаружи: акцент у выбранной плитки,
  /// приглушённый у прочих.
  final CustomPainter Function(Color ink) paint;
  final String label;
  final double width;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: t.pill,
          borderRadius: BorderRadius.circular(t.radius * 0.75),
          // Рамка есть всегда, просто у невыбранной прозрачная: иначе
          // выбранная плитка распухала бы на полтора пикселя и ряд дёргался.
          border: Border.all(
            color: active ? t.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 100 / 64,
              child: CustomPaint(painter: paint(active ? t.accent : t.text2)),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: active ? t.text : t.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Порядок вкладок ────────────────────────────────────────────────────────

String _navTabLabel(AppLocalizations l, NavTab tab) => switch (tab) {
  NavTab.home => l.navHome,
  NavTab.search => l.navSearch,
  NavTab.library => l.navLibrary,
  NavTab.settings => l.navSettings,
};

/// The tab order sheet: a row per tab in bar order, moved by the handle on the
/// right. It applies at once, no "Done".
Future<void> _pickNavOrder(BuildContext context, WidgetRef ref) =>
    showBloomSheetChild<void>(
      context: context,
      // Заголовка НЕТ (его слово): что настраивают, уже сказано строкой, из
      // которой шторку открыли.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kSheetEdge, 6, kSheetEdge, 6),
        child: Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(settingsProvider);
            final controller = ref.read(settingsProvider.notifier);
            final t = context.bloom;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Список — одна строка карточки: разделители рисуют сами
                // строки, иначе при перестановке линия уезжала бы отдельно от
                // строки, к которой она относится.
                SettingsGroupCard(
                  rows: [
                    ReorderableListView.builder(
                      // Список стоит внутри уже прокручиваемой шторки: свой
                      // скролл ему не нужен, а высоту он берёт по содержимому.
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      // The handle is my own, on the right.
                      buildDefaultDragHandles: false,
                      itemCount: settings.navOrder.length,
                      onReorder: controller.moveNavTab,
                      // Строка в полёте лежит поверх карточки, и своей плёнки
                      // у неё нет: без неё сквозь неё видно строки под ней.
                      proxyDecorator: (child, _, _) => Material(
                        color: t.pill,
                        borderRadius: BorderRadius.circular(t.radius),
                        child: child,
                      ),
                      itemBuilder: (context, i) {
                        final tab = settings.navOrder[i];
                        return _NavTabRow(
                          key: ValueKey(tab),
                          index: i,
                          tab: tab,
                          // Разделитель — у всех, кроме первой: карточка
                          // группы своих линий тут не рисует.
                          divider: i > 0,
                        );
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: Text(
                    context.l.apNavTabsDrag,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: t.text2),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

/// A tab row in the order sheet: its name and the drag handle.
class _NavTabRow extends StatelessWidget {
  const _NavTabRow({
    super.key,
    required this.index,
    required this.tab,
    required this.divider,
  });

  /// The row's place, which `ReorderableListView` reads to know what's dragged.
  final int index;
  final NavTab tab;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (divider)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Divider(
              height: 1,
              color: t.ovlLine.withValues(alpha: t.ovlLine.a * 0.5),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          child: _SettingsRow(
            title: _navTabLabel(context.l, tab),
            trailing: ReorderableDragStartListener(
              index: index,
              // Padding so a finger has something to grab.
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: BloomIcon(Bi.hamburgerMenu, size: 20, color: t.iconFgSb),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _navIndicatorLabel(AppLocalizations l, NavIndicator value) =>
    switch (value) {
      NavIndicator.none => l.apNavMarkNone,
      NavIndicator.pill => l.apNavMarkPill,
      NavIndicator.dot => l.apNavMarkDot,
      NavIndicator.line => l.apNavMarkLine,
    };

String _navLabelsLabel(AppLocalizations l, NavLabels value) => switch (value) {
  NavLabels.none => l.apNavLabelsNone,
  NavLabels.always => l.apNavLabelsAlways,
  NavLabels.active => l.apNavLabelsActive,
};

/// Макет экрана с баром внизу: рамка телефона, три полоски списка и сама
/// панель в том виде, который выберут. Рисуем кодом, а не четырьмя SVG, — те
/// же прямоугольники, что и в самом каркасе.
class _NavStyleGlyph extends CustomPainter {
  const _NavStyleGlyph({
    required this.style,
    required this.indicator,
    required this.labels,
    required this.screen,
    required this.frame,
    required this.ink,
  });

  final NavBarStyle style;

  /// Пометка активного таба: рисуется у среднего значка — он тут за активный.
  final NavIndicator indicator;
  final NavLabels labels;

  /// Заливка «экрана» — фон темы: по нему видно, как панель на нём лежит.
  final Color screen;
  final Color frame;

  /// Цвет панели и иконок: акцент у выбранной плитки, приглушённый у прочих.
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 100×64 и масштабируем разом — как значки вариантов в
    // настройках плеера.
    canvas.save();
    canvas.scale(size.width / 100, size.height / 64);

    final body = RRect.fromLTRBR(0, 0, 100, 64, const Radius.circular(8));
    final paint = Paint()..color = screen;
    canvas.drawRRect(body, paint);

    canvas.save();
    // Всё внутри режется рамкой телефона: нижние углы панели скругляются сами,
    // а панель «во всю ширину» упирается ровно в края.
    canvas.clipRRect(body);

    // Три полоски списка: разной длины, чтобы читались как строки, а не как
    // полосы.
    paint.color = ink.withValues(alpha: 0.22);
    const widths = [64.0, 76.0, 52.0];
    for (var i = 0; i < widths.length; i++) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          10,
          10 + i * 11,
          10 + widths[i],
          15 + i * 11,
          const Radius.circular(2.5),
        ),
        paint,
      );
    }

    final panel = switch (style) {
      // Прижат к низу: верх ровный, низ скруглит рамка.
      NavBarStyle.bar => RRect.fromLTRBR(0, 46, 100, 66, Radius.zero),
      NavBarStyle.rounded => RRect.fromLTRBAndCorners(
        0,
        44,
        100,
        66,
        topLeft: const Radius.circular(9),
        topRight: const Radius.circular(9),
      ),
      // Те же углы вдвое — ровно во столько же раз купол круче скруглённого и
      // в самом баре.
      NavBarStyle.dome => RRect.fromLTRBAndCorners(
        0,
        44,
        100,
        66,
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
      ),
      // Выше прижатых по высоте панели — ровно как в самом баре
      // (`kNavBarFloatHeight` против `kNavBarHeight`).
      NavBarStyle.floating => RRect.fromLTRBR(
        7,
        41,
        93,
        59,
        const Radius.circular(5),
      ),
      // Та же панель, что у плавающей, — разница только в углах: у капсулы
      // они в половину высоты.
      NavBarStyle.pill => RRect.fromLTRBR(
        7,
        41,
        93,
        59,
        const Radius.circular(9),
      ),
    };
    canvas.drawRRect(panel, paint..color = ink.withValues(alpha: 0.26));

    // Тонкая линия сверху — единственное, чем обычный бар отбит от списка.
    if (style == NavBarStyle.bar) {
      canvas.drawLine(
        const Offset(0, 46),
        const Offset(100, 46),
        Paint()
          ..color = ink.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }

    // Низ панели, который реально видно: у прижатых стилей она уходит под
    // рамку телефона, и считать по ней середину нельзя.
    final bottom = min(panel.bottom, 64);
    final half = (panel.right - panel.left) / 2 - 6;
    final step = half * 2 / 3;
    final cx = (panel.left + panel.right) / 2;
    final mid = (panel.top + bottom) / 2;
    // Подпись есть у значка [i] (средний, i == 0, тут за активный таб). С ней
    // значок мельче и поднят, освобождая место строке, — ровно как в самом
    // баре, где высота панели от подписей не меняется.
    bool titled(int i) => switch (labels) {
      NavLabels.none => false,
      NavLabels.always => true,
      NavLabels.active => i == 0,
    };

    // Пометка — ПОД значками: в самом баре она отдельный слой под рядом.
    switch (indicator) {
      case NavIndicator.none:
        break;
      case NavIndicator.pill:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, mid),
              width: step + 2,
              height: bottom - panel.top - 6,
            ),
            const Radius.circular(4),
          ),
          paint..color = ink.withValues(alpha: 0.45),
        );
      case NavIndicator.dot:
        canvas.drawCircle(Offset(cx, bottom - 4), 1.4, paint..color = ink);
      case NavIndicator.line:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, bottom - 4),
              width: 10,
              height: 1.8,
            ),
            const Radius.circular(0.9),
          ),
          paint..color = ink,
        );
    }

    // Три иконки — точки по центру панели, и подписи полосками под теми, у
    // кого они есть. Значок без подписи остаётся обычным и стоит по центру: в
    // самом баре ужимается только тот таб, под которым строка.
    for (var i = -1; i <= 1; i++) {
      final text = titled(i);
      final cy = mid - (text ? 3 : 0);
      canvas.drawCircle(
        Offset(cx + i * step, cy),
        text ? 2.2 : 2.6,
        paint..color = ink,
      );
      if (!text) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx + i * step, cy + 5.5),
            width: 11,
            height: 1.8,
          ),
          const Radius.circular(0.9),
        ),
        paint..color = ink.withValues(alpha: 0.75),
      );
    }

    canvas.restore();
    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = frame,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NavStyleGlyph old) =>
      old.style != style ||
      old.indicator != indicator ||
      old.labels != labels ||
      old.ink != ink ||
      old.screen != screen;
}

/// Строка настройки внутри группы. Своей плёнки у неё нет: связанные строки
/// стоят одной карточкой ([SettingsGroupCard]), как в корневых «Настройках».
///
/// [onTap] — строка ведёт куда-то (шторка выбора темы); без него это просто
/// место под тоггл или ползунок.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: child,
      ),
    );
  }
}

/// Карточка шрифта — порт десктопного `FontCard`: заголовок с «+» справа и
/// сетка плиток «Aa + название» в три столбца, каждая нарисована своим
/// шрифтом. Свои плитки идут после встроенных; крестик у них виден всегда
/// (наведения на телефоне нет) и спрашивает вторым нажатием, как у своих тем.
class _FontCard extends ConsumerWidget {
  const _FontCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final current = ref.watch(uiFontProvider);
    final userFonts = ref.watch(userFontsProvider);
    final settings = ref.read(settingsProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l.apFontTitle, style: theme.titleMedium),
                    const SizedBox(height: 3),
                    Text(context.l.apFontDesc, style: theme.bodySmall),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: context.l.apFontAdd,
                child: Pressable(
                  onTap: () => _addFonts(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 0, 8),
                    child: BloomIcon(Bi.addCircle, size: 22, color: t.muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 8 * 2) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in kBuiltinFonts)
                    _FontTile(
                      width: width,
                      name: f.name,
                      family: f.family,
                      active: current == f.family,
                      onTap: () => settings.setFontFamily(f.family),
                    ),
                  for (final f in userFonts)
                    _FontTile(
                      key: ValueKey(f.id),
                      width: width,
                      name: f.name,
                      family: f.family,
                      active: current == f.family,
                      onTap: () => settings.setFontFamily(f.family),
                      onDelete: () =>
                          ref.read(userFontsProvider.notifier).remove(f.id),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Выбор файлов шрифта и тосты по итогу — те же, что у десктопного
/// `addFiles`. Фильтр по расширению не ставим: у .ttf/.otf на Android часто
/// нет своего MIME, и системный выбор их просто не показал бы. Проверка — в
/// сторе.
Future<void> _addFonts(BuildContext context, WidgetRef ref) async {
  final List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles();
  } catch (e) {
    if (context.mounted) {
      showToast(context, context.l.apFontReadErr, kind: ToastKind.error);
    }
    return;
  }
  if (picked.isEmpty) return;
  final res = await ref.read(userFontsProvider.notifier).addFiles([
    for (final p in picked)
      (name: p.name, size: p.lengthSync(), read: p.readAsBytes),
  ]);
  if (!context.mounted) return;
  final l = context.l;
  if (res.added > 1) showToast(context, l.apFontAdded(res.added));
  if (res.errors.contains(FontAddError.format)) {
    showToast(context, l.apFontBadFormat, kind: ToastKind.warn);
  }
  if (res.errors.contains(FontAddError.size)) {
    showToast(
      context,
      l.apFontTooBig(kMaxFontBytes ~/ (1024 * 1024)),
      kind: ToastKind.warn,
    );
  }
  if (res.errors.contains(FontAddError.read)) {
    showToast(context, l.apFontReadErr, kind: ToastKind.error);
  }
}

/// Плитка шрифта — `.s-font-item`: плёнка 4 %, у выбранной 12 %, скругление
/// `radius*0.7`, «Aa» 22 жирным и подпись 10 приглушённым.
class _FontTile extends StatefulWidget {
  const _FontTile({
    super.key,
    required this.width,
    required this.name,
    required this.family,
    required this.active,
    required this.onTap,
    this.onDelete,
  });

  final double width;
  final String name;
  final String family;
  final bool active;
  final VoidCallback onTap;

  /// Крестик — только у своих шрифтов.
  final VoidCallback? onDelete;

  @override
  State<_FontTile> createState() => _FontTileState();
}

class _FontTileState extends State<_FontTile> {
  bool _armed = false;

  void _delete() {
    if (!_armed) {
      setState(() => _armed = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() => _armed = false);
    widget.onDelete!();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final ovl = t.text;
    final font = TextStyle(
      fontFamily: widget.family,
      fontFamilyFallback: const [kDefaultFont],
    );
    return Pressable(
      onTap: widget.onTap,
      scale: 0.97,
      child: Container(
        width: widget.width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        decoration: BoxDecoration(
          color: ovl.withValues(alpha: widget.active ? 0.12 : 0.04),
          borderRadius: BorderRadius.circular(t.radius * 0.7),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Aa',
                  textAlign: TextAlign.center,
                  style: font.copyWith(
                    fontSize: 22,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: font.copyWith(fontSize: 10, color: t.muted),
                ),
              ],
            ),
            if (widget.onDelete != null)
              Positioned(
                top: -10,
                right: -2,
                child: Semantics(
                  button: true,
                  label: context.l.apFontRemove,
                  child: Pressable(
                    onTap: _delete,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: BloomIcon(
                        _armed ? Bi.trashBinTrash : Bi.close,
                        size: 14,
                        color: _armed ? t.danger : t.text2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Шторка выбора темы: сетка пресетов в два столбца, ниже — свои темы, отбитые
/// тонкой линией (как `tp-sep` на десктопе). Список пресетов длиннее экрана не
/// бывает, но шторка всё равно скроллится — это делает её оболочка.
Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(settingsProvider.notifier);
  final width = MediaQuery.of(context).size.width;
  // Поля шторки с двух сторон + 12 зазора между столбцами.
  final cardWidth = (width - kSheetEdge * 2 - 12) / 2;

  await showBloomSheetChild<void>(
    context: context,
    // The theme changes live under the sheet, so the header reads its colours
    // in its own context, not in the screen's at the time it opened.
    header: Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(kSheetEdge, 6, kSheetEdge, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l.apThemeRow,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            // «+» — как кнопка `tp-add` рядом со строкой темы на ПК.
            CircleIconButton(
              icon: Bi.addCircle,
              size: 40,
              iconSize: 22,
              background: sheetPanelColor(context),
              color: context.bloom.text,
              onTap: () => _createTheme(context, ref),
            ),
          ],
        ),
      ),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        // Настройки читаем внутри шторки: тема применяется сразу, а свои темы
        // появляются в ней же — и галочка, и новая карточка должны приезжать,
        // не закрывая шторку.
        final settings = ref.watch(settingsProvider);
        Widget card(ThemePreset preset) => _PresetCard(
          preset: preset,
          width: cardWidth,
          active: preset.id == settings.themeId,
          onTap: () => controller.setTheme(preset.id),
          onDelete: preset.custom
              ? () => _deleteTheme(context, ref, preset)
              : null,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(kSheetEdge, 0, kSheetEdge, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Авто-тема — режим, а не палитра: стоит первой строкой во всю
              // ширину, чтобы не читаться как ещё один пресет и не ломать пары
              // ниже (десктопное `.tp-auto{grid-column:1/-1}`). Кружки живые —
              // это те цвета, что сейчас сняты с обложки.
              _AutoThemeCard(
                preset: ThemePreset(
                  id: kAutoThemeId,
                  name: context.l.thAutoCard,
                  bg: settings.preset.bg,
                  blockColor: settings.preset.blockColor,
                  accent: settings.tokens.accent,
                ),
                active: settings.autoTheme,
                onTap: () => controller.setTheme(kAutoThemeId),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final p in kThemePresets) card(p)],
              ),
              if (settings.customThemes.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1, color: sheetLineColor(context)),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [for (final p in settings.customThemes) card(p)],
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

/// Удалить свою тему. Подтверждение — вторым нажатием на сам крестик (как
/// очистка статистики в профиле), модалки нет.
void _deleteTheme(BuildContext context, WidgetRef ref, ThemePreset preset) {
  ref.read(settingsProvider.notifier).deleteCustomTheme(preset.id);
  showToast(context, context.l.thDeleted);
}

/// Шторка создания своей темы: название, три цвета, «случайные» и «сохранить» —
/// тот же набор, что в десктопном `ThemeCreator`. Созданная тема сразу
/// применяется, поэтому шторка выбора под ней остаётся открытой: видно и
/// карточку, и результат.
Future<void> _createTheme(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final draft = await showBloomSheetChild<_ThemeDraft>(
    context: context,
    header: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Text(
          context.l.thNew,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    ),
    // Отталкиваемся от текущей темы — как на ПК, где создатель открывается с
    // её цветами: чаще всего свою тему крутят именно из неё.
    child: _ThemeCreator(initial: settings.preset),
  );
  if (draft == null || !context.mounted) return;
  final created = ref
      .read(settingsProvider.notifier)
      .createCustomTheme(
        name: draft.name.isEmpty ? context.l.thNameDefault : draft.name,
        bg: draft.bg,
        blockColor: draft.blockColor,
        accent: draft.accent,
      );
  showToast(context, context.l.thCreated(created.name));
}

/// Черновик своей темы: то, с чем закрывается шторка создания.
class _ThemeDraft {
  const _ThemeDraft({
    required this.name,
    required this.bg,
    required this.blockColor,
    required this.accent,
  });

  final String name;
  final Color bg;
  final Color blockColor;
  final Color accent;
}

class _ThemeCreator extends StatefulWidget {
  const _ThemeCreator({required this.initial});

  final ThemePreset initial;

  @override
  State<_ThemeCreator> createState() => _ThemeCreatorState();
}

class _ThemeCreatorState extends State<_ThemeCreator> {
  late final TextEditingController _name = TextEditingController();
  late Color _bg = widget.initial.bg;
  late Color _block = widget.initial.blockColor;
  late Color _accent = widget.initial.accent;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Случайная приятная палитра — порт `randomThemeColors`: тёмный фон, блок
  /// чуть светлее того же тона, акцент — заметно другой тон.
  void _random() {
    final rnd = Random();
    final h = rnd.nextDouble() * 360;
    final bgL = (5 + rnd.nextDouble() * 5) / 100;
    setState(() {
      _bg = HSLColor.fromAHSL(1, h, 0.18, bgL).toColor();
      _block = HSLColor.fromAHSL(1, h, 0.16, bgL + 0.05).toColor();
      _accent = HSLColor.fromAHSL(
        1,
        (h + 20 + rnd.nextDouble() * 320) % 360,
        0.65,
        0.58,
      ).toColor();
    });
  }

  Future<void> _pick(Color current, ValueChanged<Color> apply) async {
    final picked = await showBloomColorPicker(context, current);
    if (picked != null) setState(() => apply(picked));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final width = MediaQuery.of(context).size.width;
    final preview = ThemePreset(
      id: 'draft',
      name: _name.text.trim().isEmpty
          ? context.l.thNameDefault
          : _name.text.trim(),
      bg: _bg,
      blockColor: _block,
      accent: _accent,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            maxLength: 24,
            cursorColor: t.accent,
            style: theme.titleMedium,
            // Имя видно в превью — перерисовываем на каждый символ.
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: t.pill,
              hintText: context.l.thNameDefault,
              hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.radius * 0.7),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ColorSlot(
                label: context.l.thSlotBg,
                color: _bg,
                onTap: () => _pick(_bg, (c) => _bg = c),
              ),
              const SizedBox(width: 10),
              _ColorSlot(
                label: context.l.thSlotCard,
                color: _block,
                onTap: () => _pick(_block, (c) => _block = c),
              ),
              const SizedBox(width: 10),
              _ColorSlot(
                label: context.l.thSlotAccent,
                color: _accent,
                onTap: () => _pick(_accent, (c) => _accent = c),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Живое превью: та же карточка, что потом встанет в сетку.
          Center(
            child: _PresetCard(
              preset: preview,
              width: width - 40,
              active: false,
              onTap: () {},
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: BloomButton(
                  label: context.l.thRandom,
                  icon: Bi.magicStick,
                  color: t.text2,
                  onTap: _random,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BloomButton(
                  label: context.l.commonSave,
                  tone: ButtonTone.accent,
                  onTap: () => Navigator.of(context).pop(
                    _ThemeDraft(
                      name: _name.text.trim(),
                      bg: _bg,
                      blockColor: _block,
                      accent: _accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Слот цвета: подпись и широкий сватч под ней — тап открывает пикер.
class _ColorSlot extends StatelessWidget {
  const _ColorSlot({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Pressable(
            onTap: onTap,
            scale: 0.97,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(t.radius * 0.6),
                border: Border.all(color: t.ovlLine2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Три кружка превью темы — как `Dots` в десктопном `ThemePicker`: фон, блок,
/// акцент. Кружки заходят друг на друга, поэтому у каждого своя обводка цветом
/// подложки, иначе тёмные темы сливаются в одно пятно.
class _ThemeDots extends StatelessWidget {
  const _ThemeDots({required this.preset, this.size = 22, this.ring});

  final ThemePreset preset;
  final double size;

  /// Цвет обводки — подложка, на которой лежат кружки. По умолчанию плёнка
  /// текущей темы: строка настроек лежит на ней.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final preview = preset.tokens();
    final colors = [preview.bg, preview.pill, preview.accent];
    final step = size * 0.68;
    return SizedBox(
      width: step * (colors.length - 1) + size,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < colors.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: ring ?? t.pill, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Авто-тема в шторке: строка во всю ширину над сеткой пресетов. Своих цветов
/// у неё нет — карточка красится теми, что сейчас на экране, и это как раз её
/// лицо, снятое с обложки. Плиткой в пару к пресету не ставится намеренно: на
/// ПК она тоже занимает весь ряд (`.tp-auto{grid-column:1/-1}`).
class _AutoThemeCard extends StatelessWidget {
  const _AutoThemeCard({
    required this.preset,
    required this.active,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final preview = preset.tokens();
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: preview.bg,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(
            color: active ? t.accent : preview.border,
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            _ThemeDots(preset: preset, size: 24, ring: preview.bg),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: preview.text),
              ),
            ),
            if (active) BloomIcon(Bi.check, size: 18, color: preview.accent),
          ],
        ),
      ),
    );
  }
}

/// Пресет в шторке: карточка, залитая фоном самой темы, с кружками превью
/// сверху и названием снизу. Превью считаем теми же формулами, что и саму
/// тему, — разойтись они не могут.
class _PresetCard extends StatefulWidget {
  const _PresetCard({
    required this.preset,
    required this.width,
    required this.active,
    required this.onTap,
    this.onDelete,
  });

  final ThemePreset preset;
  final double width;
  final bool active;
  final VoidCallback onTap;

  /// Крестик в углу — только у своих тем.
  final VoidCallback? onDelete;

  @override
  State<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends State<_PresetCard> {
  /// Крестик спрашивает вторым нажатием — как очистка статистики в профиле:
  /// модалки на такую мелочь нет ни там, ни на ПК.
  bool _armed = false;

  void _delete() {
    if (!_armed) {
      setState(() => _armed = true);
      // Само остывает — иначе взведённый крестик так и ждёт промаха.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() => _armed = false);
    widget.onDelete!();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final preset = widget.preset;
    final active = widget.active;
    final preview = preset.tokens();
    return Pressable(
      onTap: widget.onTap,
      scale: 0.97,
      child: Container(
        width: widget.width,
        height: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: preview.bg,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(
            color: active ? t.accent : preview.border,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ThemeDots(preset: preset, size: 24, ring: preview.bg),
                const Spacer(),
                if (active)
                  BloomIcon(Bi.check, size: 18, color: preview.accent),
                if (widget.onDelete != null)
                  // Своя зона нажатия: крестик мелкий, а мажут по нему пальцем.
                  // Взведённый — красная корзина: без модалки видно, что
                  // следующий тап удалит.
                  Pressable(
                    onTap: _delete,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: BloomIcon(
                        _armed ? Bi.trashBinTrash : Bi.close,
                        size: 18,
                        color: _armed ? preview.danger : preview.muted,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              preset.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: preview.text),
            ),
          ],
        ),
      ),
    );
  }
}
