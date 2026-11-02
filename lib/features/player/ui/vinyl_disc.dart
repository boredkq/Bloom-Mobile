/// Vinyl: the spin and the label. One entry for all: the full player and
/// settings preview take them from here, so the preview can't diverge.
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// Vinyl spin: 10 s per turn, linear, endless. A pause doesn't rewind the disc:
/// `repeat()` after `stop()` continues from the controller's CURRENT value, so
/// the turn resumes at the same angle.
class VinylSpin extends StatefulWidget {
  const VinylSpin({
    super.key,
    required this.enabled,
    required this.spinning,
    required this.child,
    this.playing,
  });

  /// The vinyl is on screen. Off, the widget is an empty wrapper: an ordinary
  /// player needs no ticker.
  final bool enabled;

  /// Whether the disc spins right now. For the player that's only the FIRST
  /// frame: then the state arrives by the [playing] stream, which doesn't give
  /// a value at once.
  final bool spinning;

  /// Stream of whether sound plays. `null` leaves it to [spinning] (the
  /// settings preview has no sound).
  final Stream<bool>? playing;

  final Widget child;

  @override
  State<VinylSpin> createState() => _VinylSpinState();
}

class _VinylSpinState extends State<VinylSpin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(VinylSpin old) {
    super.didUpdateWidget(old);
    if (widget.enabled != old.enabled ||
        widget.spinning != old.spinning ||
        widget.playing != old.playing) {
      _listen();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _turn.dispose();
    super.dispose();
  }

  /// Player subscription. With the disc off both it and the ticker stop: an
  /// ordinary player needs no idle frames.
  void _listen() {
    _sub?.cancel();
    _sub = null;
    if (!widget.enabled) {
      _apply(false);
      return;
    }
    _apply(widget.spinning);
    final playing = widget.playing;
    if (playing != null) _sub = playing.listen(_apply);
  }

  void _apply(bool spinning) {
    if (!mounted || spinning == _turn.isAnimating) return;
    if (spinning) {
      _turn.repeat();
    } else {
      _turn.stop(canceled: false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.enabled
      ? RotationTransition(turns: _turn, child: widget.child)
      : widget.child;
}

/// Label in the disc's middle: a dark circle with a thin light ring near its
/// edge. The ring is white rather than a theme film: on the light theme that
/// film is black, and wouldn't show on a nearly black label.
class VinylLabel extends StatelessWidget {
  const VinylLabel({super.key, required this.size});

  /// Label diameter.
  final double size;

  /// Share of the disc's diameter the label takes.
  static const double share = 0.22;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          // The stops are measured from the centre to the box's FAR CORNER,
          // while Flutter's radius is a share of the width. Hence 0.707, half a
          // square's diagonal.
          radius: 0.707,
          colors: [
            Color(0xFF111111),
            Color(0xFF222222),
            Color(0x1AFFFFFF),
            Color(0x08FFFFFF),
            Color(0xFF1A1A1A),
          ],
          stops: [0.30, 0.58, 0.60, 0.62, 0.64],
        ),
      ),
    ),
  );
}
