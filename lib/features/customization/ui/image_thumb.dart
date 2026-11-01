/// Slider knob from an own picture, shown only while one is picked. Drawn
/// THROUGH `SliderComponentShape` rather than a widget on top: `Slider` knows
/// where the knob is and moves it under the finger, and a layout over the track
/// would drift every frame.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/cover_store.dart';
import '../custom_store.dart';

/// Knob diameter. A bit over the player's track, so the picture shows without
/// covering the bar.
const double kSliderThumbSize = 22;

/// Decoded knob picture; `null` if none is picked or it's unreadable. The
/// painter needs a `ui.Image`: `ImageProvider` is drawn by widgets, and a
/// canvas takes ready pixels. A GIF gives its first frame.
final sliderThumbProvider = FutureProvider<ui.Image?>((ref) async {
  final src = ref.watch(customSrcProvider(CustomCtx.slider));
  if (src == null) return null;
  final provider = coverImage(src);
  if (provider == null) return null;

  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void done(ui.Image? image) {
    if (!completer.isCompleted) completer.complete(image);
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    // More than one frame may come (a GIF): I take the first and unsubscribe.
    (info, _) => done(info.image),
    onError: (_, _) => done(null),
  );
  stream.addListener(listener);
  ref.onDispose(() => stream.removeListener(listener));
  return completer.future;
});

class ImageSliderThumb extends SliderComponentShape {
  const ImageSliderThumb(this.image, {this.size = kSliderThumbSize});

  final ui.Image image;
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
    final radius = size / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    // `cover`: a picture of any shape fits the circle undistorted, with the
    // excess clipped.
    final src = _coverSrc(image, size);
    canvas.drawImageRect(
      image,
      src,
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  /// Source rectangle filling a square: the picture's central square.
  static Rect _coverSrc(ui.Image image, double side) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final cut = w < h ? w : h;
    return Rect.fromLTWH((w - cut) / 2, (h - cut) / 2, cut, cut);
  }
}
