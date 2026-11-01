import 'package:flutter/widgets.dart';

/// Base of every button: taps and the press-in, 0.94 over 120 ms.
/// Wrap the whole button, plate included — whatever is outside doesn't
/// press. Bigger things press less (cards 0.97, menu rows 0.98), track rows and
/// segments not at all.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.94,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final HitTestBehavior behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutQuad,
    reverseCurve: Curves.easeInQuad,
  );
  bool _down = false;

  // A quick tap reports down and up at once, so the press always plays in
  // full before it comes back — otherwise a tap shows nothing.
  void _press() {
    _down = true;
    _c.forward().then((_) {
      if (!_down && mounted) _c.reverse();
    });
  }

  void _release() {
    _down = false;
    if (!_c.isAnimating) _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: live ? (_) => _press() : null,
      onTapUp: live ? (_) => _release() : null,
      onTapCancel: live ? _release : null,
      child: widget.scale == 1
          ? widget.child
          : AnimatedBuilder(
              animation: _t,
              builder: (_, child) => Transform.scale(
                scale: 1 - (1 - widget.scale) * _t.value,
                child: child,
              ),
              child: widget.child,
            ),
    );
  }
}
