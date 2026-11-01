/// Full player background: a blurred cover, an adaptive gradient from its
/// colour, or none. The default is none, so nobody who never opened the setting
/// gets a recoloured player.
///
/// This is about the FULL player only; the card above the tab bar has its own
/// setting.
///
/// The customization wallpaper comes as a SEPARATE choice ([PlayerBg.app]),
/// only when picked directly.
library;

import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../customization/custom_store.dart';
import '../customization/media_store.dart';
import '../settings/cover_accent.dart';

/// What shows behind the player's cover and buttons, in sheet order, most
/// noticeable first.
enum PlayerBg {
  /// The track's cover full screen; [CoverBgFx] decides what happens to it.
  cover,

  /// The picture behind the app, with its own blur and dimming.
  app,

  /// Gradient from the cover's colour on top to the theme's below.
  color,

  /// Nothing: the theme's fill.
  none;

  bool get isNone => this == PlayerBg.none;

  bool get isCover => this == PlayerBg.cover;
}

/// What happens to the cover as the player's background ([PlayerBg.cover]), in
/// sheet order, calmest first.
enum CoverBgFx {
  /// A sharp cover under the dim film: the picture shows, and text and buttons
  /// hold on the film.
  dim,

  /// Deep blur: colour patches instead of a picture. The default.
  blur,

  /// The cover as is: no blur, film or colour correction.
  original;

  bool get isBlur => this == CoverBgFx.blur;

  bool get isOriginal => this == CoverBgFx.original;
}

final coverBgFxProvider = NotifierProvider<CoverBgFxController, CoverBgFx>(
  CoverBgFxController.new,
);

class CoverBgFxController extends Notifier<CoverBgFx> {
  @override
  CoverBgFx build() {
    final raw = ref.read(jsonStoreProvider).read('playerBgCoverFx');
    // An unknown entry silently becomes blur, the same rule as
    // [PlayerBgController].
    for (final fx in CoverBgFx.values) {
      if (fx.name == raw) return fx;
    }
    return CoverBgFx.blur;
  }

  void set(CoverBgFx fx) {
    if (fx == state) return;
    state = fx;
    ref.read(jsonStoreProvider).write('playerBgCoverFx', fx.name);
  }
}

/// The picture for [PlayerBg.app], which also decides whether that choice is
/// available. Strictly the picture from the library: the cover as background
/// has [PlayerBg.cover]. Empty means the choice is greyed out in the sheet.
final playerAppBgProvider = Provider<MediaItem?>(
  (ref) => ref.watch(customItemProvider(CustomCtx.bg)),
);

final playerBgProvider = NotifierProvider<PlayerBgController, PlayerBg>(
  PlayerBgController.new,
);

class PlayerBgController extends Notifier<PlayerBg> {
  @override
  PlayerBg build() {
    final raw = ref.read(jsonStoreProvider).read('playerBg');
    // An unknown entry silently becomes none: a background is no reason to
    // crash a launch.
    for (final mode in PlayerBg.values) {
      if (mode.name == raw) return mode;
    }
    return PlayerBg.none;
  }

  void set(PlayerBg mode) {
    if (mode == state) return;
    state = mode;
    ref.read(jsonStoreProvider).write('playerBg', mode.name);
  }
}

/// Player background colour in colour mode, the gradient's top. The key is the
/// cover link, not the track: the player may show a custom picture, and the
/// colour must come from what's visible. `null`: no cover or unreadable, so no
/// background.
final playerBgColorProvider = FutureProvider.autoDispose
    .family<Color?, String?>((ref, cover) async {
      final hsl = await extractCoverHsl(cover);
      return hsl == null ? null : playerBgFromHsl(hsl);
    });
