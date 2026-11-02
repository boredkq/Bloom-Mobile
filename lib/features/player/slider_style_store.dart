/// Progress slider type. A custom knob picture is a separate customization
/// setting, shown with any type except wave.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

/// Progress bar look in the full player.
enum SliderStyle {
  /// A 5 px track with no knob.
  standard,

  /// A hairline track with a round knob.
  thin,

  /// Two capsule segments with a clear gap and a vertical drop.
  ios,

  /// Wave bars instead of a track.
  wave,
}

final sliderStyleProvider =
    NotifierProvider<SliderStyleController, SliderStyle>(
      SliderStyleController.new,
    );

class SliderStyleController extends Notifier<SliderStyle> {
  @override
  SliderStyle build() {
    final raw = ref.read(jsonStoreProvider).read('sliderStyle');
    for (final style in SliderStyle.values) {
      if (style.name == raw) return style;
    }
    // An unknown entry silently becomes the default: a slider's look is no
    // reason to crash a launch.
    return SliderStyle.standard;
  }

  void set(SliderStyle style) {
    state = style;
    ref.read(jsonStoreProvider).write('sliderStyle', style.name);
  }
}
