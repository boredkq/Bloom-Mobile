/// Theme tokens. A theme is EXACTLY THREE COLOURS (`bg`, `blockColor`,
/// `accent`), the rest is formulas. Radius and font aren't part of it: they're
/// separate appearance settings.
///
/// The surface is flat: blocks have no colour of their own and are lifted only
/// by the translucent `ovl` film, white on dark themes, black on light.
library;

import 'package:flutter/material.dart';

/// Mixes two colours in sRGB, [t] being b's share.
Color _mix(Color a, Color b, double t) => Color.from(
  alpha: 1,
  red: a.r * (1 - t) + b.r * t,
  green: a.g * (1 - t) + b.g * t,
  blue: a.b * (1 - t) + b.b * t,
);

/// Perceived lightness, 0..1.
double _lum(Color c) => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

/// Corner radius for the whole app. One number, with no setting.
const double kBloomRadius = 14;

/// Red of dangerous actions and errors. Independent of the theme: it's a
/// signal, not a surface.
const Color kBloomDanger = Color(0xFFE03030);

@immutable
class BloomTokens extends ThemeExtension<BloomTokens> {
  // The theme's three colours.
  final Color bg;
  final Color blockColor;
  final Color accent;

  /// Whether the surface is light.
  final bool isLight;

  // Derived tones.
  final Color card;
  final Color hover;
  final Color border;
  final Color borderFocus;
  final Color glow;
  final Color text;
  final Color text2;
  final Color muted;
  final Color accent2;
  final Color accentText;
  final Color accentHover;

  // Film: everything translucent over the app background.
  final Color ovlLine;
  final Color ovlLine2;
  final Color ovlBg;
  final Color iconBg;
  final Color track;

  /// Base of the chrome: header pills, round buttons, chips, the search field.
  /// SOLID rather than a film: on the dark theme it must be exactly `#1a1a1a`,
  /// and a translucent layer depends on render rounding (6% over `#0a0a0a`
  /// lands on `#181818`). Not for things over a COVER: those use [iconBg].
  final Color pill;

  // Icons.
  final Color iconFg;
  final Color iconFgSb;

  /// Dangerous and erroneous: Delete, Clear, error text. Separate from
  /// [sysFavIco] on purpose: same value today, but different roles, and
  /// changing one shouldn't drag the other.
  final Color danger;
  final Color dangerTint;

  // System sections.
  final Color folderTint;
  final Color sysFavIco;
  final Color sysAllTint;
  final Color sysAllIco;

  /// Base in place of a missing cover, SOLID: the colour `ovlBg` gives over the
  /// theme background, already mixed. A translucent placeholder shows the
  /// wallpaper through and reads as a hole.
  final Color coverEmpty;

  /// Corner radius, always [kBloomRadius].
  final double radius;

  const BloomTokens({
    required this.bg,
    required this.blockColor,
    required this.accent,
    required this.isLight,
    required this.card,
    required this.hover,
    required this.border,
    required this.borderFocus,
    required this.glow,
    required this.text,
    required this.text2,
    required this.muted,
    required this.accent2,
    required this.accentText,
    required this.accentHover,
    required this.ovlLine,
    required this.ovlLine2,
    required this.ovlBg,
    required this.iconBg,
    required this.track,
    required this.pill,
    required this.iconFg,
    required this.iconFgSb,
    required this.danger,
    required this.dangerTint,
    required this.folderTint,
    required this.sysFavIco,
    required this.sysAllTint,
    required this.sysAllIco,
    required this.coverEmpty,
    required this.radius,
  });

