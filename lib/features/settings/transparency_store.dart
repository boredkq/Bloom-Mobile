/// Glass on the blocks of the interface: [GlassSpec] gives the fill's alpha and
/// a ready `ImageFilter`, `GlassBox` hands them out. The window itself is never
/// transparent here: glass is over the app's own background. The sliders open
/// in sheets.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

/// Percent 0–100, blur 0–40 px.
const int kTrBlurMax = 40;

const int kTrOpacityDefault = 60;
const int kTrBrightnessDefault = 50;
const int kTrBlurDefault = 12;

@immutable
class Transparency {
  const Transparency({
    this.on = false,
    this.overlayGlass = false,
    this.blockOpacity = kTrOpacityDefault,
    this.glassStr = kTrBrightnessDefault,
    this.glassBlur = kTrBlurDefault,
  });

  /// Off is plain solid blocks, on is glass.
  final bool on;

  /// Glass on what pops up: sheets, menus, dialogs and the dim under them. A
  /// sub-mode, see [overlaysOn].
  final bool overlayGlass;

  /// OPACITY of the blocks, 0–100. Shown inverted as the transparency level
  /// ([transparencyPercent]): the slider means how much of the background
  /// shows.
  final int blockOpacity;

  /// 50 is neutral.
  final int glassStr;

  final int glassBlur;

  /// What settings show.
  int get transparencyPercent => 100 - blockOpacity;

  /// 0 → 0.4 (dark glass), 50 → 1.0, 100 → 1.8.
  double get brightness => glassStr < 50
      ? 0.4 + (glassStr / 50) * 0.6
      : 1 + ((glassStr - 50) / 50) * 0.8;

  double get opacity => blockOpacity / 100;

  /// Both switches at once.
  bool get overlaysOn => on && overlayGlass;

  Transparency copyWith({
    bool? on,
    bool? overlayGlass,
    int? blockOpacity,
    int? glassStr,
    int? glassBlur,
  }) => Transparency(
    on: on ?? this.on,
    overlayGlass: overlayGlass ?? this.overlayGlass,
    blockOpacity: blockOpacity ?? this.blockOpacity,
    glassStr: glassStr ?? this.glassStr,
    glassBlur: glassBlur ?? this.glassBlur,
  );

  /// From the store or a preset's snapshot. Broken fields become defaults:
  /// looks are no reason to fail a launch.
  static Transparency fromJson(Map<dynamic, dynamic> raw) {
    int number(String field, int fallback, int max) {
      final value = raw[field];
      return value is num ? value.round().clamp(0, max) : fallback;
    }

    return Transparency(
      // The other spelling a preset file may carry.
      on: raw['on'] == true || raw['trMode'] == 'on',
      overlayGlass: raw['overlayGlass'] == true,
      blockOpacity: number('blockOpacity', kTrOpacityDefault, 100),
      glassStr: number('glassStr', kTrBrightnessDefault, 100),
      glassBlur: number('glassBlur', kTrBlurDefault, kTrBlurMax),
    );
  }

  Map<String, dynamic> toJson() => {
    'on': on,
    'overlayGlass': overlayGlass,
    'blockOpacity': blockOpacity,
    'glassStr': glassStr,
    'glassBlur': glassBlur,
  };

  @override
  bool operator ==(Object other) =>
      other is Transparency &&
      other.on == on &&
      other.overlayGlass == overlayGlass &&
      other.blockOpacity == blockOpacity &&
      other.glassStr == glassStr &&
      other.glassBlur == glassBlur;

  @override
  int get hashCode =>
      Object.hash(on, overlayGlass, blockOpacity, glassStr, glassBlur);
}

final transparencyProvider =
    NotifierProvider<TransparencyController, Transparency>(
      TransparencyController.new,
    );

class TransparencyController extends Notifier<Transparency> {
  static const _key = 'transparency';

  @override
  Transparency build() =>
      Transparency.fromJson(ref.read(jsonStoreProvider).readMap(_key));

  void setOn(bool on) => _set(state.copyWith(on: on));

  /// From a preset's snapshot.
  void restore(Transparency next) => _set(next);

  void setOverlayGlass(bool on) => _set(state.copyWith(overlayGlass: on));

  /// Comes as how much background shows, goes to the store as opacity.
  void setTransparencyPercent(int percent) =>
      _set(state.copyWith(blockOpacity: 100 - percent.clamp(0, 100)));

  void setGlassStr(int value) =>
      _set(state.copyWith(glassStr: value.clamp(0, 100)));

  void setGlassBlur(int value) =>
      _set(state.copyWith(glassBlur: value.clamp(0, kTrBlurMax)));

  void _set(Transparency next) {
    if (next == state) return;
    state = next;
    ref.read(jsonStoreProvider).write(_key, next.toJson());
  }
}

/// What to paint with and what to filter the backdrop with.
@immutable
class GlassSpec {
  const GlassSpec({required this.opacity, required this.filter});

  final double opacity;

  /// `null` when there's nothing to filter (no blur, brightness 1): then it's
  /// just a translucent fill, no layer needed.
  final ui.ImageFilter? filter;
}

/// `brightness(k)`: multiplies RGB, leaves alpha.
ui.ColorFilter _brightnessFilter(double k) => ui.ColorFilter.matrix(<double>[
  k, 0, 0, 0, 0, //
  0, k, 0, 0, 0, //
  0, 0, k, 0, 0, //
  0, 0, 0, 1, 0, //
]);

GlassSpec? _spec(Transparency tr, {required bool enabled}) {
  if (!enabled) return null;
  final blur = tr.glassBlur.toDouble();
  final bright = tr.brightness;
  // `clamp`: without it the blur pulls transparency in from the edges and a
  // light rim runs around the block.
  final blurFilter = blur > 0
      ? ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: ui.TileMode.clamp,
        )
      : null;
  final colorFilter = bright == 1 ? null : _brightnessFilter(bright);
  return GlassSpec(
    opacity: tr.opacity,
    filter: switch ((blurFilter, colorFilter)) {
      (final b?, final c?) => ui.ImageFilter.compose(outer: c, inner: b),
      (final b?, null) => b,
      (null, final c?) => c,
      _ => null,
    },
  );
}

/// `null` means off, solid blocks.
final glassProvider = Provider<GlassSpec?>((ref) {
  final tr = ref.watch(transparencyProvider);
  return _spec(tr, enabled: tr.on);
});

/// For sheets, menus and the dim under them.
final overlayGlassProvider = Provider<GlassSpec?>((ref) {
  final tr = ref.watch(transparencyProvider);
  return _spec(tr, enabled: tr.overlaysOn);
});
