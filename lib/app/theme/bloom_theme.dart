/// Builds [ThemeData] from Bloom's tokens. Inter is a variable font, so weight
/// is set TWICE: `fontWeight` for fallback synthesis and `fontVariations` with
/// the `wght` axis, without which it draws one weight.
///
/// [bloomText] has no family on purpose: the font comes from settings and the
/// style inherits it. An explicit `fontFamily` would override the choice, since
/// `ThemeData` only fills styles with no family.
library;

import 'package:flutter/material.dart';

import 'fonts.dart';
import 'tokens.dart';

TextStyle bloomText({
  required double size,
  required int weight,
  required Color color,
  double? height,
  double? letterSpacing,
}) => TextStyle(
  fontSize: size,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  fontVariations: [FontVariation('wght', weight.toDouble())],
);

/// [transparentPages]: a background picture lies under the UI, so surface fills
/// and the transition background go, or it would only show through edge gaps
/// and vanish during transitions.
///
/// [fontFamily] is the UI font from settings. The fallback is always Inter:
/// Minecraft Rus and user files may lack letters, and those should draw in
/// Inter rather than the system font.
ThemeData buildBloomTheme(
  BloomTokens t, {
  bool transparentPages = false,
  String fontFamily = kDefaultFont,
}) {
  final pageBg = transparentPages ? Colors.transparent : t.bg;
  final scheme = ColorScheme(
    brightness: t.isLight ? Brightness.light : Brightness.dark,
    primary: t.accent,
    onPrimary: t.accentText,
    secondary: t.accent2,
    onSecondary: t.accentText,
    surface: t.blockColor,
    onSurface: t.text,
    surfaceContainerHighest: t.card,
    onSurfaceVariant: t.text2,
    outline: t.border,
    error: kBloomDanger,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: pageBg,
    canvasColor: pageBg,
    fontFamily: fontFamily,
    fontFamilyFallback: const [kDefaultFont],
    // Page transition. Android's default is predictive: during the back gesture
    // the page shrinks into a card with the previous screen in the gap. I use
    // slide with fade instead, so nothing peeks and it plays whole on leaving.
    // The transition background is the theme colour, or black blinks between
    // pages.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          p: FadeForwardsPageTransitionsBuilder(backgroundColor: pageBg),
      },
    ),
    // Presses get no highlight at all: no ripple, no film. I turn off all three
    // sources (splash factory, splash colour, highlight colour), or material
    // brings the fill back through any of them. Feedback comes from the
    // element's own movement.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    extensions: [t],
    textTheme: TextTheme(
      // Screen title, track title in the player.
      headlineSmall: bloomText(
        size: 22,
        weight: 700,
        color: t.text,
        height: 1.2,
      ),
      // Section title.
      titleLarge: bloomText(size: 19, weight: 700, color: t.text, height: 1.25),
      // List row, card title.
      titleMedium: bloomText(size: 15, weight: 600, color: t.text, height: 1.3),
      titleSmall: bloomText(size: 13, weight: 600, color: t.text, height: 1.3),
      // Artist, card caption.
      bodyMedium: bloomText(
        size: 13,
        weight: 500,
        color: t.text2,
        height: 1.35,
      ),
      bodySmall: bloomText(size: 12, weight: 500, color: t.muted, height: 1.35),
      // Caps title of a settings group.
      labelSmall: bloomText(
        size: 11,
        weight: 600,
        color: t.muted,
        letterSpacing: 0.6,
      ),
    ),
    iconTheme: IconThemeData(color: t.iconFg, size: 22),
    dividerTheme: DividerThemeData(color: t.ovlLine, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: t.iconFg,
      textColor: t.text,
      titleTextStyle: bloomText(size: 15, weight: 600, color: t.text),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      inactiveTrackColor: t.track,
      thumbColor: t.accent,
      trackHeight: 3,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    // Material buttons take press highlight from their `overlayColor`,
    // bypassing the theme's `highlightColor`, so I turn it off per kind.
    textButtonTheme: const TextButtonThemeData(style: _flatButton),
    filledButtonTheme: const FilledButtonThemeData(style: _flatButton),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: _flatButton),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: _flatButton),
    iconButtonTheme: const IconButtonThemeData(style: _flatButton),
  );
}

/// Button with no fill under the finger.
const ButtonStyle _flatButton = ButtonStyle(
  splashFactory: NoSplash.splashFactory,
  overlayColor: WidgetStatePropertyAll(Colors.transparent),
);
