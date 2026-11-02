/// The auto theme: the whole interface's colors follow the playing track's
/// cover.
///
/// I check the surface formula (dark and not acid, since all text sits on it)
/// and the switching rules: auto theme and auto accent can't both be on, and a
/// cover color must not outlive the move to a normal preset.
library;

import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/settings/cover_accent.dart';
import 'package:flutter/material.dart';
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

void main() {
  group('поверхность из обложки', () {
    test('светлота десктопная — 0.075, обложка сюда входит оттенком', () {
      final hsl = HSLColor.fromColor(
        autoThemeSurfaceFromHsl(const CoverHsl(210, 0.9, 0.7)),
      );
      expect(hsl.lightness, closeTo(0.075, 0.005));
      // The hue tolerance is wide on purpose: this dark, the color lives in a
      // channel's lowest steps, and converting back to HSL rounds them.
      expect(hsl.hue, closeTo(210, 3));
    });

    test(
      'насыщенность подрезана: цветного пятна вместо интерфейса не выйдет',
      () {
        final hsl = HSLColor.fromColor(
          autoThemeSurfaceFromHsl(const CoverHsl(120, 1, 0.5)),
        );
        expect(hsl.saturation, lessThanOrEqualTo(0.5));
      },
    );

    test('серая обложка остаётся серой', () {
      final hsl = HSLColor.fromColor(
        autoThemeSurfaceFromHsl(const CoverHsl(0, 0, 0.5)),
      );
      expect(hsl.saturation, 0);
    });

    test('темнее миниплеерного тона той же обложки', () {
      // The surface is the whole app's background, so it has to be the quietest
      // of the fills computed from a cover.
      const cover = CoverHsl(350, 0.8, 0.45);
      expect(
        HSLColor.fromColor(autoThemeSurfaceFromHsl(cover)).lightness,
        lessThan(HSLColor.fromColor(miniBgFromHsl(cover)).lightness),
      );
    });
  });

  group('переключение', () {
    test('a theme that is gone falls back to Dark, a custom one stays', () {
      final gone = _container(
        JsonStore.memory({
          'settings': {'themeId': 'midnight'},
        }),
      );
      expect(gone.read(settingsProvider).themeId, 'dark');

      final mine = const ThemePreset(
        id: 'custom_1',
        name: 'Mine',
        bg: Color(0xFF101828),
        blockColor: Color(0xFF101828),
        accent: Color(0xFF4D9FFF),
        custom: true,
      );
      final kept = _container(
        JsonStore.memory({
          'settings': {
            'themeId': 'custom_1',
            'customThemes': [mine.toJson()],
          },
        }),
      );
      expect(kept.read(settingsProvider).themeId, 'custom_1');
    });

    test('включение затравливает тему текущими цветами', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme('light');
      final before = c.read(settingsProvider).tokens;

      settings.setTheme(kAutoThemeId);
      final state = c.read(settingsProvider);
      expect(state.autoTheme, isTrue);
      // The auto theme has no colors before the first cover: nothing to repaint
      // with, and the screen mustn't flash another theme.
      expect(state.tokens.bg, before.bg);
      expect(state.tokens.accent, before.accent);
    });

    test('авто-акцент гаснет: два режима за один акцент не спорят', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setAutoAccent(true);
      settings.setTheme(kAutoThemeId);
      expect(c.read(settingsProvider).autoAccent, isFalse);
    });

    test('включённый авто-акцент уводит с авто-темы', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme(kAutoThemeId);
      settings.applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));

      settings.setAutoAccent(true);
      final state = c.read(settingsProvider);
      expect(state.autoTheme, isFalse);
      expect(state.themeId, kThemePresets.first.id);
      // The cover accent left along with the mode: it doesn't belong to a
      // preset.
      expect(state.tokens.accent, kThemePresets.first.accent);
    });

    test('обложка красит фон, блоки и акцент разом', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme(kAutoThemeId);
      settings.applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));

      final tokens = c.read(settingsProvider).tokens;
      expect(tokens.bg, const Color(0xFF141018));
      expect(tokens.blockColor, const Color(0xFF141018));
      expect(tokens.accent, const Color(0xFF9B5DE5));
    });

    test('опоздавший скан на другую тему не действует', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme(kAutoThemeId);
      settings.setTheme('light');

      settings.applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));
      final state = c.read(settingsProvider);
      expect(state.tokens.bg, const Color(0xFFF0F0F0));
      expect(state.tokens.accent, const Color(0xFF000000));
    });

    test('уход на пресет сбрасывает акцент обложки', () {
      final c = _container();
      final settings = c.read(settingsProvider.notifier);
      settings.setTheme(kAutoThemeId);
      settings.applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));

      settings.setTheme('light');
      expect(c.read(settingsProvider).tokens.accent, const Color(0xFF000000));
    });
  });

  group('хранилище', () {
    test('режим и снятый цвет переживают перезапуск', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(settingsProvider.notifier).setTheme(kAutoThemeId);
      c
          .read(settingsProvider.notifier)
          .applyAutoTheme(const Color(0xFF141018), const Color(0xFF9B5DE5));

      final restored = _container(store).read(settingsProvider);
      expect(restored.autoTheme, isTrue);
      expect(restored.tokens.bg, const Color(0xFF141018));
      expect(restored.tokens.accent, const Color(0xFF9B5DE5));
    });
  });
}
