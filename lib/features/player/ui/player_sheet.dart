/// Player panel: the mini player card that grows to full screen. The player
/// here is a shell layer over everything, the tab bar too, not a route: the
/// panel must BE that card, growing out of it after the finger and collapsing
/// into it. A route comes in as a separate screen over the card.
///
/// So what a route gives free is done by hand: `PopScope` in the shell catches
/// system Back; collapse in the header, a tap on the source pill and going to
/// an artist page call [collapsePlayerSheet]; player content is built only when
/// the panel starts expanding and dies when it folds, or lyrics would hit the
/// network at app launch.
library;

import 'dart:async' show unawaited;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/settings_store.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/track_flick.dart';
import '../../../shared/ui/track_swipes.dart';
import '../mini_style_store.dart';
import '../player_controller.dart';
import '../track_swap_dir.dart';
import 'full_player.dart';
import 'mini_player.dart';

/// How long the panel travels by itself. Expanding is much longer than
/// collapsing: up it shows itself, and down it should clear out as soon as the
/// user decides to leave.
const Duration kSheetIn = Duration(milliseconds: 320);
const Duration kSheetOut = Duration(milliseconds: 260);

/// Fling speed (px/s) past which a release decides the outcome, however far the
/// finger went.
const double kSheetFling = 500;

/// Expansion share by which the player's content is opaque. Below it the card's
/// fill, row and glass show through.
const double _kBodyIn = 0.3;

/// The app's only panel, set by the shell. The mini player card is one too, so
/// a second can't appear.
_PlayerSheetState? _sheet;

/// Whether the player is open: the panel takes the screen or is heading for it.
/// A signal rather than a state field: the shell's `PopScope` listens, and must
/// rebuild when the panel opens or folds.
final ValueNotifier<bool> playerSheetOpen = ValueNotifier<bool>(false);

/// Expands the player to full screen.
void expandPlayerSheet() => _sheet?.expand();

/// Collapses the player back into the card. `false` if there was nothing to
/// collapse (already folded, or the shell isn't built).
bool collapsePlayerSheet() {
  final sheet = _sheet;
  if (sheet == null || !playerSheetOpen.value) return false;
  sheet.collapse();
  return true;
}

class PlayerSheet extends ConsumerStatefulWidget {
  const PlayerSheet({super.key});

  @override
  ConsumerState<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<PlayerSheet>
    with SingleTickerProviderStateMixin {
  /// Expansion share: 0 is the card above the tab bar, 1 the full player.
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: kSheetIn,
  )..addListener(_report);

  /// Pixels the panel's top edge travels from the card to the top of the
  /// screen. The gesture turns the finger into a share by it: the edge is
  /// what's held, and it must follow the finger one to one.
  double _travel = 0;

