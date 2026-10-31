/// Токены темы должны совпадать с десктопным Bloom: те же формулы от трёх
/// цветов дают те же тона. Значения сверены с комментариями в `themeStore.ts`
/// («Было руками: Dark #1c1c1c… #262626… #999/#555»).
library;

import 'package:bloom/app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(Color c) {
  String ch(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${ch(c.r)}${ch(c.g)}${ch(c.b)}';
}

/// Полупрозрачный [top] поверх непрозрачного [bottom] — то, что реально видит
/// глаз. Плёнки задаются альфой, а спрашивают с них итоговый цвет.
String _over(Color top, Color bottom) {
  double ch(double t, double b) => t * top.a + b * (1 - top.a);
  return _hex(
    Color.from(
      alpha: 1,
      red: ch(top.r, bottom.r),
      green: ch(top.g, bottom.g),
      blue: ch(top.b, bottom.b),
    ),
  );
}

void main() {
  test('Dark: tones derived from #0a0a0a / #0d0d0d and a white accent', () {
    final t = BloomThemes.dark;

    expect(t.isLight, isFalse);
    expect(_hex(t.card), '#0d0d0d');
    // color-mix(block, ovl 12%).
    expect(_hex(t.border), '#2a2a2a');
    expect(_hex(t.text), '#ffffff');
    // mix(text, block 40%) / 68%.
    expect(_hex(t.text2), '#9e9e9e');
    expect(_hex(t.muted), '#5a5a5a');
    // mix(accent, block 22%).
    expect(_hex(t.accent2), '#cacaca');
    // Белый акцент — надпись на нём чёрная, ховер темнеет (осветлять некуда).
    expect(_hex(t.accentText), '#000000');
    expect(_hex(t.accentHover), '#e0e0e0');
    // mix(border, ovl 20%) from the unrounded border, as CSS color-mix.
    expect(_hex(t.borderFocus), '#555555');
    // Пилюли и круглые кнопки шапки — ровно #1a1a1a, и именно сплошным
    // цветом: плёнка тех же 6% даёт 24.7 и на устройстве садится в #181818.
    expect(_hex(t.pill), '#1a1a1a');
    expect(t.pill.a, 1);
    // Плёнка --icon-bg остаётся как на десктопе — для элементов над обложкой.
    expect(_over(t.iconBg, t.bg), '#191919');
    expect(t.track.a, closeTo(0.04, 0.001));
  });

  test('Light: плёнка переворачивается в чёрную, текст темнеет', () {
    final t = BloomThemes.light;

    expect(t.isLight, isTrue);
    expect(_hex(t.text), '#111111');
    // ovl теперь чёрный → рамка ТЕМНЕЕ поверхности, а не светлее.
    expect(_hex(t.border), '#d8d8d8');
    // The black accent takes white text.
    expect(_hex(t.pill), '#e0e0e0');
    expect(_hex(t.accentText), '#ffffff');
    // Чёрная плёнка «весит» больше — дорожка ослаблена до .07.
    expect(t.track.a, closeTo(0.07, 0.001));
  });

  test('Акцентная тема: glow и folderTint идут от акцента', () {
    final t = const ThemePreset(
      id: 'blue',
      name: 'Blue',
      bg: Color(0xFF101828),
      blockColor: Color(0xFF101828),
      accent: Color(0xFF4D9FFF),
    ).tokens();
    expect(_hex(t.glow), '#4d9fff');
    expect(t.glow.a, closeTo(0.2, 0.001));
    expect(_hex(t.folderTint), '#4d9fff');
  });
}