  /// Builds the full token set from the theme's three colours. [borderAlpha] is
  /// the user's border density setting, .06 and .13 by default.
  factory BloomTokens.from({
    required Color bg,
    required Color blockColor,
    required Color accent,
    double wb = 0.06,
    double wb2 = 0.13,
  }) {
    final light = _lum(blockColor) > 0.6;
    // Film: white on dark themes, black on light, or white on white vanishes.
    final ovl = light ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final text = light ? const Color(0xFF111111) : const Color(0xFFFFFFFF);
    final accentText = _lum(accent) > 0.6
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    final border = _mix(blockColor, ovl, 0.12);

    return BloomTokens(
      bg: bg,
      blockColor: blockColor,
      accent: accent,
      isLight: light,
      card: blockColor,
      hover: ovl.withValues(alpha: 0.05),
      border: border,
      borderFocus: _mix(border, ovl, 0.20),
      glow: accent.withValues(alpha: 0.2),
      text: text,
      text2: _mix(text, blockColor, 0.40),
      muted: _mix(text, blockColor, 0.68),
      accent2: _mix(accent, blockColor, 0.22),
      accentText: accentText,
      // Hover over an accent fill: I mix in the contrast colour, or a white
      // accent has nowhere to lighten.
      accentHover: _mix(accent, accentText, 0.12),
      ovlLine: ovl.withValues(alpha: wb),
      ovlLine2: ovl.withValues(alpha: wb2),
      ovlBg: ovl.withValues(alpha: 0.03),
      iconBg: ovl.withValues(alpha: 0.06),
      // Pills sit on the page, which is bg: 16/245 takes #0a0a0a exactly to
      // #1a1a1a.
      pill: _mix(bg, ovl, 16 / 245),
      // Black film weighs more than white at the same alpha, so the light
      // theme's track is a bit weaker.
      track: ovl.withValues(alpha: light ? 0.07 : 0.04),
      iconFg: light ? const Color(0xFF3A3A3A) : const Color(0xFFD0D0D0),
      iconFgSb: light ? const Color(0xFF5A5A5A) : const Color(0xFFA8A8A8),
      danger: kBloomDanger,
      dangerTint: kBloomDanger.withValues(alpha: 0.16),
      folderTint: accent.withValues(alpha: 0.12),
      // The one favourite red for the whole app; active hearts take it from
      // here.
      sysFavIco: const Color(0xFFE03030),
      sysAllTint: const Color(0xFF2D83A8).withValues(alpha: 0.16),
      sysAllIco: const Color(0xFF4FB2D8),
      coverEmpty: _mix(blockColor, ovl, 0.03),
      radius: kBloomRadius,
    );
  }

  @override
  BloomTokens copyWith({Color? bg, Color? blockColor, Color? accent}) =>
      BloomTokens.from(
        bg: bg ?? this.bg,
        blockColor: blockColor ?? this.blockColor,
        accent: accent ?? this.accent,
      );

  @override
  BloomTokens lerp(ThemeExtension<BloomTokens>? other, double t) {
    if (other is! BloomTokens) return this;
    return BloomTokens.from(
      bg: Color.lerp(bg, other.bg, t)!,
      blockColor: Color.lerp(blockColor, other.blockColor, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

/// A theme: three colours, the rest is derived ([BloomTokens.from]).
class ThemePreset {
  final String id;
  final String name;
  final Color bg;
  final Color blockColor;
  final Color accent;

  /// My own theme: it can be deleted, a built-in one can't.
  final bool custom;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.bg,
    required this.blockColor,
    required this.accent,
    this.custom = false,
  });

  BloomTokens tokens({Color? accentOverride}) => BloomTokens.from(
    bg: bg,
    blockColor: blockColor,
    accent: accentOverride ?? accent,
  );

  /// I store only the three colours: the rest is derived anyway.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bg': bg.toARGB32(),
    'blockColor': blockColor.toARGB32(),
    'accent': accent.toARGB32(),
  };

  /// A stored custom theme; `null` for a broken entry.
  static ThemePreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final bg = raw['bg'];
    final blockColor = raw['blockColor'];
    final accent = raw['accent'];
    if (id is! String || name is! String) return null;
    if (bg is! num || blockColor is! num || accent is! num) return null;
    return ThemePreset(
      id: id,
      name: name,
      bg: Color(bg.toInt()),
      blockColor: Color(blockColor.toInt()),
      accent: Color(accent.toInt()),
      custom: true,
    );
  }
}

/// The built-in themes. Dark comes first: a theme that's gone
/// falls back to it.
const List<ThemePreset> kThemePresets = [
  ThemePreset(
    id: 'dark',
    name: 'Dark',
    bg: Color(0xFF0A0A0A),
    blockColor: Color(0xFF0D0D0D),
    accent: Color(0xFFFFFFFF),
  ),
  ThemePreset(
    id: 'light',
    name: 'Light',
    bg: Color(0xFFF0F0F0),
    blockColor: Color(0xFFF5F5F5),
    accent: Color(0xFF000000),
  ),
];

/// The built-in themes' tokens, for tests.
class BloomThemes {
  static final dark = kThemePresets.first.tokens();
  static final light = kThemePresets.last.tokens();
}

/// Quick access to the tokens from a widget.
extension BloomTokensX on BuildContext {
  BloomTokens get bloom => Theme.of(this).extension<BloomTokens>()!;
}
