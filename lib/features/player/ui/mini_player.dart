/// Миниплеер — плавающая карточка над таб-баром.
///
/// Вид взят с десктопного `#miniPlayer` в режиме `mp-floating`: сплошная
/// заливка `pill` (сама карточка непрозрачна), рамка `ovl-line`, радиус
/// темы, отступы по 8. Карточка и правда плавает: каркас пускает содержимое
/// под неё, и в поля по краям видно список.
///
/// Целиком карточку здесь никто не собирает: её заливку и место держит панель
/// плеера (`PlayerSheet`) — карточка из неё вырастает, и рисовать её дважды
/// нельзя. Отсюда панель берёт содержимое строки ([MiniCardRow]), размеры
/// ([kMiniCardHeight], [miniCardRadius]) и тон заливки ([miniCardTint]), а бар
/// каркаса — пустое место под неё ([MiniCardSlot]).
///
/// Фон, индикаторы прогресса, форма обложки и скругление углов настраиваются —
/// [MiniStyle], порт десктопных `mp*`-префов.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../features/customization/custom_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/marquee_text.dart';
import '../mini_style_store.dart';
import '../play_error.dart';
import '../player_controller.dart';
import 'play_button.dart';
import 'track_swap.dart';

/// Высота карточки. Раньше её занимали и чужие экраны — отмеряли себе запас
/// снизу, чтобы список не уезжал под плеер. Теперь запас берётся из
/// `bottomBarsInset`, и число нужно самой карточке да панели плеера, которая
/// из неё растёт.
const double kMiniCardHeight = 64;

/// Сколько видно от карточки соседа при включённых «Соседних треках» — узкая
/// полоска у самого края экрана, как в Яндекс.Музыке.
///
/// Полоска стоит ВПЛОТНУЮ к краю, а не в глубине обычного поля: висящий за ней
/// просвет читался бы как ошибка раскладки — будто карточку сдуло от края и
/// из-под неё вылезло лишнее.
const double kMiniPeek = 12;

/// Насколько карточка отодвигается от обычного поля, когда соседи включены:
/// ровно на ширину их полоски. `0` — соседей нет и карточка стоит как стояла.
///
/// Просветом между полоской и карточкой служит само поле ([kFloatGap]):
/// полоска забирает его себе, уходя к краю экрана, а поле встаёт следом за
/// ней. Поэтому и слагаемое здесь одно.
double miniPeekInset(bool neighbors) => neighbors ? kMiniPeek : 0;

/// Место карточки в покое: поля по [kFloatGap] с боков и столько же над
/// таб-баром ([navInset] — его высота с системным вырезом). С соседями
/// карточка ужимается ещё на [miniPeekInset] с каждой стороны — на ширину их
/// полоски, которая уходит к самому краю экрана.
Rect miniCardRect({
  required Size screen,
  required double navInset,
  required bool neighbors,
}) {
  final side = kFloatGap + miniPeekInset(neighbors);
  return Rect.fromLTWH(
    side,
    screen.height - navInset - kFloatGap - kMiniCardHeight,
    screen.width - side * 2,
    kMiniCardHeight,
  );
}

/// Шаг карусели: карточка плюс просвет до соседней. Сдвиг на него ставит
/// соседа ровно на место середины.
double miniStride(double cardWidth) => cardWidth + kFloatGap;

/// Сторона обложки в карточке.
const double _coverSize = 44;

/// Зазор между обложкой и кольцом прогресса (десктопный `RING_GAP`).
const double _ringGap = 4;

/// Насколько штрих кольца утоплен внутрь бокса, чтобы не срезался его краем
/// (десктопный `RING_INSET`).
const double _ringInset = 2;

const double _ringStroke = 2.5;

/// Доля прослушанного, 0..1 — общий счёт для всех трёх индикаторов.
double _progressFrac(WidgetRef ref) {
  final head =
      ref.watch(playheadProvider).value ??
      (position: Duration.zero, total: Duration.zero);
  final total = head.total.inMilliseconds;
  return total <= 0
      ? 0.0
      : (head.position.inMilliseconds / total).clamp(0.0, 1.0);
}

/// Цвет артиста под названием.
///
/// Обычный `muted` считается от плашки темы, а под подписью в карточке может
/// оказаться что угодно: тонировка от обложки, сама обложка картинкой, заливка
/// прогресса акцентом. На них серый от темы садится в фон и артиста не
/// разобрать — поэтому берём цвет текста темы с прозрачностью: он остаётся
/// контрастным к любой из этих подложек и всё равно тише белого названия.
Color _artistColor(BloomTokens t) => t.text.withValues(alpha: 0.75);

