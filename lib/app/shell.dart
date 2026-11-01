/// Каркас приложения: таб-бар, миниплеер над ним, полноэкранный плеер
/// поверх всего.
///
/// Бары лежат поверх содержимого (`extendBody`), а не отрезают ему низ: поля
/// вокруг карточки миниплеера прозрачные, и сквозь них видно список. Цена —
/// каждому скроллу нужен нижний запас в высоту баров, иначе последние строки
/// остаются под ними навсегда: он берётся из [bottomBarsInset].
library;

import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../features/customization/ui/app_background.dart';
import '../core/store/settings_store.dart';
import '../features/player/ui/mini_player.dart';
import '../features/player/ui/player_sheet.dart';
import '../features/profile/achievements.dart';
import '../features/settings/about_store.dart';
import '../features/settings/update_notes_store.dart';
import '../features/settings/ui/update_notes_sheet.dart';
import '../features/wrapped/periods.dart';
import '../core/store/play_log.dart';
import '../features/wrapped/ui/wrapped_sheet.dart';
import '../features/wrapped/wrapped_store.dart';
import '../shared/ui/atoms.dart';
import '../shared/ui/bloom_icon.dart';
import '../shared/ui/bloom_mark.dart';
import '../shared/ui/bloom_toast.dart';
import '../shared/ui/cover_hero.dart';
import '../shared/ui/glass.dart';
import '../shared/ui/pressable.dart';
import 'theme/tokens.dart';

class BloomShell extends ConsumerStatefulWidget {
  const BloomShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<BloomShell> createState() => _BloomShellState();
}

class _BloomShellState extends ConsumerState<BloomShell> {
  Timer? _noticeTimer;

