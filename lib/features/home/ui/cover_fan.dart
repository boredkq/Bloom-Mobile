/// A fan of three covers: the top one centred, the back ones set aside, tilted
/// and dimmed. Used at different sizes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';

class CoverFan extends StatelessWidget {
  const CoverFan({
    super.key,
    required this.front,
    this.left,
    this.right,
    required this.width,
    required this.height,
    required this.frontSize,
    required this.backSize,
    required this.shift,
    this.tilt = 7 * math.pi / 180,
    this.dim = 0.55,
    this.shadowScale = 1,
  });

  /// Covers: top and two back. A missing back one leaves an empty place.
  final String? front;
  final String? left;
  final String? right;

  final double width;
  final double height;
  final double frontSize;
  final double backSize;

  /// How far back covers stand from the centre.
  final double shift;

  /// Back covers' tilt, radians.
  final double tilt;

  /// Back covers' brightness.
  final double dim;

  /// Multiplier of shadow blur and offset: on a small stack a large card's
  /// shadows would spread over the plate.
  final double shadowScale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        // Child order is layer order: back before top.
        children: [
          if (left != null) _back(context, left!, -1),
          if (right != null) _back(context, right!, 1),
          _Shadowed(
            blur: 22 * shadowScale,
            offsetY: 8 * shadowScale,
            opacity: 0.5,
            child: Cover(url: front, size: frontSize),
          ),
        ],
      ),
    );
  }

  Widget _back(BuildContext context, String url, int side) {
    return Transform.translate(
      offset: Offset(side * shift, 0),
      child: Transform.rotate(
        angle: side * tilt,
        child: _Shadowed(
          blur: 14 * shadowScale,
          offsetY: 4 * shadowScale,
          opacity: 0.35,
          child: Stack(
            children: [
              Cover(url: url, size: backSize),
              // A film rather than a colour filter: dimming a picture this way
              // is cheaper.
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    context.bloom.radius * 0.72,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 1 - dim),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shadow under the cover in the cover's own shape.
class _Shadowed extends StatelessWidget {
  const _Shadowed({
    required this.child,
    required this.blur,
    required this.offsetY,
    required this.opacity,
  });

  final Widget child;
  final double blur;
  final double offsetY;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        // The same shape as [Cover] by default.
        borderRadius: BorderRadius.circular(context.bloom.radius * 0.72),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: opacity),
            blurRadius: blur,
            offset: Offset(0, offsetY),
          ),
        ],
      ),
      child: child,
    );
  }
}