  /// The card's horizontal shift, a share of its width. Held HERE rather than
  /// in `TrackFlick`: in the carousel the neighbours follow the finger too, and
  /// they lie in a separate layer.
  final ValueNotifier<double> _shift = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _sheet = this;
  }

  @override
  void dispose() {
    if (_sheet == this) _sheet = null;
    _t.dispose();
    _shift.dispose();
    playerSheetOpen.value = false;
    super.dispose();
  }

  void _report() => playerSheetOpen.value = _t.value > 0;

  void expand() => _drive(true);

  void collapse() => _drive(false);

  /// Takes the panel to the edge. The time comes from the rest of the way, not
  /// the full run, or the last percent crawl for the same 320 ms.
  void _drive(bool open) {
    final rest = open ? 1 - _t.value : _t.value;
    final full = (open ? kSheetIn : kSheetOut).inMilliseconds;
    _t.animateTo(
      open ? 1 : 0,
      duration: Duration(milliseconds: (rest * full).round().clamp(90, full)),
      curve: Curves.easeOutCubic,
    );
  }

  void _update(double dy) {
    if (_travel <= 0) return;
    _t.value = (_t.value - dy / _travel).clamp(0.0, 1.0);
  }

  /// The finger let go; [velocity] is vertical, in pixels per second.
  void _end(double velocity) =>
      _drive(velocity.abs() > kSheetFling ? velocity < 0 : _t.value >= 0.5);

  /// Flicks the carousel. `TrackSwap` layers don't animate a change under the
  /// finger ([markSwapSilent]): the card shift already showed it. Previous is
  /// always the previous track here, not a seek to the start: the user pulls in
  /// the card they see.
  void _flip(WidgetRef ref, {required bool forward}) {
    markSwapSilent();
    final player = ref.read(playbackProvider.notifier);
    unawaited(forward ? player.next() : player.prevTrack());
  }

  @override
  Widget build(BuildContext context) {
    // The queue may empty under me: the last track swiped in the queue sheet,
    // or a stop from the system. The panel goes with the card, having nothing
    // to show, and sheets above it must follow, or they'd hang over an empty
    // screen.
    ref.listen(playbackProvider, (_, next) {
      if (next.track != null) return;
      if (_t.value > 0) {
        Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
      }
      _t.value = 0;
    });

    final track = ref.watch(playbackProvider.select((s) => s.track));
    if (track == null) return const SizedBox.shrink();

    final t = context.bloom;
    final style = ref.watch(miniStyleProvider);
    final swipes = ref.watch(swipeProvider).of(SwipeZone.mini);
    final navInset = navBarInset(context, ref.watch(settingsProvider).navStyle);
    final cardRadius = miniCardRadius(style.radius, t.radius);

    // Nothing to flick: one track in the queue would be its own neighbour on
    // both sides.
    final canFlip = ref.watch(
      playbackProvider.select((s) => s.queue.length > 1),
    );
    // Carousel: the card narrows at the sides, neighbours peek into the freed
    // strips, and the horizontal gesture takes over flicking, whatever the
    // swipes setting says. Otherwise the card promises neighbours and the
    // finger likes a track.
    //
    // The setting alone doesn't make a carousel: with no second track a
    // narrowed card looks broken. Then the mini player stands as usual and the
    // gesture returns to swipes.
    final peek = style.neighbors && canFlip;

    return LayoutBuilder(
      builder: (context, box) {
        final screen = box.biggest;
        // The card's place at rest: exactly what the shell's bottom bar keeps
        // empty (`MiniCardSlot`), margins of 8 at the sides and above the tab
        // bar. With neighbours it narrows by their strips.
        final card = miniCardRect(
          screen: screen,
          navInset: navInset,
          neighbors: peek,
        );
        _travel = card.top;
        // All three move by this step on a flick, so a neighbour lands dead
        // centre.
        final stride = miniStride(card.width);

        // Own glass group: the panel lies over the page and bars, and a shared
        // backdrop snapshot wouldn't blur what's under it.
        return GlassGroup(
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final v = _t.value;
              final rect = Rect.lerp(card, Offset.zero & screen, v)!;
              // The card's row leaves quickly: as the panel grows its content
              // is wrong a tenth of the way along. The player fades in
              // overlapping: it's opaque and covers what hasn't gone yet.
              final row = 1 - const Interval(0, 0.14).transform(v);
              final body = const Interval(0.06, _kBodyIn).transform(v);

              // The keys aren't about order but about the panel outliving the
              // neighbours. The neighbour layer goes out at `row == 0`, within
              // the first hundred pixels of a pull, and with no keys `Stack`
              // matches children by INDEX: the panel's `Positioned` takes over
              // the neighbours' element, and its own, with `TrackFlick` and the
              // live recognizer, is destroyed. The finger is still moving with
              // nobody listening, and the expansion stalls midway.
              return Stack(
                children: [
                  // Neighbours lie UNDER the panel in their own coordinates:
                  // they extend past the card's edges, which can't happen from
                  // inside it. They fade with the row: an open player has no
                  // use for them.
                  if (peek && row > 0)
                    Positioned(
                      key: const ValueKey('neighbors'),
                      left: 0,
                      right: 0,
                      top: card.top,
                      height: kMiniCardHeight,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: row,
                          child: ClipRect(
                            child: _Neighbors(
                              shift: _shift,
                              stride: stride,
                              width: card.width,
                              // The layer is clipped at the screen edge, so a
                              // neighbour's strip reaches the very edge; the
                              // card stands further in, by the strip's width.
                              inset: card.left,
                              radius: cardRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fromRect(
                    key: const ValueKey('sheet'),
                    rect: rect,
                    child: TrackFlick(
                      shift: _shift,
                      carousel: peek,
                      // Flicking by a swipe on the CARD only. Once the panel
                      // moves the gesture goes: the player inside has its own,
                      // and this one would drag the whole panel sideways. A
                      // nested recognizer wins only where it was asked at all:
                      // in the gaps of the player's layout the finger came to
                      // me.
                      //
                      // A flag rather than nulled handlers: without both,
                      // `TrackFlick` changes the tree's shape, and the panel's
                      // content would rebuild from scratch on the first pixel.
                      enabled: v == 0,
                      onLeft: peek
                          ? () => _flip(ref, forward: true)
                          : swipes.left == SwipeAction.none
                          ? null
                          : () => runSwipeAction(
                              context,
                              ref,
                              swipes.left,
                              track: track,
                              fromFlick: true,
                            ),
                      onRight: peek
                          ? () => _flip(ref, forward: false)
                          : swipes.right == SwipeAction.none
                          ? null
                          : () => runSwipeAction(
                              context,
                              ref,
                              swipes.right,
                              track: track,
                              fromFlick: true,
                            ),
                      builder: (context, shift) => _Slide(
                        shift: shift,
                        // The carousel moves a whole card with no fade: what's
                        // being pulled in must stay visible to the end.
                        stride: peek ? stride : null,
                        child: _gestures(
                          expanded: v > 0,
                          child: MiniCardSkin(
                            radius: lerpDouble(cardRadius, 0, v)!,
                            // Glass stays while the fill shows through the
                            // player. Beyond that there's no reason to blur a
                            // full-screen backdrop nobody can see.
                            glass: v < _kBodyIn,
                            // Keys for the same reason as the stack above: the
                            // row goes before the player fades in, and with no
                            // keys the leaving row would take the player's
                            // element. It would rebuild mid-expansion, and go
                            // to the network for lyrics just opened.
                            child: Stack(
                              children: [
                                if (row > 0)
                                  Positioned(
                                    key: const ValueKey('row'),
                                    left: 0,
                                    right: 0,
                                    top: 0,
                                    height: kMiniCardHeight,
                                    child: Opacity(
                                      opacity: row,
                                      child: const MiniCardRow(),
                                    ),
                                  ),
                                // The player is laid out full screen and just
                                // clipped by the panel's window. Horizontally
                                // it stays put (hence `-rect.left`), or content
                                // would slide on every pixel of a pull. The top
                                // edge is shared: the player's header must ride
                                // up WITH the panel's edge, which is what makes
                                // the expansion read.
                                if (body > 0)
                                  Positioned(
                                    key: const ValueKey('body'),
                                    left: -rect.left,
                                    top: 0,
                                    width: screen.width,
                                    height: screen.height,
                                    child: Opacity(
                                      opacity: body,
                                      child: const FullPlayerBody(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// Pull and tap on the panel. One gesture for both positions: up expands the
  /// card, down folds the player. Buttons inside take the tap themselves, lying
  /// deeper.
  Widget _gestures({required bool expanded, required Widget child}) =>
      GestureDetector(
        onTap: expanded ? null : expand,
        onVerticalDragDown: (_) => _t.stop(),
        onVerticalDragUpdate: (d) => _update(d.delta.dy),
        onVerticalDragEnd: (d) => _end(d.velocity.pixelsPerSecond.dy),
        onVerticalDragCancel: () => _end(0),
        child: child,
      );
}

/// What follows the finger: in a carousel the whole card by a neighbour's step
/// with no fade; otherwise the content by a share of its width ([FlickSlide]).
class _Slide extends StatelessWidget {
  const _Slide({
    required this.shift,
    required this.stride,
    required this.child,
  });

  final ValueListenable<double> shift;

  /// Carousel step in pixels; `null` means no carousel.
  final double? stride;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final step = stride;
    return step == null
        ? FlickSlide(shift: shift, child: child)
        : CarouselSlide(shift: shift, stride: step, child: child);
  }
}

/// Neighbouring tracks' cards at the edges. Whole cards, not scraps: the rest
/// goes off screen, and on a flick the neighbour arrives in the centre fully
/// built. Their row is dead ([MiniCardRow.neighbor]), under [IgnorePointer]
/// anyway.
class _Neighbors extends ConsumerWidget {
  const _Neighbors({
    required this.shift,
    required this.stride,
    required this.width,
    required this.inset,
    required this.radius,
  });

  final ValueListenable<double> shift;

  /// Carousel step: card width plus the gap.
  final double stride;

  /// Card width, the same for neighbours.
  final double width;

  /// The card's left edge in layer coordinates: the layer is clipped at screen
  /// margins, and the card stands further in by the neighbour's visible strip.
  final double inset;

  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackProvider);
    final q = state.queue;
    if (q.length < 2 || state.index < 0 || state.index >= q.length) {
      return const SizedBox.shrink();
    }
    // The same looping as next and previous in the controller: at the queue's
    // end the next is the first.
    final prev = q[(state.index - 1 + q.length) % q.length];
    final next = q[(state.index + 1) % q.length];
    return CarouselSlide(
      shift: shift,
      stride: stride,
      child: Stack(
        clipBehavior: Clip.none,
        children: [_slot(prev, inset - stride), _slot(next, inset + stride)],
      ),
    );
  }

  Widget _slot(Track track, double left) => Positioned(
    left: left,
    top: 0,
    width: width,
    height: kMiniCardHeight,
    child: MiniCardSkin(
      radius: radius,
      glass: true,
      neighbor: track,
      child: MiniCardRow(neighbor: track),
    ),
  );
}

/// The panel's fill, also the card's: glass or a cover tone, a border, and
/// rounding that straightens into the screen's corners as it expands.
class MiniCardSkin extends ConsumerWidget {
  const MiniCardSkin({
    super.key,
    required this.radius,
    required this.glass,
    required this.child,
    this.neighbor,
  });

  /// Corner rounding in pixels.
  final double radius;

  /// Whether to use glass. An open panel doesn't need it.
  final bool glass;

  /// A neighbour's card in the carousel: the fill tone comes from ITS cover.
  final Track? neighbor;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final style = ref.watch(miniStyleProvider);
    return GlassBox(
      color: miniCardTint(ref, style, neighbor: neighbor),
      // Glass only with the theme background. A cover colour fill is already
      // dark (L 0.09–0.18), and translucent over a dark background it merges
      // into black, so the setting stops reading. A picture background is
      // opaque, with no reason to blur under it.
      enabled: glass && style.bg == MiniBg.theme,
      borderSide: BorderSide(color: t.ovlLine),
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
  }
}
