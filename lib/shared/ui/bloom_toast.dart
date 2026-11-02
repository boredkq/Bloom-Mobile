/// Bloom's toasts: a one-line capsule at the top centre, always the same height,
/// with the kind's icon in a circle; the ring around it runs out over the
/// toast's life. A long text is cut, not wrapped. Messages wait their turn in a
/// queue (the same text twice in a row shows once). A tap takes it away at once;
/// held, it stops running out and can be swiped up and away, or springs back.
///
/// Between messages it shows long jobs ([Toaster.busy]): a spinner in the badge,
/// the ring filling with the share done, "N/M" and ✕ that stops it. A job stays
/// until it's over, then shows its result in place. A message comes over the job
/// for its life.
///
/// [ToastHost] draws it above every route, so sheets and the full player don't
/// cover it, and [toaster] needs no `BuildContext`: a toast may come from a timer
/// or from a sheet that has already closed.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'glass.dart';

/// Toast kind: sets the icon and the colour.
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

/// How long a toast stays: plain, with a button, and a long job's result.
const Duration _plain = Duration(milliseconds: 2000);
const Duration _withAction = Duration(milliseconds: 5000);
const Duration _result = Duration(milliseconds: 6000);

/// The next message comes once this one has faded out.
const Duration _gap = Duration(milliseconds: 300);

/// A job that fell over never says it's done, and the toast mustn't stay for
/// good; I give it more than any download takes.
const Duration _jobLimit = Duration(minutes: 30);

const double _height = 46;
const double _pad = 4;
const double _badge = 38;
const double _side = 12;
const double _top = 8;
const double _maxWidth = 520;
const double _jobWidth = 400;

/// Hidden, it sits a touch higher and smaller, and springs in.
const Curve _spring = Cubic(0.34, 1.4, 0.64, 1);

/// Fast upward flick that takes the toast away, in px per second.
const double _flick = 500;

/// Toasts from anywhere; [ToastHost] draws them. With no host, as in store tests,
/// nothing shows.
final Toaster toaster = Toaster._();

class Toaster {
  Toaster._();

  _ToastHostState? _host;

  /// The host's context, for code that has none: it lives as long as the app.
  BuildContext? get context => _host?.context;

  /// Plain toast: text, kind icon and countdown. With [action] it lives longer
  /// and shows a button; unpressed, `action.onExpire` fires.
  void show(
    String text, {
    ToastKind kind = ToastKind.info,
    ToastAction? action,
  }) => _host?._request(
    _Face(
      ToastView(text: text, kind: kind, busy: false),
      action: action,
      life: action == null ? _plain : _withAction,
    ),
  );

  /// A toast for a job: lives until [ToastHandle.finish]. One toast that changes
  /// in place instead of Downloading then Downloaded.
  ///
  /// [live] makes it a long job watching its store for the view it shows: a fixed
  /// width with a count and ✕.
  ToastHandle busy(String text, {ToastLive? live}) {
    final face = _Face(ToastView(text: text), live: live);
    _host?._addJob(face);
    return ToastHandle._(face, long: live != null);
  }
}

/// What a long job shows now, read from its store.
typedef ToastLive =
    ToastView Function(BuildContext context, WidgetRef ref, ToastView view);

/// What a toast shows.
class ToastView {
  const ToastView({
    required this.text,
    this.kind = ToastKind.info,
    this.busy = true,
    this.share,
    this.count,
    this.onStop,
    this.stopLabel,
  });

  final String text;
  final ToastKind kind;

  /// Spinner instead of the icon.
  final bool busy;

  /// Share 0..1 the ring fills to; `null` means it isn't known.
  final double? share;

  /// "N/M" by the ✕. It changes all the time, so the capsule's width is fixed.
  final String? count;

  /// ✕ that stops the job.
  final VoidCallback? onStop;
  final String? stopLabel;
}

/// Handle of a job: [update] while working, [finish] at the end.
class ToastHandle {
  ToastHandle._(this._face, {required bool long}) : _long = long;

  final _Face _face;