  /// The app can stay open into the 1st: the date is checked on coming back.
  late final AppLifecycleListener _life = AppLifecycleListener(
    onResume: () {
      if (ref.read(wrappedDayProvider.notifier).refresh()) _wrappedNotice();
    },
  );

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _life.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _life;
    // Первый прогон — молчаливый: он же засеивает уже выполненные достижения.
    // Из `initState` провайдер трогать нельзя, ждём кадр.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync();
      _wrappedNotice(after: const Duration(seconds: 3));
      _whatsNew();
    });
  }

  /// «Что нового» — один раз после обновления приложения.
  ///
  /// Здесь, а не на экране «Система»: сравнить версию с прошлым запуском надо
  /// при старте, и до настроек человек может не дойти вовсе. Мастер первого
  /// запуска этой шторке не помешает: он живёт отдельным маршрутом, каркас при
  /// нём не построен, а свежая установка «Что нового» и не показывает (см.
  /// `UpdateNotes.whatsNew`).
  Future<void> _whatsNew() async {
    await ref.read(aboutProvider.notifier).loadVersion();
    if (!mounted) return;
    final version = ref.read(aboutProvider).version;
    if (version.isEmpty) return;
    final locale = Localizations.localeOf(context).languageCode;
    final note = await ref.read(updateNotesProvider).whatsNew(version, locale);
    if (!mounted || note == null) return;
    await showUpdateNote(context, note);
  }

  /// A review is out: a toast with a way into it, once per period. I mark it
  /// before the toast, so a restart stays quiet.
  void _wrappedNotice({Duration after = Duration.zero}) {
    final entries = ref.read(wrappedEntriesProvider);
    final marks = ref.read(wrappedMarksProvider.notifier);
    final now = ref.read(playLogClockProvider)();
    final due = [
      for (final kind in scheduledPeriods(
        now,
        force: ref.read(wrappedForceProvider),
      ))
        if (entries.of(kind) case final data?
            when !marks.isNotified(data.range))
          kind,
    ];
    if (due.isEmpty) return;
    for (final kind in due) {
      marks.markNotified(entries.of(kind)!.range);
    }
    _noticeTimer = Timer(after, () {
      if (!mounted) return;
      final l = context.l;
      final locale = Localizations.localeOf(context).languageCode;
      for (final kind in due) {
        final data = entries.of(kind)!;
        ScaffoldMessenger.of(context).toast(
          [
            periodTitle(l, kind),
            periodDatesLabel(data.range, locale),
            l.wrPlaysN(data.plays),
          ].join(' · '),
          action: ToastAction(
            label: l.wrWatch,
            // Read again on the tap: the day may have turned.
            fn: () {
              if (!mounted) return;
              final fresh = ref.read(wrappedEntriesProvider).of(kind);
              if (fresh != null) showWrappedSheet(context, fresh);
            },
          ),
        );
      }
    });
  }

  /// Достижения ловятся здесь, а не на вкладке профиля: иначе они «получались»
  /// бы только когда пользователь до неё дошёл (та же причина, по которой на
  /// десктопе вотчер живёт в `App`).
  void _sync() {
    final fresh = ref
        .read(unlockedAchievementsProvider.notifier)
        .sync(ref.read(achievementsProvider));
    // Тосты не налезают друг на друга: `ScaffoldMessenger` держит очередь и
    // показывает следующий, когда догорит предыдущий.
    for (final item in fresh) {
      ScaffoldMessenger.of(context).toast(
        context.l.achUnlockedToast(
          item.ach.def.name(context.l),
          tierLabel(context.l, item.tier),
        ),
        kind: ToastKind.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    ref.listen(achievementsProvider, (_, _) => _sync());
    final shell = widget.shell;
    final scaffold = Scaffold(
      // Картинка фона лежит под каркасом — тогда своей заливки у него нет.
      backgroundColor: ref.watch(backgroundOnProvider)
          ? Colors.transparent
          : t.bg,
      extendBody: true,
      body: shell,
      // Бары именно в `bottomNavigationBar`, а не колонкой в `body`: только так
      // плавающий тост встаёт НАД миниплеером, а не поверх него. На раскладку
      // это не влияет — Scaffold точно так же отдаёт им низ, а телу остаток.
      //
      // Группа стекла у баров СВОЯ, отдельная от страницы: они лежат поверх
      // списка, и с общим снимком подложки уходящие под них строки в размытие
      // бы не попали.
      bottomNavigationBar: GlassGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Место под карточку миниплеера: саму карточку рисует панель
            // плеера — она из карточки вырастает и лежит поверх баров.
            const MiniCardSlot(),
            _NavBar(
              style: ref.watch(settingsProvider).navStyle,
              tabs: ref.watch(settingsProvider).navOrder,
              indicator: ref.watch(settingsProvider).navIndicator,
              labels: ref.watch(settingsProvider).navLabels,
              homeLogo: ref.watch(settingsProvider).navHomeLogo,
              branch: shell.currentIndex,
              onTap: (tab) => shell.goBranch(
                tab.index,
                initialLocation: tab.index == shell.currentIndex,
              ),
            ),
          ],
        ),
      ),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: playerSheetOpen,
      builder: (context, open, child) => PopScope(
        // Развёрнутый плеер съедает системную «назад». Своего маршрута у него
        // нет, и без этого «назад» ушла бы мимо: свернула бы страницу под
        // панелью или закрыла приложение, оставив плеер во весь экран.
        canPop: !open,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) collapsePlayerSheet();
        },
        child: child!,
      ),
      // Панель лежит ПОВЕРХ каркаса вместе с барами: она и есть карточка
      // миниплеера, только выросшая, и накрывать таб-бар обязана сама.
      child: Stack(
        fit: StackFit.expand,
        children: [scaffold, const PlayerSheet()],
      ),
    );
  }
}

/// Высота панели таб-бара вместе с её нижним вырезом — столько занимает низ
/// экрана под карточкой миниплеера.
///
/// По ней панель плеера считает своё место в покое, поэтому число обязано
/// совпадать с тем, что бар раскладывает у себя (см. [_NavBar.build]): высота
/// ряда иконок плюс отступ, которым он выводит себя из системного выреза.
double navBarInset(BuildContext context, NavBarStyle style) => switch (style) {
  NavBarStyle.floating ||
  NavBarStyle.pill => kNavBarFloatHeight + bottomEdgeInset(context),
  _ => kNavBarHeight + bottomSafeInset(context),
};

