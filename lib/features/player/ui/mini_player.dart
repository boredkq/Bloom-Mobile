/// Mini player, a floating card above the tab bar: a solid `pill` fill, an
/// `ovl-line` border, the theme radius, margins of 8. It really floats: the
/// shell lets content under it, and the list shows in the margins.
///
/// Nobody builds the whole card here: the player panel (`PlayerSheet`) holds
/// its fill and place, growing out of it, and it can't be drawn twice. The
/// panel takes the row's content ([MiniCardRow]), sizes ([kMiniCardHeight],
/// [miniCardRadius]) and fill tone ([miniCardTint]), and the shell's bar an
/// empty place for it ([MiniCardSlot]).
///
/// Background, progress indicators, cover shape and rounding are set by
/// [MiniStyle].
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../features/customization/custom_store.dart';
import '../../../features/settings/user_fonts.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/marquee_text.dart';
import '../mini_style_store.dart';
import '../play_error.dart';
import '../player_controller.dart';
import 'play_button.dart';
import 'track_swap.dart';

/// Card height, needed by the card and the player panel growing out of it.
/// Others get their bottom room from `bottomBarsInset`.
const double kMiniCardHeight = 64;

/// How far the wave's screen holds the card back: 1 on the wave, 0 once the
/// shelves come in. It follows the finger.
final ValueNotifier<double> waveHoldsCard = ValueNotifier<double>(1);

/// Whether the home's first page lies on top of its tab. A page opened over it
/// brings the card back.
final ValueNotifier<bool> homeOnTop = ValueNotifier<bool>(true);

/// How much of a neighbour's card shows with neighbours on: a narrow strip at
/// the very edge. Set RIGHT at the edge rather than within the usual margin: a
/// gap behind it reads as a layout error.
const double kMiniPeek = 12;

/// How far the card moves in from the usual margin with neighbours on: exactly
/// their strip's width. `0` with no neighbours. The margin itself ([kFloatGap])
/// serves as the gap between strip and card, so there's one term.
double miniPeekInset(bool neighbors) => neighbors ? kMiniPeek : 0;

/// The card's place at rest: margins of [kFloatGap] at the sides and over the
/// tab bar ([navInset] is its height with the system inset). With neighbours it
/// narrows by [miniPeekInset] on each side.
Rect miniCardRect({
  required Size screen,
  required double navInset,
  required bool neighbors,
}) {
  final side = kFloatGap + miniPeekInset(neighbors);
  return Rect.fromLTWH(
    side,
    screen.height - navInset - kFloatGap - kMiniCardHeight,
    screen.width - side * 2,
    kMiniCardHeight,
  );
}

/// Carousel step: the card plus the gap to the next. Shifting by it puts a
/// neighbour exactly in the centre.
double miniStride(double cardWidth) => cardWidth + kFloatGap;

/// Cover side in the card.
const double _coverSize = 44;

/// Gap between the cover and the progress ring.
const double _ringGap = 4;

/// How far the ring's stroke sits inside the box, so its edge doesn't clip it.
const double _ringInset = 2;

const double _ringStroke = 2.5;

/// Share played, 0..1, shared by all three indicators.
double _progressFrac(WidgetRef ref) {
  final head =
      ref.watch(playheadProvider).value ??
      (position: Duration.zero, total: Duration.zero);
  final total = head.total.inMilliseconds;
  return total <= 0
      ? 0.0
      : (head.position.inMilliseconds / total).clamp(0.0, 1.0);
}

/// A cover's picture or colour under the card is dark whatever the theme, so on
/// a light theme its row takes the dark theme's ink.
final _miniInkProvider = Provider<ThemeData>(
  (ref) =>
      buildBloomTheme(BloomThemes.dark, fontFamily: ref.watch(uiFontProvider)),
);

/// Artist colour under the title. `muted` counts from the theme's plate, but
/// anything may lie under the card's caption: a cover tint, the cover as a
/// picture, an accent progress fill. The theme's grey sinks into those, so I
/// take the theme's text colour with opacity: contrasting on any of them and
/// still quieter than the title.
Color _artistColor(BloomTokens t) => t.text.withValues(alpha: 0.75);

