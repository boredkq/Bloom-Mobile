/// The full-screen player's background: persisting the setting, the cover color
/// and the gradient.
///
/// I check what breaks quietly: an unknown stored value mustn't crash the
/// player; a color from the cover must stay in the dark range (white labels sit
/// on it); and the gradient mustn't reach the theme's color, or the screen's
/// lower third looks like the background is off.
library;

import 'dart:ui' as ui;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/customization/custom_store.dart';
import 'package:bloom/features/player/player_bg_store.dart';
import 'package:bloom/features/player/ui/player_backdrop.dart';
import 'package:bloom/features/settings/cover_accent.dart';
import 'package:bloom/shared/ui/atoms.dart';
import 'package:bloom/shared/ui/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

/// A ready frame with no decoder: `createTestImage` never finishes in
/// `testWidgets`, since decoding is real and the clock is fake, and `await`
/// hangs forever. `toImageSync` gives the picture at once.
ui.Image _solidImage(int side) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..color = const Color(0xFFB01020),
  );
  return recorder.endRecording().toImageSync(side, side);
}

/// A ready picture instead of a network one: the network is silent in tests,
/// and I need the layout of a loaded frame.
class _FakeImage extends ImageProvider<_FakeImage> {
  _FakeImage(this.image);

  final ui.Image image;

  @override
  Future<_FakeImage> obtainKey(ImageConfiguration configuration) async => this;

