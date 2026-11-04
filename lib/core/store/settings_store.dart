/// Appearance and platform settings. A theme is THREE preset colours; radius
/// and accent live apart and survive a theme change.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/fonts.dart';
import '../../app/theme/tokens.dart';
import '../../providers/soundcloud/soundcloud.dart' as sc;
import 'json_store.dart' show jsonStoreProvider;

export '../../app/theme/tokens.dart' show ThemePreset, kThemePresets;

/// Auto theme id. Not in [kThemePresets] on purpose: it's a MODE, not a colour
/// set (the playing cover brings the three colours), but in the theme list it's
/// a card like others, picked by the same [SettingsController.setTheme].
const String kAutoThemeId = 'auto';

/// Bounds and default of auto accent brightness: the centre of the lightness
/// corridor the cover's colour is clamped around.
const double kAutoAccentLMin = 0.1;
const double kAutoAccentLMax = 0.6;
const double kAutoAccentLDefault = 0.375;

double clampAutoAccentL(double v) => v.clamp(kAutoAccentLMin, kAutoAccentLMax);

/// Shell tab bar style. They differ only in the frame and margins around the
/// icon row; the row, its height and glyph motion are shared.
enum NavBarStyle {
  /// Full width, flush to the bottom, a thin line on top.
  bar,

  /// The same place, with rounded top corners: the list shows under them.
  rounded,

  /// The same flush bar with the top twice as round: the panel arches like a
  /// dome rather than just losing corners.
  dome,

  /// A card with margins, lifted from the bottom, a pair to the mini player.
  floating,

  /// The same floating panel with corners of half its height: a capsule.
  pill,
}

/// Style from raw settings. An unknown name (settings from a newer build) is no
/// reason to crash: the plain bar.
NavBarStyle readNavStyle(Object? raw) {
  for (final style in NavBarStyle.values) {
    if (style.name == raw) return style;
  }
  return NavBarStyle.bar;
}

/// A bottom bar tab. The bar always holds all four; only their order is a
/// setting ([SettingsState.navOrder]). A fresh install's order is
/// [kDefaultNavOrder].
enum NavTab { home, search, library, settings }

/// The tabs that are router branches, in branch order. Search isn't one: it
/// opens as a layer over the tab that's open.
const List<NavTab> kBranchTabs = [NavTab.home, NavTab.library, NavTab.settings];

/// The bar order from raw settings — always every tab exactly once: I repair
/// the list rather than reject it, so a missing name lands at the end and
/// unknown names or repeats drop out.
///
/// `navOrder` is the earlier key. A list there in the earlier default order was
/// never picked by hand, so it moves to the current default; any other stays.
List<NavTab> readNavOrder(Map<String, dynamic> raw) {
  final saved = raw['navTabs'] ?? raw['navOrder'];
  if (saved is! List) return kDefaultNavOrder;
  if (raw['navTabs'] == null &&
      saved.join(',') == 'home,search,library,settings') {
    return kDefaultNavOrder;
  }
  final seen = <NavTab>{};
  return [
    for (final name in saved.whereType<String>())
      for (final tab in NavTab.values)
        if (tab.name == name && seen.add(tab)) tab,
    for (final tab in NavTab.values)
      if (!seen.contains(tab)) tab,
  ];
}

/// Bar order of a fresh install.
const List<NavTab> kDefaultNavOrder = [
  NavTab.home,
  NavTab.library,
  NavTab.search,
  NavTab.settings,
];

/// What marks the active tab.
enum NavIndicator {
  /// Nothing: the active tab shows only by its filled glyph and accent.
  none,

  /// A plate over nearly the whole tab share, under icon and label.
  pill,

  /// A dot at the row's bottom edge, under the icon.
  dot,

  /// A short line where the dot would be.
  line,
}

/// Indicator from raw settings. With no key, the settings come from a build
/// with an on/off plate switch (`navPill`), so I read that, or those who turned
/// it off would get it back.
NavIndicator readNavIndicator(Map<String, dynamic> raw) {
  final name = raw['navIndicator'];
  for (final value in NavIndicator.values) {
    if (value.name == name) return value;
  }
  return (raw['navPill'] as bool? ?? true)
      ? NavIndicator.pill
      : NavIndicator.none;
}

/// Labels under the bar icons.
enum NavLabels {
  /// Icons only.
  none,

  /// Under every icon.
  always,

  /// Only under the active tab.
  active,
}

/// Labels from raw settings. An unknown name is no reason to crash: the
/// default.
NavLabels readNavLabels(Object? raw) {
  for (final value in NavLabels.values) {
    if (value.name == raw) return value;
  }
  return NavLabels.none;
}

/// What Bloom does with a file added by plus in all tracks.
enum LocalImportMode {
  /// The file stays where it is; Bloom remembers the read permission from the
  /// system. The default.
  inPlace,

  /// The file is copied into the app: the track survives moving or deleting the
  /// original, but takes space twice.
  copy,
}

/// Mode from raw settings. An unknown name is no reason to crash: the default.
LocalImportMode readLocalImportMode(Object? raw) {
  for (final mode in LocalImportMode.values) {
    if (mode.name == raw) return mode;
  }
  return LocalImportMode.inPlace;
}

/// UI languages, English first.
const List<Locale> kLocales = [Locale('en'), Locale('ru')];

