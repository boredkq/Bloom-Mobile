/// The "Up next" pill under the slider: who it names and how the setting is
/// stored.
///
/// I check what breaks quietly. "Next" on the last track depends on repeat:
/// with `all` the queue loops ([PlaybackController.next] goes `(index + 1) %
/// length`), with `off` and `one` nothing follows. A mistake here would name
/// the wrong track while the player plays the right one.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/features/player/player_view_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Трек $id',
  artist: 'Артист $id',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

PlaybackState _state({
  int length = 3,
  required int index,
  PlayerRepeat repeat = PlayerRepeat.off,
}) => PlaybackState(
  queue: [for (var i = 0; i < length; i++) _track('$i')],
  index: index,
  repeat: repeat,
);

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group("who's next", () {
    test('mid-queue: the adjacent track', () {
      expect(_state(index: 0).nextTrack?.id, '1');
      expect(_state(index: 1).nextTrack?.id, '2');
    });

    test('last with no repeat: nobody', () {
      expect(_state(index: 2).nextTrack, isNull);
      expect(_state(index: 2, repeat: PlayerRepeat.one).nextTrack, isNull);
    });

    test('last with queue repeat: the first track', () {
      expect(_state(index: 2, repeat: PlayerRepeat.all).nextTrack?.id, '0');
    });

    test('a one-track queue stays silent even with repeat', () {
      expect(_state(length: 1, index: 0).nextTrack, isNull);
      expect(
        _state(length: 1, index: 0, repeat: PlayerRepeat.all).nextTrack,
        isNull,
      );
    });

    test('an empty queue and a snapshot with nothing playing: nobody', () {
      expect(const PlaybackState().nextTrack, isNull);
      expect(_state(index: -1).nextTrack, isNull);
    });
  });

  group('setting', () {
    test('the pill is on by default', () {
      expect(_container(JsonStore.memory()).read(nextUpProvider), isTrue);
    });

    test('turned off is read from disk', () {
      final c = _container(
        JsonStore.memory({
          'playerView': {'nextUp': false},
        }),
      );
      expect(c.read(nextUpProvider), isFalse);
    });

    test('an unknown entry means the default, not a crash', () {
      final c = _container(
        JsonStore.memory({
          'playerView': {'nextUp': 'yes'},
        }),
      );
      expect(c.read(nextUpProvider), isTrue);
    });

    test('the choice reaches the disk and keeps the neighboring setting', () {
      final store = JsonStore.memory({
        'playerView': {'titleAlign': 'left'},
      });
      final c = _container(store);
      c.read(nextUpProvider.notifier).set(false);

      final saved = store.read('playerView')! as Map;
      expect(saved['nextUp'], false);
      expect(saved['titleAlign'], 'left');
      expect(c.read(titleAlignProvider), TitleAlign.left);
    });
  });
}
