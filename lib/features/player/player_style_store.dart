/// Player style: standard, vinyl, aura, ivory, and Levyra themes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

enum PlayerStyle {
  /// A rounded square cover.
  standard,

  /// A round cover that spins while playing.
  vinyl,

  /// Apple Music Aura: live glow and dynamic spring cover.
  aura,

  /// Ivory: clean editorial magazine minimalism.
  ivory,

  /// Levyra Cosmic: deep space frosted glass with cyan and purple aura.
  levyraCosmic,

  /// Levyra Cyber: cybernetic HUD neon cyan & cobalt blue frame.
  levyraCyber,

  /// Levyra Aurora: Nordic Borealis emerald and arctic glow.
  levyraAurora,

  /// Levyra Ember: warm analog sunset glow and vacuum tube amber.
  levyraEmber,

  /// Levyra OLED: pitch black zero-power card with hairline borders.
  levyraOled,

  /// Levyra Cassette: retro audio cassette with rotating tape spools.
  levyraCassette;

  bool get isVinyl => this == PlayerStyle.vinyl;
  bool get isAura => this == PlayerStyle.aura;
  bool get isIvory => this == PlayerStyle.ivory;
  bool get isLevyraCosmic => this == PlayerStyle.levyraCosmic;
  bool get isLevyraCyber => this == PlayerStyle.levyraCyber;
  bool get isLevyraAurora => this == PlayerStyle.levyraAurora;
  bool get isLevyraEmber => this == PlayerStyle.levyraEmber;
  bool get isLevyraOled => this == PlayerStyle.levyraOled;
  bool get isLevyraCassette => this == PlayerStyle.levyraCassette;

  bool get isLevyra =>
      isLevyraCosmic ||
      isLevyraCyber ||
      isLevyraAurora ||
      isLevyraEmber ||
      isLevyraOled ||
      isLevyraCassette;
}

final playerStyleProvider =
    NotifierProvider<PlayerStyleController, PlayerStyle>(
      PlayerStyleController.new,
    );

class PlayerStyleController extends Notifier<PlayerStyle> {
  @override
  PlayerStyle build() {
    final raw = ref.read(jsonStoreProvider).read('playerStyle');
    // An unknown entry silently becomes the standard player: a style is no
    // reason to crash a launch.
    for (final style in PlayerStyle.values) {
      if (style.name == raw) return style;
    }
    return PlayerStyle.standard;
  }

  void setStyle(PlayerStyle style) {
    if (style == state) return;
    state = style;
    ref.read(jsonStoreProvider).write('playerStyle', style.name);
  }
}
