/// Player settings. Few choices stand right on the page as cards, so they can be
/// tuned in turn; a long list with notes opens in a sheet. Glyphs are drawn here,
/// the icon set has no such pictures.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../features/lyrics/lyrics_store.dart';
import '../../../features/player/play_button_store.dart';
import '../../../features/player/player_bg_store.dart';
import '../../../features/player/player_style_store.dart';
import '../../../features/player/player_view_store.dart';
import '../../../features/player/slider_style_store.dart';
import '../../../features/player/ui/slider_shapes.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/subpage_header.dart';
import 'settings_rows.dart';
import 'settings_sheets.dart';

class PlayerSettingsScreen extends ConsumerWidget {
  const PlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(playerStyleProvider);
    final queue = ref.watch(queueViewProvider);
    final bg = ref.watch(playerBgProvider);
    final coverFx = ref.watch(coverBgFxProvider);
    final align = ref.watch(titleAlignProvider);
    final playShape = ref.watch(playButtonShapeProvider);
    final lyricsMode = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
    final l = context.l;

    return SubPage(
      title: l.setPlayer,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.pvStyleRow),
        const SizedBox(height: 10),
        PickRow<PlayerStyle>(
          values: PlayerStyle.values,
          active: (v) => v == style,
          label: (v) => _styleLabel(l, v),
          picture: (v, ink) => CustomPaint(
            size: const Size(24, 24),
            painter: _StylePainter(style: v, color: ink),
          ),
          onTap: ref.read(playerStyleProvider.notifier).setStyle,
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvPlayButtonRow),
        const SizedBox(height: 10),
        PickRow<PlayButtonShape>(
          values: PlayButtonShape.values,
          active: (v) => v == playShape,
          label: (v) => _playShapeLabel(l, v),
          picture: (v, ink) => CustomPaint(
            size: const Size(24, 24),
            painter: _PlayShapePainter(shape: v, color: ink),
          ),
          onTap: ref.read(playButtonShapeProvider.notifier).set,
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupQueue),
        const SizedBox(height: 10),
        PickRow<QueueView>(
          values: QueueView.values,
          active: (v) => v == queue,
          label: (v) => v.isExtended ? l.pvQueueExtended : l.pvQueueNormal,
          picture: (v, ink) => CustomPaint(
            size: const Size(26, 20),
            painter: _QueueGlyphPainter(extended: v.isExtended, color: ink),
          ),
          onTap: ref.read(queueViewProvider.notifier).set,
        ),
        const SizedBox(height: 12),
        // About the queue it's taken from, not the slider.
        SettingsGroupCard(
          rows: [
            SettingsToggleRow(
              title: l.pvNextUp,
              subtitle: l.pvNextUpSub,
              value: ref.watch(nextUpProvider),
              onChanged: ref.read(nextUpProvider.notifier).set,
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupBg),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvBgRow,
              value: _playerBgLabel(l, bg),
              glyph: BloomIcon(_playerBgIcon(bg)),
              onTap: () => _openPlayerBg(context, ref),
            ),
          ],
        ),
        // Only under "Cover": a choice that changes nothing is worse than none.
        if (bg.isCover) ...[
          const SizedBox(height: 12),
          PickRow<CoverBgFx>(
            values: CoverBgFx.values,
            active: (v) => v == coverFx,
            label: (v) => _coverFxLabel(l, v),
            picture: (v, _) => BloomIcon(_coverFxIcon(v)),
            onTap: ref.read(coverBgFxProvider.notifier).set,
          ),
        ],
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupTitle),
        const SizedBox(height: 10),
        PickRow<TitleAlign>(
          values: TitleAlign.values,
          active: (v) => v == align,
          label: (v) => _alignLabel(l, v),
          picture: (v, ink) => CustomPaint(
            size: const Size(24, 24),
            painter: _AlignGlyph(align: v, color: ink),
          ),
          onTap: ref.read(titleAlignProvider.notifier).set,
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupSlider),
        const SizedBox(height: 10),
        const _SliderCards(),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupLyrics),
        const SizedBox(height: 10),
        PickRow<LyricsMode>(
          values: LyricsMode.values,
          active: (v) => v == lyricsMode,
          label: (v) => _modeLabel(l, v),
          picture: (v, ink) => CustomPaint(
            size: const Size(28, 24),
            painter: _ModePainter(mode: v, color: ink),
          ),
          onTap: ref.read(lyricsPrefsProvider.notifier).setMode,
        ),
      ],
    );
  }
}

