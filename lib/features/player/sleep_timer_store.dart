/// Sleep timer: when a pause comes by itself. The store is CLEAN, like
/// `speed_store`: it knows only time and mode, and `PlaybackController`, the
/// player's sole owner, does the pause and fade by subscribing here.
///
/// Time runs on the WALL CLOCK (`endsAt`), not by subtracting per tick: a
/// background tick can run late, and half an hour must mean half an hour. So a
/// manual pause doesn't stop the timer, it runs on like an alarm.
///
/// An active timer isn't saved: it needn't survive a process restart, since the
/// music is silent after one. The file holds only settings: the fade and last
/// chosen time.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

/// Preset cards of the sheet.
const List<Duration> kSleepPresets = [
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(minutes: 60),
  Duration(minutes: 90),
];

/// Bounds and step of the custom time bar, in minutes.
const int kSleepMinMinutes = 5;
const int kSleepMaxMinutes = 120;
const int kSleepStepMinutes = 5;

/// Divisions of the bar.
int get kSleepDivisions =>
    (kSleepMaxMinutes - kSleepMinMinutes) ~/ kSleepStepMinutes;

/// What the +5 minutes button adds to a running timer.
const Duration kSleepExtend = Duration(minutes: 5);

/// Fade length before the pause. It counts BACK from firing: 30 minutes with a
/// fade means silence right at minute thirty.
const Duration kSleepFade = Duration(seconds: 20);

enum SleepMode {
  /// No timer.
  off,

  /// Pause at the set time ([SleepTimerState.endsAt]).
  timer,

  /// Pause when the current track ends, however much is left.
  endOfTrack,
}

class SleepTimerState {
  const SleepTimerState({
    this.mode = SleepMode.off,
    this.endsAt,
    this.remaining = Duration.zero,
    this.choice = const Duration(minutes: 30),
    this.fade = true,
  });

  final SleepMode mode;

  /// Firing moment; not `null` only in [SleepMode.timer].
  final DateTime? endsAt;

  /// Time left, recounted on the last tick. Zero in [SleepMode.timer] tells the
  /// controller to pause.
  final Duration remaining;

  /// Last chosen time, where the custom bar opens.
  final Duration choice;

  /// Fades the volume to zero before the pause.
  final bool fade;

  bool get active => mode != SleepMode.off;

  /// The timer hit zero and waits to be carried out.
  bool get expired => mode == SleepMode.timer && remaining <= Duration.zero;

  SleepTimerState copyWith({
    SleepMode? mode,
    DateTime? endsAt,
    bool clearEndsAt = false,
    Duration? remaining,
    Duration? choice,
    bool? fade,
  }) => SleepTimerState(
    mode: mode ?? this.mode,
    endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
    remaining: remaining ?? this.remaining,
    choice: choice ?? this.choice,
    fade: fade ?? this.fade,
  );
}

/// The store's clock as its own provider, so tests can swap now instead of
/// waiting half an hour.
final sleepClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final sleepTimerProvider =
    NotifierProvider<SleepTimerController, SleepTimerState>(
      SleepTimerController.new,
    );

class SleepTimerController extends Notifier<SleepTimerState> {
  static const _key = 'sleep';

  /// Tick of the time left, for the button's caption; it also brings it to
  /// zero, which is when the player controller pauses.
  Timer? _tick;

  DateTime get _now => ref.read(sleepClockProvider)();

  @override
  SleepTimerState build() {
    final raw = ref.read(jsonStoreProvider).readMap(_key);
    final minutes = raw['minutes'];
    ref.onDispose(() => _tick?.cancel());
    return SleepTimerState(
      choice: minutes is num
          ? Duration(minutes: clampSleepMinutes(minutes.round()))
          : const Duration(minutes: 30),
      // A broken entry reads as fade on, the default.
      fade: raw['fade'] != false,
    );
  }

  /// Starts a timer for [d] afresh from this second. The slider calls this on
  /// every move: the time follows the finger, with no Start button.
  ///
  /// The UI handles cancelling (a tap on the selected preset): [d] also comes
  /// from the slider, where matching the current choice means nothing.
  void start(Duration d) {
    _tick?.cancel();
    state = state.copyWith(
      mode: SleepMode.timer,
      endsAt: _now.add(d),
      remaining: d,
      choice: d,
    );
    _save();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  /// Until the end of the track. The mode has no time of its own, it waits for
  /// `_onCompleted` in the player, so no tick.
  void untilTrackEnd() {
    _tick?.cancel();
    _tick = null;
    state = state.copyWith(
      mode: SleepMode.endOfTrack,
      clearEndsAt: true,
      remaining: Duration.zero,
    );
  }

  /// +5 minutes on a running timer. Counted FROM THE SET TIME, not now: pressed
  /// a minute before the end, it would otherwise take away four.
  void extend([Duration by = kSleepExtend]) {
    final endsAt = state.endsAt;
    if (state.mode != SleepMode.timer || endsAt == null) return;
    final next = endsAt.add(by);
    state = state.copyWith(endsAt: next, remaining: next.difference(_now));
    // The tick may have stopped at zero; if extended in the last second, it
    // starts again.
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void cancel() {
    _tick?.cancel();
    _tick = null;
    if (!state.active) return;
    state = state.copyWith(
      mode: SleepMode.off,
      clearEndsAt: true,
      remaining: Duration.zero,
    );
  }

  void setFade(bool on) {
    if (on == state.fade) return;
    state = state.copyWith(fade: on);
    _save();
  }

  void _onTick() {
    final endsAt = state.endsAt;
    if (state.mode != SleepMode.timer || endsAt == null) return;
    final left = endsAt.difference(_now);
    if (left <= Duration.zero) {
      // Nothing left to tick: zero is the signal, cleared by the player
      // controller when it pauses.
      _tick?.cancel();
      _tick = null;
      state = state.copyWith(remaining: Duration.zero);
      return;
    }
    state = state.copyWith(remaining: left);
  }

  void _save() => ref.read(jsonStoreProvider).write(_key, {
    'minutes': state.choice.inMinutes,
    'fade': state.fade,
  });
}

/// Clamps minutes to the custom bar's bounds.
int clampSleepMinutes(int minutes) =>
    minutes.clamp(kSleepMinMinutes, kSleepMaxMinutes);

/// Time left on the tool row's button: `23:14` up to an hour and `1:05` after.
/// Hours and minutes there, or `1:05:00` won't fit and FittedBox shrinks it
/// past reading.
///
/// Seconds round UP: `0:00` while sound still plays is a lie.
String sleepLabel(Duration left) {
  final total = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  if (total >= 3600) {
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