// ─── Переключение вкладок ───────────────────────────────────────────────────

/// Смена вкладки. Вдвое короче перехода страниц (450 мс): там шаг вглубь, а
/// здесь ответ на тап по бару — растворение должно успеть кончиться раньше,
/// чем палец дойдёт до следующего таба.
const Duration kTabTransition = Duration(milliseconds: 220);

/// Контейнер веток каркаса: вкладки сменяют друг друга растворением.
///
/// Готовый `StatefulShellRoute.indexedStack` меняет вкладку одним кадром —
/// здесь тот же `IndexedStack` по смыслу (все ветки живут в дереве,
/// `Offstage` + `TickerMode` у неактивных, состояние вкладки переживает
/// переключение), но на время перехода видно сразу две: уходящая гаснет,
/// приходящая проявляется.
///
/// Кривые — общие со страницами ([kPageFadeIn], [kPageFadeOut]), а вот
/// длительность своя, [kTabTransition]: страница уезжает в глубину, и ей
/// уместно идти степенно, а таб-бар отвечает под пальцем. Сдвига нет
/// намеренно — у вкладок нет общей оси, а под перелётом обложки горизонталь
/// спорила бы с ним (см. `detailPageTransition`).
class BranchCrossfade extends StatefulWidget {
  const BranchCrossfade({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<BranchCrossfade> createState() => _BranchCrossfadeState();
}

class _BranchCrossfadeState extends State<BranchCrossfade>
    with SingleTickerProviderStateMixin {
  // Стартует «догоревшим»: первый кадр приложения — вкладка уже на месте,
  // растворять нечего.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: kTabTransition,
    value: 1,
  );

  /// Ветка, с которой ушли. Её ещё рисуют, пока не догорит [_fade].
  int _leaving = 0;

  @override
  void didUpdateWidget(BranchCrossfade old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      _leaving = old.index;
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Раскладка как у `IndexedStack`: свободные ограничения, выравнивание по
    // началу — ветка сама занимает отданное каркасом место.
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [for (var i = 0; i < widget.children.length; i++) _branch(i)],
      ),
    );
  }

  Widget _branch(int i) {
    final active = i == widget.index;
    final opacity = active
        ? kPageFadeIn.transform(_fade.value)
        : i == _leaving
        ? kPageFadeOut.transform(_fade.value)
        : 0.0;

    return Offstage(
      // Уходящая гаснет за первую четверть перехода — дальше её незачем
      // раскладывать и красить, хотя переход ещё идёт.
      offstage: opacity == 0,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !active,
          // `Opacity` при 1 не заводит слой — на покое это обычная ветка.
          child: Opacity(opacity: opacity, child: widget.children[i]),
        ),
      ),
    );
  }
}

/// A tab: its icon at rest and its bold one while open.
class _NavSpec {
  const _NavSpec({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.motion = _NavMotion.wiggle,
  });

  /// Подпись резолвится при отрисовке, а не при сборке списка: таблица табов
  /// статическая и переживает смену языка.
  final String Function(AppLocalizations l) label;
  final BloomGlyph icon;
  final BloomGlyph activeIcon;

  /// Чем иконка отвечает на выбор своей вкладки — см. [_NavMotion].
  final _NavMotion motion;
}

/// Высота ряда иконок у прижатых к низу стилей.
const double kNavBarHeight = 58;

/// Высота плавающих стилей. Больше прижатых намеренно: панель кончается до
/// краёв экрана, и в тех же 58 она на фоне пустых полей вокруг читается
/// мельче, чем бар во всю ширину.
const double kNavBarFloatHeight = 68;

/// Размер глифа в баре. У плавающих крупнее — вслед за высотой панели, иначе
/// прибавка уходит в пустые поля над иконками и бар выглядит просто рыхлым.
const double _kNavIcon = 24;
const double _kNavFloatIcon = 27;

