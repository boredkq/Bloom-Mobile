/// Play button, one for both surfaces: the full player's transport and the card
/// above the tab bar. Shared because a setting sets the shape
/// ([PlayButtonShape]), and two widgets would drift.
///
/// The [size] box is the SAME for all shapes, with no fill too: the transport
/// row is `spaceEvenly`, and a button shrunk to its glyph would spread its
/// neighbours.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/pressable.dart';
import '../play_button_store.dart';
import '../player_controller.dart';

class PlayButton extends ConsumerWidget {
  const PlayButton({
    super.key,
    required this.size,
    required this.iconSize,
    required this.plainIconSize,
    required this.spinnerSize,
    this.loading = false,
    this.live = true,
    this.onTap,
  });

  /// Button side, also the circle's diameter.
  final double size;

  /// Glyph on a fill (circle and square).
  final double iconSize;

  /// Glyph with no fill. Larger than [iconSize]: with no plate holding
  /// attention it would become just another icon.
  final double plainIconSize;

  /// Spinner inside the button.
  final double spinnerSize;

  /// A change to another track is under way. The button STAYS, with a spinner
  /// for the glyph, or the transport would visually collapse on each change.
  final bool loading;

  /// A live button. `false` is a neighbour's card in the mini player's
  /// carousel: buttons are there only for layout, and the glyph is always
  /// `play`.
  final bool live;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final shape = ref.watch(playButtonShapeProvider);
    final plain = shape.isPlain;
    // With no fill the glyph takes the neighbours' colour: `accentText` relies
    // on an accent background and would vanish here.
    final color = plain ? t.iconFg : t.accentText;

    Widget shell(Widget child, {VoidCallback? tap}) {
      final inner = Center(child: child);
      return Pressable(
        onTap: tap,
        child: SizedBox(
          width: size,
          height: size,
          child: Material(
            color: plain ? Colors.transparent : t.accent,
            shape: shape == PlayButtonShape.square
                // Rounding as a share of the side, not the theme radius: the
                // card's button is nearly half the player's, and the shared
                // radius would make it a pill.
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(size * 0.3),
                  )
                : const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: inner,
          ),
        ),
      );
    }

    if (loading) {
      return shell(
        BloomSpinner(
          size: spinnerSize,
          stroke: size >= 56 ? 2.4 : 2.2,
          color: color,
        ),
      );
    }

    if (!live) {
      return shell(
        BloomIcon(
          Bi.playBold,
          size: plain ? plainIconSize : iconSize,
          color: color,
        ),
      );
    }

    // The state comes from the player itself, not `PlaybackState`: a pause from
    // the shade or headset doesn't reach that.
    return shell(
      BloomIcon(
        ref.watch(playingNowProvider) ? Bi.pauseBold : Bi.playBold,
        size: plain ? plainIconSize : iconSize,
        color: color,
      ),
      tap: onTap,
    );
  }
}
