/// Daily home shelf, shared by For you and Similar to: a day's cache, quiet
/// retries and a reset.
///
/// A selection lives a day: rebuilding per visit loses a track the user noticed
/// but didn't open. The cache holds the tracks themselves, not ids, or a
/// platform track couldn't play after a restart.
///
/// With no data there's no shelf at all (no skeleton or error): an empty place
/// is more honest than a blinking stand-in. An empty result isn't cached and
/// quietly retries: it's almost always the network or Yandex not yet logged in.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../../providers/yandex/ym_auth.dart';

/// Pauses before quiet retries; after the last I give up until the next launch
/// or Yandex login.
const List<Duration> kShowcaseRetries = [
  Duration(milliseconds: 1500),
  Duration(seconds: 4),
];

/// Local day, not UTC: a selection changes by the user's calendar.
String showcaseDay(DateTime now) => '${now.year}-${now.month}-${now.day}';

abstract class DailyShowcase<T extends Object> extends Notifier<T?> {
  /// Cache key in `bloom.json`.
  String get storeKey;

  /// Version of the selection LOGIC. Raise it on changing rules, or results
  /// built by the old ones hang until midnight. Apart from the key, so
  /// abandoned entries don't pile up in `bloom.json`.
  int get version => 1;

  /// Builds the shelf. `null` means nothing to show, and a retry follows.
  Future<T?> fetch();

  Object? encode(T value);
  T? decode(Object? raw);

  /// The build under way, returned by a second [load] and available to wait
  /// for.
  Future<void>? _pending;

  /// Build generation: a reset mid-request shouldn't let an old answer land
  /// over a new shelf.
  int _gen = 0;

  /// The provider is closed, so a network answer has nowhere to go (`state`
  /// would throw).
  bool _disposed = false;

  bool _stale(int gen) => _disposed || gen != _gen;

  @override
  T? build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // Yandex adds a platform during a session, so an empty shelf is worth
    // another try once it logs in.
    ref.listen(ymAuthProvider.select((s) => s.authed), (_, _) {
      if (state == null) unawaited(load());
    });
    final cached = _readCache();
    if (cached == null) scheduleMicrotask(() => unawaited(load()));
    return cached;
  }

  T? _readCache() {
    final raw = ref.read(jsonStoreProvider).read(storeKey);
    if (raw is! Map || raw['day'] != showcaseDay(DateTime.now())) return null;
    if ((raw['v'] ?? 1) != version) return null;
    try {
      return decode(raw['data']);
    } on Object {
      return null;
    }
  }

  /// Builds with quiet retries. A build under way starts no second; it's
  /// returned instead.
  Future<void> load() {
    final running = _pending;
    if (running != null) return running;
    late final Future<void> job;
    job = _load().whenComplete(() {
      // After a reset there's a new build here, not to be touched.
      if (identical(_pending, job)) _pending = null;
    });
    return _pending = job;
  }

  /// Waits for a build under way, if any. For a neighbouring shelf checking
  /// against this one: both build at once in the morning, and with no wait
  /// there'd be nothing to check against.
  Future<void> settled() => _pending ?? Future<void>.value();

  Future<void> _load() async {
    final gen = ++_gen;
    for (var attempt = 0; ; attempt++) {
      T? value;
      try {
        value = await fetch();
      } on Object {
        // The shelf just won't appear, with no harm to home.
        value = null;
      }
      if (_stale(gen)) return;
      if (value != null) {
        state = value;
        ref.read(jsonStoreProvider).write(storeKey, {
          'day': showcaseDay(DateTime.now()),
          'v': version,
          'data': encode(value),
        });
        return;
      }
      if (attempt >= kShowcaseRetries.length) return;
      await Future<void>.delayed(kShowcaseRetries[attempt]);
      if (_stale(gen)) return;
    }
  }

  /// Forgets the shelf and rebuilds, part of clearing stats: its seeds came
  /// from the erased top, with no reason to live until midnight.
  void reset() {
    _gen++;
    _pending = null;
    ref.read(jsonStoreProvider).removeAll([storeKey]);
    state = null;
    unawaited(load());
  }
}