/// Те же глифы, когда под ними стоит подпись. Высота панели с подписями НЕ
/// меняется (его слово), поэтому место строке освобождает сама иконка: бар
/// остаётся на своей линии, что бы ни было выбрано, и списки под ним не
/// перекладываются.
///
/// У [NavLabels.active] ужимается ОДИН активный таб — тот, под которым строка
/// и появилась. Ужимать заодно и соседей нельзя: подписи под ними нет, и
/// мелкие глифы посреди пустого места читаются как сбой, а не как ряд (поймал
/// он на первой же сборке).
const double _kNavIconText = 19;
const double _kNavFloatIconText = 21;

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.style,
    required this.tabs,
    required this.indicator,
    required this.labels,
    required this.homeLogo,
    required this.branch,
    required this.onTap,
  });

  final NavBarStyle style;

  /// The tabs in display order, see [NavTab].
  final List<NavTab> tabs;

  /// Чем помечен активный таб, см. [_NavMark].
  final NavIndicator indicator;

  /// Подписи под иконками, см. [NavLabels].
  final NavLabels labels;

  /// Знак Bloom на месте иконки «Главной», см. [SettingsState.navHomeLogo].
  final bool homeLogo;

  /// The open shell branch ([NavTab.index]), not a slot in the bar: the order
  /// is a setting.
  final int branch;

  final ValueChanged<NavTab> onTap;

  /// Неактивный таб — outline, активный — bold (правило Solar).
  static final _items = <NavTab, _NavSpec>{
    NavTab.home: _NavSpec(
      label: (l) => l.navHome,
      icon: Bi.homeAngle2,
      activeIcon: Bi.homeAngle2Bold,
    ),
    NavTab.search: _NavSpec(
      label: (l) => l.navSearch,
      icon: Bi.magnifier,
      activeIcon: Bi.magnifierBold,
    ),
    NavTab.library: _NavSpec(
      label: (l) => l.navLibrary,
      icon: Bi.library,
      activeIcon: Bi.libraryBold,
    ),
    NavTab.settings: _NavSpec(
      label: (l) => l.navSettings,
      icon: Bi.settings,
      activeIcon: Bi.settingsBold,
      motion: _NavMotion.spin,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final floating = style == NavBarStyle.floating || style == NavBarStyle.pill;
    final height = floating ? kNavBarFloatHeight : kNavBarHeight;
    final slot = tabs.indexWhere((tab) => tab.index == branch);

    // Прижатые стили отличаются друг от друга только радиусом верхних углов.
    // У «Купола» он вдвое больше темы и не мельче 28: на слабом радиусе темы он
    // иначе повторял бы «Скруглённый», ради которого его и заводили отдельным
    // видом.
    final topRadius = switch (style) {
      NavBarStyle.rounded => math.max(t.radius, 10.0),
      NavBarStyle.dome => math.max(t.radius * 2, 28.0),
      _ => 0.0,
    };
    final radius = switch (style) {
      NavBarStyle.bar || NavBarStyle.rounded || NavBarStyle.dome =>
        BorderRadius.vertical(top: Radius.circular(topRadius)),
      // Капсула круглая по определению, а не по теме: её углы — всегда половина
      // высоты, а не общий радиус приложения.
      NavBarStyle.pill => BorderRadius.circular(height / 2),
      NavBarStyle.floating => BorderRadius.circular(t.radius),
    };
    // Скругление панели одним числом — его повторяет подложка активного таба.
    // У прижатого бара углов нет вовсе, и брать оттуда ноль незачем: подложка
    // тогда берёт радиус темы, как все прочие плашки приложения.
    final corner = switch (style) {
      NavBarStyle.bar => t.radius,
      NavBarStyle.rounded || NavBarStyle.dome => topRadius,
      NavBarStyle.pill => height / 2,
      NavBarStyle.floating => t.radius,
    };

    // Ряд у всех стилей один: табы делят ширину поровну. Капсула от плавающей
    // панели отличается только радиусом — иконки в ней стоят там же, а не
    // жмутся к середине.
    final row = Row(
      children: [
        for (var i = 0; i < tabs.length; i++)
          Expanded(
            child: _NavItem(
              spec: _items[tabs[i]]!,
              active: i == slot,
              mark: homeLogo && tabs[i] == NavTab.home,
              iconSize: floating ? _kNavFloatIcon : _kNavIcon,
              textIconSize: floating ? _kNavFloatIconText : _kNavIconText,
              labels: labels,
              onTap: () => onTap(tabs[i]),
            ),
          ),
      ],
    );

    // Ряд с пометкой активного таба. Пометка ЛЕЖИТ ПОД иконками и едет между
    // табами сама — тогда переключение читается как переезд выделения, а не как
    // две вспышки. Выключена — остаётся голый ряд, как было всегда.
    final content = SizedBox(
      height: height,
      child: indicator == NavIndicator.none
          ? row
          : Stack(
              fit: StackFit.expand,
              children: [
                _NavMark(
                  kind: indicator,
                  slot: slot,
                  count: tabs.length,
                  corner: corner,
                ),
                row,
              ],
            ),
    );

    switch (style) {
      // Прижатые к низу: заливка уходит под системный вырез, ряд иконок из
      // него выводит нижний отступ ([bottomSafeInset]).
      case NavBarStyle.bar:
      case NavBarStyle.rounded:
      case NavBarStyle.dome:
        final rounded = topRadius > 0;
        // Заливка одна на все четыре стиля — та же `pill`, что у шапки главной
        // и строк настроек: бары обязаны читаться как элементы интерфейса, а
        // не как продолжение фона. В стекле она полупрозрачна, и сквозь бар
        // видно уходящий под него список.
        return GlassBox(
          // Не мельче 10 у «Скруглённого»: на нуле темы он ничем не
          // отличался бы от обычного.
          borderRadius: radius,
          // При скруглении рамка обязана быть одинаковой со всех сторон —
          // нижняя всё равно уходит за край экрана; у прямого бара линия
          // только сверху, поэтому ему нужна своя форма.
          borderSide: rounded ? BorderSide(color: t.ovlLine) : null,
          shape: rounded ? null : Border(top: BorderSide(color: t.ovlLine)),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomSafeInset(context)),
            child: content,
          ),
        );

      // Плавающие: панель кончается до низа экрана, вырез системы отдан
      // просвету под ней ([bottomEdgeInset]) — иначе она села бы на жестовую
      // полосу.
      case NavBarStyle.floating:
      case NavBarStyle.pill:
        return Padding(
          padding: EdgeInsets.fromLTRB(
            kFloatGap,
            0,
            kFloatGap,
            bottomEdgeInset(context),
          ),
          child: GlassBox(
            borderSide: BorderSide(color: t.ovlLine),
            borderRadius: radius,
            child: content,
          ),
        );
    }
  }
}

