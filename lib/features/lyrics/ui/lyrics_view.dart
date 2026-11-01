/// The lyrics of the playing track: the line being
/// sung stands in the middle, lit as a whole; a tap on another line goes there.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../player/player_controller.dart';
import '../lyrics_store.dart';

/// Sizes of one surface. Over the cover they're centred; in
/// the cover's place the box is the screen's width, so the lines are larger
/// and go to the left edge, with the gap between lines rather than inside a
/// wrapped one.
class LyricsLayout {
  const LyricsLayout({
    required this.fontSize,
    required this.activeSize,
    required this.align,
    required this.lineHeight,
    required this.gap,
    required this.introPad,
  });

  static const overlay = LyricsLayout(
    fontSize: 16,
    activeSize: 19,
    align: TextAlign.center,
    lineHeight: 1.75,
    gap: 1,
    introPad: 6,
  );

  static const replace = LyricsLayout(
    fontSize: 21,
    activeSize: 25,
    align: TextAlign.left,
    lineHeight: 1.35,
    gap: 11,
    introPad: 11,
  );

  final double fontSize;
  final double activeSize;
  final TextAlign align;
  final double lineHeight;
  final double gap;
  final double introPad;

  Alignment get origin =>
      align == TextAlign.left ? Alignment.centerLeft : Alignment.center;
}

// Colours by role, as fractions of the text colour.
const double _next = 0.45;
const double _past = 0.15;
const double _plain = 0.6;
const double _status = 0.25;

class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({
    super.key,
    this.live = true,
    this.padding = const EdgeInsets.fromLTRB(14, 36, 14, 16),
    this.layout = LyricsLayout.overlay,
  });

  /// Only a surface on screen scrolls and breathes.
  final bool live;
  final EdgeInsets padding;
  final LyricsLayout layout;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  double? _height;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (widget.live && !old.live) _center(animated: false);
  }

  /// The sung line in the middle, the intro dots before the first one. After
  /// the frame: the line has taken its active size by then.
  void _center({required bool animated}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.live) return;
      final ctx = _keys[ref.read(lyricsLineProvider)]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: animated ? const Duration(milliseconds: 520) : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    });
  }

  GlobalKey _key(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final state = ref.watch(lyricsProvider);
    final current = ref.watch(lyricsLineProvider);
    final lay = widget.layout;

    ref.listen(lyricsLineProvider, (_, _) => _center(animated: true));
    ref.listen(lyricsProvider.select((s) => s.lines), (_, _) {
      _keys.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _center(animated: false);
    });

    final lines = state.lines;
    final children = <Widget>[
      if (state.status != LyricsStatus.ready)
        Text(
          state.status == LyricsStatus.empty
              ? l.lyricsNotFound
              : l.lyricsLoading,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: t.text.withValues(alpha: _status),
          ),
        )
      else if (lines.isNotEmpty) ...[
        _IntroDots(
          key: _key(-1),
          until: lines.first.time,
          live: widget.live,
          layout: lay,
        ),
        for (var i = 0; i < lines.length; i++)
          _Line(
            key: _key(i),
            text: lines[i].text,
            active: i == current,
            color: i == current
                ? t.text
                : t.text.withValues(alpha: i == current + 1 ? _next : _past),
            layout: lay,
            onTap: i == current
                ? null
                : () => ref
                      .read(playbackProvider.notifier)
                      .seek(
                        Duration(milliseconds: (lines[i].time * 1000).round()),
                      ),
          ),
      ] else
        // Plain text: no times, nothing to follow.
        for (final row in state.plain.split('\n'))
          _Line(
            text: row.trim().isEmpty ? ' ' : row.trim(),
            active: false,
            color: t.text.withValues(alpha: _plain),
            layout: lay,
          ),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        if (_height != box.maxHeight) {
          _height = box.maxHeight;
          _center(animated: false);
        }
        return SingleChildScrollView(
          controller: _scroll,
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
      },
    );
  }
}

/// One line. The sung one is larger and bold; growing into that size and back
/// is a scale from the old size, the layout taking the new one at once.
class _Line extends StatefulWidget {
  const _Line({
    super.key,
    required this.text,
    required this.active,
    required this.color,
    required this.layout,
    this.onTap,
  });

  final String text;
  final bool active;
  final Color color;
  final LyricsLayout layout;
  final VoidCallback? onTap;

  @override
  State<_Line> createState() => _LineState();
}

class _LineState extends State<_Line> with SingleTickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  double _from = 1;

  @override
  void didUpdateWidget(_Line old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      final lay = widget.layout;
      _from = widget.active
          ? lay.fontSize / lay.activeSize
          : lay.activeSize / lay.fontSize;
      _grow.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lay = widget.layout;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        selected: widget.active,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: lay.gap),
          child: AnimatedBuilder(
            animation: _grow,
            builder: (context, child) => Transform.scale(
              scale:
                  _from +
                  (1 - _from) * Curves.easeOutQuad.transform(_grow.value),
              alignment: lay.origin,
              child: child,
            ),
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: widget.color),
              duration: const Duration(milliseconds: 300),
              builder: (context, color, _) => Text(
                widget.text,
                textAlign: lay.align,
                style: TextStyle(
                  fontSize: widget.active ? lay.activeSize : lay.fontSize,
                  height: lay.lineHeight,
                  fontWeight: widget.active ? FontWeight.w500 : FontWeight.w400,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots in place of the first line while the intro plays: they light up
/// one by one as it nears, the row breathing meanwhile; then they go grey like
/// a sung line. Every timed text has them, so all look alike from the start.
class _IntroDots extends ConsumerStatefulWidget {
  const _IntroDots({
    super.key,
    required this.until,
    required this.live,
    required this.layout,
  });

  /// The first line's time.
  final double until;
  final bool live;
  final LyricsLayout layout;

  @override
  ConsumerState<_IntroDots> createState() => _IntroDotsState();
}

class _IntroDotsState extends ConsumerState<_IntroDots>
    with SingleTickerProviderStateMixin {
  static const double _size = 7;

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    // How many dots are lit, 4 once the intro is over: the dots rebuild on a
    // change of it, not on every tick of the position.
    final lit = ref.watch(
      playheadProvider.select((h) {
        if (widget.until <= 0) return 4;
        final sec = (h.value?.position.inMilliseconds ?? 0) / 1000;
        final prog = sec / widget.until;
        return prog >= 1 ? 4 : math.min(3, (math.max(0, prog) * 3).floor() + 1);
      }),
    );
    final past = lit > 3;
    final breathe = widget.live && !past;
    if (breathe && !_breath.isAnimating) {
      _breath.repeat();
    } else if (!breathe && _breath.isAnimating) {
      _breath.stop();
    }

    final lay = widget.layout;
    final dots = Row(
      mainAxisAlignment: lay.align == TextAlign.left
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: _size * 1.1),
          AnimatedScale(
            scale: past || i >= lit ? 0.8 : 1,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOutQuad,
            child: AnimatedOpacity(
              opacity: past ? 0.5 : (i < lit ? 1 : 0.22),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOutQuad,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: past ? t.text.withValues(alpha: _past) : t.text,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: lay.introPad),
      child: AnimatedBuilder(
        animation: _breath,
        // 0.7 ↔ 1 over 1.9 s, eased in and out.
        builder: (context, child) => Opacity(
          opacity: breathe
              ? 0.85 + 0.15 * math.cos(_breath.value * 2 * math.pi)
              : 1,
          child: child,
        ),
        child: dots,
      ),
    );
  }
}
