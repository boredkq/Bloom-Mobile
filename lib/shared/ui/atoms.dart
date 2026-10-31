/// Мелкие общие элементы: круглая icon-кнопка и обложка.
///
/// Круглая кнопка — базовый элемент раскладки из референса: шапки экранов,
/// оверлей на обложке, кнопки площадки. Подложка — плёнка `iconBg`, штрих —
/// `iconFg`, как в десктопном Bloom.
library;

import 'dart:math' show max, min;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/tokens.dart';
import '../../core/store/cover_store.dart';
import 'bloom_icon.dart';
import 'bloom_mark.dart';
import 'cover_collage.dart';
import 'cover_hero.dart';
import 'glass.dart';
import 'pressable.dart';

/// Высота управляющих элементов шапки: круглых кнопок, пилюли профиля, поля
/// поиска и пилюли-заголовка подстраницы. В референсе шапка заметно крупнее,
/// чем была у нас (42), — держим все элементы шапки ровно этой высоты.
///
/// Одно число на всё приложение: свёрнутые бары детальных страниц, поиск,
/// пилюля площадки в плеере и онбординг считают свои размеры от него, поэтому
/// шапка растёт везде разом и ряды не разъезжаются.
const double kHeaderControl = 51;

/// Кегль названия внутри пилюли шапки: имя приложения на главной, раздел на
/// подстранице, запрос в поиске.
///
/// Отдельным числом, а не `titleMedium` темы: тот же стиль носят строки треков
/// и подписи карточек, и растить его ради шапки нельзя.
const double kHeaderTitleSize = 16;

/// Высота чипа-фильтра (библиотека, поиск) и круглых кнопок в том же ряду.
const double kChipHeight = 50;

/// Потолок нижнего системного выреза на iOS.
///
/// Safe area под home indicator там всегда 34 pt, тогда как жестовая полоса
/// Android просит 24 — с полным вырезом низ раскладки на айфоне висел бы
/// заметно выше, чем на андроиде, при одинаковых отступах. Сам индикатор —
/// полоска 5 pt в 8 pt от края, её верх на 13 pt: 24 оставляют над ним ещё
/// 11 pt, так что элементы его не задевают и жест «домой» тапы не
/// перехватывает.
const double _kIosBottomInsetCap = 24;

/// Нижний системный вырез, на который раскладка отступает от края экрана, —
/// вместо `SafeArea` и сырого `MediaQuery.paddingOf(context).bottom`.
///
/// Отличается от них только на iOS, где вырез зажат [_kIosBottomInsetCap]:
/// на андроиде тот же вырез может быть панелью из трёх кнопок (48 dp), и
/// обрезать его — сесть на сами кнопки.
double bottomSafeInset(BuildContext context) {
  final inset = MediaQuery.paddingOf(context).bottom;
  return defaultTargetPlatform == TargetPlatform.iOS
      ? min(inset, _kIosBottomInsetCap)
      : inset;
}

/// Просвет между плавающей панелью и краями экрана: карточкой миниплеера,
/// плавающим таб-баром, рядом инструментов в плеере.
const double kFloatGap = 8;

/// Нижний отступ панели, которая кончается до края экрана.
///
/// Системный вырез идёт ВМЕСТО просвета, а не в придачу к нему: сумма
/// отрывала бы панель от низа сильнее, чем от боков. Одна функция на плеер и
/// на таб-бар намеренно — их нижние кромки обязаны стоять на одной линии,
/// иначе переход из списка в плеер выглядит как прыжок раскладки (поймал он).
double bottomEdgeInset(BuildContext context) =>
    max(bottomSafeInset(context), kFloatGap);

/// Запас снизу под плавающие бары каркаса — миниплеер и таб-бар.
///
/// Каркас держит их поверх содержимого (`Scaffold.extendBody`), поэтому список
/// идёт до самого низа экрана и просвечивает сквозь поля вокруг карточки
/// плеера. Плата за это — последние строки навсегда остаются под барами, если
/// скролл не добрать этим отступом.
///
/// Высоту не считаем руками (64 + 8 + 58 + вырез): её кладёт в нижний отступ
/// `MediaQuery` сам `Scaffold` — при `extendBody` он берёт максимум из выреза
/// системы и высоты нижних баров. Своя копия числа разъехалась бы с раскладкой
/// при первой же правке миниплеера.
///
/// Вне каркаса (модалка поверх всего) вернёт обычный системный вырез — там это
/// и нужно.
double bottomBarsInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// Хвост `CustomScrollView` на высоту баров: там, где отступ негде дописать к
/// существующему `SliverPadding` (ветки `if`/`else` с разными списками).
class SliverBottomBarsInset extends StatelessWidget {
  const SliverBottomBarsInset({super.key, this.extra = 0});