  /// A long job's result stays longer, with a full ring and ✕.
  bool _long;
  bool _over = false;

  /// Changes the text or share in place.
  void update(String text, {double? share}) {
    if (_over) return;
    if (share != null) _long = true;
    _face.view = ToastView(text: text, share: share);
    toaster._host?._refresh();
  }

  /// Swaps in the result: the spinner gives way to the kind icon.
  void finish(String text, {ToastKind kind = ToastKind.success}) {
    if (_over) return;
    _over = true;
    toaster._host?._finish(
      _face,
      _Face(
        ToastView(text: text, kind: kind, busy: false, share: _long ? 1 : null),
        life: _long ? _result : _plain,
        held: _long,
      ),
    );
  }
}

/// One toast in the host: a message, a job or a job's result.
class _Face {
  _Face(this.view, {this.action, this.live, this.life, this.held = false});

  ToastView view;
  final ToastAction? action;
  final ToastLive? live;

  /// `null` for a job: it lives until it's over.
  final Duration? life;

  /// A long job's result: the ring stays full, ✕ closes it.
  final bool held;

  /// The button was pressed, so `onExpire` doesn't fire.
  bool used = false;

  /// A job's [_jobLimit].
  Timer? limit;
}

/// Draws the toasts over [child]: goes right above the navigator.
class ToastHost extends StatefulWidget {
  const ToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost> with TickerProviderStateMixin {
  final List<_Face> _queue = [];
  final List<_Face> _jobs = [];
  _Face? _msg;

  /// What was up last: it stays on the plate while it fades out.
  _Face? _last;

  Timer? _gapTimer;
  bool _flying = false;
  bool _pressed = false;

  /// The drag's raw offset: down it gives only a little, see [_onDrag].
  double _dragRaw = 0;

  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addStatusListener(_onIn);

  late final Animation<double> _sprung = CurvedAnimation(
    parent: _in,
    curve: _spring,
    reverseCurve: _spring.flipped,
  );

  /// A message's life, 0 → 1. It stands still while held.
  late final AnimationController _life = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _close();
    });

  /// The swipe's offset; up is negative.
  late final AnimationController _dragY = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    toaster._host = this;
  }

  @override
  void dispose() {
    if (toaster._host == this) toaster._host = null;
    _gapTimer?.cancel();
    for (final job in _jobs) {
      job.limit?.cancel();
    }
    _in.dispose();
    _life.dispose();
    _dragY.dispose();
    super.dispose();
  }

  bool get _busyNow =>
      _msg != null || _flying || (_gapTimer?.isActive ?? false);

  void _request(_Face face) {
    // A second Undo undoes something else, so only plain ones merge.
    if (face.action == null) {
      final last = _queue.isNotEmpty ? _queue.last : _msg;
      if (last != null &&
          last.action == null &&
          last.view.text == face.view.text &&
          last.view.kind == face.view.kind) {
        return;
      }
    }
    _busyNow ? _queue.add(face) : _present(face);
  }

  void _present(_Face face) {
    _dragY
      ..stop()
      ..value = 0;
    _msg = face;
    _life
      ..duration = face.life
      ..value = 0;
    if (!_pressed) unawaited(_life.forward());
    _refresh();
  }

  void _addJob(_Face job) {
    _jobs.add(job);
    job.limit = Timer(_jobLimit, () {
      _jobs.remove(job);
      _refresh();
    });
    _refresh();
  }

  /// A job on top turns into its result in place; otherwise the result waits for
  /// its turn like any message.
  void _finish(_Face job, _Face result) {
    final onTop = _msg == null && !_flying && _jobs.lastOrNull == job;
    job.limit?.cancel();
    _jobs.remove(job);
    onTop || !_busyNow ? _present(result) : _queue.add(result);
    _refresh();
  }

  /// [fly]: swiped away, it leaves upwards from where it was let go.
  void _close({bool fly = false}) {
    if (_msg == null || _flying) return;
    _life.stop();
    if (!fly) {
      _gone();
      return;
    }
    _flying = true;
    final out = _top + MediaQuery.paddingOf(context).top + _height + 8;
    unawaited(
      _dragY
          .animateTo(
            -out,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .then((_) => _gone()),
    );
  }

  void _gone() {
    final face = _msg;
    _msg = null;
    _flying = false;
    if (face != null && !face.used) face.action?.onExpire?.call();
    // The job is under it: it comes back down.
    if (_jobs.isNotEmpty) _springBack();
    _refresh();
    _gapTimer?.cancel();
    _gapTimer = Timer(_gap, () {
      if (_msg == null && _queue.isNotEmpty) _present(_queue.removeAt(0));
    });
  }

  void _springBack() => unawaited(
    _dragY.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
    ),
  );

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    final shown = _msg != null || _jobs.isNotEmpty;
    if (shown && _in.status != AnimationStatus.forward && !_in.isCompleted) {
      unawaited(_in.forward());
    } else if (!shown && _in.status != AnimationStatus.reverse) {
      unawaited(_in.reverse());
    }
  }

  void _onIn(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    _dragY.value = 0;
    setState(() => _last = null);
  }

  /// Only a message or a result can be touched: a running job stays put.
  bool get _touchable => _msg != null && !_flying;

  void _onPress(bool pressed) {
    if (pressed && !_touchable) return;
    setState(() => _pressed = pressed);
    if (pressed) {
      _life.stop();
      _dragY.stop();
    } else if (_touchable) {
      unawaited(_life.forward());
    }
  }

  void _onDrag(DragUpdateDetails d) {
    _dragRaw += d.delta.dy;
    _dragY.value = _dragRaw < 0 ? _dragRaw : _dragRaw / 4;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragY.value < -_height / 2 || (d.primaryVelocity ?? 0) < -_flick) {
      _close(fly: true);
    } else {
      _springBack();
    }
  }

  void _press(_Face face) {
    face.used = true;
    _close();
    face.action!.fn();
  }

  @override
  Widget build(BuildContext context) {
    // The job begun last: what the user just asked for shows at once.
    final face = _msg ?? _jobs.lastOrNull ?? _last;
    _last = face;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (face != null && !_in.isDismissed)
          Positioned(
            top: MediaQuery.paddingOf(context).top + _top,
            left: _side,
            right: _side,
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1,
              child: _frame(face),
            ),
          ),
      ],
    );
  }

  Widget _frame(_Face face) => AnimatedBuilder(
    animation: Listenable.merge([_in, _dragY]),
    builder: (_, child) {
      final t = _sprung.value;
      // It fades as it's swiped up.
      final swiped = 1 - (-_dragY.value / (2 * _height)).clamp(0.0, 1.0);
      return Opacity(
        opacity: (_in.value * swiped).clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, _dragY.value - 10 * (1 - t)),
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
      );
    },
    child: Listener(
      onPointerDown: (_) => _onPress(true),
      onPointerUp: (_) => _onPress(false),
      onPointerCancel: (_) => _onPress(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _touchable ? _close : null,
        onVerticalDragStart: _touchable ? (_) => _dragRaw = _dragY.value : null,
        onVerticalDragUpdate: _touchable ? _onDrag : null,
        onVerticalDragEnd: _touchable ? _onDragEnd : null,
        onVerticalDragCancel: _touchable ? _springBack : null,
        // Held, it gives a little.
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Consumer(
              builder: (context, ref, _) {
                final live = face.live;
                return ToastCard(
                  view: live == null
                      ? face.view
                      : live(context, ref, face.view),
                  countdown: face.life == null || face.held ? null : _life,
                  action: face.action,
                  onAction: face.action == null ? null : () => _press(face),
                  onClose: face.held ? _close : null,
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// The plate: a capsule with the kind's badge, one line of text, and a button
/// or, for a long job, the count and ✕.
class ToastCard extends StatelessWidget {
  const ToastCard({
    super.key,
    required this.view,
    this.countdown,
    this.action,
    this.onAction,
    this.onClose,
  });

  final ToastView view;

  /// The toast's life running 0 → 1; `null` means the ring doesn't run out.
  final Animation<double>? countdown;
  final ToastAction? action;
  final VoidCallback? onAction;

  /// ✕ of a long job's result.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = kindColor(view.kind, t);
    final count = view.count;
    final stop = view.onStop ?? onClose;
    final button = action != null && onAction != null;
    final screen = MediaQuery.sizeOf(context).width - 2 * _side;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Badge(
          color: color,
          kind: view.kind,
          busy: view.busy,
          share: view.share,
          countdown: countdown,
        ),
        const SizedBox(width: 10),
        Flexible(
          fit: stop == null ? FlexFit.loose : FlexFit.tight,
          child: Text(
            view.text,
            style: bloomText(size: 15, weight: 500, color: t.text),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (button) ...[
          const SizedBox(width: 8),
          BloomTag(
            text: action!.label ?? context.l.commonUndo,
            color: t.accent,
            size: 14,
            vertical: 8,
            onTap: onAction,
          ),
        ],
        if (count != null) ...[
          const SizedBox(width: 8),
          Text(
            count,
            style: bloomText(
              size: 14,
              weight: 400,
              color: t.text2,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
        if (stop != null) ...[
          const SizedBox(width: 4),
          CircleIconButton(
            icon: Bi.close,
            size: _badge,
            iconSize: 17,
            background: Colors.transparent,
            color: t.text2,
            label: view.stopLabel ?? context.l.commonClose,
            onTap: stop,
          ),
        ],
      ],
    );

    // Own group: the toast floats above everything and can't join their
    // backdrop snapshot.
    return GlassGroup(
      child: GlassBox(
        overlay: true,
        color: t.pill,
        shape: const StadiumBorder(),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            height: _height,
            // A long job's width is fixed: the changing count would make it jump.
            width: stop == null ? null : math.min(_jobWidth, screen),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(_maxWidth, screen),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _pad,
                  _pad,
                  button || stop != null ? _pad : 18,
                  _pad,
                ),
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `info` takes the theme's accent, and `error` the shared danger red, so the
/// app has exactly one red.
Color kindColor(ToastKind kind, BloomTokens t) => switch (kind) {
  ToastKind.info => t.accent,
  ToastKind.success => const Color(0xFF2FBF6C),
  ToastKind.warn => const Color(0xFFE0A52E),
  ToastKind.error => t.danger,
};

/// Kind icon in a circle of its colour, with the ring around it: time left, or
/// a job's share done.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.kind,
    required this.busy,
    this.share,
    this.countdown,
  });

  final Color color;
  final ToastKind kind;
  final bool busy;
  final double? share;
  final Animation<double>? countdown;

  @override
  Widget build(BuildContext context) {
    final life = countdown;
    return SizedBox.square(
      dimension: _badge,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: life != null
                ? AnimatedBuilder(
                    animation: life,
                    builder: (_, _) => _ring(1 - life.value),
                  )
                : TweenAnimationBuilder<double>(
                    tween: Tween(end: share ?? 0),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutQuad,
                    builder: (_, value, _) => _ring(value),
                  ),
          ),
          TintCircle(
            size: 29,
            color: color.withValues(alpha: 0.16),
            child: busy
                ? BloomSpinner(
                    size: 16,
                    color: color,
                    trackColor: color.withValues(alpha: 0.22),
                  )
                : BloomIcon(
                    _glyph(kind),
                    size: kind == ToastKind.success ? 20 : 19,
                    color: color,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double filled) => CustomPaint(
    painter: _RingPainter(color: color, filled: filled),
  );

  static BloomGlyph _glyph(ToastKind kind) => switch (kind) {
    ToastKind.info => Bi.infoCircle,
    ToastKind.warn => Bi.danger,
    ToastKind.error => Bi.dangerCircle,
    ToastKind.success => Bi.check,
  };
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.filled});

  final Color color;

  /// Share of the ring drawn, 0..1.
  final double filled;

  static const double _width = 2.8;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - _width) / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(
      center,
      radius,
      paint..color = color.withValues(alpha: 0.14),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * filled.clamp(0, 1),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.filled != filled || old.color != color;
}
