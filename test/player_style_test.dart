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
  });

  test("a style I don't have means the regular player", () {
    final c = _container(JsonStore.memory({'playerStyle': 'cinema'}));
    expect(c.read(playerStyleProvider), PlayerStyle.standard);
  });

  test('the choice reaches the disk', () {
    final store = JsonStore.memory();
    final c = _container(store);
    c.read(playerStyleProvider.notifier).setStyle(PlayerStyle.vinyl);
    expect(c.read(playerStyleProvider), PlayerStyle.vinyl);
    expect(store.read('playerStyle'), 'vinyl');

    c.read(playerStyleProvider.notifier).setStyle(PlayerStyle.standard);
    expect(store.read('playerStyle'), 'standard');
  });
}