  @override
  ImageStreamCompleter loadImage(_FakeImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        Future<ImageInfo>.value(ImageInfo(image: image.clone())),
      );
}

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
  group('настройка', () {
    test('по умолчанию фона нет', () {
      final c = _container(JsonStore.memory());
      expect(c.read(playerBgProvider), PlayerBg.none);
      expect(c.read(playerBgProvider).isNone, isTrue);
    });

    test('выбранный режим читается с диска', () {
      final c = _container(JsonStore.memory({'playerBg': 'cover'}));
      expect(c.read(playerBgProvider), PlayerBg.cover);
    });

    test('незнакомая запись — это «Нет»', () {
      final c = _container(JsonStore.memory({'playerBg': 'wallpaper'}));
      expect(c.read(playerBgProvider), PlayerBg.none);
    });

    test('«Фон приложения» читается с диска', () {
      final c = _container(JsonStore.memory({'playerBg': 'app'}));
      expect(c.read(playerBgProvider), PlayerBg.app);
    });

    test('выбор уезжает на диск', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(playerBgProvider.notifier).set(PlayerBg.color);
      expect(c.read(playerBgProvider), PlayerBg.color);
      expect(store.read('playerBg'), 'color');

      c.read(playerBgProvider.notifier).set(PlayerBg.none);
      expect(store.read('playerBg'), 'none');
    });
  });

  group('эффект фона обложки', () {
    test('по умолчанию размытие — как было до настройки', () {
      final c = _container(JsonStore.memory());
      expect(c.read(coverBgFxProvider), CoverBgFx.blur);
    });

    test('выбранный эффект читается с диска', () {
      final c = _container(JsonStore.memory({'playerBgCoverFx': 'original'}));
      expect(c.read(coverBgFxProvider), CoverBgFx.original);
    });

    test('незнакомая запись — это размытие', () {
      final c = _container(JsonStore.memory({'playerBgCoverFx': 'sepia'}));
      expect(c.read(coverBgFxProvider), CoverBgFx.blur);
    });

    test('выбор уезжает на диск', () {
      final store = JsonStore.memory();
      final c = _container(store);
      c.read(coverBgFxProvider.notifier).set(CoverBgFx.dim);
      expect(store.read('playerBgCoverFx'), 'dim');
    });
  });

  group('фон приложения', () {
    /// A one-picture library; `assigned` says whether it's the background.
    JsonStore withWallpaper({required bool assigned}) => JsonStore.memory({
      'media': [
        {
          'id': 'w1',
          'name': 'wall.jpg',
          'src': 'local:wall.jpg',
          'blur': 12,
          'dim': 40,
        },
      ],
      if (assigned) 'custom': {'bg': 'w1'},
    });

    test('берётся та самая картинка с её же размытием и затемнением', () {
      // The numbers are the picture's: the player must repeat the app
      // background exactly.
      final item = _container(
        withWallpaper(assigned: true),
      ).read(playerAppBgProvider);
      expect(item?.src, 'local:wall.jpg');
      expect(item?.blur, 12);
      expect(item?.dim, 40);
    });

    test('картинка есть в библиотеке, но не стоит фоном — вариант пуст', () {
      // This is what greys out the row in the sheet: nothing to take into the
      // player.
      expect(
        _container(withWallpaper(assigned: false)).read(playerAppBgProvider),
        isNull,
      );
    });

    test('фон сняли — вариант пуст, но настройку это не трогает', () {
      final store = withWallpaper(assigned: true);
      final c = _container(store);
      c.read(playerBgProvider.notifier).set(PlayerBg.app);
      c.read(customProvider.notifier).set(CustomCtx.bg, null);
      expect(c.read(playerAppBgProvider), isNull);
      expect(c.read(playerBgProvider), PlayerBg.app);
    });
  });

  group('цвет из обложки', () {
    test('почти чёрная обложка всё равно даёт видимый цвет', () {
      final hsl = HSLColor.fromColor(
        playerBgFromHsl(const CoverHsl(0, 0.9, 0)),
      );
      expect(hsl.lightness, closeTo(0.16, 0.01));
    });

    test('светлая обложка притемняется', () {
      final hsl = HSLColor.fromColor(
        playerBgFromHsl(const CoverHsl(210, 0.9, 0.95)),
      );
      expect(hsl.lightness, lessThanOrEqualTo(0.35));
    });

    test('кислотная насыщенность подрезана', () {
      final hsl = HSLColor.fromColor(
        playerBgFromHsl(const CoverHsl(120, 1, 0.4)),
      );
      expect(hsl.saturation, closeTo(0.72, 0.02));
    });

    test('серая обложка остаётся серой', () {
      final hsl = HSLColor.fromColor(
        playerBgFromHsl(const CoverHsl(0, 0, 0.5)),
      );
      expect(hsl.saturation, 0);
    });

    test('заметно живее тона миниплеера: та же обложка — светлее и сочнее', () {
      const cover = CoverHsl(350, 0.8, 0.45);
      final player = HSLColor.fromColor(playerBgFromHsl(cover));
      final mini = HSLColor.fromColor(miniBgFromHsl(cover));
      expect(player.lightness, greaterThan(mini.lightness));
      expect(player.saturation, greaterThan(mini.saturation));
    });
  });

  group('градиент', () {
    const bg = Color(0xFF0A0A0A);
    const color = Color(0xFF7A1220);

    test('сверху — сам цвет обложки', () {
      expect(playerBgGradient(color, bg).first, color);
    });

    test('снизу темнее, но не цвет темы', () {
      final colors = playerBgGradient(color, bg);
      expect(colors.last, isNot(bg));
      // The bottom point is closer to the theme than the middle, or the
      // gradient doesn't show.
      double distance(Color a, Color b) =>
          ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs());
      expect(distance(colors.last, bg), lessThan(distance(colors[1], bg)));
    });

    test('границы цветов совпадают по числу с самими цветами', () {
      // `LinearGradient` needs exactly as many stops, or it asserts at paint
      // time, not in the test.
      expect(playerBgGradient(color, bg).length, kPlayerBgStops.length);
      expect(kPlayerBgDim.length, 3);
    });

    test('под чёткой обложкой плёнка плотнее, но не в чёрный', () {
      // Both sets go into the same gradient, so their lengths must match.
      expect(kPlayerBgDimSharp.length, kPlayerBgDim.length);
      for (var i = 0; i < kPlayerBgDim.length; i++) {
        expect(kPlayerBgDimSharp[i], greaterThan(kPlayerBgDim[i]));
        expect(kPlayerBgDimSharp[i], lessThan(0.8));
      }
    });
  });

  testWidgets('размытая обложка занимает ВЕСЬ отведённый прямоугольник', (
    tester,
  ) async {
    final image = _solidImage(8);
    addTearDown(image.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 600,
            // The same `Stack` with loose constraints that `AnimatedSwitcher`
            // puts children in: with it a picture can come out at its own size
            // mid-screen instead of filling the background.
            child: Stack(
              children: [
                CoverBgImage(image: _FakeImage(image), fx: CoverBgFx.blur),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(Image)), const Size(300, 600));
  });

  testWidgets('«Оригинал» — та же картинка, но без размытия и цветокоррекции', (
    tester,
  ) async {
    final image = _solidImage(8);
    addTearDown(image.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 600,
            child: Stack(
              children: [
                CoverBgImage(image: _FakeImage(image), fx: CoverBgFx.original),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(ColorFiltered), findsNothing);
    // The same size: the zoom under the blur doesn't stretch the picture, it
    // hides the smeared edge.
    expect(tester.getSize(find.byType(Image)), const Size(300, 600));
  });

  group('шапка на фоне', () {
    Future<GlassBox> pumpButton(WidgetTester tester, {bool? glass}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jsonStoreProvider.overrideWithValue(JsonStore.memory()),
            dbProvider.overrideWithValue(BloomDb.memory()),
          ],
          child: MaterialApp(
            theme: buildBloomTheme(BloomThemes.dark),
            home: Scaffold(
              body: GlassGroup(
                child: CircleIconButton(
                  icon: Bi.close,
                  background: const Color(0x11FFFFFF),
                  glass: glass,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.widget<GlassBox>(find.byType(GlassBox));
    }

    testWidgets('плёнка поверхности стекло НЕ гасит', (tester) async {
      // The player's header on a background is painted with the block film, a
      // theme surface: with Transparency on it gets glass.
      expect((await pumpButton(tester, glass: true)).enabled, isTrue);
    });

    testWidgets('своя заливка без просьбы стекло гасит', (tester) async {
      // The default holds: the accent under play and the mini player's clear
      // circle are states and don't turn to glass.
      expect((await pumpButton(tester)).enabled, isFalse);
    });
  });

  testWidgets('в режиме «Нет» слоя нет вовсе', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jsonStoreProvider.overrideWithValue(JsonStore.memory()),
          dbProvider.overrideWithValue(BloomDb.memory()),
        ],
        child: MaterialApp(
          theme: buildBloomTheme(BloomThemes.dark),
          home: const Scaffold(body: PlayerBackdrop()),
        ),
      ),
    );
    // No picture and no gradient: the background is off, and there's nothing to
    // draw over the theme's fill.
    expect(find.byType(DecoratedBox), findsNothing);
    expect(find.byType(Image), findsNothing);
  });
}
