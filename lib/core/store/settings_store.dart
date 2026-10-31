/// Настройки внешнего вида и площадок.
///
/// Как на десктопе: тема — это ТРИ цвета пресета, а радиус и акцент живут
/// отдельно и при смене темы не сбрасываются (`themeStore.ts`: «радиус и шрифт
/// в тему не входят намеренно»).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/fonts.dart';
import '../../app/theme/tokens.dart';
import '../../providers/soundcloud/soundcloud.dart' as sc;
import 'json_store.dart' show jsonStoreProvider;

export '../../app/theme/tokens.dart' show ThemePreset, kThemePresets;

/// id авто-темы. В [kThemePresets] её нет намеренно: это РЕЖИМ, а не набор
/// цветов — три цвета ей приносит обложка играющего трека (см.
/// `features/settings/auto_accent.dart`), — но в списке тем она стоит такой же
/// карточкой и выбирается тем же [SettingsController.setTheme].
const String kAutoThemeId = 'auto';

/// Границы и дефолт яркости авто-акцента — те же числа, что в десктопном
/// `coverAccent.ts`: центр коридора светлоты, вокруг которого зажимается цвет
/// обложки.
const double kAutoAccentLMin = 0.1;
const double kAutoAccentLMax = 0.6;
const double kAutoAccentLDefault = 0.375;

double clampAutoAccentL(double v) => v.clamp(kAutoAccentLMin, kAutoAccentLMax);

/// Вид таб-бара каркаса. Настройка чисто телефонная: на десктопе навигация
/// живёт в сайдбаре, и порта у неё нет.
///
/// Отличаются только рамка и поля вокруг ряда иконок — сам ряд, его высота и
/// оживление глифов у всех стилей общие.
enum NavBarStyle {
  /// Во всю ширину, прижат к низу, тонкая линия сверху — как было всегда.
  bar,

  /// То же место, но панель отбита сверху скруглением: под её углами видно
  /// список.
  rounded,

  /// Тот же прижатый бар, но верх скруглён вдвое сильнее — панель выгибается
  /// куполом, а не просто теряет углы.
  dome,

  /// Карточка с полями по краям, приподнятая над низом, — пара к миниплееру.
  floating,

  /// Та же плавающая панель, но с углами в половину высоты — капсула.
  pill,
}

/// Стиль из сырых настроек. Неизвестное имя (настройки от новой сборки) — это
/// не повод падать: возвращаем обычный бар.
NavBarStyle readNavStyle(Object? raw) {
  for (final style in NavBarStyle.values) {
    if (style.name == raw) return style;
  }
  return NavBarStyle.bar;
}

/// A bottom bar tab. The bar always holds all four; only their order is a
/// setting ([SettingsState.navOrder]). The enum order is the fresh install's
/// order and also the router's branch order ([NavTab.index]).
enum NavTab { home, search, library, settings }

/// The bar order from raw settings — always every tab exactly once: I repair
/// the list rather than reject it, so a missing name lands at the end and
/// unknown names or repeats drop out.
List<NavTab> readNavOrder(Object? raw) {
  if (raw is! List) return kDefaultNavOrder;
  final seen = <NavTab>{};
  return [
    for (final name in raw.whereType<String>())
      for (final tab in NavTab.values)
        if (tab.name == name && seen.add(tab)) tab,
    for (final tab in NavTab.values)
      if (!seen.contains(tab)) tab,
  ];
}

/// Порядок бара у свежей установки.
const List<NavTab> kDefaultNavOrder = NavTab.values;

/// Чем помечен активный таб.
enum NavIndicator {
  /// Ничем: активный таб виден только заливкой глифа и акцентом — так бар и
  /// выглядел до того, как выделение вообще завели.
  none,

  /// Плашка почти во всю долю таба, под иконкой и подписью.
  pill,

  /// Точка у нижней кромки ряда, под иконкой.
  dot,

  /// Короткая линия там же, где стояла бы точка.
  line,
}

/// Выделение из сырых настроек. Ключа нет — настройки от сборки, где выделение
/// было тумблером «подложка да/нет» (`navPill`): её и читаем, иначе у всех, кто
/// подложку выключал, она вернулась бы сама.
NavIndicator readNavIndicator(Map<String, dynamic> raw) {
  final name = raw['navIndicator'];
  for (final value in NavIndicator.values) {
    if (value.name == name) return value;
  }
  return (raw['navPill'] as bool? ?? true)
      ? NavIndicator.pill
      : NavIndicator.none;
}