  /// Дополнительный просвет над барами — сверх их высоты.
  final double extra;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: bottomBarsInset(context) + extra),
  );
}

/// What a [BloomButton] is painted with.
enum ButtonTone {
  /// Just the label, in its color.
  text,

  /// Block plate, glass when it's on.
  plate,

  /// Main action: accent fill.
  accent,

  /// Irreversible action: red fill.
  danger,

  /// Secondary: a line, no fill.
  line,
}

/// The one button with a label. Fills the width it is given (shrinks to the
/// label in a row); height and corners are set at the place.
class BloomButton extends StatelessWidget {
  const BloomButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tone = ButtonTone.text,
    this.color,
    this.busy = false,
    this.height = 40,
    this.pill = true,
    this.overlay = false,
  });

  final String label;
  final VoidCallback? onTap;
  final BloomGlyph? icon;
  final ButtonTone tone;

  /// Label color of a [ButtonTone.text] button; accent when not set.
  final Color? color;

  /// The action runs: a spinner in place of the icon (or the label), no taps.
  final bool busy;
  final double height;

  /// Round ends; otherwise the theme radius, to sit flush with blocks.
  final bool pill;

  /// Plate on a sheet: takes the overlay glass setting.
  final bool overlay;

  static const _danger = Color(0xFFE0494A);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final live = onTap != null && !busy;
    final idle = onTap == null;
    final (Color? fill, Color ink) = switch (tone) {
      ButtonTone.text => (null, idle ? t.muted : color ?? t.accent),
      ButtonTone.plate => (null, idle ? t.muted : t.text),
      ButtonTone.line => (null, t.text2),
      ButtonTone.accent => idle ? (t.pill, t.muted) : (t.accent, t.accentText),
      ButtonTone.danger => idle ? (t.ovlBg, t.muted) : (_danger, Colors.white),
    };
    final radius = BorderRadius.circular(pill ? 999 : t.radius);
    final spinner = SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: ink),
    );
    final glyph = icon;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (glyph != null) ...[
          busy ? spinner : BloomIcon(glyph, size: 18, color: ink),
          const SizedBox(width: 8),
        ],
        if (busy && glyph == null)
          spinner
        else
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bloomText(size: 14, weight: 600, color: ink),
            ),
          ),
      ],
    );
    final box = SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(child: content),
      ),
    );

    return Pressable(
      onTap: live ? onTap : null,
      child: switch (tone) {
        ButtonTone.plate => GlassBox(
          borderRadius: radius,
          overlay: overlay,
          child: box,
        ),
        ButtonTone.line => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: t.ovlLine2),
          ),
          child: box,
        ),
        _ => DecoratedBox(
          decoration: BoxDecoration(color: fill, borderRadius: radius),
          child: box,
        ),
      },
    );
  }
}

/// Small pill with a value or a short action: tinted [color] when [active],
/// a quiet film otherwise.
class BloomTag extends StatelessWidget {
  const BloomTag({
    super.key,
    required this.text,
    this.active = true,
    this.color,
    this.onTap,
  });

  final String text;
  final bool active;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final c = color ?? t.accent;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.14) : t.ovlBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: bloomText(size: 13, weight: 700, color: active ? c : t.text2),
        ),
      ),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = kHeaderControl,
    this.iconSize = 23,
    this.background,
    this.borderColor,
    this.glass,
    this.color,
    this.tooltip,
  });

  final BloomGlyph icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? background;

  /// Обводка кружка. Нужна там, где заливка почти прозрачна: на фоне плеера
  /// плёнка в три процента сама по себе не читается — ровно как у блоков
  /// транспорта, у которых по этой же причине есть `ovlLine`.
  final Color? borderColor;

  /// Пускать ли стекло. По умолчанию — только кнопкам БЕЗ своей заливки: акцент
  /// под play и прозрачный кружок миниплеера — это состояние, а не поверхность
  /// темы. Своя плёнка поверхности (шапка плеера на фоне) — как раз наоборот, и
  /// ей стекло положено.
  final bool? glass;

  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final border = borderColor;
    final button = Pressable(
      onTap: onTap,
      child: GlassBox(
        color: background,
        enabled: glass ?? background == null,
        shape: CircleBorder(
          side: border == null ? BorderSide.none : BorderSide(color: border),
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: BloomIcon(icon, size: iconSize, color: color ?? t.iconFg),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Матовое стекло под элементами, стоящими ПОВЕРХ обложки: круглые кнопки
/// шапки, ряд действий, поле поиска по списку.
///
/// Кружок здесь светлый, а не тёмный: читаемость даёт размытие того, что под
/// ним, поэтому подложке хватает почти прозрачной белой плёнки, и кнопка
/// подхватывает цвет обложки вместо чёрной нашлёпки.
const double kGlassBlur = 14;
const Color kGlassFilm = Color(0x2BFFFFFF);

/// Обернуть в стекло произвольную форму: [shape] и обрезает размытие, и задаёт
/// границу плёнки.
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.shape, required this.child});

  final BorderRadius shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: kGlassBlur, sigmaY: kGlassBlur),
        child: Material(
          color: kGlassFilm,
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

/// Круглая кнопка ПОВЕРХ картинки: светлое стекло, белый штрих. Под ней
/// обложка, а не поверхность темы, поэтому `pill` и `iconFg` не годятся —
/// на баннере они читаются как серая заплатка.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = kHeaderControl,
    this.iconSize = 23,
    this.background,
    this.color,
  });

  final BloomGlyph icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  /// Своя подложка — для «включённых» состояний (подписка, сет сохранён).
  /// Кружок при этом сплошной: размывать под заливкой нечего.
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (background case final fill?) {
      return CircleIconButton(
        icon: icon,
        size: size,
        iconSize: iconSize,
        background: fill,
        color: color ?? Colors.white,
        onTap: onTap,
      );
    }
    return Pressable(
      onTap: onTap,
      child: GlassSurface(
        shape: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child: BloomIcon(icon, size: iconSize, color: color ?? Colors.white),
        ),
      ),
    );
  }
}

