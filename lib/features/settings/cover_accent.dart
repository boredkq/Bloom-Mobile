/// An accent from a cover: shrunk to 32×32, the juiciest pixel (saturation ×
/// closeness of lightness to 0.5) gives the hue. Lightness and saturation are
/// clamped around the level, or it merges with a dark background and fades on a
/// light one.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/cover_store.dart';
import '../../core/store/settings_store.dart';

/// Half of the lightness band around the level.
const double _lBand = 0.075;

/// The raw tone an accent is counted from. Kept apart, so the level slider
/// needs no new scan.
class CoverHsl {
  const CoverHsl(this.h, this.s, this.l);

  /// Hue 0–360.
  final double h;

  /// Saturation and lightness 0–1.
  final double s;
  final double l;
}

/// A cover's dominant colour by its link, kept until restart: scanning means
/// loading the image.
final coverHslProvider = FutureProvider.family<CoverHsl?, String?>(
  (ref, cover) => extractCoverHsl(cover),
);

/// `null` means no cover, or the picture didn't load.
Future<CoverHsl?> extractCoverHsl(String? cover) async {
  final provider = coverImage(cover);
  if (provider == null) return null;
  // 32×32: the dominant is all that's needed, and shrinking is faster and
  // averages out noise.
  final image = await _load(
    ResizeImage(provider, width: 32, height: 32, allowUpscaling: true),
  );
  if (image == null) return null;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();

    var bestH = 0.0;
    var bestS = 0.0;
    var bestL = 0.0;
    var bestScore = -1.0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      final r = bytes[i] / 255;
      final g = bytes[i + 1] / 255;
      final b = bytes[i + 2] / 255;
      final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
      final l = (max + min) / 2;
      final s = max == min
          ? 0.0
          : l < 0.5
          ? (max - min) / (max + min)
          : (max - min) / (2 - max - min);
      final score = s * (1 - (l - 0.5).abs() * 1.5);
      if (score <= bestScore) continue;
      bestScore = score;
      var h = 0.0;
      if (max != min) {
        if (max == r) {
          h = ((g - b) / (max - min) + 6) % 6;
        } else if (max == g) {
          h = (b - r) / (max - min) + 2;
        } else {
          h = (r - g) / (max - min) + 4;
        }
        h = (h * 60).roundToDouble();
      }
      bestH = h;
      bestS = s;
      bestL = l;
    }
    return CoverHsl(bestH, bestS, bestL);
  } catch (_) {
    return null;
  } finally {
    image.dispose();
  }
}

/// Saturation follows the level: on a dark hue a high S is coloured noise, a
/// light one needs juice.
Color accentFromHsl(CoverHsl hsl, double level) {
  final lvl = clampAutoAccentL(level);
  final s = (hsl.s * (0.75 + lvl)).clamp(0.0, 1.0);
  final l = hsl.l.clamp(lvl - _lBand, lvl + _lBand);
  return HSLColor.fromAHSL(1, hsl.h % 360, s, l).toColor();
}

/// The auto theme surface's lightness and saturation ceiling.
const double _autoThemeBgL = 0.075;
const double _autoThemeBgSMax = 0.5;

/// The auto theme's surface, background and blocks alike: the cover only as a
/// hue, a little above Dark in lightness, or the whole UI becomes a coloured
/// patch.
Color autoThemeSurfaceFromHsl(CoverHsl hsl) => HSLColor.fromAHSL(
  1,
  hsl.h % 360,
  (hsl.s * 0.6).clamp(0.0, _autoThemeBgSMax),
  _autoThemeBgL,
).toColor();

/// The mini player's "cover colour": lightness in a dark band so the card fits
/// in, saturation trimmed since a high S on a dark hue is coloured noise.
Color miniBgFromHsl(CoverHsl hsl) => HSLColor.fromAHSL(
  1,
  hsl.h % 360,
  (hsl.s * 0.78).clamp(0.0, 0.58),
  (hsl.l * 0.45).clamp(0.09, 0.18),
).toColor();

/// The top of the gradient in the full player's "Colour" background. Livelier
/// than the mini player's: it fills the screen and must read as the cover's
/// colour. Still dark, under white captions and block films, with S trimmed: on
/// a large area a high one turns acid.
Color playerBgFromHsl(CoverHsl hsl) => HSLColor.fromAHSL(
  1,
  hsl.h % 360,
  (hsl.s * 0.85).clamp(0.0, 0.72),
  (hsl.l * 0.62).clamp(0.16, 0.34),
).toColor();

/// `null` if the network or the file gave nothing.
Future<ui.Image?> _load(ImageProvider provider) {
  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(ui.Image? image) {
    if (!completer.isCompleted) completer.complete(image);
    stream.removeListener(listener);
  }

  listener = ImageStreamListener((info, _) {
    // A clone: the frame belongs to the image cache, so I hand out a copy and
    // close `info` at once.
    final image = info.image.clone();
    info.dispose();
    finish(image);
  }, onError: (_, _) => finish(null));
  stream.addListener(listener);
  return completer.future;
}
