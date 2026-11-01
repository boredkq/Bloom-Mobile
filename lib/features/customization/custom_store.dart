/// Where library pictures are applied. Three contexts: background, player cover
/// and progress knob.
///
/// The store holds only picture `id`s: the picture lives in [mediaLibProvider],
/// and deleting it there must clear the context. [removeMedia] does that, the
/// one point where library, contexts and presets meet.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../player/player_controller.dart' show playbackProvider;
import 'media_store.dart';
import 'presets_store.dart';

/// Where a picture can go.
enum CustomCtx {
  /// App background.
  bg,

  /// The cover in the player and mini player, over the track's cover.
  cover,

  /// The progress slider's knob.
  slider,
}

/// Default blur and dim of the track cover as a background. Dim isn't zero:
/// with no film a light cover eats the UI's text.
const int kCoverAsBgBlur = 0;
const int kCoverAsBgDim = 65;

/// Blur and dim of the track cover as a background ([SettingsState.coverAsBg]).
/// A library picture holds these numbers itself ([MediaItem.blur]), but a
/// track's cover has no library entry, so it takes a separate setting. Bounds
/// and units match the picture's page: pixels 0…[kBgBlurMax], percent
/// 0…[kBgDimMax].
class CoverAsBgFx {
  const CoverAsBgFx({this.blur = kCoverAsBgBlur, this.dim = kCoverAsBgDim});

  /// Blur, px.
  final int blur;

  /// Dim, %.
  final int dim;
}

final coverAsBgFxProvider =
    NotifierProvider<CoverAsBgFxController, CoverAsBgFx>(
      CoverAsBgFxController.new,
    );

class CoverAsBgFxController extends Notifier<CoverAsBgFx> {
  static const _key = 'coverAsBgFx';

  @override
  CoverAsBgFx build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    // A broken entry silently becomes the default: a background is no reason to
    // crash a launch.
    int value(String field, double max, int fallback) {
      final saved = raw[field];
      return saved is num ? saved.round().clamp(0, max.round()) : fallback;
    }

    return CoverAsBgFx(
      blur: value('blur', kBgBlurMax, kCoverAsBgBlur),
      dim: value('dim', kBgDimMax, kCoverAsBgDim),
    );
  }

  void setBlur(int px) =>
      _set(CoverAsBgFx(blur: px.clamp(0, kBgBlurMax.round()), dim: state.dim));

  void setDim(int pct) =>
      _set(CoverAsBgFx(blur: state.blur, dim: pct.clamp(0, kBgDimMax.round())));

  void _set(CoverAsBgFx next) {
    if (next.blur == state.blur && next.dim == state.dim) return;
    state = next;
    ref.read(jsonStoreProvider).write(_key, {
      'blur': state.blur,
      'dim': state.dim,
    });
  }
}

class CustomTargets {
  const CustomTargets({this.bg, this.cover, this.slider});

  final String? bg;
  final String? cover;
  final String? slider;

  String? of(CustomCtx ctx) => switch (ctx) {
    CustomCtx.bg => bg,
    CustomCtx.cover => cover,
    CustomCtx.slider => slider,
  };

  /// `next` unfolds right in the field: `copyWith` with `null` can't tell leave
  /// alone from clear, and clearing is constant here.
  CustomTargets with_(CustomCtx ctx, String? next) => switch (ctx) {
    CustomCtx.bg => CustomTargets(bg: next, cover: cover, slider: slider),
    CustomCtx.cover => CustomTargets(bg: bg, cover: next, slider: slider),
    CustomCtx.slider => CustomTargets(bg: bg, cover: cover, slider: next),
  };

  bool get isEmpty => bg == null && cover == null && slider == null;

  Map<String, dynamic> toJson() => {
    if (bg != null) 'bg': bg,
    if (cover != null) 'cover': cover,
    if (slider != null) 'slider': slider,
  };
}

final customProvider = NotifierProvider<CustomController, CustomTargets>(
  CustomController.new,
);

class CustomController extends Notifier<CustomTargets> {
  static const _key = 'custom';

  @override
  CustomTargets build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    String? id(String field) {
      final value = raw[field];
      return value is String && value.isNotEmpty ? value : null;
    }