// ─── Пометка активного таба ─────────────────────────────────────────────────

/// Поле подложки внутри доли таба — одно на все четыре стороны: подложка
/// занимает почти всю долю, как в телеге, и остаётся ровный просвет что между
/// соседями, что до краёв панели. Потолка ширины нет — доля таба и есть её мера.
const double _kPillPad = 5;

/// Просвет от нижней кромки ряда до точки и линии.
///
/// Кромка ряда, а не панели: у прижатых стилей заливка уходит ещё и под
/// системный вырез, и от края экрана пометка стоит дальше — зато она везде на
/// одном расстоянии от иконок, под которыми и стоит.
const double _kMarkGap = 5;

/// Точка под иконкой.
const double _kDotSize = 5;

/// Линия под иконкой. Короткая и по центру доли, а не во всю её ширину: у
/// «Капсулы» и «Купола» крайние линии срезало бы скруглением панели.
const Size _kLineSize = Size(22, 3);

/// Пометка активного таба: подложка, точка или линия — смотря по
/// [NavIndicator].
///
/// Отдельным слоем под рядом иконок, а не фоном самого таба: так она едет от
/// таба к табу одним движением. Едет в такт со сменой вкладки
/// ([kTabTransition]) — пометка и содержимое обязаны прийти вместе.
class _NavMark extends StatelessWidget {
  const _NavMark({
    required this.kind,
    required this.slot,
    required this.count,
    required this.corner,
  });

