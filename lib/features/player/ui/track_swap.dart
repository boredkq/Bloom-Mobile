/// The track change: the old layer leaves on top while the new one arrives
/// under it. Covers fade, captions slide; it isn't a setting.
///
/// The old layer is the widget of the last build: it's immutable and keeps that
/// moment's values, so nothing is copied by hand. Both surfaces slide the same
/// way: the direction comes from one place.
library;

import 'package:flutter/material.dart';

import '../track_swap_dir.dart';

/// One surface's timing and reach.
class TrackSwapTuning {
  const TrackSwapTuning({
    required this.dur,
    required this.fadeDur,
    required this.dist,
  });

  final Duration dur;

  /// Longer than the slide: nothing but opacity holds the eye here.
  final Duration fadeDur;

  /// How far a slide goes, of the layer's width.
  final double dist;

  static const player = TrackSwapTuning(
    dur: Duration(milliseconds: 420),
    fadeDur: Duration(milliseconds: 460),
    dist: 0.12,
  );

  /// A small box: a long slide reads as a jerk, so quicker and further.
  static const mini = TrackSwapTuning(
    dur: Duration(milliseconds: 300),
    fadeDur: Duration(milliseconds: 340),
    dist: 0.22,
  );
}

const Curve _slideEase = Cubic(0.22, 1, 0.36, 1);

/// Almost linear: on the slide curve 90% of a fade passed in the first 15% and
/// it read as an instant cut.
const Curve _fadeEase = Cubic(0.35, 0, 0.5, 1);

/// The arriving layer is opaque by this share of the time: otherwise the
/// background shows through both halfway and the frame darkens.
const double _fadeInShare = 0.55;

class TrackSwap extends StatefulWidget {
  const TrackSwap({
    super.key,
    required this.id,
    required this.child,
    this.fade = false,
    this.animated = true,
    this.tuning = TrackSwapTuning.player,
  });

  /// A new id starts the swap.
  final String? id;

  /// A cover fades; a caption slides.
  final bool fade;

  /// Off for what only looks like a track, a neighbour under a swipe.
  final bool animated;

  final TrackSwapTuning tuning;

  final Widget child;

  @override
  State<TrackSwap> createState() => _TrackSwapState();
}

class _TrackSwapState extends State<TrackSwap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this)
    ..addStatusListener((status) {
      // Taken off at the end: while there, the box carries an extra subtree.
      if (status == AnimationStatus.completed && _prev != null) {
        setState(() => _prev = null);
      }
    });

  /// The last build's id and content, updated without a new id as well: a cover
  /// can change by itself. Set in [initState]: a `late` initializer would first
  /// run in `didUpdateWidget`, with the new `widget`, and nothing would ever swap.
  String? _lastId;
  late Widget _lastChild;

  @override
  void initState() {
    super.initState();
    _lastId = widget.id;
    _lastChild = widget.child;
  }

  /// What's leaving now, and its id for the layer's key.
  Widget? _prev;
  String? _prevId;

  /// Backwards is mirrored.
  bool _back = false;

  @override
  void didUpdateWidget(TrackSwap old) {
    super.didUpdateWidget(old);
    if (widget.id == _lastId) {
      _lastChild = widget.child;
      return;
    }
    final from = _lastChild;
    final fromId = _lastId;
    final hadTrack = _lastId != null;
    _lastId = widget.id;
    _lastChild = widget.child;
    // Nothing to leave yet, or the finger draws the change itself: no layers.
    if (!widget.animated || !hadTrack || swapSilent) {
      _anim.stop();
      _prev = null;
      _prevId = null;
      return;
    }
    _prev = from;
    _prevId = fromId;
    _back = swapDir < 0;
    _anim
      ..duration = widget.fade ? widget.tuning.fadeDur : widget.tuning.dur
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  /// This frame's shift (of the width) and opacity; [incoming] is the arriving one.
  (double, double) _frame({required bool incoming}) {
    // At rest it stands whole; the wrappers stay, or coming and going they
    // would rebuild the subtree with its picture and marquee.
    if (_prev == null) return (0, 1);
    final value = _anim.value;
    if (widget.fade) {
      return (
        0,
        incoming
            ? _fadeEase.transform((value / _fadeInShare).clamp(0.0, 1.0))
            : 1 - _fadeEase.transform(value),
      );
    }
    final eased = _slideEase.transform(value);
    final dist = _back ? -widget.tuning.dist : widget.tuning.dist;
    // The new one comes from its side to zero, the old one leaves the other
    // way: both move in one direction.
    return (
      incoming ? dist * (1 - eased) : -dist * eased,
      incoming ? eased : 1 - eased,
    );
  }

  Widget _layer(Widget child, {required bool incoming}) {
    return AnimatedBuilder(
      animation: _anim,
      child: child,
      builder: (context, child) {
        final (shift, opacity) = _frame(incoming: incoming);
        return FractionalTranslation(
          translation: Offset(shift, 0),
          child: Opacity(opacity: opacity.clamp(0.0, 1.0), child: child!),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final prev = _prev;
    // Clipped to the box, since `Stack` sees only positioned children overflow
    // and the shift happens at paint: unclipped, a caption runs over the cover.
    // Always there: a wrapper that comes and goes rebuilds what's under it.
    return ClipRect(
      child: Stack(
        // `passthrough`: the current layer gets exactly the constraints the content
        // would, or a caption given a width collapses to its text. The old layer
        // goes in `Positioned.fill`: the current one holds the height.
        fit: StackFit.passthrough,
        children: [
          _layer(
            // A new track is a new layer, or Flutter updates the old one in place.
            KeyedSubtree(key: ValueKey(widget.id ?? '—'), child: widget.child),
            incoming: true,
          ),
          // The leaving one on top: fading, it reads as the new one appearing and
          // not as a flash. It takes no taps, the live buttons are under it.
          if (prev != null)
            Positioned.fill(
              child: _layer(
                IgnorePointer(
                  child: KeyedSubtree(
                    key: ValueKey('prev:$_prevId'),
                    child: prev,
                  ),
                ),
                incoming: false,
              ),
            ),
        ],
      ),
    );
  }
}
