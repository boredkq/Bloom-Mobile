/// Player settings. Rows show what's chosen; the choices open in sheets, since
/// open blocks took screens of scrolling. Sheets stay open on choosing:
/// settings in them get tuned in turn, watching the preview. Glyphs are drawn
/// here, the icon set has no such pictures.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../features/customization/custom_store.dart';
import '../../../features/lyrics/lyrics_store.dart';
import '../../../features/player/play_button_store.dart';
import '../../../features/player/player_bg_store.dart';
import '../../../features/player/player_style_store.dart';
import '../../../features/player/player_view_store.dart';
import '../../../features/player/slider_style_store.dart';
import '../../../features/player/ui/play_button.dart';
import '../../../features/player/ui/slider_shapes.dart';
import '../../../features/player/ui/vinyl_disc.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/util/format.dart';
import 'settings_rows.dart';
import 'settings_sheets.dart';

class PlayerSettingsScreen extends ConsumerWidget {
  const PlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsMode = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
    final style = ref.watch(playerStyleProvider);
    final playShape = ref.watch(playButtonShapeProvider);
    final align = ref.watch(titleAlignProvider);
    final slider = ref.watch(sliderStyleProvider);
    final bg = ref.watch(playerBgProvider);
    final coverFx = ref.watch(coverBgFxProvider);
    final l = context.l;

    return SubPage(
      title: l.setPlayer,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.pvGroupLook.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvStyleRow,
              value: _styleLabel(l, style),
              glyph: _StyleGlyph(style: style),
              onTap: () => _openStyle(context),
            ),
            SettingsValueRow(
              title: l.pvPlayButtonRow,
              value: _playShapeLabel(l, playShape),
              glyph: _PlayShapeGlyph(shape: playShape),
              onTap: () => _openPlayShape(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupQueue.toUpperCase()),
        const SizedBox(height: 10),
        const _QueueViewCards(),
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
        SettingsCaption(l.pvGroupBg.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvBgRow,
              value: _playerBgLabel(l, bg),
              glyph: BloomIcon(_playerBgIcon(bg)),
              onTap: () => _openPlayerBg(context, ref),
            ),
            // Only under "Cover": a row that changes nothing is worse than
            // none.
            if (bg.isCover)
              SettingsValueRow(
                title: l.pvBgFxRow,
                value: _coverFxLabel(l, coverFx),
                glyph: BloomIcon(_coverFxIcon(coverFx)),
                onTap: () => _openCoverFx(context, ref),
              ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupTitle.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvTitleAlign,
              value: _alignLabel(l, align),
              glyph: _AlignRowGlyph(align: align),
              onTap: () => _openTitleAlign(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupSlider.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvSliderRow,
              value: _sliderLabel(l, slider),
              glyph: _SliderRowGlyph(style: slider),
              onTap: () => _openSlider(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupLyrics.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvLyricsRow,
              value: _modeLabel(l, lyricsMode),
              glyph: const BloomIcon(Bi.magicStick),
              onTap: () => _openLyrics(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// The player's style. A live preview on top, rows under it: the difference is
/// a picture, no words explain it. Stays open on choosing: the square rounds
/// into a disc and starts spinning. No header, it would eat the preview's
/// height.
Future<void> _openStyle(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(playerStyleProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StylePreview(style: current),
            for (final style in PlayerStyle.values)
              SheetOptionTile(
                leading: _StyleGlyph(style: style),
                label: _styleLabel(context.l, style),
                sub: _styleSub(context.l, style),
                active: style == current,
                onTap: () =>
                    ref.read(playerStyleProvider.notifier).setStyle(style),
              ),
          ],
        );
      },
    ),
  );
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

String _playShapeSub(AppLocalizations l, PlayButtonShape shape) =>
    switch (shape) {
      PlayButtonShape.circle => l.pvPlayButtonCircleSub,
      PlayButtonShape.square => l.pvPlayButtonSquareSub,
      PlayButtonShape.plain => l.pvPlayButtonPlainSub,
    };

/// Like the style's sheet: a live button on top, the shapes under it, stays
/// open on choosing.
Future<void> _openPlayShape(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(playButtonShapeProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PlayShapePreview(),
            for (final shape in PlayButtonShape.values)
              SheetOptionTile(
                leading: _PlayShapeGlyph(shape: shape),
                label: _playShapeLabel(context.l, shape),
                sub: _playShapeSub(context.l, shape),
                active: shape == current,
                onTap: () =>
                    ref.read(playButtonShapeProvider.notifier).set(shape),
              ),
          ],
        );
      },
    ),
  );
}

