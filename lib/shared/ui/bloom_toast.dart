/// Bloom's toasts: a kind icon, text, an Undo button and a visible countdown. A
/// glass capsule, with the countdown as a ring around the icon; the bar stays
/// only for the progress of long jobs ([ToastHandle.update]), where it shows a
/// share rather than time.
///
/// On top of `ScaffoldMessenger` because it already queues toasts, handles
/// swipes, clears with the screen and places them above the bottom bars. I take
/// only the look: the `SnackBar` itself is transparent and [BloomToastCard]
/// draws everything. The shell's bars live in `Scaffold.bottomNavigationBar`,
/// so a floating snack bar lands right above them.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'glass.dart';

/// Toast kind: sets the icon and the bar colour.
enum ToastKind { info, success, warn, error }

/// The button in a toast, usually Undo.
class ToastAction {
  const ToastAction({required this.fn, this.label, this.onExpire});

  final VoidCallback fn;

  /// Button text; Undo by default.
  final String? label;

  /// The toast went out with no press. For work I can't do right away while
  /// Undo is still possible, like deleting a cover file.
  final VoidCallback? onExpire;
}

/// How long a toast stays: plain and with a button.
const Duration _plain = Duration(milliseconds: 2000);
const Duration _withAction = Duration(milliseconds: 5000);

/// `ScaffoldMessenger` starts its timer after the toast slides in, so the bar
/// waits as long, or it runs ahead of the countdown.
const Duration _enter = Duration(milliseconds: 250);

/// A long toast lives until `close()`, but `SnackBar` wants a finite duration;
/// I give it more than any download takes.
const Duration _openEnded = Duration(minutes: 30);

/// How long the result stays after `finish()`.
const Duration _finished = Duration(milliseconds: 2400);

/// The app's messenger, for code with no `BuildContext`: playlist auto-update
/// runs from a timer and still has to report new tracks.
final GlobalKey<ScaffoldMessengerState> bloomMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

extension BloomToasts on ScaffoldMessengerState {
  /// Plain toast: text, kind icon and countdown. With [action] it lives longer
  /// and shows a button; unpressed, `action.onExpire` fires.
  void toast(
    String text, {
    ToastKind kind = ToastKind.info,
    ToastAction? action,
  }) {
    final duration = action == null ? _plain : _withAction;
    var used = false;
    late ScaffoldFeatureController<SnackBar, SnackBarClosedReason> entry;

    entry = _show(
      this,
      duration: duration,
      child: BloomToastCard(
        text: text,
        kind: kind,
        barDuration: duration,
        // The card fills in the default label: toasts come from timers too,
        // with no `BuildContext` here.
        actionLabel: action?.label,
        hasAction: action != null,
        onAction: action == null
            ? null
            : () {
                used = true;
                entry.close();
                action.fn();
              },
      ),
    );

    if (action?.onExpire != null) {
      // A swipe also counts as not pressing Undo: the decision stands.
      unawaited(
        entry.closed.then((_) {
          if (!used) action!.onExpire!.call();
        }),
      );
    }
  }

  /// A toast for work in progress: a spinner instead of the icon, no timer bar,
  /// lives until [ToastHandle.finish]. One toast that changes in place instead
  /// of Downloading then Downloaded.
  ///
  /// [content] replaces the whole card: the batch download toast watches its
  /// store and updates the count itself.
  ToastHandle busyToast(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
    Widget Function(ValueListenable<ToastView>)? content,
  }) {
    final view = ValueNotifier(
      ToastView(text: text, actionLabel: actionLabel, onAction: onAction),
    );
    final entry = _show(
      this,
      duration: _openEnded,
      child: content == null ? _LiveToast(view: view) : content(view),
    );
    return ToastHandle._(entry, view);
  }
}

/// Toast from a `BuildContext`, for places that don't need the messenger
/// separately.
void showToast(
  BuildContext context,
  String text, {
  ToastKind kind = ToastKind.info,
  ToastAction? action,
}) => ScaffoldMessenger.of(context).toast(text, kind: kind, action: action);