  /// Вид пометки; [NavIndicator.none] сюда не доходит — там слоя нет вовсе.
  final NavIndicator kind;

  /// Место активного таба в ряду; −1 — активного таба в баре нет.
  final int slot;
  final int count;

  /// Скругление самой панели бара: подложка повторяет его, а не берёт радиус
  /// темы. Так у капсулы она капсула, у купола — купол, а у прижатого бара
  /// остаётся спокойный прямоугольник со скруглением темы.
  final double corner;

  @override
  Widget build(BuildContext context) {
    if (slot < 0) return const SizedBox.shrink();
    final t = context.bloom;

    return LayoutBuilder(
      builder: (context, box) {
        final cell = box.maxWidth / count;
        if (cell <= 0 || box.maxHeight <= 0) return const SizedBox.shrink();

        return Stack(
          children: [
            // Едет вся доля таба целиком, а внутри неё пометка стоит на своём
            // месте: у подложки это поля со всех сторон, у точки и линии — низ
            // ряда. Одно движение на все три вида.
            AnimatedPositioned(
              duration: kTabTransition,
              curve: Curves.easeOutCubic,
              left: cell * slot,
              top: 0,
              width: cell,
              height: box.maxHeight,
              child: switch (kind) {
                NavIndicator.pill => Padding(
                  padding: const EdgeInsets.all(_kPillPad),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Плёнка `iconBg` — та же, что под круглыми кнопками
                      // шапки: подложка обязана читаться как элемент бара, а не
                      // как второй бар внутри бара.
                      color: t.iconBg,
                      // Потолок в половину высоты: за ним скругление всё равно
                      // упирается в капсулу, а у «Купола» радиус панели заметно
                      // больше самой подложки.
                      borderRadius: BorderRadius.circular(
                        math.min(
                          corner,
                          math.max(box.maxHeight - _kPillPad * 2, 0) / 2,
                        ),
                      ),
                    ),
                  ),
                ),
                // Точка и линия — в акценте, а не плёнкой: подложка большая и
                // ей хватает еле заметной заливки, а пометка в пять пикселей на
                // той же плёнке просто не читалась бы.
                NavIndicator.dot => _Mark(
                  size: const Size(_kDotSize, _kDotSize),
                  radius: _kDotSize / 2,
                  color: t.accent,
                ),
                NavIndicator.line => _Mark(
                  size: _kLineSize,
                  radius: _kLineSize.height / 2,
                  color: t.accent,
                ),
                NavIndicator.none => const SizedBox.shrink(),
              },
            ),
          ],
        );
      },
    );
  }
}

/// Точка или линия у нижней кромки доли таба.
class _Mark extends StatelessWidget {
  const _Mark({required this.size, required this.radius, required this.color});

  final Size size;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: const EdgeInsets.only(bottom: _kMarkGap),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    ),
  );
}

// ─── Оживление иконок бара ──────────────────────────────────────────────────

/// Наплыв outline→bold и цвета. В такт со сменой самой вкладки
/// ([kTabTransition]): бар и содержимое обязаны идти одним темпом, иначе
/// заливка глифа договаривает уже поверх новой страницы.
const Duration kNavMorph = kTabTransition;

/// Чем иконка отвечает на выбор своей вкладки. Жест — свой на глиф, а не общий
/// на бар: одно и то же движение на всех трёх иконках выглядит как дёрганье
/// бара, а не как отклик конкретной.
enum _NavMotion {
  /// Качок вправо-влево с затуханием. Домик и ящик библиотеки стоят на
  /// «земле» — им идёт качнуться, как задетой вещи.
  wiggle,