/// Скругление углов карточки в пикселях.
double miniCardRadius(MiniRadius radius, double themeRadius) =>
    switch (radius) {
      MiniRadius.none => 0,
      MiniRadius.soft => themeRadius * 0.5,
      MiniRadius.rounded => themeRadius,
      MiniRadius.pill => kMiniCardHeight / 2,
    };

/// Тон заливки карточки: осветлённый доминант обложки в режиме «Цвет обложки».
/// `null` — заливка темы (в том числе пока цвет ещё считается и если обложку не
/// прочитать).
///
/// [neighbor] — карточка соседа в карусели: тон ей считаем с ЕЁ обложки, иначе
/// три карточки в ряд были бы одного цвета и карусель читалась бы одной
/// длинной плашкой.
Color? miniCardTint(WidgetRef ref, MiniStyle style, {Track? neighbor}) {
  if (style.bg != MiniBg.coverColor) return null;
  final cover = neighbor == null ? miniCardCover(ref) : neighbor.cover;
  return ref.watch(miniCoverColorProvider(cover)).value;
}

/// Обложка, которую карточка показывает на самом деле: своя из «Кастомизации»
/// важнее обложки трека — десктопный `coverOverride`. Она же идёт в фон
/// карточки и в цвет заливки: считать надо с той картинки, которую видно.
String? miniCardCover(WidgetRef ref) => ref.watch(playerCoverProvider);

/// Место карточки в нижних барах каркаса.
///
/// Саму карточку рисует не бар, а панель плеера (`PlayerSheet`): панель из неё
/// вырастает и обязана лежать ПОВЕРХ таб-бара, а из бара наружу не вылезешь.
/// Бар держит под карточку пустое место той же высоты — иначе таб-бар
/// подпрыгнул бы вверх, списки потеряли бы нижний запас (`bottomBarsInset`
/// считается по высоте баров), а всплывающие тосты выезжали бы из-под панели.
class MiniCardSlot extends ConsumerWidget {
  const MiniCardSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(playbackProvider.select((s) => s.track != null));
    // Просвет под карточкой (её нижние 8) входит в место: панель отбита от
    // таб-бара ровно на него.
    return SizedBox(height: playing ? kMiniCardHeight + kFloatGap : 0);
  }
}

/// Содержимое карточки: фон-обложка, заливка прогресса, строка с обложкой,
/// подписями и кнопками, полоска прогресса по нижней кромке.
///
/// Ровно [kMiniCardHeight] в высоту и без своей заливки: заливку держит панель,
/// которая эту строку и растит. По мере разворота строка гаснет — поэтому
/// смысла считать её содержимое, когда её не видно, нет (панель её тогда просто
/// не строит).
class MiniCardRow extends ConsumerWidget {
  const MiniCardRow({super.key, this.neighbor});

  /// Строка карточки СОСЕДА в карусели («Соседние треки»): рисуется по этому
  /// треку, а не по играющему, и живого в ней нет ничего — ни индикаторов
  /// прогресса (прогресс есть только у играющего), ни анимации смены (её и
  /// делает сама карусель), ни нажатий. `null` — обычная строка миниплеера.
  final Track? neighbor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final live = neighbor == null;
    final track = neighbor ?? state.track;
    if (track == null) return const SizedBox.shrink();

    final theme = Theme.of(context).textTheme;
    final style = ref.watch(miniStyleProvider);
    // Своя картинка из «Кастомизации» подменяет обложку ИГРАЮЩЕГО трека —
    // соседи показывают свои.
    final cover = live ? miniCardCover(ref) : track.cover;
    final tint = miniCardTint(ref, style, neighbor: neighbor);
    final progress = live ? style.progress : const MiniProgress(line: false);
    final error = live ? state.error : null;
    final visible = MiniButton.values.where(style.hasButton).toList();

