/// Акцент из обложки — порт десктопного `coverAccent.ts`.
///
/// Обложка сжимается до 32×32, из пикселей берётся самый «сочный» (насыщенность
/// × близость светлоты к 0.5), его тон и служит акцентом. Светлота и
/// насыщенность зажимаются вокруг заданной яркости, иначе на тёмной обложке
/// акцент сливается с фоном, а на светлой выцветает.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/cover_store.dart';
import '../../core/store/settings_store.dart';

/// Полуширина коридора светлоты вокруг заданной яркости (десктопный `L_BAND`).
const double _lBand = 0.075;

/// Доминантный цвет обложки в HSL — сырьё, из которого считается акцент.
///
/// Держим отдельно от готового цвета: движение ползунка яркости пересчитывает
/// акцент из него же, без повторного скана картинки.
class CoverHsl {
  const CoverHsl(this.h, this.s, this.l);

  /// Тон 0–360.
  final double h;

  /// Насыщенность и светлота 0–1.
  final double s;
  final double l;
}

/// Доминантный HSL обложки; `null` — обложки нет или картинка не загрузилась.
Future<CoverHsl?> extractCoverHsl(String? cover) {
  final provider = coverImage(cover);
  if (provider == null) return Future.value();
  return extractProviderHsl(provider);
}

/// A cover's dominant colour by its link, kept until restart: scanning means
/// loading the image.
final coverHslProvider = FutureProvider.family<CoverHsl?, String?>(
  (ref, cover) => extractCoverHsl(cover),
);

/// То же по УЖЕ ВЫБРАННОМУ провайдеру. Нужно там, где картинка не сводится к
/// ссылке из стора: карточки «Поделиться» берут обложку покрупнее и с откатом
/// на исходный размер, и тон должен считаться ровно по той, что нарисована.
Future<CoverHsl?> extractProviderHsl(ImageProvider provider) async {
  // Скан идёт по 32×32: сеть и декодер отдают полноразмерную картинку, а нам
  // нужен доминант — сжатие и быстрее, и заодно усредняет шум.
  final image = await _load(
    ResizeImage(provider, width: 32, height: 32, allowUpscaling: true),
  );
  if (image == null) return null;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();

    var bestH = 0.0;
    var bestS = 0.0;
    var bestL = 0.0;
    var bestScore = -1.0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      final r = bytes[i] / 255;
      final g = bytes[i + 1] / 255;
      final b = bytes[i + 2] / 255;
      final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
      final l = (max + min) / 2;
      final s = max == min
          ? 0.0
          : l < 0.5
          ? (max - min) / (max + min)
          : (max - min) / (2 - max - min);
      final score = s * (1 - (l - 0.5).abs() * 1.5);
      if (score <= bestScore) continue;
      bestScore = score;
      var h = 0.0;
      if (max != min) {
        if (max == r) {
          h = ((g - b) / (max - min) + 6) % 6;
        } else if (max == g) {
          h = (b - r) / (max - min) + 2;
        } else {
          h = (r - g) / (max - min) + 4;
        }
        h = (h * 60).roundToDouble();
      }
      bestH = h;
      bestS = s;
      bestL = l;
    }
    return CoverHsl(bestH, bestS, bestL);
  } catch (_) {
    return null;
  } finally {
    image.dispose();
  }
}

/// Доминантный HSL → цвет акцента при заданной яркости.
///
/// Насыщенность едет за яркостью (0.75 + level): на тёмном тоне высокая S даёт
/// цветной шум, на светлом — наоборот нужна «сочность».
Color accentFromHsl(CoverHsl hsl, double level) {
  final lvl = clampAutoAccentL(level);
  final s = (hsl.s * (0.75 + lvl)).clamp(0.0, 1.0);
  final l = hsl.l.clamp(lvl - _lBand, lvl + _lBand);
  return HSLColor.fromAHSL(1, hsl.h % 360, s, l).toColor();
}

/// Акцент самой обложки — для мест, которые красятся «цветом трека» всегда, а
/// не только при включённом авто-акценте: заливка полосы «Продолжить».
///
/// Ключ — ссылка на обложку; `null` — обложки нет или картинка не читается,
/// тогда место красится акцентом приложения. Яркость берём ту же, что у
/// авто-акцента: иначе два цвета от одной обложки жили бы в разных коридорах
/// светлоты и рядом смотрелись бы как разные цвета.
final coverAccentProvider = FutureProvider.autoDispose.family<Color?, String?>((
  ref,
  cover,
) async {
  final level = ref.watch(settingsProvider.select((s) => s.autoAccentL));
  final hsl = await extractCoverHsl(cover);
  return hsl == null ? null : accentFromHsl(hsl, level);
});

