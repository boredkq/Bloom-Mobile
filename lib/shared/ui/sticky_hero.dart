/// Page header that doesn't scroll away whole. The cover, title and action row
/// leave upward as ordinary content, but the row of round buttons sticks to the
/// top: on a long track list there'd be nothing to press without scrolling all
/// the way back.
///
/// The collapsed header is a strip of the same cover, so the buttons stay on
/// the picture, not a flat bar.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show OverScrollHeaderStretchConfiguration;

import '../../app/theme/tokens.dart';
import 'cover_hero.dart';

class StickyHero extends StatelessWidget {
  const StickyHero({
    super.key,
    required this.height,
    required this.background,
    required this.bar,
    required this.barHeight,
    required this.body,
    this.flying = false,
  });

  final double height;

  /// Picture for the whole header: a cover, a collage or a section tint.
  final Widget background;

  /// The row of buttons that stays visible.
  final Widget bar;

  /// Height of that row, for the collapsed header. Not from layout: a sliver
  /// needs its min extent before the child is laid out.
  final double barHeight;

  /// Title, captions and action row: the lower part that scrolls away.
  final Widget body;

  /// A cover is flying in from a card: the content waits for the landing.
  final bool flying;

  /// Header content margins, the same on all hero pages.
  static const double _side = 16;
  static const double _barTop = 10;
  static const double _barBottom = 10;
  static const double _bodyBottom = 12;

  /// Height of the collapsed header: how much of the list the stuck row covers.
  /// For code that works out whether a row is visible (the now-playing pill); a
  /// copy of these numbers would drift.
  static double collapsedHeight(BuildContext context, double barHeight) =>
      MediaQuery.paddingOf(context).top + _barTop + barHeight + _barBottom;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyHeroDelegate(
        height: height,
        top: MediaQuery.paddingOf(context).top,
        radius: context.bloom.radius * 1.5,
        background: background,
        bar: bar,
        barHeight: barHeight,
        body: body,
        flying: flying,
      ),
    );
  }
}

class _StickyHeroDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeroDelegate({
    required this.height,
    required this.top,
    required this.radius,
    required this.background,
    required this.bar,
    required this.barHeight,
    required this.body,
    required this.flying,
  });

  final double height;

  /// Status bar: the buttons sit below it, collapsed too.
  final double top;

  final double radius;
  final Widget background;
  final Widget bar;
  final double barHeight;
  final Widget body;
  final bool flying;

  @override
  double get maxExtent => math.max(height, minExtent);

  @override
  double get minExtent =>
      top + StickyHero._barTop + barHeight + StickyHero._barBottom;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final extent = math.max(minExtent, maxExtent - shrinkOffset);
    final collapse = ((maxExtent - extent) / (maxExtent - minExtent)).clamp(
      0.0,
      1.0,
    );
    // The title and action row fade only over the last stretch: before that
    // they're still in place.
    final fade = (1 - (collapse - 0.55) / 0.45).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The cover with its captions scrolls up as ordinary content, leaving
          // its lower, darkest strip in the collapsed header, where white
          // buttons read on any picture. Pulled past the top, the box is taller
          // and the cover fills it all.
          Positioned(
            top: extent - maxExtent,
            left: 0,
            right: 0,
            bottom: 0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                background,
                Positioned(
                  left: StickyHero._side,
                  right: StickyHero._side,
                  bottom: StickyHero._bodyBottom,
                  // Faded content sits right under the button row and would
                  // stay pressable: an invisible Play under Back starts the
                  // list by accident.
                  child: IgnorePointer(
                    ignoring: fade == 0,
                    child: Opacity(
                      opacity: fade,
                      child: HeroContent(flying: flying, child: body),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: top + StickyHero._barTop,
            left: StickyHero._side,
            right: StickyHero._side,
            child: HeroContent(flying: flying, child: bar),
          ),
        ],
      ),
    );
  }

  /// Pulled past the top, the header is laid out taller rather than baring
  /// the page above it.
  @override
  OverScrollHeaderStretchConfiguration get stretchConfiguration =>
      OverScrollHeaderStretchConfiguration();

  /// The content arrives built and has nothing to compare by, so I always
  /// rebuild.
  @override
  bool shouldRebuild(_StickyHeroDelegate old) => true;
}
