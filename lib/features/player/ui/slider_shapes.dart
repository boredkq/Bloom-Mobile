/// Drawing of slider types, all through `Slider`'s own shapes
/// (`SliderTrackShape`, `SliderComponentShape`) rather than a layout over the
/// track: the slider knows where the knob is and moves it under the finger, and
/// a parallel layout would drift every frame. The touch trap, drag and tap on
/// the track come free.
///
/// One entry for all, [bloomSliderTheme]: the player and the settings preview
/// take their look from here so they can't diverge.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../customization/ui/image_thumb.dart';
import '../slider_style_store.dart';

/// Track height per type. Wave isn't a track but a strip of bars, so its height
/// is for bars; thin is 1.5 px.
double sliderTrackHeight(SliderStyle style) => switch (style) {
  SliderStyle.standard => 5,
  SliderStyle.thin => 1.5,
  SliderStyle.ios => 5,
  SliderStyle.wave => 28,
};

/// Progress slider look for the picked type. [thumbImage] is the knob photo
/// from customization. It overrides the type's knob but not wave, which has no
/// knob: the edge of the filled bars shows the position.
///
/// [waveSeed] is the wave pattern's seed, one per track (see [WaveTrackShape]).
SliderThemeData bloomSliderTheme(
  SliderThemeData base, {
  required SliderStyle style,
  required BloomTokens tokens,
  ui.Image? thumbImage,
  int waveSeed = 0,
}) {
  final SliderComponentShape thumb = switch (style) {
    SliderStyle.wave => SliderComponentShape.noThumb,
    _ when thumbImage != null => ImageSliderThumb(thumbImage),
    SliderStyle.standard => SliderComponentShape.noThumb,
    SliderStyle.thin => const DotSliderThumb(),
    SliderStyle.ios => const CapsuleSliderThumb(),
  };
  final SliderTrackShape track = switch (style) {
    SliderStyle.ios => const IosTrackShape(),
    SliderStyle.wave => WaveTrackShape(seed: waveSeed),
    _ => const RoundedRectSliderTrackShape(),
  };

  return base.copyWith(
    trackShape: track,
    trackHeight: sliderTrackHeight(style),
    thumbShape: thumb,
    activeTrackColor: tokens.accent,
    inactiveTrackColor: style == SliderStyle.wave
        ? waveRestColor(tokens)
        : tokens.track,
    // No halo under the finger anywhere: Bloom has no such fills.
    overlayShape: SliderComponentShape.noOverlay,
  );
}

/// Round knob of the thin type: 10 px in the accent.
class DotSliderThumb extends SliderComponentShape {
  const DotSliderThumb({this.size = 10});

  final double size;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final color = sliderTheme.thumbColor ?? sliderTheme.activeTrackColor!;
    canvas.drawCircle(center, size / 2, Paint()..color = color);
  }
}

/// Vertical drop of the iOS type: 4×28 in the accent.
class CapsuleSliderThumb extends SliderComponentShape {
  const CapsuleSliderThumb({this.width = 4, this.height = 28});

  final double width;
  final double height;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final color = sliderTheme.thumbColor ?? sliderTheme.activeTrackColor!;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(width / 2),
    );
    canvas.drawRRect(rect, Paint()..color = color);
  }
}

/// iOS type track: two capsule segments with a clear gap at the knob, drawn
/// directly rather than cut out.
class IosTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const IosTrackShape({this.gap = 6});

  /// Empty space on each side of the knob.
  final double gap;

  @override
  bool get isRounded => true;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;

    final radius = Radius.circular(rect.height / 2);
    final canvas = context.canvas;
    // A segment is drawn only if something's left after the gap: at the track's
    // ends it degenerates, and a negative-width capsule would be a blot.
    void segment(double left, double right, Color color) {
      if (right - left <= 0) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, rect.top, right, rect.bottom),
          radius,
        ),
        Paint()..color = color,
      );
    }

    segment(rect.left, thumbCenter.dx - gap, sliderTheme.activeTrackColor!);
    segment(thumbCenter.dx + gap, rect.right, sliderTheme.inactiveTrackColor!);
  }
}

/// Wave track: bars instead of a strip, accent up to the position and film
/// beyond. The pattern is an envelope of three sines with random phases plus
/// jitter. Phases come from [seed] (the track id) rather than fresh randomness:
/// the painter runs every frame of a seek, and new random values would redraw
/// the wave dozens of times a second.
class WaveTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const WaveTrackShape({required this.seed});

  /// Pattern seed: one track, one drawing.
  final int seed;

  /// Bar step (the bar plus the gap). I keep the step constant and compute the
  /// count from the width: a fixed count would collapse into mush on a narrow
  /// strip.
  static const double pitch = 5;

  /// Gap between bars.
  static const double slit = 1.5;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;

    final count = math.max(1, (rect.width / pitch).round());
    final bars = waveBars(seed, count, rect.height);
    final width = rect.width / count;
    final canvas = context.canvas;

    void draw(Paint paint) {
      for (var i = 0; i < count; i++) {
        final height = bars[i];
        final inner = math.max(width - slit, 1.0);
        final left = rect.left + i * width + slit / 2;
        final top = rect.top + (rect.height - height) / 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, inner, height),
            Radius.circular(math.min(inner / 2, height / 2)),
          ),
          paint,
        );
      }
    }

    draw(Paint()..color = sliderTheme.inactiveTrackColor!);
    // The filled part is the same bars under a clip at the position, so the bar
    // on the edge splits rather than recolours whole.
    final split = thumbCenter.dx - rect.left;
    if (split > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(rect.left, rect.top, split, rect.height));
      draw(Paint()..color = sliderTheme.activeTrackColor!);
      canvas.restore();
    }
  }
}

/// Wave bar heights. They're computed for a 28 px strip; [height] scales them,
/// since the settings preview is lower than the player's.
List<double> waveBars(int seed, int count, double height) {
  final rnd = math.Random(seed);
  final s1 = rnd.nextDouble() * 10;
  final s2 = rnd.nextDouble() * 10;
  final s3 = rnd.nextDouble() * 10;
  final scale = height / 28;
  return [
    for (var i = 0; i < count; i++)
      () {
        final t = i / count;
        final env =
            (math.sin(t * math.pi * 4 + s1)).abs() * 0.45 +
            (math.sin(t * math.pi * 9 + s2)).abs() * 0.35 +
            (math.sin(t * math.pi * 17 + s3)).abs() * 0.2;
        return (2 + env * 16 + rnd.nextDouble() * 3) * scale;
      }(),
  ];
}

/// Colour of unfilled wave bars. The shared track (`track`, a 4% film) is too
/// quiet for bars, thinner than a strip, so they get a 10% film.
Color waveRestColor(BloomTokens tokens) =>
    (tokens.isLight ? const Color(0xFF000000) : const Color(0xFFFFFFFF))
        .withValues(alpha: 0.1);
