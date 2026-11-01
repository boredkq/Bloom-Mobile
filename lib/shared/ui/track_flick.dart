/// Horizontal gesture to flick tracks, in the mini player and the full player.
/// Unlike [SwipeRow] nothing stays under the finger: no plates, the content
/// slides off, the action fires and the new content arrives from the opposite
/// edge.
///
/// The caller decides what moves: [builder] gets the shift (−1…1) and wraps
/// just that part in [FlickSlide].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Share of the width after which letting go flicks the track.
const double kFlickThreshold = 0.22;

const double _flingVelocity = 700;
const Duration _out = Duration(milliseconds: 150);
const Duration _back = Duration(milliseconds: 240);
const Duration _snap = Duration(milliseconds: 200);

/// Where the new track enters from, short of the edge: a full pass reads as a
/// jerk.
const double _enterFrom = 0.55;

class TrackFlick extends StatefulWidget {
  const TrackFlick({
    super.key,
    required this.builder,
    this.onLeft,
    this.onRight,
    this.shift,
    this.carousel = false,
    this.enabled = true,
    this.behavior,
  });

  /// Swipe left. `null` means the content doesn't move that way.
  final VoidCallback? onLeft;

  /// Swipe right.
  final VoidCallback? onRight;

  /// A shift from outside instead of my own. For the mini player's carousel:
  /// the neighbours at the edges follow the finger too, in a layer outside this
  /// widget. Whoever gave it disposes it.
  final ValueNotifier<double>? shift;

  /// Carousel: the neighbour ALREADY waits at the edge and comes to the centre
  /// by itself. The usual mode slides off and brings new content in from the
  /// other side. Here after the change the shift just resets: the arrived card
  /// is the new centre, and an entrance on top would read as a bounce.
  final bool carousel;

  /// Whether to listen to the finger. `false` removes the recognizer WITHOUT
  /// changing the tree's shape. Nulling the handlers won't do: [build] then
  /// takes another branch and everything rebuilds from scratch.
  final bool enabled;

  /// How to catch the finger. `deferToChild` by default, only where content
  /// draws. The full player needs `opaque`: there's no content between its
  /// blocks, and the gesture would fall through to the panel below.
  final HitTestBehavior? behavior;

  final Widget Function(BuildContext context, ValueListenable<double> shift)
  builder;

  @override
  State<TrackFlick> createState() => _TrackFlickState();
}

class _TrackFlickState extends State<TrackFlick>
    with SingleTickerProviderStateMixin {
  /// The shift I hold myself when none is given.
  ValueNotifier<double>? _own;

  late final ValueNotifier<double> _shift;

  /// Set up in [initState], not lazily: a cover never flicked would first touch
  /// it in `dispose()`, and `vsync` reaches for `TickerMode` in a dead context
  /// and crashes the disposal.
  late final AnimationController _anim;

  Animation<double>? _slide;

  @override
  void initState() {
    super.initState();
    _shift = widget.shift ?? (_own = ValueNotifier<double>(0));
    _anim = AnimationController(vsync: this, duration: _snap)
      ..addListener(() => _shift.value = _slide?.value ?? 0);
  }

  @override
  void didUpdateWidget(TrackFlick old) {
    super.didUpdateWidget(old);
    // The gesture was removed under the finger (the panel started expanding),
    // and the recognizer left with it, so nobody will report the release. I
    // reset the shift myself or the content stays shifted.
    if (old.enabled && !widget.enabled && _shift.value != 0) {
      _animateTo(0, _snap);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _own?.dispose();
    super.dispose();
  }

  Future<void> _animateTo(double target, Duration duration) {
    _slide = Tween<double>(
      begin: _shift.value,
      end: target,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.duration = duration;
    return _anim.forward(from: 0);
  }

  void _update(DragUpdateDetails d, double width) {
    if (width <= 0) return;
    _anim.stop();
    var next = _shift.value + d.delta.dx / width;
    if (next < 0 && widget.onLeft == null) next = 0;
    if (next > 0 && widget.onRight == null) next = 0;
    _shift.value = next.clamp(-1.0, 1.0);
  }

  Future<void> _end(DragEndDetails d, double width) async {
    final value = _shift.value;
    final velocity = width <= 0 ? 0.0 : (d.primaryVelocity ?? 0);
    final flung =
        velocity.abs() > _flingVelocity && velocity.sign == value.sign;
    final action = value < 0 ? widget.onLeft : widget.onRight;
    if (action == null || !(value.abs() >= kFlickThreshold || flung)) {
      await _animateTo(0, _snap);
      return;
    }
    // Slide to the edge, change the track, bring the new one in from the other
    // side: the swap lands on the frame when the old one is out of sight.
    await _animateTo(value.sign, _out);
    if (!mounted) return;
    action();
    // In a carousel this shift already put the neighbour dead centre, so
    // there's nothing to bring in.
    if (widget.carousel) {
      _shift.value = 0;
      return;
    }
    _shift.value = -value.sign * _enterFrom;
    await _animateTo(0, _back);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onLeft == null && widget.onRight == null) {
      return widget.builder(context, _shift);
    }
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final on = widget.enabled;
        return GestureDetector(
          behavior: widget.behavior,
          onHorizontalDragUpdate: on ? (d) => _update(d, width) : null,
          onHorizontalDragEnd: on ? (d) => _end(d, width) : null,
          onHorizontalDragCancel: on ? () => _animateTo(0, _snap) : null,
          child: widget.builder(context, _shift),
        );
      },
    );
  }
}

/// The part that follows the finger in a CAROUSEL ([TrackFlick.carousel]):
/// shift in PIXELS with no fade. [FlickSlide] fails here twice: a share of its
/// own width misses the carousel's step (there's a gap between cards), and a
/// fade would dim what's being pulled in, while the neighbours are opaque.
class CarouselSlide extends StatelessWidget {
  const CarouselSlide({
    super.key,
    required this.shift,
    required this.stride,
    required this.child,
  });

  /// Shift share from [TrackFlick], of the card width.
  final ValueListenable<double> shift;

  /// Carousel step in pixels: card width plus the gap, so a full shift (1)
  /// swaps the neighbour exactly into the centre.
  final double stride;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: shift,
      child: child,
      builder: (context, value, child) =>
          Transform.translate(offset: Offset(value * stride, 0), child: child),
    );
  }
}

/// The part that follows the finger: a shift as a share of ITS OWN width, plus
/// a fade.
class FlickSlide extends StatelessWidget {
  const FlickSlide({
    super.key,
    required this.shift,
    required this.child,
    this.amplitude = 1,
  });

  /// Shift share from [TrackFlick].
  final ValueListenable<double> shift;

  /// How strongly this part responds: the cover moves fully, the captions below
  /// much less, or they outrun it at the edge.
  final double amplitude;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: shift,
      child: child,
      builder: (context, value, child) => FractionalTranslation(
        translation: Offset(value * amplitude, 0),
        child: Opacity(
          opacity: (1 - value.abs() * 1.2).clamp(0.0, 1.0),
          child: child,
        ),
      ),
    );
  }
}
