/// A row that can be swiped aside. A rounded plate comes out from under the
/// row, exactly as wide as the swipe, with the action icon centred; red for
/// delete, quiet `pill` for the rest.
///
/// One threshold everywhere ([kSwipeThreshold] of the row width, or a fast
/// fling). Below it the plate is dim; past it the icon grows and the phone
/// gives a short buzz. Delete carries the row off the edge before calling the
/// handler; other actions fire at once and the row returns, since queueing
/// removes nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../app/theme/tokens.dart';
import 'bloom_icon.dart';

/// Share of the row width after which the action fires.
const double kSwipeThreshold = 0.32;

/// A fling faster than this fires with no threshold.
const double _flingVelocity = 900;

const Duration _snapBack = Duration(milliseconds: 220);
const Duration _flyOut = Duration(milliseconds: 160);

/// Plate of one direction.
@immutable
class SwipePanel {
  const SwipePanel({
    required this.icon,
    required this.onFire,
    this.danger = false,
    this.dismiss = false,
  });

  final BloomGlyph icon;

  final VoidCallback onFire;

  /// A red plate, for deleting.
  final bool danger;

  /// The row slides off the edge because it's about to go; otherwise it
  /// returns.
  final bool dismiss;
}

class SwipeRow extends StatefulWidget {
  const SwipeRow({super.key, required this.child, this.left, this.right});

  /// Plate coming out on the LEFT, a right swipe. `null` means the row doesn't
  /// move that way.
  final SwipePanel? left;

  /// Plate on the right, a left swipe.
  final SwipePanel? right;

  final Widget child;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow>
    with SingleTickerProviderStateMixin {
  /// Set up in [initState], not lazily: a row never swiped would first touch it
  /// in `dispose()`, and `vsync` reaches for `TickerMode` in a dead context and
  /// crashes the disposal.
  late final AnimationController _anim;

  Animation<double>? _slide;

  /// Row offset in pixels; positive is right.
  double _offset = 0;

  /// Past the threshold: the icon grew and letting go will fire.
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _snapBack)
      ..addListener(_onTick);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onTick() {
    final slide = _slide;
    if (slide == null) return;
    setState(() => _offset = slide.value);
  }

  /// The plate showing now, or due to come out on this side.
  SwipePanel? _panelFor(double offset) =>
      offset > 0 ? widget.left : (offset < 0 ? widget.right : null);

  void _update(DragUpdateDetails d, double width) {
    _anim.stop();
    var next = _offset + d.delta.dx;
    // The row doesn't go where there's no action: an empty plate looks broken.
    if (next > 0 && widget.left == null) next = 0;
    if (next < 0 && widget.right == null) next = 0;
    final armed = next.abs() >= width * kSwipeThreshold;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _offset = next.clamp(-width, width);
      _armed = armed;
    });
  }

  void _end(DragEndDetails d, double width) {
    final panel = _panelFor(_offset);
    final velocity = d.primaryVelocity ?? 0;
    final flung =
        velocity.abs() > _flingVelocity && velocity.sign == _offset.sign;
    if (panel == null || !(_armed || flung)) {
      _animateTo(0, _snapBack);
      return;
    }
    if (!panel.dismiss) {
      panel.onFire();
      _animateTo(0, _snapBack);
      return;
    }
    _animateTo(_offset.sign * width, _flyOut).then((_) {
      if (!mounted) return;
      // I clear the offset BEFORE removing: the list isn't animated, and this
      // row's element goes to the next track, which mustn't stay shifted.
      setState(() {
        _offset = 0;
        _armed = false;
      });
      panel.onFire();
    });
  }

  Future<void> _animateTo(double target, Duration duration) {
    _slide = Tween<double>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.duration = duration;
    if (target == 0) _armed = false;
    return _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.left == null && widget.right == null) return widget.child;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final panel = _panelFor(_offset);
        return GestureDetector(
          // Tap and long press stay with the row; this detector catches only
          // horizontal movement.
          onHorizontalDragUpdate: (d) => _update(d, width),
          onHorizontalDragEnd: (d) => _end(d, width),
          onHorizontalDragCancel: () => _animateTo(0, _snapBack),
          child: Stack(
            children: [
              if (panel != null)
                Positioned.fill(
                  child: _Panel(
                    panel: panel,
                    extent: _offset.abs(),
                    fromLeft: _offset > 0,
                    armed: _armed,
                  ),
                ),
              Transform.translate(
                offset: Offset(_offset, 0),
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The plate itself: grows from the edge after the finger, with the icon
/// centred.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.panel,
    required this.extent,
    required this.fromLeft,
    required this.armed,
  });

  final SwipePanel panel;
  final double extent;
  final bool fromLeft;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    // The icon appears once the plate has room for it, or it would crawl out
    // clipped from the first millimetre.
    final show = ((extent - 16) / 40).clamp(0.0, 1.0);
    return Align(
      alignment: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: SizedBox(
        width: extent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(t.radius * 0.85),
          child: ColoredBox(
            color: panel.danger ? t.danger : t.pill,
            child: Center(
              child: Opacity(
                opacity: show,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 140),
                  scale: armed ? 1.15 : 1,
                  child: BloomIcon(
                    panel.icon,
                    size: 22,
                    color: panel.danger ? Colors.white : t.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
