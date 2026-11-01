/// Play button look. On a phone it's the player's largest element, so its shape
/// shows first.
///
/// One setting for both surfaces (the player and the card above the tab bar):
/// it's one button in meaning, and different looks would read as unfinished.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

enum PlayButtonShape {
  /// A circle filled with the accent.
  circle,

  /// The same fill as a rounded square.
  square,

  /// No fill: just the glyph, in the neighbours' colour and larger.
  plain;

  bool get isPlain => this == PlayButtonShape.plain;
}

final playButtonShapeProvider =
    NotifierProvider<PlayButtonShapeController, PlayButtonShape>(
      PlayButtonShapeController.new,
    );

class PlayButtonShapeController extends Notifier<PlayButtonShape> {
  @override
  PlayButtonShape build() {
    final raw = ref.read(jsonStoreProvider).read('playButtonShape');
    for (final shape in PlayButtonShape.values) {
      if (shape.name == raw) return shape;
    }
    // An unknown entry silently becomes the default: a button's shape is no
    // reason to crash a launch.
    return PlayButtonShape.circle;
  }

  void set(PlayButtonShape shape) {
    if (shape == state) return;
    state = shape;
    ref.read(jsonStoreProvider).write('playButtonShape', shape.name);
  }
}