    return SizedBox(
      height: kMiniCardHeight,
      child: Stack(
        children: [
          // Фон-обложка и заливка прогресса лежат ПОД содержимым — порядком в
          // стопке, а не z-index, как на ПК.
          if (style.bg == MiniBg.cover)
            Positioned.fill(child: _CoverBackdrop(cover: cover)),
          if (progress.fill) Positioned.fill(child: _FillProgress(tint: tint)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _MiniCover(
                  trackId: track.id,
                  cover: cover,
                  animated: live,
                  shape: style.shape,
                  ring: progress.ring,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TrackSwap(
                    id: track.id,
                    animated: live,
                    tuning: TrackSwapTuning.mini,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Название бежит, если не влезло, — как `#mpTitle` на
                        // ПК; артист под ним остаётся с эллипсисом.
                        MarqueeText(track.name, style: theme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          // В состоянии лежит КОД ошибки — разворачиваем его в
                          // фразу здесь (см. `play_error.dart`).
                          error == null
                              ? track.artist
                              : describePlayError(context.l, error),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodySmall?.copyWith(
                            color: error != null ? t.danger : _artistColor(t),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Порядок кнопок задан самим перечислением, набор —
                // настройкой; убранная не оставляет после себя зазора, иначе
                // подпись упиралась бы в пустоту.
                for (var i = 0; i < visible.length; i++) ...[
                  SizedBox(width: i == 0 ? 8 : 4),
                  _MiniButton(
                    button: visible[i],
                    track: track,
                    loading: live && state.loading,
                    live: live,
                  ),
                ],
              ],
            ),
          ),
          if (progress.line)
            const Positioned(left: 0, right: 0, bottom: 0, child: _Hairline()),
        ],
      ),
    );
  }
}

/// Кнопка в строке карточки. Какие из них стоят — настройка «Кнопки
/// управления» ([MiniButton]).
class _MiniButton extends ConsumerWidget {
  const _MiniButton({
    required this.button,
    required this.track,
    required this.loading,
    this.live = true,
  });

  final MiniButton button;
  final Track track;

  /// Идёт переход на другой трек — место play занимает кружок ожидания.
  final bool loading;

  /// Карточка играющего трека. `false` — сосед в карусели: кнопки там стоят
  /// только ради раскладки (иначе подпись соседа была бы шире и на въезде
  /// прыгала), делать им нечего, и play показывает play — сосед не играет.
  final bool live;

  static const double _size = 38;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    switch (button) {
      case MiniButton.prev:
        // Перемотка — Bold, как в транспорте плеера: рядом с ней стоит play, и
        // тонкий контур возле сплошного знака читается как чужая иконка.
        return CircleIconButton(
          icon: Bi.skipPreviousBold,
          size: _size,
          iconSize: 20,
          background: Colors.transparent,
          onTap: live ? ref.read(playbackProvider.notifier).prev : null,
        );
      case MiniButton.next:
        return CircleIconButton(
          icon: Bi.skipNextBold,
          size: _size,
          iconSize: 20,
          background: Colors.transparent,
          onTap: live ? ref.read(playbackProvider.notifier).next : null,
        );
      case MiniButton.fav:
        final fav = ref.watch(
          libraryProvider.select((lib) => lib.isFav(track.id)),
        );
        return CircleIconButton(
          icon: fav ? Bi.heartBold : Bi.heart,
          size: _size,
          iconSize: 20,
          background: Colors.transparent,
          color: fav ? t.sysFavIco : null,
          onTap: live
              ? () => ref.read(libraryProvider.notifier).toggleFav(track)
              : null,
        );
      case MiniButton.play:
        // Форма — общая настройка обеих поверхностей, и рисует кнопку тот же
        // виджет, что в транспорте плеера ([PlayButton]). Кружок ожидания
        // остаётся внутри неё: на переходе трека кнопка не должна пропадать из
        // строки.
        return PlayButton(
          size: _size,
          iconSize: 18,
          plainIconSize: 26,
          spinnerSize: 20,
          loading: loading,
          live: live,
          onTap: ref.read(playbackProvider.notifier).toggle,
        );
    }
  }
}

/// Обложка карточки: скруглённый квадрат или круг, при включённом индикаторе —
/// в кольце прогресса.
///
/// Кольцо рисуется ЗА пределами обложки и в раскладке места не занимает
/// (десктопный `#mpCircleRing` — абсолютный слой в `#mpCoverWrap`): иначе от
/// одной галочки в настройках разъезжалась бы вся строка.
class _MiniCover extends StatelessWidget {
  const _MiniCover({
    required this.trackId,
    required this.cover,
    required this.animated,
    required this.shape,
    required this.ring,
  });

  final String trackId;
  final String? cover;
  final bool animated;
  final MiniCoverShape shape;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final radius = shape == MiniCoverShape.circle
        ? _coverSize / 2
        : t.radius * 0.72;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Слои смены трека клипует рамка обложки, картинка внутри идёт без
        // своего радиуса — иначе уезжающая показывала бы скруглённый угол
        // посреди кадра.
        SizedBox(
          width: _coverSize,
          height: _coverSize,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: TrackSwap(
              id: trackId,
              fade: true,
              animated: animated,
              tuning: TrackSwapTuning.mini,
              child: Cover(url: cover, size: _coverSize, radius: 0),
            ),
          ),
        ),
        if (ring)
          Positioned(
            left: -_ringGap,
            top: -_ringGap,
            child: IgnorePointer(child: _RingProgress(coverRadius: radius)),
          ),
      ],
    );
  }
}

