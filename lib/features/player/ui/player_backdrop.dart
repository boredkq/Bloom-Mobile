/// Full player background: a blurred cover or a gradient from its colour. It
/// lies UNDER all the player's content and over the theme fill; blocks are
/// painted with a thin `ovlBg` film, tinted by it rather than covering it.
///
/// Drawn inside the player, not under the panel: the panel grows out of the
/// mini player card and clips its content, so the background arrives with the
/// player, with no second layer to fade in step.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/cover_store.dart';
import '../../customization/custom_store.dart';
import '../../customization/ui/app_background.dart';
import '../player_bg_store.dart';
import '../player_style_store.dart';

/// Blur of the background cover, sigma. Large: colour patches should show, not
/// the picture, or details turn to mush behind captions and buttons.
const double kPlayerBgBlur = 42;

/// How much the frame is scaled under the blur, which eats the edges: with no
/// margin a smeared frame shows at the screen edges.
const double kPlayerBgScale = 1.18;

/// Dimming of a blurred cover: top, middle and bottom. Uneven: the transport
/// and tool row at the bottom need contrast for white icons on a light cover,
/// with only the header on top. Kept light: half of covers are dark, and
/// blurred they're almost black even with no film, reading as if the background
/// were off.
const List<double> kPlayerBgDim = [0.30, 0.40, 0.62];

/// The same dimming for a SHARP cover ([CoverBgFx.dim]). Denser than blurred:
/// blur erases details by itself, while under a sharp picture captions and
/// icons keep contrasty details like drawings, letters and faces. About an
/// eighth more throughout, so the picture still shows.
const List<double> kPlayerBgDimSharp = [0.38, 0.48, 0.70];

/// Saturation and brightness of a blurred cover, plus a lift of black. A film
/// on top can't save a dark cover, it has to be pulled up itself: the
/// multiplier lifts everything, the term tears black from the theme's
/// background, and saturation returns colour the blur averaged away.
const double kPlayerBgSaturation = 1.25;
const double kPlayerBgBrightness = 1.12;
const double kPlayerBgLift = 0.05;

/// How long the background takes to recolour on a track change. Much longer
/// than the cover's change (420 ms): it's full screen, and at that speed it
/// would blink.
const Duration kPlayerBgFade = Duration(milliseconds: 620);

/// The cover the background comes from: a custom one from customization beats
/// the track's, in the same order as the player's cover.
String? playerBgCover(WidgetRef ref) => ref.watch(playerCoverProvider);

/// Gradient colours in colour mode, top to bottom. The top is the cover's
/// colour; the bottom heads for the theme's colour but doesn't reach it, or the
/// lower third would look as if the background were off.
List<Color> playerBgGradient(Color color, Color bg) => [
  color,
  Color.lerp(color, bg, 0.5)!,
  Color.lerp(color, bg, 0.88)!,
];

/// Stops for those colours. The middle sits high: the cover takes the screen's
/// upper half, and the colour should hold on it and fade below.
const List<double> kPlayerBgStops = [0, 0.5, 1];

class PlayerBackdrop extends ConsumerWidget {
  const PlayerBackdrop({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playerBgProvider);
    final style = ref.watch(playerStyleProvider);
    final cover = playerBgCover(ref);

    // Living Apple Music Aura backdrop if mode is none but style is Aura.
    if (mode.isNone && !style.isAura) return const SizedBox.shrink();

    // Own repaint boundary: under the background time ticks each second and the
    // progress bar creeps, and blurring and recomputing for each of their
    // frames isn't needed.
    return RepaintBoundary(
      child: (mode.isNone && style.isAura)
          ? _AuraWash(cover: cover)
          : switch (mode) {
              PlayerBg.cover => _CoverWash(cover: cover),
              PlayerBg.app => const _AppWash(),
              PlayerBg.color => _ColorWash(cover: cover),
              PlayerBg.none => const SizedBox.shrink(),
            },
    );
  }
}

/// Living Apple Music Aura backdrop: an ambient radial aura mesh sampled from
/// the track cover's dominant color.
class _AuraWash extends ConsumerWidget {
  const _AuraWash({required this.cover});

  final String? cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final color = ref.watch(playerBgColorProvider(cover)).value ?? t.accent;

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: kPlayerBgFade,
      curve: Curves.easeOut,
      builder: (context, c, _) {
        final tint = c ?? t.accent;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.4),
              radius: 1.15,
              colors: [
                tint.withValues(alpha: 0.40),
                Color.lerp(tint, t.bg, 0.65)!.withValues(alpha: 0.25),
                t.bg,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// App background mode: the same picture that lies under the whole app, with
/// its blur and dimming. Redrawn INSIDE the player, not seen through: the
/// player's `Scaffold` covers what's below. It shares layers with the app's
/// ([BackgroundLayers]), or the picture would flinch when the player opens.
///
/// If the picture was removed there's just no background, as in none mode; the
/// setting stays, and it returns with the picture.
class _AppWash extends ConsumerWidget {
  const _AppWash();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(playerAppBgProvider);
    if (item == null) return const SizedBox.shrink();
    final image = coverImage(item.src);
    if (image == null) return const SizedBox.shrink();
    return BackgroundLayers(image: image, blur: item.blur, dim: item.dim);
  }
}

/// Colour mode: a gradient from the cover's dominant to the theme's colour. The
/// colour comes asynchronously, so the first frame is the theme's colour and
/// the dominant fades in over [kPlayerBgFade]. The same transition recolours on
/// a track change: [TweenAnimationBuilder] starts from what's on screen.
class _ColorWash extends ConsumerWidget {
  const _ColorWash({required this.cover});