/// Card corner rounding in pixels.
double miniCardRadius(MiniRadius radius, double themeRadius) =>
    switch (radius) {
      MiniRadius.none => 0,
      MiniRadius.soft => themeRadius * 0.5,
      MiniRadius.rounded => themeRadius,
      MiniRadius.pill => kMiniCardHeight / 2,
    };

/// Card fill tone: a lightened cover dominant in cover colour mode. `null` is
/// the theme's fill, also while the colour is being computed or if the cover is
/// unreadable.
///
/// [neighbor] is a neighbour's card in the carousel: its tone comes from ITS
/// cover, or three cards in a row share a colour and read as one long plate.
Color? miniCardTint(WidgetRef ref, MiniStyle style, {Track? neighbor}) {
  if (style.bg != MiniBg.coverColor) return null;
  final cover = neighbor == null ? miniCardCover(ref) : neighbor.cover;
  return ref.watch(miniCoverColorProvider(cover)).value;
}

/// The cover the card really shows: a custom one from customization beats the
/// track's. It also feeds the card's background and fill colour: the count must
/// come from what's visible.
String? miniCardCover(WidgetRef ref) => ref.watch(playerCoverProvider);

/// The card's place in the shell's bottom bars. The player panel
/// (`PlayerSheet`) draws the card: it grows out of it and must lie OVER the tab
/// bar, which can't happen from inside a bar. The bar holds an empty place of
/// that height, or the tab bar would jump up and lists would lose their bottom
/// room.
class MiniCardSlot extends ConsumerWidget {
  const MiniCardSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playbackProvider.select((s) => s.track != null));
    // The gap under the card counts in the place: the panel stands off the tab
    // bar by exactly that.
    return SizedBox(height: playing ? kMiniCardHeight + kFloatGap : 0);
  }
}

/// Card content: a cover background, the progress fill, a row of cover,
/// captions and buttons, a progress strip along the bottom edge. Exactly
/// [kMiniCardHeight] tall with no fill of its own: the panel holds it. The row
/// fades as the panel expands, and the panel doesn't build it when it can't be
/// seen.
class MiniCardRow extends ConsumerWidget {
  const MiniCardRow({super.key, this.neighbor});

  /// A NEIGHBOUR's card row in the carousel: drawn for this track, not the
  /// playing one, and nothing in it is live: no progress, no change animation
  /// (the carousel does that), no presses. `null` is the usual row.
  final Track? neighbor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final live = neighbor == null;
    final track = neighbor ?? state.track;
    if (track == null) return const SizedBox.shrink();

    final style = ref.watch(miniStyleProvider);
    // A custom picture replaces the PLAYING track's cover; neighbours show
    // their own.
    final cover = live ? miniCardCover(ref) : track.cover;
    final tint = miniCardTint(ref, style, neighbor: neighbor);
    final progress = live ? style.progress : const MiniProgress(line: false);
    final error = live ? state.error : null;
    final visible = MiniButton.values.where(style.hasButton).toList();
    final island = t.isLight && style.bg != MiniBg.theme;
    Widget ink(Widget row) =>
        island ? Theme(data: ref.watch(_miniInkProvider), child: row) : row;