/// Подписи под иконками бара.
enum NavLabels {
  /// Только иконки — как бар выглядел всегда.
  none,

  /// Под каждой иконкой.
  always,

  /// Только под активным табом. Место под строку занято при этом всё равно,
  /// иначе ряд дёргался бы на каждом переключении.
  active,
}

/// Подписи из сырых настроек. Неизвестное имя — не повод падать: дефолт.
NavLabels readNavLabels(Object? raw) {
  for (final value in NavLabels.values) {
    if (value.name == raw) return value;
  }
  return NavLabels.none;
}

/// Что Bloom делает с файлом, добавленным плюсом во «Всех треках» — порт
/// десктопного `local_import_mode` (там он про папки, у нас — про одиночные
/// файлы, папок на телефоне мы не смотрим).
enum LocalImportMode {
  /// Файл остаётся там, где лежит; Bloom помнит выданное системой разрешение
  /// на чтение. Дефолт, как и на ПК.
  inPlace,

  /// Файл копируется внутрь приложения — тогда трек переживает переезд и
  /// удаление оригинала, но занимает место второй раз.
  copy,
}

/// Режим из сырых настроек. Неизвестное имя — не повод падать: дефолт.
LocalImportMode readLocalImportMode(Object? raw) {
  for (final mode in LocalImportMode.values) {
    if (mode.name == raw) return mode;
  }
  return LocalImportMode.inPlace;
}

/// Языки интерфейса — те же два, что в десктопном `LOCALES` (`i18nStore.ts`).
///
/// Порядок показа: английский первым, как на ПК.
const List<Locale> kLocales = [Locale('en'), Locale('ru')];

/// Сохранённый язык из сырой карты настроек; `null` — «как в системе».
///
/// Отдельной функцией, потому что нужна и до создания контейнера: `main()`
/// собирает название канала уведомлений раньше первого кадра.
Locale? readSavedLocale(Map<String, dynamic> raw) {
  final code = raw['locale'];
  if (code is! String) return null;
  for (final locale in kLocales) {
    if (locale.languageCode == code) return locale;
  }
  return null;
}

class SettingsState {
  final String themeId;

  /// Язык интерфейса; `null` — «как в системе».
  ///
  /// Именно null, а не подставленный при первом запуске код: тогда телефон,
  /// переключённый на другой язык, переключает и приложение, пока пользователь
  /// не выбрал язык руками. Дальше выбор уже не сбивается.
  final Locale? locale;

  /// Переопределение акцента; null — берётся из пресета.
  ///
  /// Ручного выбора акцента на телефоне нет (как и на ПК — там только пикеры
  /// внутри своей темы), так что заполняет его сейчас ровно одно — авто-акцент
  /// из обложки.
  final Color? accent;

  /// Акцент из обложки играющего трека (десктопный `autoAccent`).
  final bool autoAccent;

  /// Яркость авто-акцента: центр коридора светлоты, см. [clampAutoAccentL].
  /// Общая с авто-темой — акцент та считает по той же формуле.
  final double autoAccentL;

  /// Поверхность авто-темы — цвет, снятый с обложки. Фон и блоки у неё
  /// одинаковые, как у встроенных пресетов, поэтому цвет один.
  ///
  /// Живёт и когда авто-тема не выбрана: это последнее её лицо, им и рисуется
  /// карточка в шторке выбора. При включении авто-темы сюда кладётся цвет
  /// текущей темы — до первой обложки перекрашивать не из чего (десктопный
  /// `applyTheme` в этом месте тоже остаётся на текущих цветах).
  final Color? autoSurface;

  /// Ручной client_id SoundCloud (пусто — авто-подбор).
  final String? scClientId;

  /// Бейджи источника в цвете акцента. По умолчанию выключено — бейджи в
  /// фирменных цветах площадок (то же поведение и дефолт, что на десктопе).
  final bool accentBadges;

  /// Шрифт интерфейса — семейство, как оно сохранено (десктопный
  /// `fontFamily`). Сырое значение: свои шрифты живут в своём сторе, и
  /// проверять выбор против них здесь нечем — это делает `normalizeFont` там,
  /// где собирается тема.
  final String fontFamily;