// ── Play button
// ─────────────────────────────────────────────────────────────── One setting
// for the player and the card above the tab bar (see [PlayButtonShape]).

String _playShapeLabel(AppLocalizations l, PlayButtonShape shape) =>
    switch (shape) {
      PlayButtonShape.circle => l.pvPlayButtonCircle,
      PlayButtonShape.square => l.pvPlayButtonSquare,
      PlayButtonShape.plain => l.pvPlayButtonPlain,
    };

/// The play sign in a frame of its shape. Drawn here: ready icons differ in
/// weight and placement and would read as different icons, not as one button in
/// three shapes.
class _PlayShapePainter extends CustomPainter {
  const _PlayShapePainter({required this.shape, required this.color});

  final PlayButtonShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in a 24×24 grid and scaled at once.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (shape) {
      case PlayButtonShape.circle:
        canvas.drawCircle(const Offset(12, 12), 9.5, stroke);
      case PlayButtonShape.square:
        canvas.drawRRect(
          // The button's own share of the side: the frame must repeat its
          // rounding.
          RRect.fromLTRBR(2.5, 2.5, 21.5, 21.5, const Radius.circular(5.7)),
          stroke,
        );
      case PlayButtonShape.plain:
        break;
    }

    // Without a frame the sign is bigger, as on the button.
    final k = shape.isPlain ? 1.9 : 1.0;
    final path = Path()
      ..moveTo(12 - 2.6 * k, 12 - 4.2 * k)
      ..lineTo(12 + 4.4 * k, 12)
      ..lineTo(12 - 2.6 * k, 12 + 4.2 * k)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlayShapePainter old) =>
      old.shape != shape || old.color != color;
}

/// A flat list against one with section headers. Drawn here: the icon set has
/// one "list", and two equal icons show no difference.
class _QueueGlyphPainter extends CustomPainter {
  _QueueGlyphPainter({required this.extended, required this.color});

  final bool extended;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A bar: its share of the width and its alpha. A section header is short
    // and dim, a track row full width.
    const rows = <({double width, double alpha, double height})>[
      (width: 1, alpha: 0.9, height: 2.5),
    ];
    final plan = extended
        ? const [
            (width: 0.42, alpha: 0.45, height: 2.0),
            (width: 1.0, alpha: 0.9, height: 2.5),
            (width: 1.0, alpha: 0.9, height: 2.5),
            (width: 0.42, alpha: 0.45, height: 2.0),
            (width: 1.0, alpha: 0.9, height: 2.5),
          ]
        : [for (var i = 0; i < 4; i++) rows.first];

    final total = plan.fold<double>(0, (sum, r) => sum + r.height);
    final gap = (size.height - total) / (plan.length - 1);
    final paint = Paint()..style = PaintingStyle.fill;
    var y = 0.0;
    for (final row in plan) {
      paint.color = color.withValues(alpha: color.a * row.alpha);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y, size.width * row.width, row.height),
          Radius.circular(row.height / 2),
        ),
        paint,
      );
      y += row.height + gap;
    }
  }

  @override
  bool shouldRepaint(_QueueGlyphPainter old) =>
      old.extended != extended || old.color != color;
}

/// Three lines of different length moved to their side.
class _AlignGlyph extends CustomPainter {
  const _AlignGlyph({required this.align, required this.color});

  final TitleAlign align;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in a 24×24 grid and scaled at once.
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;

    // The first is always full width: only the short ones move, or the
    // difference is lost at 22 px.
    canvas.drawLine(const Offset(3, 6), const Offset(21, 6), stroke);
    final (mid, last) = switch (align) {
      TitleAlign.left => ((3.0, 15.0), (3.0, 18.0)),
      TitleAlign.center => ((6.0, 18.0), (4.0, 20.0)),
      TitleAlign.right => ((9.0, 21.0), (6.0, 21.0)),
    };
    canvas.drawLine(Offset(mid.$1, 12), Offset(mid.$2, 12), stroke);
    canvas.drawLine(Offset(last.$1, 18), Offset(last.$2, 18), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AlignGlyph old) =>
      old.align != align || old.color != color;
}

String _alignLabel(AppLocalizations l, TitleAlign align) => switch (align) {
  TitleAlign.left => l.pvTitleAlignLeft,
  TitleAlign.center => l.pvTitleAlignCenter,
  TitleAlign.right => l.pvTitleAlignRight,
};

