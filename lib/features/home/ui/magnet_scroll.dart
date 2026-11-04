/// Two screens in one scroll, held apart by a magnet: a weak swipe between them
/// springs back, a strong one snaps across. Past the second screen's top the
/// scroll is free, and a fling from there stops at that top.
library;

import 'package:flutter/widgets.dart';

// Knobs: how far a drag must go to leave a screen, as a share of the viewport;
// how fast a flick leaves it from anywhere (px/s); how hard the finger pulls
// between the screens; the snap itself.
const double _leaveShare = 0.15;
const double _leaveFlick = 800;
const double _dragPull = 0.75;
final SpringDescription _snap = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 170,
);

/// Where the second screen starts and which screen the scroll last rested on.
class MagnetStop {
  double at = 0;
  bool onFirst = true;

  void settle(double pixels) {
    if (pixels <= 0) {
      onFirst = true;
    } else if (pixels >= at) {
      onFirst = false;
    }
  }
}

class MagnetScrollPhysics extends ScrollPhysics {
  const MagnetScrollPhysics(this.stop, {super.parent});

  final MagnetStop stop;

  @override
  MagnetScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      MagnetScrollPhysics(stop, parent: buildParent(ancestor));

  bool _between(ScrollMetrics m) => m.pixels > 0 && m.pixels < stop.at;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      _between(position)
      ? offset * _dragPull
      : super.applyPhysicsToUserOffset(position, offset);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final pixels = position.pixels;
    if (pixels >= stop.at && velocity < 0) {
      final fling = super.createBallisticSimulation(position, velocity);
      return fling == null ? null : _StopAt(fling, stop.at);
    }
    if (!_between(position)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final toward = stop.onFirst ? velocity : -velocity;
    final moved = stop.onFirst ? pixels : stop.at - pixels;
    // A flick back cancels a drag that went far enough.
    final leave =
        toward >= _leaveFlick ||
        (moved >= position.viewportDimension * _leaveShare &&
            toward > -_leaveFlick / 4);
    return ScrollSpringSimulation(
      _snap,
      pixels,
      stop.onFirst == leave ? stop.at : 0,
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}

/// A fling that ends dead at [limit] instead of flying past it.
class _StopAt extends Simulation {
  _StopAt(this._fling, this.limit) : super(tolerance: _fling.tolerance);

  final Simulation _fling;
  final double limit;

  @override
  double x(double time) {
    final at = _fling.x(time);
    return at < limit ? limit : at;
  }

  @override
  double dx(double time) => _fling.x(time) <= limit ? 0 : _fling.dx(time);

  @override
  bool isDone(double time) => _fling.isDone(time) || _fling.x(time) <= limit;
}