  /// Вид таб-бара, см. [NavBarStyle].
  final NavBarStyle navStyle;

  /// The bar tabs in display order.
  final List<NavTab> navOrder;

  /// Чем помечен активный таб, см. [NavIndicator].
  final NavIndicator navIndicator;

  /// Подписи под иконками, см. [NavLabels].
  final NavLabels navLabels;

  /// Знак Bloom вместо иконки «Главной» — десктопная
  /// `settings.interface.nav.homeLogo`. Пара глифов у таба при этом остаётся:
  /// знак нарисован одной заливкой, и наплыва outline→bold ему не из чего
  /// собрать — выбранность у него показывает только цвет.
  final bool navHomeLogo;

  /// Обложка играющего трека как фон приложения — десктопная
  /// `settings.background.coverAsBg`. Своя картинка фона (её ставят в
  /// «Кастомизации») эту настройку перебивает, как и на ПК.
  final bool coverAsBg;

  /// Что делать с добавленным своим файлом, см. [LocalImportMode].
  final LocalImportMode localImport;

  /// Возвращать при запуске трек, очередь и позицию прошлой сессии — но НЕ
  /// начинать играть. Настройка мобильная: на ПК её пока нет (пользователь
  /// собирался завести такую же и там), а десктопный `autoplay` — это сразу
  /// «восстановить и играть», см. [autoplay].
  final bool restoreQueue;

  /// Восстановить сессию и сразу продолжить воспроизведение — десктопная
  /// `settings.system.autoplay`. Надстройка над [restoreQueue]: сама она ничего
  /// не восстанавливает, поэтому без него не показывается и не действует.
  final bool autoplay;

  /// «Авто похожие» (десктопный `audioStore.autoSimilar`): доигравшая очередь
  /// продолжается похожими треками, дописанными в её хвост. Кнопка «Похожие на
  /// очередь» в шторке — другое: она заменяет очередь волной сразу.
  final bool autoSimilar;

  /// Свои темы — в порядке создания, после встроенных.
  final List<ThemePreset> customThemes;

  const SettingsState({
    this.themeId = 'dark',
    this.locale,
    this.accent,
    this.autoAccent = false,
    this.autoAccentL = kAutoAccentLDefault,
    this.autoSurface,
    this.scClientId,
    this.accentBadges = false,
    this.fontFamily = kDefaultFont,
    this.navStyle = NavBarStyle.bar,
    this.navOrder = kDefaultNavOrder,
    this.navIndicator = NavIndicator.pill,
    this.navLabels = NavLabels.none,
    this.navHomeLogo = false,
    this.coverAsBg = false,
    this.localImport = LocalImportMode.inPlace,
    this.restoreQueue = false,
    this.autoplay = false,
    this.autoSimilar = false,
    this.customThemes = const [],
  });

  /// Встроенные и свои разом — в этом порядке они и показываются.
  List<ThemePreset> get allThemes => [...kThemePresets, ...customThemes];

  /// Выбрана авто-тема: цвета едут за обложкой.
  bool get autoTheme => themeId == kAutoThemeId;

  ThemePreset get preset {
    if (autoTheme) {
      // Пресета с таким id нет — собираем его из снятых с обложки цветов.
      // Название тут служебное: в интерфейсе у авто-темы своя строка из
      // переводов (`thAutoName`), пресетное имя ей не показывают.
      final surface = autoSurface ?? kThemePresets.first.bg;
      return ThemePreset(
        id: kAutoThemeId,
        name: 'Auto',
        bg: surface,
        blockColor: surface,
        accent: accent ?? kThemePresets.first.accent,
      );
    }
    return allThemes.firstWhere(
      (p) => p.id == themeId,
      orElse: () => kThemePresets.first,
    );
  }

  BloomTokens get tokens => preset.tokens(accentOverride: accent);