/// Нижний край обложки в hero-шапках.
///
/// Обложка идёт на всю высоту шапки — под название, счётчик и ряд кнопок — и
/// ОБРЕЗАЕТСЯ скруглёнными нижними углами, а не растворяется в фоне: в
/// референсе граница видна, картинка просто кончается. Плёнка поверх нужна
/// только чтобы белый текст и кнопки не тонули на светлом снимке, поэтому она
/// не доходит до полной непрозрачности — иначе сам край станет не виден.
class HeroCover extends StatelessWidget {
  const HeroCover({super.key, required this.child, this.start = 0.20});

  /// Сама картинка: одна обложка, коллаж или заглушка.
  final Widget child;

  /// Доля высоты шапки, до которой картинка не затемняется вовсе.
  final double start;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final rest = 1 - start;
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(t.radius * 1.5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // Верх: на светлом снимке белые кнопки и часы системной строки
          // исчезают, поэтому им нужна тёмная подложка независимо от обложки.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0),
                ],
                stops: const [0, 0.28],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  t.bg.withValues(alpha: 0),
                  t.bg.withValues(alpha: 0.45),
                  t.bg.withValues(alpha: 0.70),
                  t.bg.withValues(alpha: 0.80),
                ],
                stops: [start, start + rest * 0.40, start + rest * 0.72, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Эквалайзер играющего трека — порт десктопного `.bars` (library.css) и кадров
/// `npBar1..3` (animations.css): три полоски-пилюли шириной 3 с зазором 2 в
/// контейнере высотой 17, растут от нижнего края.
///
/// У каждой полоски свой цикл и своя длительность (1.7 / 1.35 / 2 с) со стартом
/// с середины цикла, поэтому группа не синхронизируется. Кадры начинаются и
/// заканчиваются одним значением — петля бесшовная. На паузе полоски просто
/// замирают, без затухания (десктопное `body.audio-paused`).
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    this.color,
    this.scale = 1,
  });

  final bool playing;
  final Color? color;

  /// Множитель размера — полоски заданы в тех же пикселях, что на десктопе.
  final double scale;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with SingleTickerProviderStateMixin {
  static const double _barW = 3;
  static const double _gap = 2;
  static const double _height = 17;

  /// Кадры `npBar1..3`: (доля цикла, высота в долях контейнера).
  static const List<List<(double, double)>> _frames = [
    [(0, .44), (.24, .80), (.48, .52), (.72, .90), (.88, .62), (1, .44)],
    [(0, .76), (.20, .46), (.42, .86), (.64, .54), (.82, .72), (1, .76)],
    [(0, .56), (.26, .92), (.52, .42), (.74, .78), (.90, .50), (1, .56)],
  ];

  /// Длительность цикла и отрицательный delay каждой полоски, мс.
  static const List<int> _durations = [1700, 1350, 2000];
  static const List<int> _delays = [0, 500, 1100];

  /// Заводится в [initState], а не лениво: у неигравших полосок первое
  /// обращение пришлось бы на `dispose`, где искать предков уже нельзя.
  late final Ticker _ticker;

  /// Время, наигранное до последней паузы, и время текущего отрезка.
  Duration _before = Duration.zero;
  Duration _elapsed = Duration.zero;

  void _tick(Duration d) => setState(() => _elapsed = _before + d);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (widget.playing) _ticker.start();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing == old.playing) return;
    if (widget.playing) {
      _ticker.start();
    } else {
      _ticker.stop();
      _before = _elapsed;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Высота полоски [i] в долях контейнера: кадры с ease-in-out на каждом
  /// отрезке — так CSS применяет `animation-timing-function`.
  double _level(int i) {
    final ms = _elapsed.inMicroseconds / 1000 + _delays[i];
    final p = (ms % _durations[i]) / _durations[i];
    final frames = _frames[i];
    for (var f = 1; f < frames.length; f++) {
      final (t1, v1) = frames[f];
      if (p > t1) continue;
      final (t0, v0) = frames[f - 1];
      final local = Curves.easeInOut.transform((p - t0) / (t1 - t0));
      return v0 + (v1 - v0) * local;
    }
    return frames.last.$2;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.bloom.accent;
    final k = widget.scale;
    return SizedBox(
      height: _height * k,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _frames.length; i++) ...[
            if (i > 0) SizedBox(width: _gap * k),
            Container(
              width: _barW * k,
              height: _height * k * _level(i),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Тумблер настроек — порт десктопного `.tele-sw`: дорожка 44×24 цвета
/// `border`, кружок 18 у левого края, включённый — дорожка акцентом, кружок
/// `accentText`. Свой, а не material `Switch`: тому не отключить заливку под
/// пальцем и он тянет за собой свою палитру.
class BloomSwitch extends StatelessWidget {
  const BloomSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.color,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// Track when on; accent by default.
  final Color? color;

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: _duration,
        curve: Curves.easeOut,
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? color ?? t.accent : t.border,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: _duration,
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? t.accentText : Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Обложка: скруглённая картинка с заглушкой на месте отсутствующей.
class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.url,
    required this.size,
    this.radius,
    this.circle = false,
    this.flight,
    this.overlay,
    this.covers,
  });

  final String? url;
  final double size;
  final double? radius;
  final bool circle;

  /// Обложки треков списка — из них собирается коллаж, когда своей картинки у
  /// списка нет. Так же, как в шапке этого списка (`CoverCollage`): карточка и
  /// страница обязаны показывать одно и то же. `null` — сущность не список
  /// (трек, артист), собирать нечего.
  final Iterable<String?>? covers;

  /// Слой поверх картинки — эквалайзер играющего сета. Стоит РЯДОМ с перелётом,
  /// а не внутри: летит одна обложка, полоски остаются на карточке.
  final Widget? overlay;

  /// Метка перелёта в шапку страницы, которую откроет эта карточка. `null` —
  /// обложка никуда не летит (строка трека, шапка шторки, превью выбора).
  ///
  /// Летит только НАСТОЯЩАЯ картинка: заглушке лететь некуда — на той стороне
  /// её место занимает коллаж или тинт раздела.
  final CoverFlight? flight;

  static double defaultRadius(BloomTokens t) => t.radius * 0.72;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final shape = circle
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(radius ?? defaultRadius(t));

    // Пустая обложка — приглушённый знак bloom, как `.ps-cover-empty` на
    // десктопе (там глиф с opacity .12).
    // Цвет сплошной, а не плёнка: над картинкой-фоном полупрозрачная заглушка
    // показывала обои и плитка читалась дыркой в списке.
    Widget placeholder() => DecoratedBox(
      decoration: BoxDecoration(color: t.coverEmpty, borderRadius: shape),
      child: Center(
        child: BloomMark(size: size * 0.34, color: t.text, opacity: 0.16),
      ),
    );

    // Оверлей обрезаем той же формой, что и картинку, — иначе плёнка вылезет
    // за скруглённые углы.
    Widget withOverlay(Widget child) => overlay == null
        ? child
        : Stack(
            fit: StackFit.expand,
            children: [
              child,
              ClipRRect(borderRadius: shape, child: overlay),
            ],
          );

    final image = coverImage(url);
    if (image == null) {
      final collage = covers;
      return SizedBox(
        width: size,
        height: size,
        child: withOverlay(
          collage == null
              ? placeholder()
              : ClipRRect(
                  borderRadius: shape,
                  child: CoverCollage(covers: collage, fallback: placeholder()),
                ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: withOverlay(
        // Скругление внутри перелёта, а не снаружи: обрезка родителя на летящую
        // копию не действует, форму ей задаёт сам [CoverHero].
        CoverHero(
          tag: flight?.tag,
          shape: shape,
          child: ClipRRect(
            borderRadius: shape,
            child: Image(
              image: image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder(),
              frameBuilder: (context, child, frame, wasSync) {
                if (wasSync || frame != null) return child;
                return placeholder();
              },
            ),
          ),
        ),
      ),
    );
  }
}