/// The real [PlayButton] between its neighbours, or "bigger than the others"
/// has nothing to compare with. Not live: it shows the look, it doesn't touch
/// the sound.
class _PlayShapePreview extends StatelessWidget {
  const _PlayShapePreview();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          // The fill of the sheet's blocks.
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BloomIcon(Bi.skipPreviousBold, size: 30, color: t.iconFg),
            const SizedBox(width: 26),
            const PlayButton(
              size: 68,
              iconSize: 28,
              plainIconSize: 40,
              spinnerSize: 28,
              live: false,
            ),
            const SizedBox(width: 26),
            BloomIcon(Bi.skipNextBold, size: 30, color: t.iconFg),
          ],
        ),
      ),
    );
  }
}

/// The play sign in a frame of its shape. Drawn here: ready icons differ in
/// weight and placement and would read as different icons, not as one button in
/// three shapes.
class _PlayShapeGlyph extends StatelessWidget {
  const _PlayShapeGlyph({required this.shape});

  final PlayButtonShape shape;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(23, 23),
    painter: _PlayShapePainter(
      shape: shape,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

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

/// The queue's look. The one setting standing as cards: two choices, and the
/// glyph itself shows the difference.
class _QueueViewCards extends ConsumerWidget {
  const _QueueViewCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(queueViewProvider);
    final l = context.l;
    return Row(
      children: [
        for (final view in QueueView.values) ...[
          if (view != QueueView.values.first) const SizedBox(width: 12),
          Expanded(
            child: _OptionCard(
              label: view.isExtended ? l.pvQueueExtended : l.pvQueueNormal,
              selected: view == current,
              glyph: _QueueViewGlyph(extended: view.isExtended),
              onTap: () => ref.read(queueViewProvider.notifier).set(view),
            ),
          ),
        ],
      ],
    );
  }
}

/// A glyph over a label: "one of several" reads the same wherever it stands on
/// this page.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.label,
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// Coloured through [IconTheme]: accent when chosen.
  final Widget glyph;
  final bool selected;
  final VoidCallback onTap;