  SettingsState copyWith({
    String? themeId,
    Locale? locale,
    bool clearLocale = false,
    Color? accent,
    bool clearAccent = false,
    bool? autoAccent,
    double? autoAccentL,
    Color? autoSurface,
    String? scClientId,
    bool clearClientId = false,
    bool? accentBadges,
    String? fontFamily,
    NavBarStyle? navStyle,
    List<NavTab>? navOrder,
    NavIndicator? navIndicator,
    NavLabels? navLabels,
    bool? navHomeLogo,
    bool? coverAsBg,
    LocalImportMode? localImport,
    bool? restoreQueue,
    bool? autoplay,
    bool? autoSimilar,
    List<ThemePreset>? customThemes,
  }) => SettingsState(
    themeId: themeId ?? this.themeId,
    locale: clearLocale ? null : (locale ?? this.locale),
    accent: clearAccent ? null : (accent ?? this.accent),
    autoAccent: autoAccent ?? this.autoAccent,
    autoAccentL: autoAccentL ?? this.autoAccentL,
    autoSurface: autoSurface ?? this.autoSurface,
    scClientId: clearClientId ? null : (scClientId ?? this.scClientId),
    accentBadges: accentBadges ?? this.accentBadges,
    fontFamily: fontFamily ?? this.fontFamily,
    navStyle: navStyle ?? this.navStyle,
    navOrder: navOrder ?? this.navOrder,
    navIndicator: navIndicator ?? this.navIndicator,
    navLabels: navLabels ?? this.navLabels,
    navHomeLogo: navHomeLogo ?? this.navHomeLogo,
    coverAsBg: coverAsBg ?? this.coverAsBg,
    localImport: localImport ?? this.localImport,
    restoreQueue: restoreQueue ?? this.restoreQueue,
    autoplay: autoplay ?? this.autoplay,
    autoSimilar: autoSimilar ?? this.autoSimilar,
    customThemes: customThemes ?? this.customThemes,
  );
}

/// The saved theme id, or Dark when that theme is gone (a preset dropped in
/// an update), as the PC's `syncPreset` does.
String _knownTheme(Object? id, List<ThemePreset> custom) {
  final known =
      id == kAutoThemeId ||
      kThemePresets.any((p) => p.id == id) ||
      custom.any((p) => p.id == id);
  return known ? id! as String : kThemePresets.first.id;
}

