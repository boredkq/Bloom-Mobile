/// Полноэкранный плеер. Раскладка — по референсу: шапка (свернуть / «Играет
/// из» / меню), большая обложка, название и артист по
/// центру, прогресс, транспорт отдельным блоком, под ним ряд инструментов.
///
/// Вид (цвета, плёнки, радиус) — токены десктопного Bloom.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/entities/entities.dart';
import '../../../core/log/bloom_log.dart';
import '../../../core/store/library_store.dart';
import '../../../features/customization/custom_store.dart';
import '../../../features/customization/ui/image_thumb.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/marquee_text.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/ui/track_flick.dart';
import '../../../shared/ui/track_swipes.dart';
import '../../../shared/util/format.dart';
import '../../detail/artists_sheet.dart';
import '../../lyrics/lyrics_store.dart';
import '../../lyrics/ui/lyrics_view.dart';
import '../../pc/pc_remote.dart';
import '../../pc/pc_store.dart';
import '../play_error.dart';
import '../player_bg_store.dart';
import '../player_controller.dart';
import '../player_style_store.dart';
import '../player_view_store.dart';
import '../sleep_timer_store.dart';
import '../slider_style_store.dart';
import '../speed_store.dart';
import 'artist_avatars.dart';
import 'play_button.dart';
import 'player_backdrop.dart';
import 'player_sheet.dart';
import 'queue_sheet.dart';
import 'sleep_sheet.dart';
import 'slider_shapes.dart';
import 'source_pill.dart';
import 'speed_sheet.dart';
import 'track_swap.dart';
import 'vinyl_disc.dart';

/// Радиус обложки в плеере — заметно круглее блоков (как в референсе).
const double _coverRadius = 20;

/// Просвет между пилюлей источника и круглыми кнопками шапки.
const double _headerGap = 8;

/// Что уходит в буфер по тапу на название: «Название — Артист», как на ПК
/// (`TitleCopyOnClick`: `title + ' — ' + artist`). Артиста нет — одно название,
/// иначе в буфере оставалось бы висящее тире.
String trackCopyText(Track track) {
  final artist = track.artist.trim();
  return artist.isEmpty ? track.name : '${track.name} — $artist';
}

/// Содержимое плеера во весь экран.
///
/// Не экран и не маршрут: его строит панель ([PlayerSheet]) внутри растущей
/// карточки и обрезает своим окном, пока та не дошла до краёв. Отсюда два
/// следствия. Раскладка всегда считается по ПОЛНОМУ экрану, сколько бы от неё
/// сейчас ни было видно, — иначе на середине разворота она сжималась бы и в
/// конце прыгала. А закрывается плеер не `pop`, а [collapsePlayerSheet]: своего
/// маршрута у него нет.
///
/// `Scaffold` тут нужен не ради раскладки, а ради тостов: `ScaffoldMessenger`
/// показывает их на последнем собранном `Scaffold`, и без своего они выезжали
/// бы на каркасе — то есть ПОД панелью.
class FullPlayerBody extends ConsumerStatefulWidget {
  const FullPlayerBody({super.key});

  @override
  ConsumerState<FullPlayerBody> createState() => _FullPlayerBodyState();
}