/// Saved language from the raw settings map; `null` means system. A separate
/// function because it's needed before the container exists: `main()` builds
/// the notification channel's name before the first frame.
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

  /// UI language; `null` means system. Null rather than a code filled in on
  /// first launch: a phone switched to another language switches the app too,
  /// until the user picks by hand.
  final Locale? locale;

  /// Accent override; null takes the preset's. There's no manual accent choice,
  /// so only the auto accent fills it.
  final Color? accent;

  /// Accent from the playing cover.
  final bool autoAccent;

  /// Auto accent brightness: centre of the lightness corridor, see
  /// [clampAutoAccentL]. Shared with the auto theme, whose accent uses the same
  /// formula.
  final double autoAccentL;

  /// Auto theme's surface, a colour taken from the cover. Background and blocks
  /// match, as in built-in presets, so it's one colour.
  ///
  /// Lives on when the auto theme isn't picked: it's its last look, and the
  /// picker's card draws with it. On turning the auto theme on, the current
  /// theme's colour goes here, with nothing to recolour from until the first
  /// cover.
  final Color? autoSurface;

  /// Manual SoundCloud client_id; empty means automatic.
  final String? scClientId;

  /// Source badges in the accent colour. Off by default: badges in platform
  /// brand colours.
  final bool accentBadges;

  /// UI font, the family as saved. A raw value: user fonts live in their own
  /// store and can't be checked here; `normalizeFont` does that where the theme
  /// is built.
  final String fontFamily;

  /// Tab bar style; see [NavBarStyle].
  final NavBarStyle navStyle;

  /// The bar tabs in display order.
  final List<NavTab> navOrder;

  /// What marks the active tab; see [NavIndicator].
  final NavIndicator navIndicator;

  /// Labels under icons; see [NavLabels].
  final NavLabels navLabels;

  /// Bloom mark instead of the home icon. The tab's glyph pair stays: the mark
  /// is one fill with nothing to blend, so only colour shows selection.
  final bool navHomeLogo;

  /// The playing cover as the app background. A custom background picture
  /// overrides this.
  final bool coverAsBg;

  /// What to do with an added local file; see [LocalImportMode].
  final LocalImportMode localImport;

  /// Bring back the last session's track, queue and position at launch, but NOT
  /// start playing; see [autoplay].
  final bool restoreQueue;

  /// Restore the session and continue playing at once. An add-on over
  /// [restoreQueue]: it restores nothing itself and does nothing without it.
  final bool autoplay;

  /// Auto similar: a finished queue continues with similar tracks added to its
  /// tail. The sheet's Similar to queue button is different: it replaces the
  /// queue with a wave at once.
  final bool autoSimilar;

  /// User themes in creation order, after built-in ones.
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

  /// Built-in and user themes together, in display order.
  List<ThemePreset> get allThemes => [...kThemePresets, ...customThemes];

  /// The auto theme is picked: colours follow the cover.
  bool get autoTheme => themeId == kAutoThemeId;

  ThemePreset get preset {
    if (autoTheme) {
      // No preset with this id, so I build it from the colours taken from the
      // cover. The name here is internal: the UI has its own string
      // (`thAutoName`).
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
/// an update).
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
      navOrder: readNavOrder(raw),
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
    // The SoundCloud provider keeps client_id in module state, so it gets the
    // saved one at launch, or the manual key is forgotten until restart.
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
      'navTabs': [for (final tab in state.navOrder) tab.name],
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

  /// A theme change doesn't touch accent and radius, independent settings.
  ///
  /// Except the auto theme, whose accent comes from the cover. On entry it
  /// seeds from current colours (nothing to recolour from yet) and turns off
  /// auto accent, since the two would fight over one accent; on exit the taken
  /// colour resets, or the chosen preset keeps a foreign accent.
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

  /// Creates a user theme from three colours and applies it. Returns the
  /// preset: the caller needs its name for the toast.
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

  /// Deletes a user theme. If active, I go back to the first built-in one, or
  /// the app stays on a theme that doesn't exist.
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

  /// Returns a theme from a snapshot (customization preset). If it exists I
  /// just pick it; if not (deleted, preset from another phone) I recreate it
  /// under the same id, so applying again makes no copies.
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

  /// Picks the UI language; `null` returns to the system's.
  void setLocale(Locale? locale) {
    state = locale == null
        ? state.copyWith(clearLocale: true)
        : state.copyWith(locale: locale);
    _save();
  }

  /// Toggles auto accent. Turning off returns the preset's colour at once:
  /// there's no manual accent to restore.
  ///
  /// Turning on leaves the auto theme, which is broader, and both can't paint
  /// the accent. It goes to a built-in theme: there's nowhere to hold frozen
  /// colours.
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

  /// Colour taken from a cover, via the auto accent bridge. If the switch is
  /// already off I ignore it, or a late scan would bring the accent back.
  void applyAutoAccent(Color color) {
    if (!state.autoAccent) return;
    if (state.accent?.toARGB32() == color.toARGB32()) return;
    state = state.copyWith(accent: color);
    _save();
  }

  /// Auto theme colours from the cover: surface (background equals blocks) and
  /// accent. Via the same bridge; the theme may have changed while the picture
  /// loaded, so then I just return.
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

  /// Mode for adding local files. Tracks already added aren't affected.
  void setLocalImport(LocalImportMode mode) {
    state = state.copyWith(localImport: mode);
    _save();
  }

  /// Restores the session at launch. Turning off also clears
  /// [SettingsState.autoplay], or bringing restore back would start the player
  /// playing out of nowhere.
  void setRestoreQueue(bool value) {
    state = value
        ? state.copyWith(restoreQueue: true)
        : state.copyWith(restoreQueue: false, autoplay: false);
    _save();
  }

  /// Autoplay. Doesn't turn restore back on: the add-on doesn't control what it
  /// sits on.
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
