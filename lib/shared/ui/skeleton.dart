/// Loading skeletons: grey plates laid out like what's loading. No progress
/// bars on purpose: a skeleton holds the future height, so results don't jump
/// when the answer comes.
///
/// The whole subtree pulses ([SkeletonPulse]), not each plate: one controller
/// per screen and neighbours never go out of sync.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// Placeholder plate. A `null` [width] takes all available width.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double? radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: t.iconBg,
        borderRadius: BorderRadius.circular(
          circle ? height / 2 : radius ?? t.radius * 0.72,
        ),
      ),
    );
  }
}

/// A section's title while it loads.
class SectionLabelSkeleton extends StatelessWidget {
  const SectionLabelSkeleton({
    super.key,
    required this.width,
    this.height = 14,
    this.padding = const EdgeInsets.fromLTRB(8, 24, 8, 12),
  });

  final double width;
  final double height;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: SkeletonBox(width: width, height: height, radius: height / 2),
    ),
  );
}

/// Plate in place of a text line: rounding from height, width a share of what's
/// available, so the lines don't look like a ruler.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, required this.widthFactor, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SkeletonBox(height: height, radius: height / 2),
    );
  }
}

/// Shared pulse for a subtree of skeletons.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  late final _opacity = Tween(
    begin: 1.0,
    end: 0.45,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Takes no taps: nothing here can be pressed, and touches on it shouldn't
    // die here.
    return IgnorePointer(
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}

/// Caption line widths, cycled so plates don't form a uniform column.
const List<double> _titleWidths = [0.62, 0.48, 0.71, 0.55];
const List<double> _subWidths = [0.34, 0.42, 0.28, 0.38];

/// Stand-in for [TrackRow]: the same padding and 48 cover, so the row height
/// matches.
class TrackRowSkeleton extends StatelessWidget {
  const TrackRowSkeleton({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          const SkeletonBox(width: 48, height: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(
                  widthFactor: _titleWidths[index % _titleWidths.length],
                  height: 13,
                ),
                const SizedBox(height: 7),
                SkeletonLine(
                  widthFactor: _subWidths[index % _subWidths.length],
                  height: 11,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const SkeletonBox(width: 30, height: 11, radius: 6),
        ],
      ),
    );
  }
}

/// Stand-in for [SetCard] and [ArtistCard]: a cover filling the cell and two
/// caption lines (one for an artist).
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key, required this.circle, this.width});

  final bool circle;

  /// `null` fills a grid cell; a number is a fixed carousel card width.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: circle
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          SkeletonBox(
            width: box.maxWidth,
            height: box.maxWidth,
            circle: circle,
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: box.maxWidth * (circle ? 0.7 : 0.8), height: 12),
          if (!circle) ...[
            const SizedBox(height: 6),
            SkeletonBox(width: box.maxWidth * 0.5, height: 10),
          ],
        ],
      ),
    );
    return width == null ? content : SizedBox(width: width, child: content);
  }
}

/// Skeleton strip instead of [EntityCarousel], with enough cards to fill the
/// row to the right edge.
class CarouselSkeleton extends StatelessWidget {
  const CarouselSkeleton({
    super.key,
    required this.height,
    required this.card,
    this.circle = false,
  });

  final double height;
  final double card;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final count = (width / (card + 12)).ceil();

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, _) => CardSkeleton(circle: circle, width: card),
      ),
    );
  }
}