/// Светлота и потолок насыщенности поверхности авто-темы — десктопные
/// `AUTO_THEME_BG_L` и `AUTO_THEME_BG_S_MAX`.
const double _autoThemeBgL = 0.075;
const double _autoThemeBgSMax = 0.5;

/// The auto theme's surface, background and blocks alike: the cover only as a
/// hue, a little above Dark in lightness, or the whole UI becomes a coloured
/// patch.
Color autoThemeSurfaceFromHsl(CoverHsl hsl) => HSLColor.fromAHSL(
  1,
  hsl.h % 360,
  (hsl.s * 0.6).clamp(0.0, _autoThemeBgSMax),
  _autoThemeBgL,
).toColor();

/// Доминантный HSL → фон миниплеера в режиме «Цвет обложки» (десктопный
/// `extractMpBgColor`).
///
/// Светлота держится в тёмном коридоре, чтобы карточка не выбивалась из
/// интерфейса, а насыщенность подрезана: на тёмном тоне высокая S даёт цветной
/// шум.
Color miniBgFromHsl(CoverHsl hsl) => HSLColor.fromAHSL(
  1,
  hsl.h % 360,
  (hsl.s * 0.78).clamp(0.0, 0.58),
  (hsl.l * 0.45).clamp(0.09, 0.18),
).toColor();

/// Доминантный HSL → верхний цвет градиента в полноэкранном плеере (режим
/// «Цвет» настройки «Фон плеера»).
///
/// Заметно живее, чем тон карточки миниплеера ([miniBgFromHsl]): там заливка
/// лежит полосой среди хрома и обязана из него не выбиваться, а тут она во весь
/// экран и должна читаться цветом обложки. Но и не акцент: поверх этого фона
/// стоят белые подписи и плёнки блоков, поэтому светлота держится в тёмном
/// коридоре (0.16–0.34), а насыщенность подрезана — на большой площади высокая
/// S даёт кислотное пятно.
Color playerBgFromHsl(CoverHsl hsl) => HSLColor.fromAHSL(
  1,
  hsl.h % 360,
  (hsl.s * 0.85).clamp(0.0, 0.72),
  (hsl.l * 0.62).clamp(0.16, 0.34),
).toColor();

/// Коридор насыщенности и светлота тона карточек «Поделиться» — десктопные
/// `TONE_SAT_MIN` / `TONE_SAT_MAX` / `TONE_LIGHT` из `shared/lib/cardKit.ts`.
const double _shareToneSMin = 0.34;
const double _shareToneSMax = 0.72;
const double _shareToneL = 0.42;

/// Тон карточки «Поделиться», когда обложки нет или её не удалось прочитать.
const Color kShareToneFallback = Color(0xFF3A3A40);

/// Доминантный HSL → тон карточки «Поделиться».
///
/// От обложки остаётся только оттенок: насыщенность зажата в коридор, светлота
/// фиксирована. Без этого тёмная обложка дала бы грязно-серый фон, а кислотная —
/// светлый, на котором не видно белых подписей карточки.
Color shareToneFromHsl(CoverHsl hsl) => HSLColor.fromAHSL(
  1,
  hsl.h % 360,
  // Почти серый источник оставляем серым: у ч/б обложки оттенок — шум JPEG.
  hsl.s < 0.04 ? 0.05 : hsl.s.clamp(_shareToneSMin, _shareToneSMax),
  _shareToneL,
).toColor();

/// Тон карточки из готового цвета (обложка профиля, когда аватара нет).
Color shareToneFromColor(Color color) {
  final hsl = HSLColor.fromColor(color);
  return shareToneFromHsl(CoverHsl(hsl.hue, hsl.saturation, hsl.lightness));
}

/// Картинка провайдера в виде `ui.Image`; `null` — сеть/файл не отдали.
Future<ui.Image?> _load(ImageProvider provider) {
  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(ui.Image? image) {
    if (!completer.isCompleted) completer.complete(image);
    stream.removeListener(listener);
  }

  listener = ImageStreamListener((info, _) {
    // Клон: сам кадр принадлежит кешу картинок, освобождать его нам нельзя —
    // отдаём наружу копию, а `info` закрываем сразу.
    final image = info.image.clone();
    info.dispose();
    finish(image);
  }, onError: (_, _) => finish(null));
  stream.addListener(listener);
  return completer.future;
}
