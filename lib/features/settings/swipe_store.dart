/// What a finger's move left and right does in each of four places: library,
/// queue, mini player, player.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

/// One list in all four places: a library row can do "Next" too, and the player
/// "Delete".
enum SwipeAction {
  /// No swipe: the row doesn't move, the player doesn't flip.
  none,

  /// Toggles the track's like.
  like,

  /// To the end of the queue.
  queue,

  /// Right after the current one.
  playNext,

  next,

  prev,

  /// An offline copy inside the app.
  download,

  /// A row from its list, a track in the player from the queue.
  delete,
}

enum SwipeZone { library, queue, mini, player }

class SwipePair {
  const SwipePair(this.left, this.right);

  /// The row goes left, the plate comes out on the right.
  final SwipeAction left;

  final SwipeAction right;

  SwipePair withSide(bool isLeft, SwipeAction action) =>
      isLeft ? SwipePair(action, right) : SwipePair(left, action);
}

/// In lists left deletes and right queues; in the queue both delete; the
/// players flip tracks.
const Map<SwipeZone, SwipePair> kDefaultSwipes = {
  SwipeZone.library: SwipePair(SwipeAction.delete, SwipeAction.queue),
  SwipeZone.queue: SwipePair(SwipeAction.delete, SwipeAction.delete),
  SwipeZone.mini: SwipePair(SwipeAction.next, SwipeAction.prev),
  SwipeZone.player: SwipePair(SwipeAction.next, SwipeAction.prev),
};

class SwipeSettings {
  const SwipeSettings({this.zones = kDefaultSwipes});

  final Map<SwipeZone, SwipePair> zones;

  SwipePair of(SwipeZone zone) => zones[zone] ?? kDefaultSwipes[zone]!;

  SwipeSettings withZone(SwipeZone zone, SwipePair pair) =>
      SwipeSettings(zones: {...zones, zone: pair});
}

final swipeProvider = NotifierProvider<SwipeController, SwipeSettings>(
  SwipeController.new,
);

class SwipeController extends Notifier<SwipeSettings> {
  @override
  SwipeSettings build() {
    final raw = ref.read(jsonStoreProvider).readMap('swipes');
    return SwipeSettings(
      zones: {
        for (final zone in SwipeZone.values)
          zone: _pairFromJson(raw[zone.name], kDefaultSwipes[zone]!),
      },
    );
  }

  void setAction(
    SwipeZone zone, {
    required bool isLeft,
    required SwipeAction action,
  }) {
    state = state.withZone(zone, state.of(zone).withSide(isLeft, action));
    _save();
  }

  void _save() => ref.read(jsonStoreProvider).write('swipes', {
    for (final zone in SwipeZone.values)
      zone.name: {
        'left': state.of(zone).left.name,
        'right': state.of(zone).right.name,
      },
  });
}

/// A broken or unknown entry becomes the default: gestures are no reason to
/// fail a launch.
SwipePair _pairFromJson(Object? raw, SwipePair fallback) {
  if (raw is! Map) return fallback;
  return SwipePair(
    _actionFromJson(raw['left'], fallback.left),
    _actionFromJson(raw['right'], fallback.right),
  );
}

SwipeAction _actionFromJson(Object? raw, SwipeAction fallback) {
  for (final action in SwipeAction.values) {
    if (action.name == raw) return action;
  }
  return fallback;
}