// ── Slider
// ────────────────────────────────────────────────────────────────────

/// The types one under another, each showing itself: they differ in the track
/// and the knob, a small picture wouldn't tell them apart.
class _SliderCards extends ConsumerWidget {
  const _SliderCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(sliderStyleProvider);
    return Column(
      children: [
        for (final style in SliderStyle.values) ...[
          if (style != SliderStyle.values.first) const SizedBox(height: 8),
          _SliderCard(
            style: style,
            active: style == current,
            onTap: () => ref.read(sliderStyleProvider.notifier).set(style),
          ),
        ],
      ],
    );
  }
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.style,
    required this.active,
    required this.onTap,
  });

  final SliderStyle style;
  final bool active;
  final VoidCallback onTap;

  /// Constant: the wave's pattern doesn't change from one opening to the next.
  static const int waveSeed = 42;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return PickPlate(
      active: active,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                CustomPaint(
                  size: const Size(44, 10),
                  painter: _SliderGlyph(
                    style: style,
                    color: active ? t.accent : t.iconFg,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _sliderLabel(context.l, style),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: active ? t.text : t.text2,
                    ),
                  ),
                ),
                if (active) const SheetTick(),
              ],
            ),
            // The player's own theme, so this can't differ from the real one.
            // Only shows: a press anywhere on the plate chooses.
            ExcludeSemantics(
              child: IgnorePointer(
                child: SizedBox(
                  height: 34,
                  child: SliderTheme(
                    data:
                        bloomSliderTheme(
                          SliderTheme.of(context),
                          style: style,
                          tokens: t,
                          waveSeed: waveSeed,
                        ).copyWith(
                          padding: EdgeInsets.zero,
                          // The player's track is lost on a plate this light.
                          inactiveTrackColor: style == SliderStyle.wave
                              ? null
                              : t.text.withValues(alpha: 0.2),
                        ),
                    child: Slider(value: 0.45, onChanged: (_) {}),
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

/// A filled bar, a hairline with a dot, two segments with a drop, and columns.
class _SliderGlyph extends CustomPainter {
  const _SliderGlyph({required this.style, required this.color});

  final SliderStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in a 44×10 grid and scaled at once.
    canvas.save();
    canvas.scale(size.width / 44, size.height / 10);
    final fill = Paint()..color = color;
    // The unfilled part, at a third of the brightness.
    final rest = Paint()..color = color.withValues(alpha: 0.3);

    void bar(double x, double y, double w, double h, Paint paint) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(math.min(1, h / 2)),
          ),
          paint,
        );

    switch (style) {
      case SliderStyle.standard:
        bar(0, 4, 44, 2, rest);
        bar(0, 4, 22, 2, fill);
      case SliderStyle.thin:
        bar(0, 4.5, 44, 1, rest);
        bar(0, 4.5, 22, 1, fill);
        canvas.drawCircle(const Offset(22, 5), 2.5, fill);
      case SliderStyle.ios:
        bar(0, 4, 20, 2, fill);
        bar(24, 4, 20, 2, rest);
        bar(21, 1, 2, 8, fill);
      case SliderStyle.wave:
        // Fifteen columns, step 3: seven filled, the rest quiet.
        const List<double> heights = [
          4, 6, 3, 8, 5, 7, 4, 6, 3, 7, 5, 4, 8, 3, 5, //
        ];
        for (var i = 0; i < heights.length; i++) {
          final h = heights[i];
          bar(i * 3, (10 - h) / 2, 2, h, i < 7 ? fill : rest);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SliderGlyph old) =>
      old.style != style || old.color != color;
}

String _sliderLabel(AppLocalizations l, SliderStyle style) => switch (style) {
  SliderStyle.standard => l.pvSliderStandard,
  SliderStyle.thin => l.pvSliderThin,
  // A platform's name isn't translated.
  SliderStyle.ios => 'iOS',
  SliderStyle.wave => l.pvSliderWave,
};

String _styleLabel(AppLocalizations l, PlayerStyle style) => switch (style) {
  PlayerStyle.standard => l.pvStyleStandard,
  PlayerStyle.vinyl => l.pvStyleVinyl,
};

String _modeLabel(AppLocalizations l, LyricsMode mode) => switch (mode) {
  LyricsMode.overlay => l.pvLyricsModeOverlay,
  LyricsMode.replace => l.pvLyricsModeReplace,
};

/// A square cover for standard, a disc with a label for vinyl.
class _StylePainter extends CustomPainter {
  const _StylePainter({required this.style, required this.color});

  final PlayerStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (style) {
      case PlayerStyle.standard:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 3, 21, 21, const Radius.circular(5)),
          stroke,
        );
      case PlayerStyle.vinyl:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        canvas.drawCircle(const Offset(12, 12), 3, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StylePainter old) =>
      old.style != style || old.color != color;
}

/// A cover square with lines over it on the left, lines alone on the right. Not
/// in the icon set, so drawn here.
class _ModePainter extends CustomPainter {
  const _ModePainter({required this.mode, required this.color});

  final LyricsMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 24);
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(
        alpha: mode == LyricsMode.overlay ? 0.38 : 0.9,
      );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = color;

    if (mode == LyricsMode.overlay) {
      // The cover's frame and the text lines over it.
      canvas.drawRRect(
        RRect.fromLTRBR(4, 3, 24, 21, const Radius.circular(3)),
        frame,
      );
      canvas.drawLine(const Offset(8, 9), const Offset(20, 9), line);
      canvas.drawLine(const Offset(8, 13), const Offset(17, 13), line);
      canvas.drawLine(const Offset(8, 17), const Offset(19, 17), line);
    } else {
      // No cover: lines alone, full width.
      canvas.drawLine(const Offset(4, 6), const Offset(24, 6), line);
      canvas.drawLine(const Offset(4, 11), const Offset(20, 11), line);
      canvas.drawLine(const Offset(4, 16), const Offset(23, 16), line);
      canvas.drawLine(const Offset(4, 21), const Offset(15, 21), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ModePainter old) =>
      old.mode != mode || old.color != color;
}

// ── Player background
// ───────────────────────────────────────────────────────── The player takes
// the whole screen, with emptiness behind the cover. Large rows with notes: the
// word "Colour" doesn't say it comes from the cover.

String _playerBgLabel(AppLocalizations l, PlayerBg bg) => switch (bg) {
  PlayerBg.cover => l.pvBgCover,
  PlayerBg.app => l.pvBgApp,
  PlayerBg.color => l.pvBgColor,
  PlayerBg.none => l.pvBgNone,
};

String _playerBgSub(AppLocalizations l, PlayerBg bg) => switch (bg) {
  PlayerBg.cover => l.pvBgCoverSub,
  PlayerBg.app => l.pvBgAppSub,
  PlayerBg.color => l.pvBgColorSub,
  PlayerBg.none => l.pvBgNoneSub,
};

BloomGlyph _playerBgIcon(PlayerBg bg) => switch (bg) {
  PlayerBg.cover => Bi.gallery,
  // The icon "Background" has on a picture in the customization library: one
  // place, one icon.
  PlayerBg.app => Bi.galleryWide,
  PlayerBg.color => Bi.palette,
  PlayerBg.none => Bi.forbiddenCircle,
};

/// Player background. No header: the row it came from stays visible, each
/// choice's caption explains it. Closes on choosing.
///
/// "App background" greys out without a background, and says where to set one.
Future<void> _openPlayerBg(BuildContext context, WidgetRef ref) {
  final hasAppBg = ref.read(playerAppBgProvider) != null;
  return pickOneSheet(
    context: context,
    values: PlayerBg.values,
    current: ref.read(playerBgProvider),
    icon: _playerBgIcon,
    label: (bg) => _playerBgLabel(context.l, bg),
    sub: (bg) => bg == PlayerBg.app && !hasAppBg
        ? context.l.pvBgAppOff
        : _playerBgSub(context.l, bg),
    enabled: (bg) => bg != PlayerBg.app || hasAppBg,
    apply: ref.read(playerBgProvider.notifier).set,
  );
}

// ── Cover background effect
// ──────────────────────────────────────────────────── Shows only under
// "Cover": other backgrounds have no cover behind the player.

String _coverFxLabel(AppLocalizations l, CoverBgFx fx) => switch (fx) {
  CoverBgFx.dim => l.pvBgFxDim,
  CoverBgFx.blur => l.pvBgFxBlur,
  CoverBgFx.original => l.pvBgFxOriginal,
};

BloomGlyph _coverFxIcon(CoverBgFx fx) => switch (fx) {
  // Moon is dim, drop is blur, the wand is "as it is".
  CoverBgFx.dim => Bi.moon,
  CoverBgFx.blur => Bi.waterdrop,
  CoverBgFx.original => Bi.magicStick,
};
