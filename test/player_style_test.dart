/// Стиль плеера: персист и разбор записи с диска.
///
/// Проверяем то, что ломается тихо: в `bloom.json` могла приехать десктопная
/// запись (`large`, `cinema`) — таких стилей у нас нет, и молча падать из-за
/// них плеер не должен.
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
  test('по умолчанию — обычный плеер', () {
    final c = _container(JsonStore.memory());
    expect(c.read(playerStyleProvider), PlayerStyle.standard);
    expect(c.read(playerStyleProvider).isVinyl, isFalse);
  });

  test('выбранный стиль читается с диска', () {
    final c = _container(JsonStore.memory({'playerStyle': 'vinyl'}));
    expect(c.read(playerStyleProvider), PlayerStyle.vinyl);
    expect(c.read(playerStyleProvider).isVinyl, isTrue);

    final cAura = _container(JsonStore.memory({'playerStyle': 'aura'}));
    expect(cAura.read(playerStyleProvider), PlayerStyle.aura);
    expect(cAura.read(playerStyleProvider).isAura, isTrue);

    final cIvory = _container(JsonStore.memory({'playerStyle': 'ivory'}));
    expect(cIvory.read(playerStyleProvider), PlayerStyle.ivory);
    expect(cIvory.read(playerStyleProvider).isIvory, isTrue);
  });

  test('десктопный стиль, которого у нас нет, — это обычный плеер', () {
    final c = _container(JsonStore.memory({'playerStyle': 'cinema'}));
    expect(c.read(playerStyleProvider), PlayerStyle.standard);
  });

  test('выбор уезжает на диск', () {
    final store = JsonStore.memory();
    final c = _container(store);
    c.read(playerStyleProvider.notifier).setStyle(PlayerStyle.vinyl);
    expect(c.read(playerStyleProvider), PlayerStyle.vinyl);
    expect(store.read('playerStyle'), 'vinyl');

    c.read(playerStyleProvider.notifier).setStyle(PlayerStyle.aura);
    expect(c.read(playerStyleProvider), PlayerStyle.aura);
    expect(store.read('playerStyle'), 'aura');

    c.read(playerStyleProvider.notifier).setStyle(PlayerStyle.ivory);
    expect(c.read(playerStyleProvider), PlayerStyle.ivory);
    expect(store.read('playerStyle'), 'ivory');

    c.read(playerStyleProvider.notifier).setStyle(PlayerStyle.standard);
    expect(store.read('playerStyle'), 'standard');
  });
}