class _FullPlayerBodyState extends ConsumerState<FullPlayerBody> {
  @override
  void initState() {
    super.initState();
    // Открытие плеера — в журнал, сразу на диск. Экран тяжёлый: размытия,
    // тень обложки, анимации. Если процесс умирает молча где-то здесь, а не на
    // звуке, разобрать это можно только по тому, доехала строка или нет.
    logInfo('ui', 'открыт полноэкранный плеер', now: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final track = state.track;
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    final lyricsMode = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
    final swipes = ref.watch(swipeProvider).of(SwipeZone.player);

    return Scaffold(
      // Заливка темы остаётся под фоном плеера: сам фон её накрывает целиком, а
      // в режиме «Нет» её и видно. Прозрачным `Scaffold` делать нельзя — сквозь
      // него просвечивало бы то, над чем лежит панель.
      backgroundColor: t.bg,
      // Тяги вниз здесь нет: панель ловит её сама, снаружи содержимого — иначе
      // жест пришлось бы заводить дважды и они спорили бы за палец.
      //
      // Горизонтальный жест ловится со всего экрана, а едут от него обложка и
      // подписи: тянуть плеер целиком незачем — шапка и транспорт к треку не
      // относятся. Своя ловушка прогресса ниже перебивает этот жест, как и
      // положено ближнему детектору.
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Фон — настройка «Плеер → Фон плеера». Ниже содержимого и выше
          // заливки: плёнки блоков (`ovlBg`) обязаны проступать на нём.
          const PlayerBackdrop(),
          _body(context, state, track, lyricsOpen, lyricsMode, swipes),
        ],
      ),
    );
  }

  /// Содержимое плеера поверх фона.
  Widget _body(
    BuildContext context,
    PlaybackState state,
    Track? track,
    bool lyricsOpen,
    LyricsMode lyricsMode,
    SwipePair swipes,
  ) {
    return TrackFlick(
      // Жест обязан ловиться СО ВСЕГО экрана, а не только там, где под пальцем
      // что-то нарисовано: по бокам от квадратной обложки и в просветах колонки
      // содержимого нет, и `deferToChild` пропускал жест насквозь — к панели под
      // нами. Та в режиме «Соседние треки» едет целой карточкой, и вбок уезжал
      // весь развёрнутый плеер (он это и поймал).
      behavior: HitTestBehavior.opaque,
      onLeft: track == null || swipes.left == SwipeAction.none
          ? null
          : () => runSwipeAction(
              context,
              ref,
              swipes.left,
              track: track,
              fromFlick: true,
            ),
      onRight: track == null || swipes.right == SwipeAction.none
          ? null
          : () => runSwipeAction(
              context,
              ref,
              swipes.right,
              track: track,
              fromFlick: true,
            ),
      builder: (context, shift) => SafeArea(
        // Низ — не `SafeArea`, а [bottomEdgeInset]: ряд инструментов
        // обязан кончаться там же, где кромка таб-бара под списком,
        // иначе открытие плеера выглядит как прыжок раскладки. Заодно
        // на iOS полный вырез под home indicator (34) поднял бы весь низ
        // заметно выше, чем на андроиде.
        bottom: false,
        child: track == null
            ? const SizedBox.shrink()
            : Padding(
                // Сверху воздух: шапка не должна липнуть к статус-бару.
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  bottomEdgeInset(context),
                ),
                child: Column(
                  children: [
                    _Header(track: track, state: state),
                    const SizedBox(height: 16),
                    // Обложка по центру свободного места — или текст на её
                    // месте, если выбран вид «вместо обложки». В виде
                    // «поверх» обложка остаётся, а текст ложится на неё
                    // самой карточкой (см. `_Cover`).
                    // Именно `Expanded`, а не `Flexible`: панель текста —
                    // скролл, и по свободным ограничениям он берёт высоту
                    // по СОДЕРЖИМОМУ. Пока текст грузится, содержимое —
                    // одна строчка «Загрузка текста…», колонка схлопывалась
                    // и весь низ экрана уезжал вверх (поймал он). Обложке
                    // это ничего не меняет: её `Center` и раньше занимал
                    // всё свободное место.
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: lyricsOpen && lyricsMode == LyricsMode.replace
                            ? const _LyricsPane(key: ValueKey('lyrics'))
                            : Center(
                                key: const ValueKey('cover'),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: FlickSlide(
                                    shift: shift,
                                    child: _Cover(
                                      state: state,
                                      lyricsOpen:
                                          lyricsOpen &&
                                          lyricsMode == LyricsMode.overlay,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    // Отступы вокруг названия одинаковые: оно должно стоять
                    // ровно посередине между обложкой и прогрессом. Снизу
                    // те же ~24 набегают из полей вокруг имени артиста, этой
                    // восьмёрки и верхней половины ловушки прогресса
                    // (`_Progress.slack`).
                    const SizedBox(height: 24),
                    // Подписи отзываются вдвое слабее обложки: они уже
                    // самой карточки, и на одном с ней ходу успевали бы
                    // улететь за край раньше неё.
                    FlickSlide(
                      shift: shift,
                      amplitude: 0.5,
                      child: _TitleBlock(state: state),
                    ),
                    const SizedBox(height: 8),
                    const _Progress(),
                    const SizedBox(height: 16),
                    const _Transport(),
                    const SizedBox(height: 12),
                    const _Tools(),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.track, required this.state});

  /// Текущий трек — он уходит в меню под тремя точками.
  final Track track;

  /// Состояние плеера: пилюле нужны источник очереди и флаг перемешки.
  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    // На своём фоне шапка красится ТЕМ ЖЕ, чем блоки транспорта и инструментов
    // (`ovlBg` + `ovlLine`): сплошная плашка темы (`pill`) на цветном фоне
    // читается чёрной нашлёпкой рядом с полупрозрачным низом — он это и
    // заметил. Без фона всё остаётся как было: плёнка в три процента поверх
    // заливки темы — это почти та же заливка, только тусклее.
    final bg = ref.watch(playerBgProvider);
    final fill = bg.isNone ? null : t.ovlBg;
    final line = bg.isNone ? null : t.ovlLine;

    return Row(
      children: [
        CircleIconButton(
          icon: Bi.altArrowDown,
          iconSize: 23,
          background: fill,
          borderColor: line,
          // Своя заливка обычно гасит стекло, но здесь это поверхность темы, а
          // не состояние: при включённой «Прозрачности» шапке стекло положено.
          glass: true,
          // Не `pop`: плеер — слой каркаса, а не маршрут (см. `PlayerSheet`).
          onTap: collapsePlayerSheet,
        ),
        // Пилюля источника — та же плёнка и та же высота, что у круглых кнопок
        // по краям: шапка читается одной ровной строкой, а не ступенькой. Имя
        // источника бывает длинным, поэтому она забирает весь остаток ширины и
        // ужимается по содержимому уже внутри. Просветы по бокам обязательны:
        // без них длинное имя раздувает пилюлю впритык к кружкам, и все три
        // плёнки слипаются в одну полосу.
        const SizedBox(width: _headerGap),
        Expanded(
          child: SourcePill(
            source: state.source,
            shuffle: state.shuffle,
            count: state.queue.length,
            background: fill,
            borderColor: line,
          ),
        ),
        const SizedBox(width: _headerGap),
        CircleIconButton(
          icon: Bi.kebab,
          background: fill,
          borderColor: line,
          glass: true,
          onTap: () => showTrackActions(context, ref, track),
        ),
      ],
    );
  }
}

/// Текст на месте обложки — вид «вместо обложки».
///
/// Занимает ВСЁ свободное место колонки, а не квадрат обложки: строк на экран
/// влезает заметно больше, и ради этого вид и заводился.
class _LyricsPane extends StatelessWidget {
  const _LyricsPane({super.key});

  @override
  Widget build(BuildContext context) => const LyricsView(
    padding: EdgeInsets.fromLTRB(8, 24, 8, 24),
    // Своя раскладка: крупнее и по левому краю — коробка тут во всю ширину
    // экрана, а не квадрат обложки (см. `LyricsLayout`).
    layout: LyricsLayout.replace,
  );
}

class _Cover extends ConsumerWidget {
  const _Cover({required this.state, this.lyricsOpen = false});

  final PlaybackState state;

  /// Панель текста поверх обложки открыта — вид «поверх обложки».
  final bool lyricsOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = state.track!;
    // Пластинка (`playerStyle: 'vinyl'` с ПК): круглая обложка, вращение и
    // тёмная этикетка по центру.
    final vinyl = ref.watch(playerStyleProvider).isVinyl;
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.biggest.shortestSide;
        // Круг — тот же радиус, доведённый до половины стороны: всё, что
        // обрезается рамкой обложки (сама картинка, панель текста), становится
        // круглым разом.
        final radius = vinyl ? side / 2 : _coverRadius;
        // Крутим ТОЛЬКО пока идёт звук — десктопное `vinyl-paused`
        // (`animation-play-state:paused`). Состояние берём у самого плеера, а
        // не у `PlaybackState`: там его нет, а пауза из шторки и с гарнитуры
        // обязана останавливать диск так же, как кнопка на экране.
        final spinning = ref.watch(playingNowProvider);
        return Stack(
          children: [
            // Слои смены трека клипует сама рамка обложки, а картинки внутри
            // идут БЕЗ своего радиуса: иначе уезжающая показывала бы
            // скруглённый угол посреди кадра.
            SizedBox(
              width: side,
              height: side,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: VinylSpin(
                  // Вращается вся стопка слоёв смены трека, а не одна текущая
                  // картинка: иначе приезжающая обложка встала бы ровно, а
                  // уезжающая продолжала крутиться — два разных движения в
                  // одном кадре.
                  enabled: vinyl,
                  spinning: spinning,
                  child: TrackSwap(
                    id: track.id,
                    fade: true,
                    child: Cover(
                      // Своя обложка из «Кастомизации» важнее обложки трека —
                      // десктопный `coverOverride` (с учётом режима).
                      url: ref.watch(playerCoverProvider),
                      size: side,
                      radius: 0,
                    ),
                  ),
                ),
              ),
            ),
            // Этикетка — порт `.ps-cover.vinyl-mode::after`. Стоит НАД
            // обложкой, но под панелью текста (на ПК у неё z-index 3) и, само
            // собой, не крутится вместе с диском.
            if (vinyl)
              Positioned(
                left: 0,
                top: 0,
                width: side,
                height: side,
                child: Center(child: VinylLabel(size: side * VinylLabel.share)),
              ),
            // Панель текста поверх обложки — порт `.lyrics-panel` с ПК: та же
            // подложка (цвет блока, 96%) и то же появление (прозрачность плюс
            // лёгкий наплыв). Рисуется ВСЕГДА, видимость даёт прозрачность:
            // иначе анимации не из чего играть.
            Positioned(
              left: 0,
              top: 0,
              width: side,
              height: side,
              child: IgnorePointer(
                ignoring: !lyricsOpen,
                child: AnimatedOpacity(
                  opacity: lyricsOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: AnimatedScale(
                    scale: lyricsOpen ? 1 : 0.97,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: ColoredBox(
                        color: context.bloom.blockColor.withValues(alpha: 0.96),
                        child: LyricsView(
                          live: lyricsOpen,
                          // A disc keeps the lines off its edge: the PC's 52
                          // on a 380 disc.
                          padding: vinyl
                              ? EdgeInsets.all(side * 0.14)
                              : const EdgeInsets.fromLTRB(14, 36, 14, 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final track = state.track!;
    final theme = Theme.of(context).textTheme;

    // По имени артиста уходим на его страницу — как из меню трека; артистов в
    // строке несколько — сперва шторка с выбором. На месте имени может стоять
    // ошибка воспроизведения: тогда строка просто текст. Одиночного артиста
    // без точного id открывать тоже нечем.
    final canOpen = state.error == null && canOpenTrackArtist(track);

    // Куда прижаты название с артистом — настройка «Выравнивание заголовка»
    // (порт десктопного `titleAlign`, там это классы `.title-left/.title-right`
    // на `#playerContent`).
    final align = ref.watch(titleAlignProvider);

    // В состоянии лежит КОД ошибки — разворачиваем его в фразу здесь, при
    // отрисовке (см. `play_error.dart`).
    final error = state.error;
    final subtitle = Text(
      error == null ? track.artist : describePlayError(context.l, error),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align.text,
      // Крупнее общей подписи (13): в плеере под названием стоит одна
      // строка, и она должна читаться с руки.
      style: theme.bodyMedium?.copyWith(
        fontSize: 18,
        color: state.error != null ? t.danger : null,
      ),
    );

    // Ловушка под палец шире самой строки — но только со СВОБОДНОЙ стороны:
    // прижатый заголовок обязан начинаться там же, где полоса прогресса и время
    // под ней, а лишние 20 px по краю утаскивали бы его внутрь. По центру
    // отступ остаётся с обеих сторон: там он ничего не двигает, только держит
    // строку от краёв.
    final pad = switch (align) {
      TitleAlign.left => const EdgeInsets.only(right: 20),
      TitleAlign.center => const EdgeInsets.symmetric(horizontal: 20),
      TitleAlign.right => const EdgeInsets.only(left: 20),
    };

    // Слои подписи занимают всю ширину колонки — иначе слайд считался бы от
    // ширины самого текста и короткое название ехало бы заметно меньше
    // длинного. Куда встают сами строки внутри — дело колонки: строка, которая
    // влезла, шириной равна тексту, и одним `textAlign` её не подвинуть.
    return SizedBox(
      width: double.infinity,
      child: TrackSwap(
        id: track.id,
        child: Column(
          crossAxisAlignment: align.cross,
          children: [
            // Тап по названию копирует «Название — Артист» (порт
            // `TitleCopyOnClick` с ПК). Ловушка шире самой строки — по бокам, а
            // не по высоте: сверху и снизу отступы выверены, лишние пиксели
            // сдвинули бы весь блок.
            GestureDetector(
              onTap: () => _copy(context, track),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: pad,
                // Название бежит, если не влезло, — порт `MarqueeTitle` с ПК.
                // На ходу строка идёт от левого края, в покое — по настройке.
                child: MarqueeText(
                  track.name,
                  align: align.text,
                  style: theme.headlineSmall?.copyWith(fontSize: 25),
                ),
              ),
            ),
            // Отступ до имени даёт сама ловушка под палец: одной строкой текста
            // в 19 px по центру экрана попасть тяжело.
            GestureDetector(
              onTap: canOpen
                  ? () => openTrackArtist(context, ref, track)
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: pad + const EdgeInsets.symmetric(vertical: 7),
                // Перед именем — аватарки артистов с площадки. На месте имени
                // может стоять ошибка воспроизведения: к ней картинки не
                // относятся. Ряд ужимается по содержимому, чтобы вставать по
                // выравниванию колонкой, а имя внутри остаётся гибким — иначе
                // длинная строка выпирала бы за экран вместо многоточия.
                child: state.error != null
                    ? subtitle
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TrackArtistAvatars(track: track),
                          Flexible(child: subtitle),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// «Название — Артист» в буфер, как на ПК.
  Future<void> _copy(BuildContext context, Track track) async {
    if (track.name.isEmpty) return;
    final l = context.l;
    try {
      await Clipboard.setData(ClipboardData(text: trackCopyText(track)));
      if (context.mounted) {
        showToast(context, l.playerCopied, kind: ToastKind.success);
      }
    } catch (_) {
      if (context.mounted) {
        showToast(context, l.playerCopyError, kind: ToastKind.error);
      }
    }
  }
}

class _Progress extends ConsumerStatefulWidget {
  const _Progress();

  /// Толщина дорожки обычного типа и высота ловушки под палец.
  ///
  /// Слайдер без кружка и без ореола ужимается по высоте до самой дорожки, а в
  /// 5 px пальцем не попасть — перемотать получалось, только ткнув точно в
  /// полоску. Растягиваем его на [hit]: дорожку он рисует по центру своей
  /// высоты, а нажатие ловит всей площадью.
  ///
  /// Ловушка одна на все типы слайдера, хотя дорожки у них разной толщины
  /// (`sliderTrackHeight`, самая высокая — волна в 28): иначе смена типа
  /// двигала бы под собой времена и весь низ плеера.
  static const double trackHeight = 5;

  /// Пустота, которая при этом остаётся над и под дорожкой внутри ловушки.
  ///
  /// Ловушка симметричная, а вот воздух вокруг дорожки — нет: снизу к пустоте
  /// прибавляется ещё и верхний отступ строки времён (у `bodyMedium` над
  /// цифрами есть свой межстрочный запас), и провал под полоской выходит явно
  /// шире, чем над ней. Поэтому [slack] держим по нижней стороне, а недостачу
  /// сверху добирает `SizedBox` перед прогрессом.
  static const double slack = 12;

  static const double hit = trackHeight + slack * 2;

  @override
  ConsumerState<_Progress> createState() => _ProgressState();
}

class _ProgressState extends ConsumerState<_Progress> {
  /// Позиция под пальцем, пока тянут (мс). Пока она не null — дорожка и время
  /// слева живут от неё, а не от плеера.
  ///
  /// Иначе `Slider` (он управляемый) рисует то, что пришло из стрима, и
  /// заливка отпрыгивает назад к фактической позиции — резинка. Перематываем
  /// один раз, на отпускании: seek по сетевому стриму дорогой, а на каждый
  /// кадр перетаскивания их набегают десятки.
  double? _drag;

  Future<void> _commit(double v) async {
    await ref
        .read(playbackProvider.notifier)
        .seek(Duration(milliseconds: v.round()));
    // Отпускаем только после самой перемотки: до неё стрим отдаёт ещё старую
    // позицию, и полоска моргнула бы назад.
    if (mounted) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final head =
        ref.watch(playheadProvider).value ??
        (position: Duration.zero, total: Duration.zero);

    // Картинка ползунка декодируется асинхронно: пока её нет (или её не
    // выбирали), дорожка живёт без пуговки, как и раньше.
    final thumb = ref.watch(sliderThumbProvider).value;
    final style = ref.watch(sliderStyleProvider);
    // Узор волны — свой на каждый трек, как на ПК (`regenWave` на смену
    // трека); id и есть зерно.
    final seed = ref.watch(playbackProvider.select((s) => s.track?.id)) ?? '';

    final max = head.total.inMilliseconds.toDouble();
    final live = max <= 0
        ? 0.0
        : head.position.inMilliseconds
              .clamp(0, head.total.inMilliseconds)
              .toDouble();
    final value = (_drag ?? live).clamp(0.0, max <= 0 ? 0.0 : max);

    return Column(
      children: [
        SizedBox(
          height: _Progress.hit,
          child: SliderTheme(
            // Вид дорожки и пуговки — целиком из типа слайдера (настройка
            // «Плеер → Слайдер»). У обычного типа это ровно то, что было:
            // дорожка в 5 (толще общей тройки — это главный орган управления
            // экрана, а не строка настройки) и без кружка, если в
            // «Кастомизации» не выбрали картинку ползунка.
            data: bloomSliderTheme(
              SliderTheme.of(context),
              style: style,
              tokens: context.bloom,
              thumbImage: thumb,
              waveSeed: seed.hashCode,
            ),
            child: Slider(
              value: value,
              max: max <= 0 ? 1 : max,
              onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
              onChangeEnd: max <= 0 ? null : _commit,
            ),
          ),
        ),
        // Времена стоят сразу под ловушкой: весь воздух до дорожки они
        // получают из её нижней половины (`_Progress.slack`).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          // Плашка «Далее» стоит СЛОЕМ поверх строки времён, а не третьей
          // ячейкой в ней: в ряду её центр съезжал бы вслед за шириной времён
          // («1:45» против «1:02:33»), а она обязана стоять ровно посреди
          // экрана. Ряд задаёт слою ширину, плашка — высоту.
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Тем же цветом, что артист под названием (`bodyMedium`).
                  Text(
                    mmss(Duration(milliseconds: value.round())),
                    style: theme.bodyMedium,
                  ),
                  Text(mmss(head.total), style: theme.bodyMedium),
                ],
              ),
              // Поля — запас под времена: длинное название ужимается
              // многоточием, а не наезжает на цифры.
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 62),
                child: _NextUpPill(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Плашка «Далее: <трек>» под слайдером — что заиграет после текущего.
///
/// Своя, десктопной пары нет: на ПК очередь стоит колонкой рядом с плеером и
/// следующий трек виден в ней сам, а у нас она спрятана в шторку. Плашки нет
/// вовсе, когда дальше ничего (`nextTrack`) или настройку выключили — пустое
/// место под слайдером не оставляем.
///
/// Тап открывает очередь, как пилюля источника в шапке: перематывать вперёд
/// есть чем (кнопка транспорта прямо под ней), а вот увидеть, что дальше
/// целым списком, больше неоткуда. Обложка и подпись — те же, что у пилюли:
/// две плашки на одном экране обязаны читаться одинаково.
class _NextUpPill extends ConsumerWidget {
  const _NextUpPill();

  /// Сторона обложки. Меньше, чем в пилюле источника (28): та стоит в шапке
  /// вровень с круглыми кнопками, а эта живёт в строке времён и переросшей
  /// раздвигала бы весь низ плеера.
  static const double _cover = 19;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(nextUpProvider)) return const SizedBox.shrink();
    final next = ref.watch(playbackProvider.select((s) => s.nextTrack));
    if (next == null) return const SizedBox.shrink();

    final t = context.bloom;
    return Pressable(
      onTap: () => showQueueSheet(context),
      child: Material(
        color: t.ovlBg,
        shape: StadiumBorder(side: BorderSide(color: t.ovlLine)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          // Слева поля ВДВОЕ больше, чем сверху и снизу, — та же поправка, что
          // в пилюле источника: край плашки скруглён, и квадрат обложки,
          // отодвинутый от него «поровну», упирается углами в саму дугу
          // (при высоте 27 её левый край на высоте угла обложки проходит по
          // 3.9 px — ровно там, где стоял отступ в 4). Справа воздуха больше:
          // там текст, а не картинка.
          padding: const EdgeInsets.fromLTRB(9, 4, 13, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Cover(url: next.cover, size: _cover, radius: t.radius * 0.3),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  context.l.playerNextUp(next.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The plate under the player's buttons, with softer corners than a card's.
class _Plate extends StatelessWidget {
  const _Plate({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.ovlBg,
        border: Border.all(color: t.ovlLine),
        borderRadius: BorderRadius.circular(t.radius * 1.8),
      ),
      child: child,
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final ctrl = ref.read(playbackProvider.notifier);

    // Режим повтора различаем бейджем, а не подменой иконки (как на ПК): сама
    // кнопка всегда repeat, сверху справа — «список» для всей очереди и «1» для
    // одного трека.
    final repeatMark = switch (state.repeat) {
      PlayerRepeat.all => BloomIcon(Bi.list, size: 9, color: t.accentText),
      PlayerRepeat.one => Text(
        '1',
        style: TextStyle(
          fontSize: 8,
          // Цифра оптически сидит выше центра — прижимаем высотой строки.
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: t.accentText,
        ),
      ),
      _ => null,
    };

    return _Plate(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _FlatIcon(
            icon: Bi.repeat,
            size: 24,
            active: state.repeat != PlayerRepeat.off,
            onTap: ctrl.cycleRepeat,
            mark: repeatMark,
          ),
          _FlatIcon(icon: Bi.skipPreviousBold, size: 30, onTap: ctrl.prev),
          PlayButton(
            size: 68,
            iconSize: 28,
            plainIconSize: 40,
            spinnerSize: 28,
            loading: state.loading,
            onTap: ctrl.toggle,
          ),
          _FlatIcon(icon: Bi.skipNextBold, size: 30, onTap: ctrl.next),
          _FlatIcon(
            icon: Bi.shuffle,
            size: 24,
            active: state.shuffle,
            onTap: ctrl.toggleShuffle,
          ),
        ],
      ),
    );
  }
}

/// Кнопка таймера сна. Отдельным виджетом, а не строчкой в [_Tools]: пока
/// таймер идёт, состояние тикает раз в секунду, и перерисовывать из-за этого
/// весь ряд инструментов незачем.
///
/// Идущий таймер показывает остаток ВМЕСТО луны — тем же приёмом, что кнопка
/// скорости показывает `1.25×`.
class _SleepButton extends ConsumerWidget {
  const _SleepButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleep = ref.watch(sleepTimerProvider);
    // Метка нужна своя: остаток вместо иконки скринридер прочёл бы как голое
    // «23:14», без единого слова о том, что это вообще такое.
    return Semantics(
      button: true,
      label: context.l.playerSleep,
      child: _FlatIcon(
        icon: sleep.mode == SleepMode.endOfTrack
            ? Bi.moonSleepBold
            : Bi.moonSleep,
        size: 25,
        label: sleep.mode == SleepMode.timer
            ? sleepLabel(sleep.remaining)
            : null,
        active: sleep.active,
        onTap: () => showSleepSheet(context),
      ),
    );
  }
}

/// «Играть на» (Connect): куда идёт звук — этот телефон или компьютер. Есть,
/// только пока ПК на связи; горит, пока звук на ПК.
class _PlayOnButton extends ConsumerWidget {
  const _PlayOnButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(pcProvider.select((s) => s.live))) {
      return const SizedBox.shrink();
    }
    final onPc = ref.watch(pcRemoteProvider.select((r) => r != null));
    return Semantics(
      button: true,
      label: context.l.pcPlayOn,
      child: _FlatIcon(
        icon: Bi.monitorSmartphone,
        size: 25,
        active: onPc,
        onTap: () => _showPlayOn(context, ref, onPc),
      ),
    );
  }

  static void _showPlayOn(BuildContext context, WidgetRef ref, bool onPc) {
    final t = context.bloom;
    final pc = ref.read(pcProvider).link?.name ?? '';
    final remote = ref.read(pcRemoteProvider.notifier);
    Widget? mark(bool on) =>
        on ? BloomIcon(Bi.check, size: 18, color: t.accent) : null;
    showBloomSheet(
      context: context,
      groups: [
        [
          SheetAction(
            icon: Bi.monitor,
            label: pc.isEmpty ? context.l.setPc : pc,
            trailing: mark(onPc),
            onTap: onPc ? null : remote.playOnPc,
          ),
          SheetAction(
            icon: Bi.smartphone,
            label: context.l.pcThisPhone,
            trailing: mark(!onPc),
            onTap: onPc ? remote.playHere : null,
          ),
        ],
      ],
    );
  }
}

class _FlatIcon extends StatelessWidget {
  const _FlatIcon({
    required this.icon,
    this.onTap,
    this.size = 22,
    this.active = false,
    this.mark,
    this.label,
    this.color,
  });

  final BloomGlyph icon;
  final VoidCallback? onTap;
  final double size;
  final bool active;

  /// Свой цвет иконки вместо обычного — у ♡ в избранном он красный.
  final Color? color;

  /// Мини-бейдж в кружке акцента поверх иконки (перенос .cc-badge с ПК): им
  /// различаем режимы кнопки, чтобы не подменять саму иконку.
  final Widget? mark;

  /// Надпись ВМЕСТО иконки — перенос `.cc-cap` с ПК: кнопка скорости при
  /// значении не 1× показывает само значение, а не спидометр.
  final String? label;

  /// Ширина коробки надписи. Фиксированная, а не по тексту: иначе ряд
  /// инструментов расходился бы на каждой смене скорости. Длинное значение
  /// (`1.35×`) внутри неё поджимается [FittedBox].
  static const double _labelWidth = 34;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = this.color ?? (active ? t.accent : t.iconFg);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (label == null)
              BloomIcon(icon, size: size, color: color)
            else
              SizedBox(
                width: _labelWidth,
                height: size,
                child: FittedBox(
                  child: Text(
                    label!,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1,
                      color: color,
                    ),
                  ),
                ),
              ),
            if (mark != null)
              Positioned(
                right: -4,
                top: -3,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: mark,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ряд инструментов — две пилюли по краям: слева то, что про сам трек (♡, ⊕ и
/// текст), справа то, что про прослушивание (скорость и сон). Кнопки очереди
/// тут нет: очередь открывает пилюля источника в шапке (тап), а долгое нажатие
/// на ней уводит на сам источник.
class _Tools extends ConsumerWidget {
  const _Tools();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final track = ref.watch(playbackProvider.select((s) => s.track));
    if (track == null) return const SizedBox.shrink();
    final isFav = ref.watch(
      libraryProvider.select((lib) => lib.isFav(track.id)),
    );
    // Скорость: пока она 1×, кнопка — обычный спидометр; иначе на её месте
    // само значение, как `cc-cap` в десктопном транспорте.
    final rate = ref.watch(speedProvider).rate;
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    // Кнопки «Т» нет, пока текст не нашёлся, — как на ПК
    // (`useLyricsBtnVisible`). Открытую панель кнопка переживает в любом
    // случае: иначе её было бы нечем закрыть.
    final lyricsFound = ref.watch(lyricsProvider).status == LyricsStatus.ready;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ToolPill(
          children: [
            _FlatIcon(
              icon: isFav ? Bi.heartBold : Bi.heart,
              size: 25,
              color: isFav ? t.sysFavIco : null,
              onTap: () => ref.read(libraryProvider.notifier).toggleFav(track),
            ),
            // Именно addCircle, а не plus: в solar_icons 0.1.0 `plus` и `minus`
            // сидят на одном коде 0xec4a и рисуются знаком «±» из
            // калькуляторной группы.
            _FlatIcon(
              icon: Bi.addCircle,
              size: 25,
              onTap: () => showAddToPlaylistSheet(context, ref, track),
            ),
            if (lyricsFound || lyricsOpen)
              _FlatIcon(
                icon: Bi.text,
                size: 25,
                active: lyricsOpen,
                onTap: () =>
                    ref.read(lyricsOpenProvider.notifier).state = !lyricsOpen,
              ),
          ],
        ),
        _ToolPill(
          children: [
            const _PlayOnButton(),
            _FlatIcon(
              icon: Bi.speed,
              size: 25,
              label: rate == 1 ? null : speedLabel(rate),
              active: rate != 1,
              onTap: () => showSpeedSheet(context),
            ),
            const _SleepButton(),
          ],
        ),
      ],
    );
  }
}

/// A plate of the tools' row, as wide as what's on it.
class _ToolPill extends StatelessWidget {
  const _ToolPill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _Plate(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}