  final String? cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    // No cover or unreadable: I aim at the theme's colour, so a gradient from
    // it to itself is invisible and no background appears.
    final target = ref.watch(playerBgColorProvider(cover)).value ?? t.bg;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: kPlayerBgFade,
      curve: Curves.easeOut,
      builder: (context, color, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: playerBgGradient(color ?? t.bg, t.bg),
            stops: kPlayerBgStops,
          ),
        ),
      ),
    );
  }
}

/// Cover mode: the picture full screen, blurred, dimmed or as is, per
/// [CoverBgFx]. Frames fade through [AnimatedSwitcher] by the cover link.
/// Dimming stands OUTSIDE the switcher, or two films add up mid-fade and the
/// background falls into black.
class _CoverWash extends ConsumerWidget {
  const _CoverWash({required this.cover});

  final String? cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fx = ref.watch(coverBgFxProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: kPlayerBgFade,
          child: KeyedSubtree(
            // Changing the effect also fades: the frame's key includes the
            // cover. Otherwise the picture jumps from blurred to sharp in one
            // frame right under the open picker sheet.
            key: ValueKey((cover, fx)),
            child: CoverBgImage(image: coverImage(cover), fx: fx),
          ),
        ),
        // Original is a clean cover with no film at all; that's the whole
        // option.
        if (!fx.isOriginal) IgnorePointer(child: _Dim(fx: fx)),
      ],
    );
  }
}

/// The picture itself, filling its rectangle. Blur, scale and colour correction
/// are only for [CoverBgFx.blur]: scale hides a smeared edge that doesn't exist
/// without blur, and correction restores the colour blur eats. They'd only
/// spoil a sharp cover.
///
/// Public and taking a ready [ImageProvider] for a test, since the network is
/// silent there and SIZE is what needs checking: `AnimatedSwitcher` puts
/// children in a `Stack` with LOOSE constraints, and an `Image` with no sides
/// would take the picture's own size.
class CoverBgImage extends StatelessWidget {
  const CoverBgImage({super.key, required this.image, required this.fx});

  final ImageProvider? image;
  final CoverBgFx fx;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) return const SizedBox.shrink();
    Widget picture = Image(
      image: image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
    if (fx.isBlur) {
      picture = ImageFiltered(
        // `TileMode.decal` would give a clear edge; `clamp` stretches the last
        // pixels, and the scale takes the edge itself off screen.
        imageFilter: ui.ImageFilter.blur(
          sigmaX: kPlayerBgBlur,
          sigmaY: kPlayerBgBlur,
        ),
        child: Transform.scale(
          scale: kPlayerBgScale,
          child: ColorFiltered(colorFilter: playerBgFilter(), child: picture),
        ),
      );
    }
    return SizedBox.expand(child: ClipRect(child: picture));
  }
}

/// Saturation × brightness plus a black lift, in one matrix. The term is on a
/// 0–255 scale, added to a channel AFTER multiplying.
ColorFilter playerBgFilter() {
  const lr = 0.2126;
  const lg = 0.7152;
  const lb = 0.0722;
  const s = kPlayerBgSaturation;
  const b = kPlayerBgBrightness;
  double diag(double weight) => b * (weight + (1 - weight) * s);
  double off(double weight) => b * (weight * (1 - s));
  const lift = kPlayerBgLift * 255;
  return ColorFilter.matrix(<double>[
    diag(lr), off(lg), off(lb), 0, lift, //
    off(lr), diag(lg), off(lb), 0, lift, //
    off(lr), off(lg), diag(lb), 0, lift, //
    0, 0, 0, 1, 0, //
  ]);
}

/// Film over the cover. Black rather than the theme's colour: under it is a
/// picture, not a UI surface, and the theme's tone would tint it. It changes
/// with the effect ([kPlayerBgDimSharp] under a sharp picture), SMOOTHLY:
/// otherwise a choice in the sheet jumps the density.
class _Dim extends StatelessWidget {
  const _Dim({required this.fx});

  final CoverBgFx fx;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // I run one share rather than three colours: it's the whole difference
      // between the sets.
      tween: Tween(begin: 0, end: fx.isBlur ? 0 : 1),
      duration: kPlayerBgFade,
      curve: Curves.easeOut,
      builder: (context, k, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              for (var i = 0; i < kPlayerBgDim.length; i++)
                Colors.black.withValues(
                  alpha: kPlayerBgDim[i] * (1 - k) + kPlayerBgDimSharp[i] * k,
                ),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
      ),
    );
  }
}
