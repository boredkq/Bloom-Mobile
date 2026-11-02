/// Customization: the picture library, contexts, presets and their file.
///
/// I check what breaks quietly: a removed picture must leave contexts and
/// presets too (or the background points nowhere), an own background picture
/// must beat "cover as background", and the presets file must survive an export
/// and import with the same pictures and no duplicates in the library.
library;

import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/customization/custom_store.dart';
import 'package:bloom/features/customization/media_store.dart';
import 'package:bloom/features/customization/presets_file.dart';
import 'package:bloom/features/customization/presets_store.dart';
import 'package:bloom/features/settings/transparency_store.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';

ProviderContainer _container([JsonStore? store]) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store ?? JsonStore.memory()),
      dbProvider.overrideWithValue(BloomDb.memory()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Adds a picture by URL, the only route that needs no disk.
String _add(ProviderContainer c, String url) {
  expect(c.read(mediaLibProvider.notifier).addUrl(url), isTrue);
  return c.read(mediaLibProvider).last.id;
}

void main() {
  group('библиотека', () {
    test('ссылку принимаем, мусор — нет', () {
      final c = _container();
      final lib = c.read(mediaLibProvider.notifier);
      expect(lib.addUrl('https://example.com/a.gif'), isTrue);
      expect(lib.addUrl('ftp://example.com/a.gif'), isFalse);
      expect(lib.addUrl('  '), isFalse);
      expect(c.read(mediaLibProvider), hasLength(1));
      expect(c.read(mediaLibProvider).single.name, 'a.gif');
    });

    test('имя из ссылки не тащит параметры запроса', () {
      expect(urlName('https://e.com/pic.png?w=1&h=2'), 'pic.png');
      expect(urlName('https://e.com/'), 'image');
    });

    test('размытие и затемнение живут у картинки и переживают перезапуск', () {
      final store = JsonStore.memory();
      final c = _container(store);
      final id = _add(c, 'https://e.com/a.jpg');
      c.read(mediaLibProvider.notifier).setBlur(id, 40);
      c.read(mediaLibProvider.notifier).setDim(id, 200); // above the ceiling
      final fresh = _container(store);
      final item = fresh.read(mediaLibProvider).single;
      expect(item.blur, 40);
      expect(item.dim, kBgDimMax);
    });

    test('битую запись из файла молча пропускаем', () {
      final store = JsonStore.memory({
        'media': [
          {'id': 'ml1', 'src': 'https://e.com/a.jpg'},
          {'id': 'ml2'}, // no picture
          'мусор',
        ],
      });
      expect(_container(store).read(mediaLibProvider), hasLength(1));
    });
  });

  group('контексты', () {
    test('контекст держит одну картинку', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      final b = _add(c, 'https://e.com/b.jpg');
      final custom = c.read(customProvider.notifier);
      custom.toggle(CustomCtx.bg, a, true);
      custom.toggle(CustomCtx.bg, b, true);
      expect(c.read(customProvider).bg, b);
      // Turning off another picture doesn't remove the active one.
      custom.toggle(CustomCtx.bg, a, false);
      expect(c.read(customProvider).bg, b);
      custom.toggle(CustomCtx.bg, b, false);
      expect(c.read(customProvider).bg, isNull);
    });

    test('одна картинка может стоять сразу в двух контекстах', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      c.read(customProvider.notifier).toggle(CustomCtx.slider, a, true);
      expect(c.read(customSrcProvider(CustomCtx.bg)), 'https://e.com/a.jpg');
      expect(
        c.read(customSrcProvider(CustomCtx.slider)),
        'https://e.com/a.jpg',
      );
      expect(c.read(customSrcProvider(CustomCtx.cover)), isNull);
    });

    test('значки на плитке показывают занятые контексты по порядку', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      final b = _add(c, 'https://e.com/b.jpg');
      expect(c.read(mediaUsageProvider(a)), isEmpty);

      c.read(customProvider.notifier).toggle(CustomCtx.slider, a, true);
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      // The order follows the toggles on the picture page, not the order they
      // were turned on.
      expect(c.read(mediaUsageProvider(a)), [CustomCtx.bg, CustomCtx.slider]);
      expect(c.read(mediaUsageProvider(b)), isEmpty);

      // Another picture took over the context, so the badge must go.
      c.read(customProvider.notifier).toggle(CustomCtx.bg, b, true);
      expect(c.read(mediaUsageProvider(a)), [CustomCtx.slider]);
      expect(c.read(mediaUsageProvider(b)), [CustomCtx.bg]);
    });

    test('удаление картинки чистит контексты и пресеты', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      final b = _add(c, 'https://e.com/b.jpg');
      final custom = c.read(customProvider.notifier);
      custom.toggle(CustomCtx.bg, a, true);
      custom.toggle(CustomCtx.cover, b, true);
      expect(c.read(presetsProvider.notifier).save('оба'), isNotNull);

      removeMedia(c.read, a);
      expect(c.read(customProvider).bg, isNull);
      expect(c.read(customProvider).cover, b);
      expect(c.read(mediaLibProvider), hasLength(1));
      // The preset stays, without the removed picture.
      expect(c.read(presetsProvider).single.bg, isNull);
      expect(c.read(presetsProvider).single.cover, b);

      // The last one is gone, so the empty preset goes entirely.
      removeMedia(c.read, b);
      expect(c.read(presetsProvider), isEmpty);
      expect(c.read(mediaLibProvider), isEmpty);
    });
  });

  group('пресеты', () {
    test('пустые контексты сохранять нечего', () {
      final c = _container();
      expect(c.read(presetsProvider.notifier).save('пусто'), isNull);
      expect(c.read(presetsProvider), isEmpty);
    });

    test('применение ставит заданные контексты и не трогает пустые', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      final b = _add(c, 'https://e.com/b.jpg');
      final custom = c.read(customProvider.notifier);
      custom.toggle(CustomCtx.bg, a, true);
      final preset = c.read(presetsProvider.notifier).save('только фон')!;

      custom.set(CustomCtx.bg, null);
      custom.toggle(CustomCtx.cover, b, true);
      c.read(presetsProvider.notifier).apply(preset.id);
      expect(c.read(customProvider).bg, a);
      // The preset had no cover, so the current one stays as it is.
      expect(c.read(customProvider).cover, b);
    });

    test('размытие, затемнение и режим обложки снимаются в пресет', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      final b = _add(c, 'https://e.com/b.jpg');
      final lib = c.read(mediaLibProvider.notifier);
      final custom = c.read(customProvider.notifier);
      custom.toggle(CustomCtx.bg, a, true);
      custom.toggle(CustomCtx.cover, b, true);
      lib.setBlur(a, 30);
      lib.setDim(a, 40);
      c.read(coverModeProvider.notifier).set(CoverMode.fallback);
      final preset = c.read(presetsProvider.notifier).save('снимок')!;

      // I change everything after saving: the preset must bring its own back.
      lib.setBlur(a, 5);
      lib.setDim(a, 90);
      c.read(coverModeProvider.notifier).set(CoverMode.always);
      c.read(presetsProvider.notifier).apply(preset.id);
      final item = c.read(mediaLibProvider).firstWhere((i) => i.id == a);
      expect(item.blur, 30);
      expect(item.dim, 40);
      expect(c.read(coverModeProvider), CoverMode.fallback);
    });

    test('тема, прозрачность и шрифт — только по тумблерам', () {
      final store = JsonStore.memory();
      final c = _container(store);
      final a = _add(c, 'https://e.com/a.jpg');
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme('light');
      settings.setFontFamily('Inter');
      c.read(transparencyProvider.notifier).setOn(true);

      final plain = c.read(presetsProvider.notifier).save('без вида')!;
      expect(plain.theme, isNull);
      expect(plain.transparency, isNull);
      expect(plain.font, isNull);
      final full = c
          .read(presetsProvider.notifier)
          .save('с видом', theme: true, transparency: true, font: true)!;

      settings.setTheme('dark');
      settings.setFontFamily('Other');
      c.read(transparencyProvider.notifier).setOn(false);
      c.read(presetsProvider.notifier).apply(plain.id);
      expect(c.read(settingsProvider).themeId, 'dark');

      // A round trip through the store: the preset reads back the same.
      final fresh = _container(store);
      fresh.read(presetsProvider.notifier).apply(full.id);
      expect(fresh.read(settingsProvider).themeId, 'light');
      expect(fresh.read(settingsProvider).fontFamily, 'Inter');
      expect(fresh.read(transparencyProvider).on, isTrue);
    });

    test('своя тема из пресета возвращается, даже если её удалили', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      final settings = c.read(settingsProvider.notifier);
      final mine = settings.createCustomTheme(
        name: 'моя',
        bg: const Color(0xFF112233),
        blockColor: const Color(0xFF112233),
        accent: const Color(0xFFFF0000),
      );
      final preset = c
          .read(presetsProvider.notifier)
          .save('с темой', theme: true)!;
      settings.deleteCustomTheme(mine.id);

      c.read(presetsProvider.notifier).apply(preset.id);
      c.read(presetsProvider.notifier).apply(preset.id); // no duplicates
      final state = c.read(settingsProvider);
      expect(state.themeId, mine.id);
      expect(state.customThemes.where((t) => t.id == mine.id), hasLength(1));
    });

    test('пресет с видом переживает удаление всех картинок', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      c.read(presetsProvider.notifier).save('вид', font: true);
      removeMedia(c.read, a);
      final left = c.read(presetsProvider).single;
      expect(left.bg, isNull);
      expect(left.blur, isNull);
      expect(left.font, isNotNull);
    });

    test('лимит пресетов', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      for (var i = 0; i < kPresetsLimit; i++) {
        expect(c.read(presetsProvider.notifier).save('p$i'), isNotNull);
      }
      expect(c.read(presetsProvider.notifier).save('лишний'), isNull);
      expect(c.read(presetsProvider), hasLength(kPresetsLimit));
    });
  });

  group('файл пресетов', () {
    test(
      'круг выгрузка → загрузка сохраняет картинки и не плодит дубли',
      () async {
        final source = _container();
        final a = _add(source, 'https://e.com/a.jpg');
        final b = _add(source, 'https://e.com/b.gif');
        source.read(mediaLibProvider.notifier).setBlur(a, 24);
        source.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
        source.read(customProvider.notifier).toggle(CustomCtx.slider, b, true);
        final preset = source.read(presetsProvider.notifier).save('мой')!;

        final content = await encodePresets([
          preset,
        ], source.read(mediaLibProvider));

        // Another device: an empty library.
        final target = _container();
        expect(await importPresets(target.read, content), 1);
        expect(target.read(mediaLibProvider), hasLength(2));
        final imported = target.read(presetsProvider).single;
        expect(imported.name, 'мой');
        // The blur came along with the background picture.
        expect(
          target.read(mediaLibProvider.notifier).byId(imported.bg)!.blur,
          24,
        );
        expect(
          target.read(mediaLibProvider.notifier).byId(imported.slider)!.src,
          'https://e.com/b.gif',
        );

        // Importing the same file again: a second preset, the same pictures.
        expect(await importPresets(target.read, content), 1);
        expect(target.read(mediaLibProvider), hasLength(2));
        expect(target.read(presetsProvider), hasLength(2));
      },
    );

    test('чужой и битый файл не проходят', () async {
      final c = _container();
      expect(decodePresets('не json'), isEmpty);
      expect(decodePresets('{"kind":"чужое"}'), isEmpty);
      // A preset with no picture isn't a preset.
      expect(decodePresets('[{"name":"пусто"}]'), isEmpty);
      expect(await importPresets(c.read, 'не json'), 0);
    });

    test('голый массив пресетов тоже читаем', () {
      final parsed = decodePresets(
        '[{"name":"a","bg":"https://e.com/a.jpg","dim":50}]',
      );
      expect(parsed, hasLength(1));
      expect(parsed.single.dim, 50);
    });

    test(
      'вид пресета из файла ПК: #rrggbb, trMode, шрифт CSS-строкой',
      () async {
        final c = _container();
        final added = await importPresets(c.read, '''
{"kind":"bloom-presets","presets":[{
  "name":"с ПК","cover":"https://e.com/c.jpg","coverMode":"fallback",
  "theme":{"id":"custom_1","name":"Моя","bg":"#112233","blockColor":"#112233","accent":"#ff0000","custom":true},
  "transparency":{"trMode":"on","overlayGlass":true,"nativeTransparent":true,"blockOpacity":70,"glassStr":50,"glassBlur":10},
  "font":"'Minecraft Rus',monospace"
}]}''');
        expect(added, 1);
        final preset = c.read(presetsProvider).single;
        expect(preset.coverMode, CoverMode.fallback);
        expect(preset.transparency!.on, isTrue);
        expect(preset.transparency!.blockOpacity, 70);

        c.read(presetsProvider.notifier).apply(preset.id);
        final settings = c.read(settingsProvider);
        expect(settings.themeId, 'custom_1');
        expect(settings.preset.bg, const Color(0xFF112233));
        expect(c.read(coverModeProvider), CoverMode.fallback);

        // And back: the file holds the fields the computer reads.
        final json = preset.extrasToJson();
        expect((json['theme'] as Map)['accent'], '#ff0000');
        expect((json['transparency'] as Map)['trMode'], 'on');
      },
    );

    test('имя файла чистится от запрещённых символов', () {
      // Spaces stay: they're legal in file names.
      expect(presetFileName('лето/2026: ночь'), 'лето_2026_ ночь.bloompresets');
      expect(presetFileName('   '), 'preset.bloompresets');
    });
  });

  group('фон', () {
    test('своя картинка важнее обложки трека', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      c.read(settingsProvider.notifier).setCoverAsBg(true);
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      c.read(mediaLibProvider.notifier).setDim(a, 30);

      final bg = c.read(customItemProvider(CustomCtx.bg));
      expect(bg!.src, 'https://e.com/a.jpg');
      expect(bg.dim, 30);
    });

    test('«обложка как фон» переживает перезапуск', () {
      final store = JsonStore.memory();
      _container(store).read(settingsProvider.notifier).setCoverAsBg(true);
      expect(_container(store).read(settingsProvider).coverAsBg, isTrue);
    });

    test('размытие и затемнение обложки: умолчания, границы, перезапуск', () {
      final store = JsonStore.memory();
      final fx = _container(store).read(coverAsBgFxProvider.notifier);
      // Before the first edit it's the built-in default.
      expect(fx.state.blur, kCoverAsBgBlur);
      expect(fx.state.dim, kCoverAsBgDim);

      fx.setBlur(200);
      fx.setDim(40);
      expect(fx.state.blur, kBgBlurMax.round());

      final after = _container(store).read(coverAsBgFxProvider);
      expect(after.blur, kBgBlurMax.round());
      expect(after.dim, 40);
    });
  });
}
