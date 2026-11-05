/// Player style: standard, vinyl, and Levyra player deck styles.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

enum PlayerStyle {
  /// A rounded square cover.
  standard,

  /// A round cover that spins while playing.
  vinyl,

  /// Fluid ambient surface with flowing light (Levyra Flow).
  flow,

  /// Glowing atmospheric velvet aura (Levyra Aura / Velvet).
  aura,

  /// Floating vinyl card sleeve with physical depth (Levyra Sleeve / Card).
  sleeve,

  /// Sharp cinematic gallery poster (Levyra Poster / Artwork).
  poster,

  /// Floating artwork surrounded by an ethereal glowing halo ring (Levyra Halo).
  halo,

  /// Audio-reactive rhythmic pulse ripples (Levyra Pulse).
  pulse,

  /// Asymmetric two-tone editorial magazine layout (Levyra Folio / Editorial).
  folio,

  /// Dynamic Material 3 Expressive pill squircle (Levyra Expressive).
  expressive;

  bool get isVinyl => this == PlayerStyle.vinyl;

  static PlayerStyle of(Object? name) {
    if (name is! String) return PlayerStyle.standard;
    for (final s in values) {
      if (s.name == name) return s;
    }
    // Backward compatibility with Levyra storage identifiers:
    switch (name.toLowerCase()) {
      case 'canvas_card':
      case 'card':
        return sleeve;
      case 'canvas_immersive':
      case 'immersive':
      case 'velvet':
        return aura;
      case 'editorial':
        return folio;
      case 'gallery':
      case 'artwork':
        return poster;
      default:
        return standard;
    }
  }
}

final playerStyleProvider =
    NotifierProvider<PlayerStyleController, PlayerStyle>(
      PlayerStyleController.new,
    );

class PlayerStyleController extends Notifier<PlayerStyle> {
  @override
  PlayerStyle build() {
    final raw = ref.read(jsonStoreProvider).read('playerStyle');
    return PlayerStyle.of(raw);
  }

  void setStyle(PlayerStyle style) {
    if (style == state) return;
    state = style;
    ref.read(jsonStoreProvider).write('playerStyle', style.name);
  }
}