final settingsProvider = NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final raw = ref.read(jsonStoreProvider).readMap('settings');
    final accent = raw['accent'];
    final autoSurface = raw['autoSurface'];
    final clientId = raw['scClientId'];
    final customThemes = [
      for (final item in (raw['customThemes'] as List?) ?? const [])
        ?ThemePreset.fromJson(item),
    ];
    final state = SettingsState(
      themeId: _knownTheme(raw['themeId'], customThemes),
      locale: readSavedLocale(raw),
      accent: accent is num ? Color(accent.toInt()) : null,
      autoAccent: raw['autoAccent'] as bool? ?? false,
      autoAccentL: clampAutoAccentL(
        (raw['autoAccentL'] as num?)?.toDouble() ?? kAutoAccentLDefault,
      ),
      autoSurface: autoSurface is num ? Color(autoSurface.toInt()) : null,
      scClientId: clientId is String && clientId.isNotEmpty ? clientId : null,
      accentBadges: raw['accentBadges'] as bool? ?? false,
      fontFamily: raw['fontFamily'] as String? ?? kDefaultFont,
      navStyle: readNavStyle(raw['navStyle']),
      navOrder: readNavOrder(raw['navOrder']),
      navIndicator: readNavIndicator(raw),
      navLabels: readNavLabels(raw['navLabels']),
      navHomeLogo: raw['navHomeLogo'] as bool? ?? false,
      coverAsBg: raw['coverAsBg'] as bool? ?? false,
      localImport: readLocalImportMode(raw['localImport']),
      restoreQueue: raw['restoreQueue'] as bool? ?? false,
      autoplay: raw['autoplay'] as bool? ?? false,
      autoSimilar: raw['autoSimilar'] as bool? ?? false,
      customThemes: customThemes,
    );
    // Провайдер SoundCloud держит client_id в модульном состоянии — при старте
    // ему надо отдать сохранённый, иначе ручной ключ забудется до перезапуска.
    sc.setManualClientId(state.scClientId);
    return state;
  }

  void _save() {
    ref.read(jsonStoreProvider).write('settings', {
      'themeId': state.themeId,
      if (state.locale != null) 'locale': state.locale!.languageCode,
      if (state.accent != null) 'accent': state.accent!.toARGB32(),
      'autoAccent': state.autoAccent,
      'autoAccentL': state.autoAccentL,
      if (state.autoSurface != null)
        'autoSurface': state.autoSurface!.toARGB32(),
      if (state.scClientId != null) 'scClientId': state.scClientId,
      'accentBadges': state.accentBadges,
      'fontFamily': state.fontFamily,
      'navStyle': state.navStyle.name,
      'navOrder': [for (final tab in state.navOrder) tab.name],
      'navIndicator': state.navIndicator.name,
      'navLabels': state.navLabels.name,
      'navHomeLogo': state.navHomeLogo,
      'coverAsBg': state.coverAsBg,
      'localImport': state.localImport.name,
      'restoreQueue': state.restoreQueue,
      'autoplay': state.autoplay,
      'autoSimilar': state.autoSimilar,
      'customThemes': [for (final t in state.customThemes) t.toJson()],
    });
  }

  /// Смена темы НЕ трогает акцент и радиус — это независимые настройки вида.
  ///
  /// Исключение — авто-тема: акцент у неё свой, снятый с обложки. На входе она
  /// затравливается текущими цветами (перекрашивать пока не из чего) и гасит
  /// авто-акцент — вдвоём они спорили бы за один акцент; на выходе снятый цвет
  /// сбрасывается, иначе выбранный пресет остался бы с чужим акцентом.
  void setTheme(String id) {
    if (id == kAutoThemeId) {
      state = state.copyWith(
        themeId: id,
        autoSurface: state.preset.bg,
        accent: state.tokens.accent,
        autoAccent: false,
      );
    } else {
      state = state.copyWith(themeId: id, clearAccent: state.autoTheme);
    }
    _save();
  }

  /// Создать свою тему из трёх цветов и сразу её применить — как
  /// `createCustomTheme` на десктопе. Возвращает готовый пресет: вызывающему
  /// нужно его имя для тоста.
  ThemePreset createCustomTheme({
    required String name,
    required Color bg,
    required Color blockColor,
    required Color accent,
  }) {
    final preset = ThemePreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      bg: bg,
      blockColor: blockColor,
      accent: accent,
      custom: true,
    );
    state = state.copyWith(
      customThemes: [...state.customThemes, preset],
      themeId: preset.id,
    );
    _save();
    return preset;
  }

  /// Удалить свою тему. Если она была активной — возвращаемся на первую
  /// встроенную, как на ПК: иначе приложение осталось бы с темой, которой нет.
  void deleteCustomTheme(String id) {
    final rest = [
      for (final t in state.customThemes)
        if (t.id != id) t,
    ];
    state = state.copyWith(
      customThemes: rest,
      themeId: state.themeId == id ? kThemePresets.first.id : null,
    );
    _save();
  }

  /// Вернуть тему из снимка (пресет кастомизации). Есть такая — просто
  /// выбираем; своей темы из снимка у нас нет (удалили, пресет с другого
  /// телефона) — заводим её заново под тем же id, чтобы повторное применение не
  /// плодило копий.
  void restoreTheme(ThemePreset theme) {
    final known =
        theme.id == kAutoThemeId ||
        state.allThemes.any((t) => t.id == theme.id);
    if (known || !theme.custom) {
      setTheme(known ? theme.id : kThemePresets.first.id);
      return;
    }
    state = state.copyWith(
      customThemes: [...state.customThemes, theme],
      themeId: theme.id,
      clearAccent: state.autoTheme,
    );
    _save();
  }

  /// Выбрать язык интерфейса; `null` — вернуться к системному.
  void setLocale(Locale? locale) {
    state = locale == null
        ? state.copyWith(clearLocale: true)
        : state.copyWith(locale: locale);
    _save();
  }

  /// Включить/выключить авто-акцент. При выключении акцент сразу возвращается
  /// к цвету пресета — на десктопе там точка восстановления (`accentManual`),
  /// но ручного акцента у нас нет, восстанавливать нечего.
  ///
  /// Включение снимает авто-тему — она шире, и красить акцент им обоим нельзя
  /// (то же правило в десктопном `setAutoAccent`). Уходить приходится на
  /// встроенную тему: замороженных цветов, как `activeThemeId: 'custom'` на ПК,
  /// у нас держать негде. На экране вида тоггла при авто-теме и нет вовсе —
  /// сюда приходят разве что из онбординга.
  void setAutoAccent(bool value) {
    state = value
        ? state.copyWith(
            autoAccent: true,
            themeId: state.autoTheme ? kThemePresets.first.id : null,
            clearAccent: state.autoTheme,
          )
        : state.copyWith(autoAccent: false, clearAccent: true);
    _save();
  }

  void setAutoAccentL(double value) {
    state = state.copyWith(autoAccentL: clampAutoAccentL(value));
    _save();
  }

  /// Цвет, вытащенный из обложки. Приходит из моста авто-акцента; если тоггл
  /// уже успели выключить — молча игнорируем, иначе поздний скан вернул бы
  /// акцент обратно.
  void applyAutoAccent(Color color) {
    if (!state.autoAccent) return;
    if (state.accent?.toARGB32() == color.toARGB32()) return;
    state = state.copyWith(accent: color);
    _save();
  }

  /// Цвета авто-темы, посчитанные от обложки: поверхность (фон = блоки) и
  /// акцент. Приходят из того же моста; тему могли успеть переключить, пока
  /// грузилась картинка, — тогда молча выходим.
  void applyAutoTheme(Color surface, Color accent) {
    if (!state.autoTheme) return;
    if (state.autoSurface?.toARGB32() == surface.toARGB32() &&
        state.accent?.toARGB32() == accent.toARGB32()) {
      return;
    }
    state = state.copyWith(autoSurface: surface, accent: accent);
    _save();
  }

  void setAccentBadges(bool value) {
    state = state.copyWith(accentBadges: value);
    _save();
  }

  void setFontFamily(String family) {
    if (state.fontFamily == family) return;
    state = state.copyWith(fontFamily: family);
    _save();
  }

  void setNavStyle(NavBarStyle style) {
    state = state.copyWith(navStyle: style);
    _save();
  }

  /// Move a bar tab. [to] follows `ReorderableListView`: it counts the list
  /// before the row is taken out, so moving down I subtract one.
  void moveNavTab(int from, int to) {
    final order = [...state.navOrder];
    if (from < 0 || from >= order.length) return;
    final tab = order.removeAt(from);
    order.insert((to > from ? to - 1 : to).clamp(0, order.length), tab);
    state = state.copyWith(navOrder: order);
    _save();
  }

  void setNavIndicator(NavIndicator value) {
    state = state.copyWith(navIndicator: value);
    _save();
  }

  void setNavLabels(NavLabels value) {
    state = state.copyWith(navLabels: value);
    _save();
  }

  void setNavHomeLogo(bool value) {
    state = state.copyWith(navHomeLogo: value);
    _save();
  }

  void setCoverAsBg(bool value) {
    state = state.copyWith(coverAsBg: value);
    _save();
  }

  /// Режим добавления своих файлов. На уже добавленные треки не влияет — как и
  /// на ПК, где смена режима не трогает добавленные папки.
  void setLocalImport(LocalImportMode mode) {
    state = state.copyWith(localImport: mode);
    _save();
  }

  /// Восстанавливать сессию при запуске. Выключение снимает и
  /// [SettingsState.autoplay]: его строку экран прячет, а поднятый флаг в
  /// скрытой строке остаться не должен — иначе восстановление вернут и получат
  /// внезапно играющий с порога плеер.
  void setRestoreQueue(bool value) {
    state = value
        ? state.copyWith(restoreQueue: true)
        : state.copyWith(restoreQueue: false, autoplay: false);
    _save();
  }

  /// Автовоспроизведение. Восстановление обратно не включает: тумблер
  /// показывают только под уже включённым восстановлением, и надстройка «и
  /// сразу продолжить» им не распоряжается.
  void setAutoplay(bool value) {
    state = state.copyWith(autoplay: value);
    _save();
  }

  void setAutoSimilar(bool value) {
    state = state.copyWith(autoSimilar: value);
    _save();
  }

  void setScClientId(String? id) {
    final v = id?.trim();
    final norm = (v == null || v.isEmpty) ? null : v;
    state = norm == null
        ? state.copyWith(clearClientId: true)
        : state.copyWith(scClientId: norm);
    sc.setManualClientId(norm);
    _save();
  }
}
