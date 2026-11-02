/// The interface font: the catalog, recognizing a saved choice (a CSS stack
/// included) and storing it in settings.
library;

import 'package:bloom/app/theme/fonts.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/settings/user_fonts.dart';
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
  group('normalizeFont', () {
    test('десктопный CSS-стек узнаётся по первому семейству', () {
      expect(
        normalizeFont("'Minecraft Rus',monospace", const []),
        'Minecraft Rus',
      );
      expect(normalizeFont('Inter, system-ui, sans-serif', const []), 'Inter');
    });

    test('Monocraft переезжает на Minecraft Rus', () {
      expect(normalizeFont("'Monocraft',monospace", const []), 'Minecraft Rus');
    });

    test('Comic Sans, мусор и пустота — Inter', () {
      expect(normalizeFont("'Comic Sans MS',cursive", const []), kDefaultFont);
      expect(normalizeFont(42, const []), kDefaultFont);
      expect(normalizeFont(null, const []), kDefaultFont);
    });

    test('свой шрифт узнаётся, пока он есть в списке', () {
      expect(
        normalizeFont('bloomfont-uf1', const ['bloomfont-uf1']),
        'bloomfont-uf1',
      );
      expect(normalizeFont('bloomfont-uf1', const []), kDefaultFont);
    });
  });

  test('сигнатура файла шрифта', () {
    expect(looksLikeFont([0, 1, 0, 0, ...List.filled(8, 0)]), isTrue);
    expect(looksLikeFont('OTTO'.codeUnits + List.filled(8, 0)), isTrue);
    expect(looksLikeFont('PK'.codeUnits + List.filled(8, 0)), isFalse);
    expect(looksLikeFont([0, 1, 0, 0]), isFalse);
  });

  test('имя плитки — имя файла без расширения, не длиннее 40', () {
    expect(fontNameFromFile('JetBrainsMono-Bold.ttf'), 'JetBrainsMono-Bold');
    expect(fontNameFromFile('.ttf'), '.ttf');
    expect(fontNameFromFile('${'a' * 50}.otf').length, 40);
  });

  test('выбор шрифта сохраняется и переживает перезапуск', () {
    final store = JsonStore.memory();
    final c = _container(store);
    expect(c.read(uiFontProvider), kDefaultFont);
    c.read(settingsProvider.notifier).setFontFamily('Minecraft Rus');
    expect(c.read(uiFontProvider), 'Minecraft Rus');

    final again = _container(store);
    expect(again.read(settingsProvider).fontFamily, 'Minecraft Rus');
  });

  test('выбранный свой шрифт без записи в сторе рисуется Inter', () {
    final store = JsonStore.memory();
    final c = _container(store);
    c.read(settingsProvider.notifier).setFontFamily('bloomfont-gone');
    expect(c.read(uiFontProvider), kDefaultFont);
  });

  test('неподходящие файлы отсеиваются до чтения', () async {
    final c = _container(JsonStore.memory());
    var reads = 0;
    final res = await c.read(userFontsProvider.notifier).addFiles([
      (
        name: 'font.woff2',
        size: 100,
        read: () async {
          reads++;
          return throw 0;
        },
      ),
      (
        name: 'huge.ttf',
        size: kMaxFontBytes + 1,
        read: () async {
          reads++;
          return throw 0;
        },
      ),
    ]);
    expect(res.added, 0);
    expect(res.errors, {FontAddError.format, FontAddError.size});
    expect(reads, 0);
    expect(c.read(userFontsProvider), isEmpty);
  });
}
