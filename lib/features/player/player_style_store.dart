/// Player style: standard or vinyl.
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
  ivory;

  bool get isVinyl => this == PlayerStyle.vinyl;
  bool get isAura => this == PlayerStyle.aura;
  bool get isIvory => this == PlayerStyle.ivory;
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
