/// Cover flight: from a list card to its place in the page header. Both ends
/// wrap the picture in [CoverHero] with one tag, and the navigator draws a copy
/// in its overlay that travels between the two rectangles.
///
/// The ends differ in rounding, so I compute the flying copy's shape myself: a
/// parent's clip doesn't reach it.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// The cover of the card being left. The card makes its own [tag], one per
/// instance. An id won't do: one album can sit in two result sections, and two
/// `Hero`s with one tag in a tree throw when the transition starts.
class CoverFlight {
  const CoverFlight({required this.tag, this.image});

  final Object tag;

  /// The card's picture, already cached. The header shows it until its own
  /// loads: platforms serve the same cover under another, bigger link, and the
  /// landing would blink a placeholder.
  final String? image;
}

/// One end of the flight. With a `null` [tag] there is no flight and this is
/// just [child].
class CoverHero extends StatelessWidget {
  const CoverHero({
    super.key,
    required this.tag,
    required this.shape,
    required this.child,
  });

  final Object? tag;

  /// Picture rounding at THIS end. The flying copy moves between the two ends'
  /// shapes.
  final BorderRadius shape;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tag = this.tag;
    if (tag == null) return child;
    return Hero(tag: tag, flightShuttleBuilder: _shuttle, child: child);
  }

  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final from = _shapeOf(fromContext);
    final to = _shapeOf(toContext);
    // What flies is the destination's content: exactly what stays after
    // landing.
    final child = (toContext.widget as Hero).child;
    // Flight progress. On pop the navigator runs from 1 to 0 but the copy still
    // goes `from` to `to`, or the rounding would run backwards.
    final t = direction == HeroFlightDirection.pop
        ? ReverseAnimation(animation)
        : animation;

    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) => ClipRRect(
        borderRadius: BorderRadius.lerp(from, to, t.value)!,
        child: child,
      ),
    );
  }

  /// Shape of a flight end: I ask the `Hero`'s context for the wrapper that
  /// placed it.
  static BorderRadius _shapeOf(BuildContext context) =>
      context.findAncestorWidgetOfExactType<CoverHero>()?.shape ??
      BorderRadius.zero;
}

/// Fades in the header's content (buttons, title, action row) at the end of a
/// flight. The flying copy draws over the page and by the end of the trip
/// covers the whole header. Without this the text would fade in, hide under the
/// cover and pop out on landing, so it appears just as the cover settles.
///
/// With [flying] `false` there's nothing to hold back.
class HeroContent extends StatelessWidget {
  const HeroContent({super.key, required this.flying, required this.child});

  final bool flying;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    if (!flying || animation == null) return child;
    return FadeTransition(
      // First half of the 450 ms transition: the cover is still travelling;
      // text comes in during the second. `drive`, not `CurvedAnimation`: that
      // one starts in `build` and nobody would dispose it.
      opacity: animation.drive(
        CurveTween(curve: const Interval(0.5, 1, curve: Curves.easeOut)),
      ),
      child: child,
    );
  }
}

// ─── Page transition under a flight ─────────────────────────────────────

/// Transition to a page whose header receives a flying cover: the app-wide
/// dissolve without the horizontal slide. The shared transition brings a page
/// in sideways; under a flight that makes two movements in one frame, the cover
/// diagonally and everything else across. Here the page stays put: only the
/// cover moves, the rest just fades in.
///
/// Dissolve curves come from the shared transition so pages keep one tempo.

/// The new page fades in over the first 3/4 of the transition. Public because
/// shell tabs fade on the same curves.
final Animatable<double> kPageFadeIn = Tween<double>(
  begin: 0,
  end: 1,
).chain(CurveTween(curve: const Interval(0, 0.75)));

/// The leaving one fades over the first quarter.
final Animatable<double> kPageFadeOut = Tween<double>(
  begin: 1,
  end: 0,
).chain(CurveTween(curve: const Interval(0, 0.25)));

/// Same length as the shared transition: the navigator runs the flight and the
/// page with it, and they must end together.
const Duration kDetailTransition = Duration(
  milliseconds: FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds,
);

/// Fade with no slide, both entering ([animation]) and being covered by the
/// next page ([secondaryAnimation]).
Widget detailPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return DualTransitionBuilder(
    animation: animation,
    forwardBuilder: (context, animation, child) =>
        FadeTransition(opacity: kPageFadeIn.animate(animation), child: child),
    reverseBuilder: (context, animation, child) => IgnorePointer(
      ignoring: animation.status == AnimationStatus.forward,
      child: FadeTransition(
        opacity: kPageFadeOut.animate(animation),
        child: child,
      ),
    ),
    // A fill for the transition, or black shows between the pages as the next
    // one covers this.
    child: ColoredBox(
      color: secondaryAnimation.isAnimating
          ? context.bloom.bg
          : Colors.transparent,
      child: DualTransitionBuilder(
        animation: ReverseAnimation(secondaryAnimation),
        forwardBuilder: (context, animation, child) => FadeTransition(
          opacity: kPageFadeIn.animate(animation),
          child: child,
        ),
        reverseBuilder: (context, animation, child) => FadeTransition(
          opacity: kPageFadeOut.animate(animation),
          child: child,
        ),
        child: child,
      ),
    ),
  );
}

/// Route of an artist or set page; they open with the branch's ordinary
/// navigator.
PageRoute<T> detailPageRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  pageBuilder: (context, _, _) => builder(context),
  transitionsBuilder: detailPageTransition,
  transitionDuration: kDetailTransition,
  reverseTransitionDuration: kDetailTransition,
);