    return SizedBox(
      height: kMiniCardHeight,
      child: Stack(
        children: [
          // The cover background and progress fill lie UNDER the content, by
          // stack order.
          if (style.bg == MiniBg.cover)
            Positioned.fill(child: _CoverBackdrop(cover: cover)),
          if (progress.fill) Positioned.fill(child: _FillProgress(tint: tint)),
          ink(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  _MiniCover(
                    trackId: track.id,
                    cover: cover,
                    animated: live,
                    shape: style.shape,
                    ring: progress.ring,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TrackSwap(
                      id: track.id,
                      animated: live,
                      tuning: TrackSwapTuning.mini,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The title scrolls if it doesn't fit; the artist
                          // below keeps an ellipsis.
                          Builder(
                            builder: (context) => MarqueeText(
                              track.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Builder(
                            builder: (context) => Text(
                              // The state holds an error CODE, expanded to a
                              // phrase here.
                              error == null
                                  ? track.artist
                                  : describePlayError(context.l, error),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: error != null
                                        ? t.danger
                                        : _artistColor(context.bloom),
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // The enum sets button order, the setting the set; a removed
                  // one leaves no gap, or the caption would end in emptiness.
                  for (var i = 0; i < visible.length; i++) ...[
                    SizedBox(width: i == 0 ? 8 : 4),
                    _MiniButton(
                      button: visible[i],
                      track: track,
                      loading: live && state.loading,
                      live: live,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (progress.line)
            const Positioned(left: 0, right: 0, bottom: 0, child: _Hairline()),
        ],
      ),
    );
  }
}

/// A button in the card's row. Which ones show is a setting ([MiniButton]).
class _MiniButton extends ConsumerWidget {
  const _MiniButton({
    required this.button,
    required this.track,
    required this.loading,
    this.live = true,
  });

  final MiniButton button;
  final Track track;

  /// A change to another track is under way: a spinner takes play's place.
  final bool loading;

  /// The playing track's card. `false` is a carousel neighbour: its buttons are
  /// only there for layout (or its caption would be wider and jump on arrival),
  /// with nothing to do, and play shows play.
  final bool live;

  static const double _size = 38;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    switch (button) {
      case MiniButton.prev:
        // Skip icons are Bold, as in the player's transport: a thin outline
        // beside the solid play reads as a foreign icon.
        return CircleIconButton(
          icon: Bi.skipPreviousBold,
          size: _size,
          iconSize: 20,
          background: Colors.transparent,
          color: t.iconFg,
          onTap: live ? ref.read(playbackProvider.notifier).prev : null,
        );
      case MiniButton.next:
        return CircleIconButton(
          icon: Bi.skipNextBold,
          size: _size,
          iconSize: 20,
          background: Colors.transparent,
          color: t.iconFg,
          onTap: live ? ref.read(playbackProvider.notifier).next : null,
        );
      case MiniButton.fav:
        final fav = ref.watch(
          libraryProvider.select((lib) => lib.isFav(track.id)),
        );
        return CircleIconButton(
          icon: fav ? Bi.heartBold : Bi.heart,
          size: _size,
          iconSize: 20,
          background: Colors.transparent,
          color: fav ? t.sysFavIco : t.iconFg,
          onTap: live
              ? () => ref.read(libraryProvider.notifier).toggleFav(track)
              : null,
        );
      case MiniButton.play:
        // The shape is a shared setting, and the same widget draws it as in the
        // player's transport ([PlayButton]). The spinner stays inside: the
        // button shouldn't vanish from the row on a track change.
        return PlayButton(
          size: _size,
          iconSize: 18,
          plainIconSize: 26,
          spinnerSize: 20,
          loading: loading,
          live: live,
          onTap: ref.read(playbackProvider.notifier).toggle,
        );
    }
  }
}

/// Card cover: a rounded square or circle, inside the progress ring if on. The
/// ring draws OUTSIDE the cover and takes no layout room, or one setting would
/// shift the whole row.
class _MiniCover extends StatelessWidget {
  const _MiniCover({
    required this.trackId,
    required this.cover,
    required this.animated,
    required this.shape,
    required this.ring,
  });

  final String trackId;
  final String? cover;
  final bool animated;
  final MiniCoverShape shape;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final radius = shape == MiniCoverShape.circle
        ? _coverSize / 2
        : t.radius * 0.72;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The cover frame clips the change layers, and the picture inside has
        // no radius of its own, or the leaving one shows a rounded corner
        // mid-frame.
        SizedBox(
          width: _coverSize,
          height: _coverSize,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: TrackSwap(
              id: trackId,
              fade: true,
              animated: animated,
              tuning: TrackSwapTuning.mini,
              child: Cover(url: cover, size: _coverSize, radius: 0),
            ),
          ),
        ),
        if (ring)
          Positioned(
            left: -_ringGap,
            top: -_ringGap,
            child: IgnorePointer(child: _RingProgress(coverRadius: radius)),
          ),
      ],
    );
  }
}

/// Progress ring around the cover, following its shape: a circle for a round
/// one, the same frame set off by the gap for a rounded one.
class _RingProgress extends ConsumerWidget {
  const _RingProgress({required this.coverRadius});

  final double coverRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    return CustomPaint(
      size: const Size.square(_coverSize + _ringGap * 2),
      painter: _RingPainter(
        frac: _progressFrac(ref),
        // Muted: on a cover auto accent a full-strength ring blazes around the
        // picture and pulls the eye from the card.
        color: t.accent.withValues(alpha: 0.7),
        track: t.ovlLine,
        // A round cover gets a true circle rather than a square with a large
        // radius: corners of a rounded rectangle with r at half the side still
        // flatten slightly.
        radius: coverRadius >= _coverSize / 2
            ? null
            : coverRadius + _ringGap - _ringInset,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.frac,
    required this.color,
    required this.track,
    required this.radius,
  });

  final double frac;
  final Color color;
  final Color track;

  /// Ring corner radius; `null` is a circle.
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    ).deflate(_ringInset);
    // The path starts at the top middle and runs clockwise: progress should
    // grow from where a round indicator is expected to.
    final path = radius == null
        ? (Path()..addArc(box, -math.pi / 2, 2 * math.pi))
        : _roundedPath(box, radius!);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line..color = track);
    if (frac <= 0) return;
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * frac),
      line..color = color,
    );
  }

  /// A rounded rectangle started from the top middle.
  static Path _roundedPath(Rect box, double r) {
    final c = box.center.dx;
    return Path()
      ..moveTo(c, box.top)
      ..lineTo(box.right - r, box.top)
      ..quadraticBezierTo(box.right, box.top, box.right, box.top + r)
      ..lineTo(box.right, box.bottom - r)
      ..quadraticBezierTo(box.right, box.bottom, box.right - r, box.bottom)
      ..lineTo(box.left + r, box.bottom)
      ..quadraticBezierTo(box.left, box.bottom, box.left, box.bottom - r)
      ..lineTo(box.left, box.top + r)
      ..quadraticBezierTo(box.left, box.top, box.left + r, box.top)
      ..lineTo(c, box.top);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.frac != frac ||
      old.color != color ||
      old.track != track ||
      old.radius != radius;
}

