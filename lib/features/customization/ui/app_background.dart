/// The app's background layer. It lies BELOW the whole UI, drawn once for the
/// app: a full-screen `cover` picture with blur and a black dim film over it.
/// The numbers come from the picture itself ([MediaItem.blur],
/// [MediaItem.dim]).
///
/// No picture, nothing drawn: the shell's `Scaffold` paints the theme's `bg`.
/// With a picture, pages must go clear or it's under a solid fill (`_Page` in
/// the router and the shell watch [backgroundOnProvider]).
///
/// The background shows through plates only with transparency on; otherwise
/// only in gaps between blocks.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/cover_store.dart';
import '../../../core/store/settings_store.dart';
import '../../player/player_controller.dart';
import '../custom_store.dart';

/// What shows as the background: an own library picture or the playing cover.
/// Both empty, no background. An own picture WINS over the cover.
final backgroundProvider = Provider<({String src, double blur, double dim})?>((
  ref,
) {
  final item = ref.watch(customItemProvider(CustomCtx.bg));
  if (item != null) {
    return (src: item.src, blur: item.blur, dim: item.dim);
  }
  if (!ref.watch(settingsProvider).coverAsBg) return null;
  final cover = ref.watch(playbackProvider).track?.cover;
  if (cover == null || cover.isEmpty) return null;
  // A track cover has no page with sliders, since it isn't in the library: its
  // blur and dim are set in appearance settings and kept in
  // [coverAsBgFxProvider].
  final fx = ref.watch(coverAsBgFxProvider);
  return (src: cover, blur: fx.blur.toDouble(), dim: fx.dim.toDouble());
});

/// Background on: pages can't paint themselves solid.
final backgroundOnProvider = Provider<bool>(
  (ref) => ref.watch(backgroundProvider) != null,
);

class AppBackground extends ConsumerWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = ref.watch(backgroundProvider);
    if (bg == null) return child;
    final image = coverImage(bg.src);
    if (image == null) return child;

    return Stack(
      children: [
        Positioned.fill(
          child: BackgroundLayers(image: image, blur: bg.blur, dim: bg.dim),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// The background picture: blur, scale and dim film. A separate widget (taking
/// a ready [ImageProvider]) for the full player: in app background mode
/// (`PlayerBg.app`) it draws THESE layers inside itself, since its `Scaffold`
/// covers what's below. Shared so the picture doesn't flinch when the player
/// opens.
class BackgroundLayers extends StatelessWidget {
  const BackgroundLayers({
    super.key,
    required this.image,
    required this.blur,
    required this.dim,
  });

  final ImageProvider image;

  /// Blur (sigma) and dim (0–100), the picture's own.
  final double blur;
  final double dim;

  @override
  Widget build(BuildContext context) {
    // A picture a bit larger than the screen: blur pulls the edges in, and with
    // no margin emptiness shows there. The clip is a must, or the scaled layer
    // overflows the screen.
    Widget layer = Image(
      image: image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // While loading or if it fails there's just no background, and the UI
      // stays put.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    if (blur > 0) {
      layer = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: layer,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(child: Transform.scale(scale: 1.1, child: layer)),
        // Dim film.
        if (dim > 0)
          ColoredBox(color: Colors.black.withValues(alpha: dim / 100)),
      ],
    );
  }
}