    return CustomTargets(
      bg: id('bg'),
      cover: id('cover'),
      slider: id('slider'),
    );
  }

  /// Puts a picture in a context, which holds ONE: a new one displaces the
  /// last, as the switches on the picture's page read.
  void set(CustomCtx ctx, String? id) {
    if (state.of(ctx) == id) return;
    state = state.with_(ctx, id);
    _save();
  }

  /// Switch on the picture's page: on puts it in the context, off clears the
  /// context (only if this one's there).
  void toggle(CustomCtx ctx, String id, bool on) =>
      set(ctx, on ? id : (state.of(ctx) == id ? null : state.of(ctx)));

  /// Applies a preset snapshot: set contexts get placed, empty ones are NOT
  /// touched.
  void applyTargets(CustomTargets next) {
    var value = state;
    for (final ctx in CustomCtx.values) {
      final id = next.of(ctx);
      if (id != null) value = value.with_(ctx, id);
    }
    if (value.bg == state.bg &&
        value.cover == state.cover &&
        value.slider == state.slider) {
      return;
    }
    state = value;
    _save();
  }

  /// Removes references to a deleted picture.
  void purge(String id) {
    var value = state;
    for (final ctx in CustomCtx.values) {
      if (value.of(ctx) == id) value = value.with_(ctx, null);
    }
    if (identical(value, state)) return;
    state = value;
    _save();
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, state.toJson());
}

/// Provider read: a screen's `ref.read`, a test's `container.read`. So the
/// cascade is tied to neither widget nor container.
typedef ReadProvider = T Function<T>(ProviderListenable<T> provider);

/// Deleting a picture from the library with the whole cascade: contexts,
/// presets, file. Outside the stores on purpose: a store reaching into
/// neighbours brings circular imports.
void removeMedia(ReadProvider read, String id) {
  read(customProvider.notifier).purge(id);
  read(presetsProvider.notifier).purgeImage(id);
  read(mediaLibProvider.notifier).remove(id);
}

/// A context's whole picture (the background also needs blur and dim). `null`
/// if the context is empty or the picture was deleted past the cascade.
final customItemProvider = Provider.family<MediaItem?, CustomCtx>((ref, ctx) {
  final id = ref.watch(customProvider).of(ctx);
  if (id == null) return null;
  for (final item in ref.watch(mediaLibProvider)) {
    if (item.id == id) return item;
  }
  return null;
});

/// Link to a context's picture, as `coverImage` understands it.
final customSrcProvider = Provider.family<String?, CustomCtx>(
  (ref, ctx) => ref.watch(customItemProvider(ctx))?.src,
);

/// When a custom cover goes over a track's.
enum CoverMode {
  /// On all tracks.
  always,

  /// Only on those with no cover of their own.
  fallback,
}

final coverModeProvider = NotifierProvider<CoverModeController, CoverMode>(
  CoverModeController.new,
);

class CoverModeController extends Notifier<CoverMode> {
  static const _key = 'coverMode';

  @override
  CoverMode build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    return raw['mode'] == 'fallback' ? CoverMode.fallback : CoverMode.always;
  }

  void set(CoverMode mode) {
    if (mode == state) return;
    state = mode;
    ref.read(jsonStoreProvider).write(_key, {'mode': mode.name});
  }
}

/// The cover the player really shows: a custom one (per [CoverMode]) or the
/// track's.
final playerCoverProvider = Provider<String?>((ref) {
  final own = ref.watch(playbackProvider.select((s) => s.track?.cover));
  final custom = ref.watch(customSrcProvider(CustomCtx.cover));
  if (custom == null) return own;
  final hasOwn = own != null && own.isNotEmpty;
  return ref.watch(coverModeProvider) == CoverMode.fallback && hasOwn
      ? own
      : custom;
});

/// Where this picture stands, for the icons on its library tile. In the order
/// of the switches on its page.
final mediaUsageProvider = Provider.family<List<CustomCtx>, String>((ref, id) {
  final targets = ref.watch(customProvider);
  return [
    for (final ctx in CustomCtx.values)
      if (targets.of(ctx) == id) ctx,
  ];
});