  /// Оборот вокруг центра — шестерёнке настроек. Она круглая и симметричная:
  /// поворот на ней читается как вращение, а качок — как перекос.
  spin,
}

/// Отклик живёт отдельно от наплыва и заметно дольше него: это ответ под
/// пальцем, ему нормально догорать уже после того, как вкладка встала.
const Duration kNavWiggle = Duration(milliseconds: 380);
const Duration kNavSpin = Duration(milliseconds: 520);

/// Размах первого взмаха качка.
const double kWiggleMax = 9 * math.pi / 180;

/// Затухающий качок: три полувзмаха — вправо, влево, вправо. Взмахи даёт
/// синус, а множитель `(1 − t)` их гасит и ровно в конце обнуляет угол, так
/// что иконка успокаивается сама, а не сбрасывается в ноль рывком.
double _wiggleAngle(double t) =>
    kWiggleMax * math.sin(t * math.pi * 3) * (1 - t);

/// Оборот с выбегом: стартует быстро и тормозит к концу — шестерёнку будто
/// крутанули пальцем, а не провернули мотором. Полный круг, а не половина:
/// зубцы у неё частые, и на половине глаз не поймёт, что она вернулась.
double _spinAngle(double t) => 2 * math.pi * Curves.easeOutCubic.transform(t);

/// Подпись под иконкой: мельче всего, что есть в теме, — в доле таба стоит
/// строка вроде «Настройки», и на обычном мелком тексте она стала бы
/// многоточием.
const double _kNavLabelSize = 10.5;

