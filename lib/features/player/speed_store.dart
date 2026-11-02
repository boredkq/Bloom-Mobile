/// Playback speed. With nightcore, pitch moves with tempo; off (the default),
/// pitch holds. Presets, bounds, step and rounding match across devices, so one
/// number means one thing.
///
/// The store is CLEAN: it knows nothing of the player, only the value and
/// saving it. `PlaybackController`, the player's sole owner, applies it by
/// subscribing here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

/// Picker preset cards: slow, normal, fast.
const List<double> kSpeedPresets = [0.75, 1, 1.25];

/// Bounds and step of the custom speed slider.
const double kSpeedMin = 0.5;
const double kSpeedMax = 2;
const double kSpeedStep = 0.05;

/// Marks under the bar every 0.25×. Those matching presets are larger.
const List<double> kSpeedTicks = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

/// Slider divisions between [kSpeedMin] and [kSpeedMax].
int get kSpeedDivisions => ((kSpeedMax - kSpeedMin) / kSpeedStep).round();

/// Rounds to the slider's step and clamps: 0.05 in double leaves tails, and
/// `1.3000000000000003` would reach the disk.
double clampRate(double rate) {
  if (!rate.isFinite) return 1;
  final snapped = (rate / kSpeedStep).round() * kSpeedStep;
  final rounded = (snapped * 100).round() / 100;
  return rounded.clamp(kSpeedMin, kSpeedMax);
}

/// `1×`, `1.35×`, with no trailing zeros.
String speedLabel(double rate) {
  var text = rate.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return '$text×';
}

class SpeedSettings {
  const SpeedSettings({this.rate = 1, this.nightcore = false});

  /// Current playback speed ([kSpeedMin]…[kSpeedMax]).
  final double rate;

  /// Nightcore: pitch follows tempo. Off, pitch holds.
  final bool nightcore;

  /// Pitch multiplier for the player. With nightcore off it's exactly 1: pitch
  /// holds by itself (ExoPlayer stretches tempo through sonic).
  double get pitch => nightcore ? rate : 1;

  SpeedSettings copyWith({double? rate, bool? nightcore}) => SpeedSettings(
    rate: rate ?? this.rate,
    nightcore: nightcore ?? this.nightcore,
  );
}

final speedProvider = NotifierProvider<SpeedController, SpeedSettings>(
  SpeedController.new,
);

class SpeedController extends Notifier<SpeedSettings> {
  static const _key = 'speed';

  @override
  SpeedSettings build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    final rate = raw['rate'];
    return SpeedSettings(
      // A broken entry silently becomes 1×: a speed is no reason to crash a
      // launch.
      rate: rate is num ? clampRate(rate.toDouble()) : 1,
      nightcore: raw['nightcore'] == true,
    );
  }

  void setRate(double rate) {
    final value = clampRate(rate);
    if (value == state.rate) return;
    state = state.copyWith(rate: value);
    _save();
  }

  /// Resets to 1×, on a tap of the current value's pill.
  void reset() => setRate(1);

  void setNightcore(bool on) {
    if (on == state.nightcore) return;
    state = state.copyWith(nightcore: on);
    _save();
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, {
    'rate': state.rate,
    'nightcore': state.nightcore,
  });
}
