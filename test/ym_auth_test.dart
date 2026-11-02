/// Yandex Music sign-in: what survives a restart and when the platform takes
/// part in search at all. The store is in memory, no network.
library;

import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/providers/yandex/models.dart';
import 'package:bloom/providers/yandex/yandex.dart' as ym;
import 'package:bloom/providers/yandex/ym_auth.dart';
import 'package:bloom/providers/yandex/ym_provider.dart';
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
  setUp(() => ym.setToken(null));
  tearDown(() => ym.setToken(null));

  test('сохранённый токен поднимается при старте и включает площадку', () {
    final store = JsonStore.memory({
      'yandex': {'token': 'saved-token'},
    });
    final c = _container(store);

    expect(
      const YandexProvider().isEnabled,
      isFalse,
      reason: 'до чтения стора',
    );
    expect(c.read(ymAuthProvider).authed, isTrue);
    // The token goes to the network layer, or the very first request would
    // leave without it.
    expect(ym.activeToken(), 'saved-token');
    expect(const YandexProvider().isEnabled, isTrue);
  });

  test('пустое хранилище — площадка выключена', () {
    final c = _container(JsonStore.memory());
    expect(c.read(ymAuthProvider).authed, isFalse);
    expect(ym.activeToken(), isNull);
    expect(const YandexProvider().isEnabled, isFalse);
  });

  test('выход стирает токен и с диска, и из сетевого слоя', () {
    final store = JsonStore.memory({
      'yandex': {'token': 'saved-token', 'deviceId': 'abcdef0123456789'},
    });
    final c = _container(store);
    c.read(ymAuthProvider);

    c.read(ymAuthProvider.notifier).logout();

    expect(c.read(ymAuthProvider).authed, isFalse);
    expect(ym.activeToken(), isNull);
    final raw = store.readMap('yandex');
    expect(raw['token'], isNull);
    // The device id survives signing out: it belongs to the install, not the
    // account.
    expect(raw['deviceId'], 'abcdef0123456789');
  });

  test('статус подписки не проверяется, пока не вошли', () async {
    final c = _container(JsonStore.memory());
    await c.read(ymAuthProvider.notifier).refresh();
    // No network here: if the refresh went to the API, the test would fail on
    // the exception.
    expect(c.read(ymAuthProvider).hasPlus, isNull);
    expect(c.read(ymAuthProvider).checking, isFalse);
  });

  test('отмена входа гасит поллинг и убирает код с экрана', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(ymAuthProvider.notifier);

    notifier.cancelAuth();

    final s = c.read(ymAuthProvider);
    expect(s.connecting, isFalse);
    expect(s.userCode, isNull);
    expect(s.note, isNull);
  });

  test('причина отказа доезжает до UI кодом, а не «Instance of»', () {
    expect(
      ymErrorCode(const YmException('ym.err.needPlus')),
      'ym.err.needPlus',
    );
    // An error that surfaced through toString, as it comes from the store's
    // state.
    expect(ymErrorCode('YmException: ym.err.auth'), 'ym.err.auth');
  });
}
