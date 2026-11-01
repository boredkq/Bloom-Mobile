/// My Wave's living circle on the stage's colour.
/// The circle is drawn into a small square at 30 fps and
/// stretched: it's all soft, the size doesn't show, and the cost is the same
/// on any screen. Playing, it runs three times faster and takes the cover's
/// colour; paused, it slows down and goes back to the theme's accent, in steps
/// towards the blocks' colour from the inside out.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../../app/theme/tokens.dart';
import '../../settings/cover_accent.dart' show CoverHsl;

// Knobs: the square's side in pixels, the frame rate, the motion's pace, how
// far down the stage's colour runs before fading into the page.
const int _texSide = 430;
const Duration _frame = Duration(milliseconds: 33);
const double _paceIdle = 0.2;
const double _pacePlay = 0.6;
const double _fadeFrom = 0.5;

class Vibe extends StatefulWidget {
  const Vibe({
    super.key,
    required this.tone,
    required this.playing,
    required this.center,
    required this.core,
    this.running = true,
  });

  /// The cover's colour; `null` = the idle palette.
  final CoverHsl? tone;
  final bool playing;

  /// The circle's centre in the box and its dense part's diameter.
  final Offset center;
  final double core;

  /// Off while nobody sees it: the last frame stays.
  final bool running;

  @override
  State<Vibe> createState() => _VibeState();
}

/// One load for the whole run.
final Future<ui.FragmentProgram?> _program = ui.FragmentProgram.fromAsset(
  'shaders/vibe.frag',
).then<ui.FragmentProgram?>((p) => p, onError: (_) => null);

class _VibeState extends State<Vibe> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<int> _frames = ValueNotifier(0);
  ui.FragmentShader? _shader;
  ui.Image? _image;

  double _time = math.Random().nextDouble() * 3600;
  double _pace = _paceIdle;
  Duration _last = Duration.zero;

  /// Outer, middle, inner disc.
  List<Color>? _cols;

  @override
  void initState() {
    super.initState();
    _program.then((p) {
      if (p == null || !mounted) return;
      _shader = p.fragmentShader();
      _render();
      _frames.value++;
    });
    if (widget.running) _ticker.start();
  }

  @override
  void didUpdateWidget(Vibe old) {
    super.didUpdateWidget(old);
    if (widget.running == old.running) return;
    if (widget.running) {
      _last = Duration.zero;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frames.dispose();
    _shader?.dispose();
    _image?.dispose();
    super.dispose();
  }

  /// Lightness and saturation lifted per disc, the inner one brightest.
  List<Color> _targets() {
    final t = context.bloom;
    final tone = widget.tone;
    if (!widget.playing || tone == null) {
      return [
        Color.lerp(t.accent, t.blockColor, 0.45)!,
        Color.lerp(t.accent, t.blockColor, 0.22)!,
        t.accent,
      ];
    }
    Color hsl(double s, double l) => HSLColor.fromAHSL(
      1,
      tone.h % 360,
      s.clamp(0.0, 1.0),
      l.clamp(0.0, 1.0),
    ).toColor();
    return [
      hsl(tone.s, tone.l),
      hsl(tone.s + 0.15, tone.l + 0.05),
      hsl(tone.s + 0.15, tone.l + 0.1),
    ];
  }

  void _tick(Duration elapsed) {
    final dt = elapsed - _last;
    if (_last != Duration.zero && dt < _frame) return;
    final s = _last == Duration.zero
        ? 0.0
        : math.min(dt.inMilliseconds, 100) / 1000;
    _last = elapsed;

    final settle = 1 - math.exp(-s / 0.35);
    _pace += ((widget.playing ? _pacePlay : _paceIdle) - _pace) * settle;
    _time = (_time + _pace * s) % 86400;

    // A new cover's colour comes in over about three seconds.
    final to = _targets();
    final k = 1 - math.exp(-s / 0.8);
    _cols = [
      for (var i = 0; i < 3; i++) Color.lerp(_cols?[i] ?? to[i], to[i], k)!,
    ];
    _render();
    _frames.value++;
  }

  void _render() {
    final shader = _shader;
    if (shader == null) return;
    final cols = _cols ??= _targets();
    final side = _texSide.toDouble();
    final box = context.size;
    final big = box == null ? 1.0 : math.max(box.width, box.height) * 1.3;
    shader
      ..setFloat(0, side)
      ..setFloat(1, side)
      ..setFloat(2, _time)
      ..setFloat(3, widget.core / big);
    for (var i = 0; i < 3; i++) {
      shader
        ..setFloat(4 + i * 3, cols[i].r)
        ..setFloat(5 + i * 3, cols[i].g)
        ..setFloat(6 + i * 3, cols[i].b);
    }
    final rec = ui.PictureRecorder();
    Canvas(
      rec,
    ).drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..shader = shader);
    final pic = rec.endRecording();
    _image?.dispose();
    _image = pic.toImageSync(_texSide, _texSide);
    pic.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(size: Size.infinite, painter: _VibePainter(this)),
    );
  }
}

class _VibePainter extends CustomPainter {
  _VibePainter(this.vibe) : super(repaint: vibe._frames);

  final _VibeState vibe;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = vibe._cols ??= vibe._targets();
    final bg = vibe.context.bloom.bg;
    // The stage in the wave's colour (its outer disc's, a little towards the
    // page), fading out downwards with an ease-out: a straight ramp shows a kink.
    final c = Color.lerp(cols[0], bg, 0.3)!;
    final rest = 1 - _fadeFrom;
    // Clipped to the box save upwards: a pull past the top of the page shows
    // more of the stage, not the page's black.
    canvas.clipRect(Rect.fromLTRB(0, -size.height, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTRB(0, -size.height, size.width, 0),
      Paint()..color = c,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            c,
            c,
            c.withValues(alpha: 0.85),
            c.withValues(alpha: 0.6),
            c.withValues(alpha: 0.3),
            c.withValues(alpha: 0.08),
            c.withValues(alpha: 0),
          ],
          [
            0,
            _fadeFrom,
            _fadeFrom + rest * 0.16,
            _fadeFrom + rest * 0.32,
            _fadeFrom + rest * 0.56,
            _fadeFrom + rest * 0.8,
            1,
          ],
        ),
    );

    final image = vibe._image;
    if (image == null) return;
    // Wider than the stage, so the spikes run out past its edges instead of
    // fading inside.
    final side = math.max(size.width, size.height) * 1.3;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: vibe.widget.center, width: side, height: side),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_VibePainter old) => true;
}
