/// Токены темы — порт `themeStore.ts` + `root.css` из десктопного Bloom.
///
/// Тема — это РОВНО ТРИ ЦВЕТА (`bg`, `blockColor`, `accent`), всё остальное
/// считается формулами. Те же формулы, что на десктопе, поэтому одна и та же
/// тройка даёт тот же вид. Радиус и шрифт в тему не входят намеренно — это
/// независимые настройки внешнего вида.
///
/// Поверхность плоская: блоки не выделяются своим цветом, их приподнимает
/// только полупрозрачная плёнка `ovl` (белая в тёмных темах, чёрная в светлых).
library;

import 'package:flutter/material.dart';

/// Смешать два цвета как CSS `color-mix(in srgb, a, b t%)`.
Color _mix(Color a, Color b, double t) => Color.from(
  alpha: 1,
  red: a.r * (1 - t) + b.r * t,
  green: a.g * (1 - t) + b.g * t,
  blue: a.b * (1 - t) + b.b * t,
);

/// Воспринимаемая светлота, 0..1 — тот же вес каналов, что в `themeStore.ts`.
double _lum(Color c) => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

/// Скругление на всё приложение (`--radius`). Одно число и ровно здесь: своей
/// настройки у него нет — ползунок он убрал сам, и подкрутить радиус неоткуда,
/// даже из сохранённого файла.
const double kBloomRadius = 14;

/// Красный опасных действий и ошибок — десктопный `.plctx-item.danger`.
/// От темы не зависит: это сигнал, а не поверхность.
const Color kBloomDanger = Color(0xFFE03030);

@immutable
class BloomTokens extends ThemeExtension<BloomTokens> {
  // Три цвета темы.
  final Color bg;
  final Color blockColor;
  final Color accent;

  /// Светлая ли поверхность (аналог класса `.theme-light` на `<html>`).
  final bool isLight;

  // Производные тона.
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

  // Плёнка (`--ovl-*`): всё полупрозрачное поверх фона приложения.
  final Color ovlLine;
  final Color ovlLine2;
  final Color ovlBg;
  final Color iconBg;
  final Color track;

  /// Подложка «хрома»: пилюли шапки, круглые кнопки, чипы, поле поиска.
  ///
  /// СПЛОШНОЙ цвет, а не плёнка: на тёмной теме должно получаться ровно
  /// `#1a1a1a`, а полупрозрачный слой зависит от округления рендера (плёнка 6%
  /// поверх `#0a0a0a` даёт 24.7 и на устройстве садится в `#181818`). Для
  /// элементов поверх ОБЛОЖКИ это не годится — там остаётся [iconBg].
  final Color pill;

  // Иконки.
  final Color iconFg;
  final Color iconFgSb;

  /// Опасное и ошибочное: «Удалить», «Очистить», опасная зона, текст ошибок.
  ///
  /// Отдельно от [sysFavIco] намеренно: значение сейчас то же (`#E03030`, как
  /// на ПК), но роли разные, и менять одно не должно тянуть другое. Значение с
  /// десктопа, `.plctx-item.danger`.
  final Color danger;
  final Color dangerTint;

  // Системные разделы.
  final Color folderTint;
  final Color sysFavIco;
  final Color sysAllTint;
  final Color sysAllIco;

  /// Подложка на месте отсутствующей обложки — СПЛОШНАЯ.
  ///
  /// Ровно тот цвет, который плёнка `ovlBg` даёт над фоном темы, но уже
  /// смешанный: заглушке нельзя быть полупрозрачной, иначе с картинкой-фоном
  /// сквозь неё видно обои и плитка читается дыркой, а не пустой обложкой.
  final Color coverEmpty;

  /// Радиус скругления — всегда [kBloomRadius], менять его нечем.
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

  /// Собрать полный набор токенов из трёх цветов темы.
  ///
  /// [borderAlpha] — пользовательская настройка плотности рамок (`--wb`/`--wb2`
  /// на десктопе); дефолт .06/.13.
  factory BloomTokens.from({
    required Color bg,
    required Color blockColor,
    required Color accent,
    double wb = 0.06,
    double wb2 = 0.13,
  }) {
    final light = _lum(blockColor) > 0.6;
    // Плёнка: белая в тёмных темах, чёрная в светлых — иначе на светлой теме
    // белое по белому просто исчезает.
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
      // Ховер по залитому акцентом: подмешиваем контрастный цвет, иначе на
      // белом акценте осветлять нечего и ховера просто нет.
      accentHover: _mix(accent, accentText, 0.12),
      ovlLine: ovl.withValues(alpha: wb),
      ovlLine2: ovl.withValues(alpha: wb2),
      ovlBg: ovl.withValues(alpha: 0.03),
      iconBg: ovl.withValues(alpha: 0.06),
      // 16/245 — доля, при которой #0a0a0a уезжает ровно в #1a1a1a.
      pill: _mix(blockColor, ovl, 16 / 245),
      // Чёрная плёнка «весит» больше белой при той же альфе — на светлой теме
      // дорожку слегка ослабляем.
      track: ovl.withValues(alpha: light ? 0.07 : 0.04),
      iconFg: light ? const Color(0xFF3A3A3A) : const Color(0xFFD0D0D0),
      iconFgSb: light ? const Color(0xFF5A5A5A) : const Color(0xFFA8A8A8),
      danger: kBloomDanger,
      dangerTint: kBloomDanger.withValues(alpha: 0.16),
      folderTint: accent.withValues(alpha: 0.12),
      // Один красный «избранного» на всё приложение — `--sys-fav-ico` с ПК.
      // Все активные сердечки берут его отсюда, своих копий цвета не держат.
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

/// Встроенные пресеты — та же тройка цветов, что в `THEME_PRESETS`.
/// Пока приложение живёт на одной теме `dark`; остальные заведены, чтобы
/// формулы сразу проверялись на них же.
class BloomThemes {
  static final dark = BloomTokens.from(
    bg: const Color(0xFF0A0A0A),
    blockColor: const Color(0xFF0A0A0A),
    accent: const Color(0xFFFFFFFF),
  );

  static final amoled = BloomTokens.from(
    bg: const Color(0xFF000000),
    blockColor: const Color(0xFF000000),
    accent: const Color(0xFFFFFFFF),
  );

  static final midnight = BloomTokens.from(
    bg: const Color(0xFF101828),
    blockColor: const Color(0xFF101828),
    accent: const Color(0xFF4D9FFF),
  );

  static final nord = BloomTokens.from(
    bg: const Color(0xFF3B4252),
    blockColor: const Color(0xFF3B4252),
    accent: const Color(0xFF88C0D0),
  );

  static final warm = BloomTokens.from(
    bg: const Color(0xFF1C1610),
    blockColor: const Color(0xFF1C1610),
    accent: const Color(0xFFD4875A),
  );

  static final light = BloomTokens.from(
    bg: const Color(0xFFE8E8E8),
    blockColor: const Color(0xFFE8E8E8),
    accent: const Color(0xFF333333),
  );
}

/// Быстрый доступ к токенам из виджета.
extension BloomTokensX on BuildContext {
  BloomTokens get bloom => Theme.of(this).extension<BloomTokens>()!;
}