  /// As tall as two settings rows: any lower, the glyph and the label touch.
  static const double height = 88;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: GlassBox(
        // The settings group's radius: it stands in a group's place.
        borderRadius: BorderRadius.circular(t.radius * 1.3),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            // A thin film of accent over the glass: the card stays a surface of
            // the theme.
            color: selected ? t.accent.withValues(alpha: 0.12) : null,
            child: SizedBox(
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconTheme(
                    data: IconThemeData(color: selected ? t.accent : t.iconFg),
                    child: glyph,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyMedium?.copyWith(
                      color: selected ? t.text : t.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A flat list against one with section headers. Drawn here: the icon set has
/// one "list", and two equal icons show no difference.
class _QueueViewGlyph extends StatelessWidget {
  const _QueueViewGlyph({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(26, 20),
    painter: _QueueGlyphPainter(
      extended: extended,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

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

/// The style's preview: the playing track's real cover, the disc spinning with
/// the same [VinylSpin]. With nothing playing, the usual placeholder.
class _StylePreview extends ConsumerWidget {
  const _StylePreview({required this.style});

  final PlayerStyle style;

  static const double side = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final vinyl = style.isVinyl;
    final url = ref.watch(playerCoverProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          // The fill of the sheet's blocks.
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: Column(
          children: [
            SizedBox(
              width: side,
              height: side,
              child: Stack(
                children: [
                  // The square rounds into a circle before the eyes: that shows
                  // what the setting did. The player's radius is taken as a
                  // share of the side, or a small picture looks sharper.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: vinyl ? 1 : 0),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    builder: (context, k, child) => ClipRRect(
                      borderRadius: BorderRadius.circular(
                        side * (0.11 + 0.39 * k),
                      ),
                      child: child,
                    ),
                    child: VinylSpin(
                      enabled: vinyl,
                      // Always spinning here: no sound in settings, and a still
                      // circle would hide half of the mode.
                      spinning: true,
                      child: Cover(url: url, size: side, radius: 0),
                    ),
                  ),
                  if (vinyl)
                    Positioned.fill(
                      child: Center(
                        child: VinylLabel(size: side * VinylLabel.share),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Bars, not text: the preview shows the layout, a live title would
            // take all the attention.
            _Bar(width: 104, height: 9, color: t.text.withValues(alpha: 0.55)),
            const SizedBox(height: 8),
            _Bar(width: 68, height: 7, color: t.text.withValues(alpha: 0.24)),
          ],
        ),
      ),
    );
  }
}

/// A bar in place of a text line.
class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}

/// The title's alignment: three large rows with a caption, closing on choosing,
/// since nothing else is set here. No header: the row it came from stays
/// visible above.
Future<void> _openTitleAlign(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(titleAlignProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final align in TitleAlign.values)
              SheetOptionTile(
                leading: CustomPaint(
                  size: const Size(22, 22),
                  painter: _AlignGlyph(align: align, color: context.bloom.text),
                ),
                label: _alignLabel(context.l, align),
                sub: _alignSub(context.l, align),
                active: align == current,
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(titleAlignProvider.notifier).set(align);
                },
              ),
          ],
        );
      },
    ),
  );
}

/// The row's version: no circle, in [IconTheme]'s colour.
class _AlignRowGlyph extends StatelessWidget {
  const _AlignRowGlyph({required this.align});

  final TitleAlign align;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(21, 21),
    painter: _AlignGlyph(
      align: align,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
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

String _alignSub(AppLocalizations l, TitleAlign align) => switch (align) {
  TitleAlign.left => l.pvTitleAlignLeftSub,
  TitleAlign.center => l.pvTitleAlignCenterSub,
  TitleAlign.right => l.pvTitleAlignRightSub,
};

/// The slider's type: a live bar on top, rows under it. Stays open on choosing,
/// that's what the preview is for. No header: it would eat the height and the
/// bar says it.
Future<void> _openSlider(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(sliderStyleProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SliderPreview(style: current),
            for (final style in SliderStyle.values)
              SheetOptionTile(
                // In its 44×10 proportions: at 28 px it reads as a bar with a
                // thumb, not a dash.
                leading: CustomPaint(
                  size: const Size(28, 6.4),
                  painter: _SliderGlyph(
                    style: style,
                    color: context.bloom.text,
                  ),
                ),
                label: _sliderLabel(context.l, style),
                active: style == current,
                onTap: () => ref.read(sliderStyleProvider.notifier).set(style),
              ),
          ],
        );
      },
    ),
  );
}

/// A live bar on the player's [bloomSliderTheme], so settings can't differ from
/// the real one. It can be dragged: half the types differ in the thumb and how
/// it cuts the track.
class _SliderPreview extends StatefulWidget {
  const _SliderPreview({required this.style});

  final SliderStyle style;

  /// A sample track: 3:45, at 1:24 (ms).
  static const int total = 225000;
  static const int start = 84000;

  /// Constant: the pattern here doesn't change from one opening to the next.
  static const int waveSeed = 42;