/// Кольцо прогресса вокруг обложки. Форма повторяет обложку: у круглой — круг,
/// у скруглённой — та же рамка, отодвинутая на зазор.
class _RingProgress extends ConsumerWidget {
  const _RingProgress({required this.coverRadius});

  final double coverRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    return CustomPaint(
      size: const Size.square(_coverSize + _ringGap * 2),
      painter: _RingPainter(
        frac: _progressFrac(ref),
        // Приглушено, как на ПК: на автоакценте от обложки кольцо в полную силу
        // полыхает вокруг картинки и перетягивает внимание с самой карточки.
        color: t.accent.withValues(alpha: 0.7),
        track: t.ovlLine,
        // Круглой обложке кольцо кладём кругом, а не квадратом с большим
        // радиусом: у скруглённого прямоугольника с r = половине стороны углы
        // всё равно чуть спрямляются.
        radius: coverRadius >= _coverSize / 2
            ? null
            : coverRadius + _ringGap - _ringInset,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.frac,
    required this.color,
    required this.track,
    required this.radius,
  });

  final double frac;
  final Color color;
  final Color track;

  /// Радиус углов кольца; `null` — круг.
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    ).deflate(_ringInset);
    // Обход начинается с верхней середины и идёт по часовой — прогресс должен
    // расти оттуда же, откуда его ждут у круглого индикатора.
    final path = radius == null
        ? (Path()..addArc(box, -math.pi / 2, 2 * math.pi))
        : _roundedPath(box, radius!);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line..color = track);
    if (frac <= 0) return;
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * frac),
      line..color = color,
    );
  }

  /// Скруглённый прямоугольник, начатый с верхней середины (десктопный `d`).
  static Path _roundedPath(Rect box, double r) {
    final c = box.center.dx;
    return Path()
      ..moveTo(c, box.top)
      ..lineTo(box.right - r, box.top)
      ..quadraticBezierTo(box.right, box.top, box.right, box.top + r)
      ..lineTo(box.right, box.bottom - r)
      ..quadraticBezierTo(box.right, box.bottom, box.right - r, box.bottom)
      ..lineTo(box.left + r, box.bottom)
      ..quadraticBezierTo(box.left, box.bottom, box.left, box.bottom - r)
      ..lineTo(box.left, box.top + r)
      ..quadraticBezierTo(box.left, box.top, box.left + r, box.top)
      ..lineTo(c, box.top);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.frac != frac ||
      old.color != color ||
      old.track != track ||
      old.radius != radius;
}

/// Обложка фоном карточки — десктопный `#mpBgImgLayer` с его же фильтром
/// (`brightness(.38) saturate(.7)`): без притемнения подпись на светлой
/// картинке не читается.
class _CoverBackdrop extends StatelessWidget {
  const _CoverBackdrop({required this.cover});

  final String? cover;

  /// Яркость и насыщенность фоновой картинки.
  static const double _brightness = 0.38;
  static const double _saturation = 0.7;

  /// Веса яркости каналов — те же, что у CSS-фильтра `saturate`.
  static const double _lr = 0.2126;
  static const double _lg = 0.7152;
  static const double _lb = 0.0722;

  static double _diag(double weight) =>
      _brightness * (weight + (1 - weight) * _saturation);

  static double _off(double weight) =>
      _brightness * (weight * (1 - _saturation));

  @override
  Widget build(BuildContext context) {
    final image = coverImage(cover);
    if (image == null) return const SizedBox.shrink();
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        _diag(_lr), _off(_lg), _off(_lb), 0, 0, //
        _off(_lr), _diag(_lg), _off(_lb), 0, 0, //
        _off(_lr), _off(_lg), _diag(_lb), 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
      child: Image(image: image, fit: BoxFit.cover),
    );
  }
}

/// Прогресс заливкой фона — десктопный `#mpBgProgress`.
class _FillProgress extends ConsumerWidget {
  const _FillProgress({required this.tint});

  /// Фон карточки в режиме «Цвет обложки»; `null` — фон не тонирован.
  final Color? tint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: _progressFrac(ref),
        heightFactor: 1,
        // На тонированном фоне заливка строится от тона самого трека
        // (осветлённый доминант): акцент приложения смотрелся там чужеродно —
        // синяя полоса поверх красной карточки.
        child: ColoredBox(
          color: tint == null
              ? t.accent.withValues(alpha: 0.18)
              : Color.lerp(tint, const Color(0xFFFFFFFF), 0.05)!,
        ),
      ),
    );
  }
}

/// Прогресс полоской по нижней кромке карточки.
class _Hairline extends ConsumerWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final frac = _progressFrac(ref);
    return SizedBox(
      height: 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: frac,
          child: ColoredBox(color: t.accent, child: const SizedBox(height: 2)),
        ),
      ),
    );
  }
}
