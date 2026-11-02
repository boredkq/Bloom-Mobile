/// Scrolling line for a long title. I measure the text against the wrapper; if
/// it's more than 4 px wider, I draw text, gap, text and scroll left by exactly
/// text plus gap, so the second copy lands on the first and the loop has no
/// seam. The speed is constant but a cycle takes at least 4 s, or short titles
/// jitter.
///
/// If it fits, a plain `Text` with an ellipsis: no timer, no extra repaints.
library;

import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.align = TextAlign.start,
    this.gap = 64,
    this.speed = 55,
  });

  final String text;
  final TextStyle? style;

  /// Alignment while the line fits. Once scrolling it always starts from the
  /// left.
  final TextAlign align;

  /// Gap between the copies, px.
  final double gap;

  /// Scroll speed, px/s.
  final double speed;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Starts a cycle of the right length or stops it. Called from `build`, where
  /// the width is known, so the controller change waits for the end of the
  /// frame: an animation can't be touched mid-layout.
  void _sync(Duration? duration) {
    if (_c.duration == duration && _c.isAnimating == (duration != null)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _c.duration = duration;
      if (duration == null) {
        _c
          ..stop()
          ..value = 0;
      } else {
        _c.repeat();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        )..layout();
        final width = painter.width;
        final height = painter.height;
        final maxWidth = constraints.maxWidth;

        // A couple of pixels is the measurer's rounding, not an overflow.
        if (!maxWidth.isFinite || width <= maxWidth + 4) {
          _sync(null);
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.align,
            style: widget.style,
          );
        }

        final step = width + widget.gap;
        final seconds = (step / widget.speed).round();
        _sync(Duration(seconds: seconds < 4 ? 4 : seconds));

        // The copies sit in a `Stack`, not a `Row`: `Positioned` with an
        // explicit width may overflow the parent, while a `Row` would limit the
        // text to the wrapper width and ellipsize it again.
        final line = Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        );
        return SizedBox(
          width: maxWidth,
          height: height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final dx = -_c.value * step;
                return Stack(
                  children: [
                    Positioned(left: dx, top: 0, width: width, child: child!),
                    Positioned(
                      left: dx + step,
                      top: 0,
                      width: width,
                      child: child,
                    ),
                  ],
                );
              },
              child: line,
            ),
          ),
        );
      },
    );
  }
}