  @override
  State<_SliderPreview> createState() => _SliderPreviewState();
}

class _SliderPreviewState extends State<_SliderPreview> {
  double _value = _SliderPreview.start.toDouble();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        decoration: BoxDecoration(
          // The fill of the sheet's blocks.
          color: sheetPanelColor(context),
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: Column(
          children: [
            SizedBox(
              // Taller than in the player: it's what the sheet is opened for.
              height: 44,
              child: SliderTheme(
                data: bloomSliderTheme(
                  SliderTheme.of(context),
                  style: widget.style,
                  tokens: t,
                  waveSeed: _SliderPreview.waveSeed,
                ),
                child: Slider(
                  value: _value,
                  max: _SliderPreview.total.toDouble(),
                  onChanged: (v) => setState(() => _value = v),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    mmss(Duration(milliseconds: _value.round())),
                    style: theme.bodyMedium,
                  ),
                  Text(
                    mmss(const Duration(milliseconds: _SliderPreview.total)),
                    style: theme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The row's version, narrower than in the sheet: full width it looks like a
/// ruler beside the icons.
class _SliderRowGlyph extends StatelessWidget {
  const _SliderRowGlyph({required this.style});

  final SliderStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(26, 6),
    painter: _SliderGlyph(
      style: style,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
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

/// The lyrics' place: only the view, the active line lights up whole.
Future<void> _openLyrics(BuildContext context) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
        final ctrl = ref.read(lyricsPrefsProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Section(
              title: l.pvLyricsMode,
              subtitle: l.pvLyricsModeSub,
              // Two large buttons with their glyphs: the difference is a
              // picture.
              child: Row(
                children: [
                  for (final mode in LyricsMode.values) ...[
                    if (mode != LyricsMode.values.first)
                      const SizedBox(width: 8),
                    Expanded(
                      child: _OptionCard(
                        label: _modeLabel(l, mode),
                        selected: current == mode,
                        glyph: _ModeGlyph(mode: mode),
                        onTap: () => ctrl.setMode(mode),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// One setting in a sheet: name, note, buttons. No plate: the buttons are cards
/// already, a box around them would be a frame in a frame.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 8, kSheetEdge, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.titleMedium),
          if (subtitle case final text?) ...[
            const SizedBox(height: 3),
            Text(text, style: theme.bodySmall),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

String _styleLabel(AppLocalizations l, PlayerStyle style) => switch (style) {
  PlayerStyle.standard => l.pvStyleStandard,
  PlayerStyle.vinyl => l.pvStyleVinyl,
};

String _styleSub(AppLocalizations l, PlayerStyle style) => switch (style) {
  PlayerStyle.standard => l.pvStyleStandardSub,
  PlayerStyle.vinyl => l.pvStyleVinylSub,
};

String _modeLabel(AppLocalizations l, LyricsMode mode) => switch (mode) {
  LyricsMode.overlay => l.pvLyricsModeOverlay,
  LyricsMode.replace => l.pvLyricsModeReplace,
};

/// Two tiles side by side for standard, a circle in a circle for vinyl.
class _StyleGlyph extends StatelessWidget {
  const _StyleGlyph({required this.style});

  final PlayerStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(24, 24),
    painter: _StylePainter(
      style: style,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

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
      // A wide tile on the left, a narrow one on the right.
      case PlayerStyle.standard:
        canvas.drawRRect(
          RRect.fromLTRBR(3, 3, 11, 21, const Radius.circular(1)),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(14, 3, 21, 21, const Radius.circular(1)),
          stroke,
        );
      // A disc with a label.
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
class _ModeGlyph extends StatelessWidget {
  const _ModeGlyph({required this.mode});

  final LyricsMode mode;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(28, 24),
    painter: _ModePainter(
      mode: mode,
      color: IconTheme.of(context).color ?? context.bloom.iconFg,
    ),
  );
}

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

String _coverFxSub(AppLocalizations l, CoverBgFx fx) => switch (fx) {
  CoverBgFx.dim => l.pvBgFxDimSub,
  CoverBgFx.blur => l.pvBgFxBlurSub,
  CoverBgFx.original => l.pvBgFxOriginalSub,
};

BloomGlyph _coverFxIcon(CoverBgFx fx) => switch (fx) {
  // Moon is dim, drop is blur, the wand is "as it is".
  CoverBgFx.dim => Bi.moon,
  CoverBgFx.blur => Bi.waterdrop,
  CoverBgFx.original => Bi.magicStick,
};

/// Built like the background's sheet: captions explain the choices, closes on
/// choosing, no header.
Future<void> _openCoverFx(BuildContext context, WidgetRef ref) {
  return pickOneSheet(
    context: context,
    values: CoverBgFx.values,
    current: ref.read(coverBgFxProvider),
    icon: _coverFxIcon,
    label: (fx) => _coverFxLabel(context.l, fx),
    sub: (fx) => _coverFxSub(context.l, fx),
    apply: ref.read(coverBgFxProvider.notifier).set,
  );
}
