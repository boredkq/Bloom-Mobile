/// Telegram auth: parsing, persistence and state.
library;

import 'package:bloom/core/db/db.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/telegram/telegram_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  test('по умолчанию Telegram не авторизован', () {
    final c = _container(JsonStore.memory());
    final state = c.read(telegramAuthProvider);
    expect(state.authed, isFalse);
    expect(state.user, isNull);
  });

  test('разбор пользователя из JSON и сохранение в store', () {
    final store = JsonStore.memory();
    final c = _container(store);

    c.read(telegramAuthProvider.notifier).loginWithData({
      'id': 12345678,
      'first_name': 'Pavel',
      'last_name': 'Durov',
      'username': 'durov',
      'photo_url': 'https://t.me/i/userpic/320/durov.jpg',
      'auth_date': 1700000000,
    });

    final state = c.read(telegramAuthProvider);
    expect(state.authed, isTrue);
    expect(state.user?.id, 12345678);
    expect(state.user?.displayName, 'Pavel Durov');
    expect(state.user?.handle, '@durov');
    expect(state.user?.photoUrl, 'https://t.me/i/userpic/320/durov.jpg');

    // Проверяем персист в JsonStore
    final saved = store.readMap('telegram');
    expect(saved['first_name'], 'Pavel');
    expect(saved['username'], 'durov');
  });

  test('выход очищает данные пользователя', () {
    final store = JsonStore.memory({
      'telegram': {
        'id': 999,
        'first_name': 'Alice',
        'auth_date': 1700000000,
      },
    });
    final c = _container(store);
    expect(c.read(telegramAuthProvider).authed, isTrue);

    c.read(telegramAuthProvider.notifier).logout();
    expect(c.read(telegramAuthProvider).authed, isFalse);
    expect(c.read(telegramAuthProvider).user, isNull);
    expect(store.readMap('telegram'), isEmpty);
  });
}