/// The cover as card background, dimmed and desaturated: otherwise a caption
/// doesn't read on a light picture.
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.cover});

  final String? cover;

  /// Brightness and saturation of the background picture.
  static const double _brightness = 0.38;
  static const double _saturation = 0.7;

  /// Channel luminance weights for the saturation matrix.
  static const double _lr = 0.2126;
  static const double _lg = 0.7152;
  static const double _lb = 0.0722;

  static double _diag(double weight) =>
      _brightness * (weight + (1 - weight) * _saturation);

  static double _off(double weight) =>
      _brightness * (weight * (1 - _saturation));

  @override
  Widget build(BuildContext context) {
    final image = coverImage(cover);
    if (image == null) return const SizedBox.shrink();
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        _diag(_lr), _off(_lg), _off(_lb), 0, 0, //
        _off(_lr), _diag(_lg), _off(_lb), 0, 0, //
        _off(_lr), _off(_lg), _diag(_lb), 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
      child: Image(image: image, fit: BoxFit.cover),
    );
  }
}

/// Progress as a background fill.
class _FillProgress extends ConsumerWidget {
  const _FillProgress({required this.tint});

  /// Card background in cover colour mode; `null` means no tint.
  final Color? tint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: _progressFrac(ref),
        heightFactor: 1,
        // On a tinted background the fill comes from the track's own tone (a
        // lightened dominant): the app's accent looks foreign there, a blue bar
        // over a red card.
        child: ColoredBox(
          color: tint == null
              ? t.accent.withValues(alpha: 0.18)
              : Color.lerp(tint, const Color(0xFFFFFFFF), 0.05)!,
        ),
      ),
    );
  }
}

/// Progress as a strip along the card's bottom edge.
class _Hairline extends ConsumerWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final frac = _progressFrac(ref);
    return SizedBox(
      height: 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac,
          child: ColoredBox(color: t.accent, child: const SizedBox(height: 2)),
        ),
      ),
    );
  }
}