/// Просвет между глифом и подписью.
const double _kNavLabelGap = 3;

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.spec,
    required this.active,
    required this.mark,
    required this.iconSize,
    required this.textIconSize,
    required this.labels,
    required this.onTap,
  });

  final _NavSpec spec;
  final bool active;

  /// Вместо пары глифов — знак Bloom (настройка [SettingsState.navHomeLogo]).
  final bool mark;

  /// Глиф без подписи под ним.
  final double iconSize;

  /// Глиф, под которым стоит подпись, — мельче обычного, см. [_kNavIconText].
  final double textIconSize;

  /// Подписи под иконками, см. [NavLabels].
  final NavLabels labels;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with TickerProviderStateMixin {
  /// 0 — покой, 1 — активный таб. Стартует «доехавшим»: на первом кадре
  /// приложения наплывать неоткуда.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: kNavMorph,
    value: widget.active ? 1 : 0,
  );

  /// Жест иконки: качок или оборот, смотря по [_NavSpec.motion].
  late final AnimationController _react = AnimationController(
    vsync: this,
    duration: widget.spec.motion == _NavMotion.spin ? kNavSpin : kNavWiggle,
  );

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _morph.forward();
      _react.forward(from: 0);
    } else {
      _morph.reverse();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _react.dispose();
    super.dispose();
  }

  void _tap() {
    // Повторный тап по своей же вкладке не меняет `active` (и жеста из
    // `didUpdateWidget` не будет), но что-то делает — сбрасывает ветку в
    // корень. Отвечаем на него тем же жестом, иначе тап выглядит потерянным.
    if (widget.active) _react.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.spec.label(context.l),
      // Без подложки и без ряби: активный таб отличается заливкой глифа
      // (bold вместо outline) и цветом акцента — этого достаточно, а
      // material-ripple на голом фоне читается как посторонний круг.
      child: Pressable(
        onTap: _tap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_morph, _react]),
          builder: (context, _) {
            // В покое контроллер стоит на 1 (жест доигран), и обе формы там
            // дают ту же картинку, что при 0: качок обнулён затуханием, а
            // оборот — это полный круг. Отдельного «покоя» заводить не надо.
            final angle = widget.spec.motion == _NavMotion.spin
                ? _spinAngle(_react.value)
                : _wiggleAngle(_react.value);
            // Крутится и качается ОДИН глиф, а не столбик с подписью: наклонная
            // строка текста читается как сбой раскладки, а не как отклик.
            final glyph = Transform.rotate(
              angle: angle,
              child: _icons(t, _iconSize()),
            );
            if (widget.labels == NavLabels.none) return Center(child: glyph);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [glyph, _label(t)],
            );
          },
        ),
      ),
    );
  }

  /// Размер глифа.
  ///
  /// У [NavLabels.active] он едет между обычным и ужатым вместе с наплывом
  /// ([kNavMorph]): таб, под которым проявляется строка, освобождает ей место
  /// сам, а тот, с которого ушли, ровно так же возвращается к обычному глифу.
  /// Разъехаться они не могут — оба движения ведёт один контроллер.
  double _iconSize() => switch (widget.labels) {
    NavLabels.none => widget.iconSize,
    NavLabels.always => widget.textIconSize,
    NavLabels.active =>
      widget.iconSize +
          (widget.textIconSize - widget.iconSize) * _morph.value.clamp(0, 1),
  };

  /// Подпись под глифом.
  ///
  /// У [NavLabels.active] строки под неактивными табами НЕ ЗАНИМАЮТ места:
  /// пустой отступ под мелким глифом читается как повисшая в воздухе иконка, а
  /// не как ряд (его слово по первой сборке). Строка раскрывается вместе с
  /// глифом — от нулевой высоты, а не проявляется в готовой дырке.
  Widget _label(BloomTokens t) {
    final m = _morph.value.clamp(0.0, 1.0);
    final open = widget.labels == NavLabels.always ? 1.0 : m;
    if (open == 0) return const SizedBox.shrink();

    return ClipRect(
      child: Align(
        // Верхом к глифу: строка выезжает из-под иконки вниз, а не
        // проявляется, обрезанная с обеих сторон.
        alignment: Alignment.topCenter,
        heightFactor: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, _kNavLabelGap, 2, 0),
          child: Opacity(
            // Текст догоняет раскрытие: на полпути строка уже заняла место, но
            // ещё бледна — иначе она въезжает в ряд готовой и бьёт по глазам.
            opacity: open,
            child: Text(
              widget.spec.label(context.l),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _kNavLabelSize,
                height: 1.15,
                fontWeight: FontWeight.w500,
                // Тот же наплыв цвета, что у глифа: подпись и иконка — одна
                // вещь.
                color: Color.lerp(t.text, t.accent, m),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Два слоя друг на друге: bold проявляется поверх outline.
  ///
  /// Кривые подобраны так, чтобы слои перекрывались, а не разошлись в
  /// середине: outline держится первую треть на полной непрозрачности и
  /// уходит, когда заливка уже набрала вес. Иначе на половине перехода
  /// суммарная альфа контура проседает и иконка на кадр тускнеет.
  Widget _icons(BloomTokens t, double size) {
    final m = _morph.value;
    // Покой — полный контраст (`text`), а не приглушённый `iconFgSb`: в баре
    // всего три глифа, и тусклые они читаются как выключенные. Активный таб
    // и без разницы в яркости виден — по заливке и акценту.
    final color = Color.lerp(t.text, t.accent, m)!;
    // Знак бренда парой глифов не бывает: он нарисован одной заливкой, и
    // наплывать в нём нечему — выбранность показывает тот же цвет, что у
    // остальных табов. Чуть мельче глифа: звезда занимает свой квадрат почти
    // целиком, а у Solar внутри бокса есть поля, и в равном размере знак в
    // ряду выпирал бы.
    if (widget.mark) return BloomMark(size: size * 0.86, color: color);
    final fill = Curves.easeOut.transform(m);
    final line = 1 - const Interval(0.35, 1).transform(m);
    final spec = widget.spec;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (line > 0) _layer(spec.icon, color, line, size),
        if (fill > 0) _layer(spec.activeIcon, color, fill, size),
      ],
    );
  }

  Widget _layer(BloomGlyph glyph, Color color, double opacity, double size) =>
      Opacity(
        opacity: opacity.clamp(0, 1),
        child: BloomIcon(glyph, size: size, color: color),
      );
}
