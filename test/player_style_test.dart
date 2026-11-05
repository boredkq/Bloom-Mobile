/// The player style: persisting and parsing the stored value.
///
/// I check what breaks quietly: sync can bring in a value I don't have
/// (`large`, `cinema`), and the player mustn't crash on it.
library;

import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/player/player_style_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

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
  test('the regular player by default', () {
    final c = _container(JsonStore.memory());
    expect(c.read(playerStyleProvider), PlayerStyle.standard);
    expect(c.read(playerStyleProvider).isVinyl, isFalse);
  });

  test('the chosen style is read from disk', () {
    final c = _container(JsonStore.memory({'playerStyle': 'vinyl'}));
    expect(c.read(playerStyleProvider), PlayerStyle.vinyl);
    expect(c.read(playerStyleProvider).isVinyl, isTrue);

    final aura = _container(JsonStore.memory({'playerStyle': 'aura'}));
    expect(aura.read(playerStyleProvider), PlayerStyle.aura);

    final flow = _container(JsonStore.memory({'playerStyle': 'flow'}));
    expect(flow.read(playerStyleProvider), PlayerStyle.flow);

    final apple = _container(JsonStore.memory({'playerStyle': 'appleMusic'}));
    expect(apple.read(playerStyleProvider), PlayerStyle.appleMusic);
    expect(apple.read(playerStyleProvider).isAppleMusic, isTrue);

    final spotify = _container(JsonStore.memory({'playerStyle': 'spotify'}));
    expect(spotify.read(playerStyleProvider), PlayerStyle.spotify);
    expect(spotify.read(playerStyleProvider).isSpotify, isTrue);

    final ytm = _container(JsonStore.memory({'playerStyle': 'youtubeMusic'}));
    expect(ytm.read(playerStyleProvider), PlayerStyle.youtubeMusic);
    expect(ytm.read(playerStyleProvider).isYouTubeMusic, isTrue);
  });

  test('levyra aliases map to identical styles', () {
    expect(PlayerStyle.of('velvet'), PlayerStyle.aura);
    expect(PlayerStyle.of('canvas_immersive'), PlayerStyle.aura);
    expect(PlayerStyle.of('canvas_card'), PlayerStyle.sleeve);
    expect(PlayerStyle.of('card'), PlayerStyle.sleeve);
    expect(PlayerStyle.of('editorial'), PlayerStyle.folio);
    expect(PlayerStyle.of('gallery'), PlayerStyle.poster);
    expect(PlayerStyle.of('artwork'), PlayerStyle.poster);
    expect(PlayerStyle.of('halo'), PlayerStyle.halo);
    expect(PlayerStyle.of('pulse'), PlayerStyle.pulse);
    expect(PlayerStyle.of('expressive'), PlayerStyle.expressive);
    expect(PlayerStyle.of('apple_music'), PlayerStyle.appleMusic);
    expect(PlayerStyle.of('apple'), PlayerStyle.appleMusic);
    expect(PlayerStyle.of('applemusic'), PlayerStyle.appleMusic);
    expect(PlayerStyle.of('spotify'), PlayerStyle.spotify);
    expect(PlayerStyle.of('spotify_style'), PlayerStyle.spotify);
    expect(PlayerStyle.of('youtube_music'), PlayerStyle.youtubeMusic);
    expect(PlayerStyle.of('ytm'), PlayerStyle.youtubeMusic);
    expect(PlayerStyle.of('youtube'), PlayerStyle.youtubeMusic);
  });

  test("a style I don't have means the regular player", () {
    final c = _container(JsonStore.memory({'playerStyle': 'cinema'}));
    expect(c.read(playerStyleProvider), PlayerStyle.standard);
  });

  test('the choice reaches the disk', () {
    final store = JsonStore.memory();
    final c = _container(store);
    c.read(playerStyleProvider.notifier).setStyle(PlayerStyle.aura);
    expect(c.read(playerStyleProvider), PlayerStyle.aura);
    expect(store.read('playerStyle'), 'aura');

    c.read(playerStyleProvider.notifier).setStyle(PlayerStyle.flow);
    expect(store.read('playerStyle'), 'flow');

    c.read(playerStyleProvider.notifier).setStyle(PlayerStyle.standard);
    expect(store.read('playerStyle'), 'standard');
  });
}