/// Live state of a toast: what [ToastHandle] changes on the fly.
class ToastView {
  const ToastView({
    required this.text,
    this.kind = ToastKind.info,
    this.busy = true,
    this.progress,
    this.barDuration,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final ToastKind kind;

  /// Spinner instead of the icon.
  final bool busy;

  /// Share 0..1 for the bottom bar; `null` means no progress bar.
  final double? progress;

  /// Countdown length; `null` means no countdown.
  final Duration? barDuration;

  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Handle of a live toast: [update] while working, [finish] at the end.
class ToastHandle {
  ToastHandle._(this._entry, this._view) {
    unawaited(_entry.closed.then((_) => _closed = true));
  }

  final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _entry;
  final ValueNotifier<ToastView> _view;
  bool _closed = false;
  Timer? _timer;

  /// Changes the text or progress without rebuilding the toast.
  void update(String text, {double? progress}) {
    if (_closed) return;
    _view.value = ToastView(
      text: text,
      progress: progress,
      actionLabel: _view.value.actionLabel,
      onAction: _view.value.onAction,
    );
  }

  /// Swaps in the result: the spinner gives way to the kind icon and countdown,
  /// and the toast goes out on its own after 2.4 s.
  void finish(String text, {ToastKind kind = ToastKind.success}) {
    if (_closed) return;
    _view.value = ToastView(
      text: text,
      kind: kind,
      busy: false,
      barDuration: _finished,
    );
    _timer?.cancel();
    _timer = Timer(_finished, close);
  }

  void close() {
    _timer?.cancel();
    if (_closed) return;
    _closed = true;
    _entry.close();
  }
}

/// Shows any widget as a snack bar with no look of its own.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _show(
  ScaffoldMessengerState messenger, {
  required Widget child,
  required Duration duration,
}) => messenger.showSnackBar(
  SnackBar(
    content: child,
    duration: duration,
    // The card does all the drawing: the snack bar has no background, shadow or
    // padding.
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    dismissDirection: DismissDirection.horizontal,
    shape: const RoundedRectangleBorder(),
  ),
);

class _LiveToast extends StatelessWidget {
  const _LiveToast({required this.view});

  final ValueListenable<ToastView> view;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: view,
    builder: (_, v, _) => BloomToastCard(
      text: v.text,
      kind: v.kind,
      busy: v.busy,
      progress: v.progress,
      barDuration: v.barDuration,
      actionLabel: v.actionLabel,
      onAction: v.onAction,
    ),
  );
}

/// The plate: a glass capsule, a kind icon with its countdown ring, text, a
/// pill button and, for long jobs only, a progress bar along the bottom.
class BloomToastCard extends StatelessWidget {
  const BloomToastCard({
    super.key,
    required this.text,
    this.kind = ToastKind.info,
    this.busy = false,
    this.progress,
    this.barDuration,
    this.actionLabel,
    this.hasAction = false,
    this.onAction,
  });

  final String text;
  final ToastKind kind;
  final bool busy;
  final double? progress;
  final Duration? barDuration;
  final String? actionLabel;

  /// There is a button but no label of its own, so it says Undo.
  final bool hasAction;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = kindColor(kind, t);
    final label = actionLabel ?? (hasAction ? context.l.commonUndo : null);
    final action = label != null && onAction != null;

    return _Pop(
      child: Align(
        // Width follows the content: a short message has no reason to span the
        // screen. The cap keeps the capsule from sprawling on a tablet.
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          // Own group: the toast floats above the page and its bars and can't
          // join their backdrop snapshot.
          child: GlassGroup(
            child: GlassBox(
              // A floating surface: the glass of sheets and menus, not of page
              // blocks.
              overlay: true,
              // `pill`, not `card`: on the dark theme `card` equals the
              // background and only the border would show.
              color: t.pill,
              shape: StadiumBorder(
                side: BorderSide(color: t.ovlLine2, width: 1),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      8,
                      action ? 8 : 18,
                      // Room for the progress bar only when there is one.
                      progress == null ? 8 : 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Badge(
                          color: color,
                          kind: kind,
                          busy: busy,
                          duration: barDuration,
                        ),
                        const SizedBox(width: 11),
                        Flexible(
                          child: Text(
                            text,
                            style: bloomText(
                              size: 13.5,
                              weight: 500,
                              color: t.text,
                              height: 1.3,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (action) ...[
                          const SizedBox(width: 10),
                          BloomTag(
                            text: label,
                            color: t.accent,
                            onTap: onAction!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (progress != null)
                    Positioned(
                      // Margins are a must: the capsule's rounding narrows the
                      // bottom and would clip a full-width bar.
                      left: 18,
                      right: 18,
                      bottom: 5,
                      child: BloomBar(
                        value: progress!,
                        color: color,
                        track: color.withValues(alpha: 0.14),
                        height: 3,
                        animated: const Duration(milliseconds: 250),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Entrance: the toast fades in and grows a little from the bottom edge. A
/// separate stateful widget because `_LiveToast` rebuilds the card on every
/// text update and this must not replay.
class _Pop extends StatefulWidget {
  const _Pop({required this.child});

  final Widget child;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
    child: ScaleTransition(
      scale: Tween(
        begin: 0.92,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
      alignment: Alignment.bottomCenter,
      child: widget.child,
    ),
  );
}

/// `info` takes the theme's accent, and `error` the shared danger red, so the
/// app has exactly one red.
Color kindColor(ToastKind kind, BloomTokens t) => switch (kind) {
  ToastKind.info => t.accent,
  ToastKind.success => const Color(0xFF2FBF6C),
  ToastKind.warn => const Color(0xFFE0A52E),
  ToastKind.error => t.danger,
};

/// Kind icon in a circle of its colour, with the countdown ring around it.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.kind,
    required this.busy,
    this.duration,
  });

  final Color color;
  final ToastKind kind;
  final bool busy;

  /// Time left to live; `null` means no ring (work in progress, or held until
  /// `close()`).
  final Duration? duration;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (duration != null)
          Positioned.fill(
            child: _Ring(color: color, duration: duration!),
          ),
        TintCircle(
          size: 27,
          color: color.withValues(alpha: 0.16),
          child: busy
              ? BloomSpinner(size: 15, color: color)
              // A bare tick for success: the icon already sits in a circle, and
              // a circle in a circle reads as a target.
              : kind == ToastKind.success
              ? BloomIcon(Bi.check, size: 18, color: color)
              : BloomIcon(_glyph(kind), size: 17, color: color),
        ),
      ],
    ),
  );

  static BloomGlyph _glyph(ToastKind kind) => switch (kind) {
    ToastKind.info => Bi.infoCircle,
    ToastKind.warn => Bi.danger,
    ToastKind.error => Bi.dangerCircle,
    ToastKind.success => Bi.check,
  };
}

/// Countdown ring: the arc drains clockwise over the toast's life. The start
/// waits for the entrance because the snack bar's timer does too.
class _Ring extends StatefulWidget {
  const _Ring({required this.color, required this.duration});

  final Color color;
  final Duration duration;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(_Ring old) {
    super.didUpdateWidget(old);
    // A result replaced the content, so the countdown restarts.
    if (widget.duration != old.duration) _run();
  }

  void _run() {
    _delay?.cancel();
    _c
      ..duration = widget.duration
      ..value = 0;
    _delay = Timer(_enter, () {
      if (mounted) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => CustomPaint(
      painter: _RingPainter(color: widget.color, left: 1 - _c.value),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.left});

  final Color color;

  /// Share of time left, 1 → 0.
  final double left;

  static const double _width = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - _width) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..strokeCap = StrokeCap.round;

    // Ring track: the same colour, barely visible, shows how much time has
    // gone.
    canvas.drawCircle(
      center,
      radius,
      paint..color = color.withValues(alpha: 0.14),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * left.clamp(0, 1),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.left != left || old.color != color;
}
