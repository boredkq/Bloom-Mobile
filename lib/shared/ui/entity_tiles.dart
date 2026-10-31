/// Строки и карточки сущностей — общие для поиска, страниц артиста и
/// библиотеки. Работают с нейтральными [Track]/[Artist]/[Playlist], поэтому
/// одинаковы для всех площадок.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/entities/entities.dart';
import '../../features/detail/detail_nav.dart';
import '../../features/offline/offline_store.dart';
import '../../features/player/play_source.dart';
import '../../features/player/player_controller.dart';
import '../util/format.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'chart_trend.dart';
import 'cover_hero.dart';
import 'platform_logo.dart';
import 'pressable.dart';
import 'track_actions.dart';

/// Метка перелёта обложки — своя у КАЖДОГО экземпляра карточки. Считать её из
/// id нельзя: один альбом легко стоит сразу в двух секциях выдачи, а два `Hero`
/// с одинаковой меткой в одном дереве — исключение на старте перехода.
///
/// Обложки нет — перелёта нет: заглушке лететь некуда.
CoverFlight? _flightFor(String? cover, Object tag) =>
    cover == null || cover.isEmpty ? null : CoverFlight(tag: tag, image: cover);

/// Поля строки трека. Высота нужна снаружи: очередь открывается сразу на
/// играющем треке и считает по ней смещение прокрутки.
const EdgeInsets kTrackRowPadding = EdgeInsets.symmetric(
  horizontal: 8,
  vertical: 6,
);
const double kTrackRowCover = 52;
const double kTrackRowHeight = kTrackRowCover + 12;

/// Ширина колонки номера, которой в альбоме подменяется обложка (см.
/// [TrackRowShell.number]). Уже обложки: цифре хватает, а на телефоне
/// пятидесятидвухпиксельный отступ под двузначное число съедает название.
/// Высота при этом прежняя — [kTrackRowHeight] считает очередь.
const double kTrackRowNumber = 30;

/// Пометка строки в «Истории»: во сколько трек слушали в последний раз и
/// сколько раз всего. На десктопе это счётчик у названия и время у правого края
/// строки — здесь ровно то же.
@immutable
class HistoryMark {
  const HistoryMark({required this.time, required this.count});

  /// Уже отформатированное время («18:32»): формат зависит от локали и от
  /// системных настроек, а их знает только виджет.
  final String time;

  final int count;
}

/// Строка трека: обложка, название/артист, длительность. Тап ставит [queue]
/// целиком, чтобы работали «дальше»/«назад», а не один трек.
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.source,
    this.dragIndex,
    this.mark,
    this.onOpen,
    this.number,
    this.rank,
  });

  final Track track;
  final List<Track> queue;
  final int index;

  /// Порядковый номер вместо обложки — см. [TrackRowShell.number].
  final int? number;

  /// Место в чарте — см. [TrackRowShell.rank].
  final int? rank;

  /// Позвать перед запуском — «записать в недавно открытые» на экране поиска.
  /// В остальных списках не задан: недавние копит только поиск, как на ПК
  /// (`openActions.ts`).
  final VoidCallback? onOpen;

  /// Откуда взята [queue] — см. [PlaybackState.source]. Строка внутри
  /// плейлиста заводит его целиком: плитка этого плейлиста должна показать
  /// эквалайзер, а пилюля в плеере — назвать его.
  final PlaySource? source;

  /// Номер строки в `ReorderableList` — см. [TrackRowShell.dragIndex]. `null` в
  /// списках, где порядок не свой: в выдаче поиска и на страницах площадок
  /// двигать нечего.
  final int? dragIndex;

  /// Задана только в «Истории» — см. [HistoryMark].
  final HistoryMark? mark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrackRowShell(
      track: track,
      active: ref.watch(playbackProvider).track?.id == track.id,
      onTap: () {
        onOpen?.call();
        ref
            .read(playbackProvider.notifier)
            .playQueue(queue, index, source: source);
      },
      // Раздел библиотеки шторка узнаёт из источника списка: другого признака,
      // «откуда эта строка», у неё нет, а от него зависит «Убрать из плейлиста».
      onMenu: () => showTrackActions(
        context,
        ref,
        track,
        listId: switch (source) {
          LibSource(:final listId) => listId,
          _ => null,
        },
      ),
      dragIndex: dragIndex,
      mark: mark,
      number: number,
      rank: rank,
    );
  }
}

/// Строка трека без привязки к списку: вид и жесты, действия — снаружи. Одна
/// на всё — плейлисты, выдачу поиска, страницы площадок и очередь, — иначе
/// списки неминуемо разъезжаются видом.
class TrackRowShell extends StatelessWidget {
  const TrackRowShell({
    super.key,
    required this.track,
    required this.active,
    required this.onTap,
    required this.onMenu,
    this.dragIndex,
    this.mark,
    this.number,
    this.rank,
  });

  final Track track;

  /// Место в чарте: колонка «номер + динамика» ПЕРЕД обложкой — обложка, в
  /// отличие от [number], остаётся. Только на странице «Чарт».
  final int? rank;

  /// «Играет сейчас»: название акцентом, вместо длительности эквалайзер.
  /// Считает вызывающий — в очереди один трек может стоять дважды, и по id их
  /// не различить.
  final bool active;

  final VoidCallback onTap;

  /// Долгий тап — контекстное меню трека, как на десктопе.
  final VoidCallback onMenu;

  /// Номер строки в `ReorderableList`. Задан — обложка становится тянучкой:
  /// зажать и тащить (на десктопе handle тоже на обложке). Меню при этом
  /// переезжает с обложки на остальную часть строки: два долгих жеста на одном
  /// месте иначе спорят в арене и меню открывается вместо перетаскивания.
  final int? dragIndex;

  /// Задана только в «Истории» — см. [HistoryMark].
  final HistoryMark? mark;

  /// Порядковый номер трека в альбоме. Задан — вместо обложки стоит он
  /// (десктопный `TrackRowNum`): на странице альбома обложка у всех строк одна
  /// и та же, и повторять её четырнадцать раз бессмысленно.
  final int? number;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final drag = dragIndex;
    final Widget plain = switch (number) {
      final n? => _Number(number: n, active: active),
      null => _Cover(track: track),
    };
    final Widget cover = switch (rank) {
      final r? => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Rank(rank: r, track: track, active: active),
          const SizedBox(width: 6),
          plain,
        ],
      ),
      null => plain,
    };

    return InkWell(
      onTap: onTap,
      onLongPress: drag == null ? onMenu : null,
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Padding(
        padding: kTrackRowPadding,
        child: Row(
          children: [
            if (drag == null)
              cover
            else
              ReorderableDelayedDragStartListener(index: drag, child: cover),
            const SizedBox(width: 12),
            Expanded(
              child: _Rest(
                track: track,
                active: active,
                onMenu: drag == null ? null : onMenu,
                mark: mark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Обложка трека в строке. Бейдж площадки в углу: в общем списке треки могут
/// быть из разных источников, и по обложке этого не понять.
class _Cover extends StatelessWidget {
  const _Cover({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Cover(url: track.cover, size: kTrackRowCover),
        Positioned(
          right: 3,
          bottom: 3,
          child: SourceBadge(track.source, size: kRowBadge),
        ),
      ],
    );
  }
}

/// Номер трека на месте обложки — десктопный `.trnum`: приглушённая цифра
/// моноширинными знаками (чтобы «9» и «10» стояли колонкой), у играющего трека
/// акцентом.
///
/// Полосок эквалайзера здесь, в отличие от ПК, нет: на мобилке они и так стоят
/// в рамке длительности у правого края строки, и вторые в той же строке — шум.
class _Number extends StatelessWidget {
  const _Number({required this.number, required this.active});

  final int number;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      width: kTrackRowNumber,
      height: kTrackRowCover,
      child: Center(
        child: Text(
          '$number',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: active ? t.accent : t.text2,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Место в чарте и его динамика — десктопный `.trrank`: цифра, под ней «▲2».
class _Rank extends StatelessWidget {
  const _Rank({required this.rank, required this.track, required this.active});

  final int rank;
  final Track track;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      width: kTrackRowNumber + 4,
      height: kTrackRowCover,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$rank',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: active ? t.accent : t.text,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          ChartTrend(track: track),
        ],
      ),
    );
  }
}

/// Строка без обложки: тексты, отметка офлайна, длительность. Отдельным
/// куском, потому что у тянущихся строк именно на нём висит долгий тап.
class _Rest extends StatelessWidget {
  const _Rest({
    required this.track,
    required this.active,
    this.onMenu,
    this.mark,
  });

  final Track track;
  final bool active;
  final VoidCallback? onMenu;
  final HistoryMark? mark;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final mark = this.mark;

    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: active
                          ? theme.titleMedium?.copyWith(color: t.accent)
                          : theme.titleMedium,
                    ),
                  ),
                  // Сколько раз слушали — только когда больше одного: единица
                  // в истории и так у всех, кроме повторов.
                  if (mark != null && mark.count > 1) ...[
                    const SizedBox(width: 6),
                    _PlayCountBadge(count: mark.count),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Ярче обычной подписи: в строке трека артист читается наравне
                // с названием, а не как второстепенная мелочь.
                style: theme.bodySmall?.copyWith(color: t.text2),
              ),
            ],
          ),
        ),
        _OfflineMark(trackId: track.id),
        if (mark != null) ...[
          const SizedBox(width: 10),
          Text(
            mark.time,
            style: theme.bodySmall?.copyWith(color: t.muted, fontSize: 11),
          ),
        ],
        const SizedBox(width: 10),
        DurationPill(track: track, active: active),
      ],
    );

    if (onMenu == null) return row;
    // `opaque`: меню должно открываться и с пустого места между текстом и
    // длительностью. Тап при этом остаётся у `InkWell` строки — свой тап этот
    // детектор не ловит, и подсветка идёт по всей строке.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onMenu,
      child: row,
    );
  }
}

/// Счётчик прослушиваний у названия — акцентная пилюля из десктопной истории
/// (`historyMeta.count`). Цифра, а не «N раз»: строка узкая, а смысл читается из
/// самого раздела.
class _PlayCountBadge extends StatelessWidget {
  const _PlayCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: t.accentText,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// Отметка «трек лежит на устройстве» — стрелка перед длительностью, аналог
/// десктопной иконки `save` в строке. Пока трек качается, на её месте кольцо
/// прогресса (или бесконечное, если CDN не сказал размер).
///
/// Подписка через `select`: строк в списке сотни, и перерисовывать их все на
/// каждый тик прогресса чужого трека незачем.
class _OfflineMark extends ConsumerWidget {
  const _OfflineMark({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final status = ref.watch(
      offlineProvider.select(
        (s) => (
          saved: s.has(trackId),
          pending: s.isPending(trackId),
          progress: s.progressOf(trackId),
        ),
      ),
    );

    if (status.pending) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            value: status.progress,
            strokeWidth: 1.6,
            color: t.accent,
            backgroundColor: t.ovlLine,
          ),
        ),
      );
    }
    if (!status.saved) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      // Дискета и приглушённый цвет — как `.tr-offline` на десктопе (там
      // `Ico name="save"` = solar/diskette-linear, color: var(--text2)).
      child: BloomIcon(Bi.diskette, size: 14, color: t.text2),
    );
  }
}

/// Длительность трека в рамке — десктопный `.trd` (прозрачный фон, тонкая
/// линия), но скругление круче десктопного (0.85 от темы вместо 0.45) и линия
/// самая тихая (`ovlLine`): на мобилке рамка не должна спорить с названием.
/// У играющего трека вместо цифр в той же рамке стоит эквалайзер: строка сама
/// показывает, что играет.
class DurationPill extends ConsumerWidget {
  const DurationPill({super.key, required this.track, required this.active});

  final Track track;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    // Поток play/pause спрашиваем только у играющей строки — остальным он не
    // нужен и лишние подписки в длинном списке ни к чему.
    final child = active
        ? EqualizerBars(playing: ref.watch(playingNowProvider))
        : Text(
            mmss(track.duration),
            style: theme.bodySmall?.copyWith(
              color: t.text2,
              fontWeight: FontWeight.w600,
            ),
          );

    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      height: 30,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.ovlLine),
        borderRadius: BorderRadius.circular(t.radius * 0.85),
      ),
      child: child,
    );
  }
}

/// Эквалайзер играющего сета — оверлей для обложки его карточки. То же, что
/// полоски вместо длительности в строке трека: список сам показывает, что
/// играет именно он. Обложка под полосками слегка притемняется — на пёстрой
/// картинке их иначе не разглядеть.
///
/// Неиграющий сет отдаёт пустоту, а не отсутствие оверлея: решать, показывать
/// ли полоски, должен сам оверлей — иначе подписку на плеер пришлось бы
/// заводить каждой плитке сетки.
class SetEqualizer extends ConsumerWidget {
  const SetEqualizer({super.key, required this.setId});

  /// Тот же id, что уходит в `playQueue(sourceId:)`: id сета площадки или
  /// id библиотечного списка.
  final String setId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playingSet = ref.watch(
      playbackProvider.select((s) => s.sourceId == setId),
    );
    if (!playingSet) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.32),
        child: Center(
          // Полоски заданы в пикселях строки трека — на крупной обложке плитки
          // их надо увеличить, на мелкой (строка сета) оставить как есть.
          child: EqualizerBars(
            playing: ref.watch(playingNowProvider),
            scale: (box.maxWidth / 56).clamp(1.0, 3.0),
          ),
        ),
      ),
    );
  }
}

/// Строка альбома или плейлиста: обложка, название, владелец. Нужна там, где
/// сет стоит в списке, а не в карусели — в репостах артиста.
class SetRow extends StatefulWidget {
  const SetRow({super.key, required this.set});

  final Playlist set;

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final flight = _flightFor(set.cover, _tag);
    final sub = [
      set.isAlbum ? context.l.commonAlbum : context.l.commonPlaylist,
      set.ownerName,
      if (set.trackCount != null) context.l.tracksCount(set.trackCount!),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: () => openSet(context, set, flight: flight),
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Stack(
              children: [
                Cover(
                  url: set.cover,
                  size: 48,
                  flight: flight,
                  overlay: SetEqualizer(setId: set.id),
                ),
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: SourceBadge(set.source, size: kRowBadge),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    set.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка трека для карусели («Популярные» на странице артиста). Тап ставит
/// [queue] целиком — как и строка трека.
class TrackCard extends ConsumerWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.source,
    this.size = 132,
  });

  final Track track;
  final List<Track> queue;
  final int index;

  /// Откуда взята [queue] — см. [TrackRow.source].
  final PlaySource? source;

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final active = ref.watch(playbackProvider).track?.id == track.id;

    return Pressable(
      onTap: () => ref
          .read(playbackProvider.notifier)
          .playQueue(queue, index, source: source),
      onLongPress: () => showTrackActions(context, ref, track),
      scale: 0.97,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Бейдж крупнее и с большим отступом от угла, чем в строке, — как
            // `.sp-tc-cover .cov-badge` на десктопе.
            Stack(
              children: [
                Cover(url: track.cover, size: size),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: SourceBadge(track.source, size: kCardBadge),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: active
                  ? theme.titleSmall?.copyWith(color: t.accent)
                  : theme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка артиста: круглый аватар, имя, «Артист» (у слушателя SoundCloud —
/// «Профиль»). Тап открывает страницу артиста.
///
/// [size] `null` — карточка занимает всю ширину ячейки (сетка выдачи); число —
/// фиксированная ширина (карусель).
class ArtistCard extends StatefulWidget {
  const ArtistCard({
    super.key,
    required this.artist,
    this.size = 104,
    this.centerLabel = false,
    this.pinned = false,
    this.onOpen,
  });

  final Artist artist;
  final double? size;

  /// A pin after the name.
  final bool pinned;

  /// См. [TrackRow.onOpen].
  final VoidCallback? onOpen;

  /// Подписи по центру — так стоят артисты в сетке и подписки в библиотеке.
  final bool centerLabel;

  @override
  State<ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<ArtistCard> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    final size = widget.size;
    final centerLabel = widget.centerLabel;
    final theme = Theme.of(context).textTheme;
    final align = centerLabel ? TextAlign.center : TextAlign.start;
    final flight = _flightFor(artist.avatar, _tag);

    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: centerLabel
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Cover(
            url: artist.avatar,
            size: box.maxWidth,
            circle: true,
            flight: flight,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  artist.name,
                  maxLines: 1,
                  textAlign: align,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleSmall,
                ),
              ),
              if (widget.pinned) ...[
                const SizedBox(width: 4),
                BloomIcon(Bi.pin, size: 13, color: context.bloom.text2),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            artist.profile ? context.l.commonProfile : context.l.commonArtist,
            maxLines: 1,
            textAlign: align,
            style: theme.bodySmall,
          ),
        ],
      ),
    );

    return Pressable(
      onTap: () {
        widget.onOpen?.call();
        openArtist(context, artist.id, initial: artist, flight: flight);
      },
      scale: 0.97,
      child: size == null ? content : SizedBox(width: size, child: content),
    );
  }
}

/// A release's type as the platform says it; an album unless it says otherwise.
String releaseKind(AppLocalizations l, String? albumType) => switch (albumType) {
  'single' => l.relSingle,
  'ep' => l.relEp,
  'compilation' => l.relCompilation,
  'podcast' => l.relPodcast,
  _ => l.relAlbum,
};

/// The lines under an album's or a playlist's title: an album's "artist ·
/// type" over its date (the year when that's all the platform says), a
/// playlist's owner. The same on the PC.
List<String> setLines(BuildContext context, Playlist set) {
  final owner = set.ownerName ?? '';
  if (!set.isAlbum) return [if (owner.isNotEmpty) owner];
  final date =
      releaseDayShort(
        set.releaseDate,
        Localizations.localeOf(context).toString(),
      ) ??
      set.year ??
      '';
  return [
    [
      owner,
      releaseKind(context.l, set.albumType),
    ].where((s) => s.isNotEmpty).join(' · '),
    if (date.isNotEmpty) date,
  ];
}

/// An album card's caption is a line taller than a playlist's: its height
/// under the cover, for the rows and grids that size their cells.
double setCaption(Iterable<Playlist> sets) =>
    sets.any((s) => s.isAlbum) ? 66 : 48;

/// A carousel of [SetCard]s at their default width: the cover, the caption
/// and some air under it.
double setRowHeight(Iterable<Playlist> sets) => 146 + setCaption(sets);

/// Карточка плейлиста или альбома: обложка, название и [setLines].
///
/// [size] `null` — на всю ширину ячейки сетки, число — фиксированная ширина
/// карусели.
class SetCard extends StatefulWidget {
  const SetCard({super.key, required this.set, this.size = 132, this.onOpen});

  final Playlist set;
  final double? size;

  /// См. [TrackRow.onOpen].
  final VoidCallback? onOpen;

  @override
  State<SetCard> createState() => _SetCardState();
}

class _SetCardState extends State<SetCard> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final size = widget.size;
    final theme = Theme.of(context).textTheme;
    final flight = _flightFor(set.cover, _tag);

    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Бейдж площадки — как у карточки трека: в одной ленте выдачи рядом
          // стоят альбомы разных площадок, и по обложке этого не понять.
          Stack(
            children: [
              Cover(
                url: set.cover,
                size: box.maxWidth,
                flight: flight,
                overlay: SetEqualizer(setId: set.id),
              ),
              Positioned(
                right: 6,
                bottom: 6,
                child: SourceBadge(set.source, size: kCardBadge),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            set.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.titleSmall,
          ),
          const SizedBox(height: 2),
          for (final line in setLines(context, set))
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall,
            ),
        ],
      ),
    );

    return Pressable(
      onTap: () {
        widget.onOpen?.call();
        openSet(context, set, flight: flight);
      },
      scale: 0.97,
      child: size == null ? content : SizedBox(width: size, child: content),
    );
  }
}

/// Горизонтальная лента карточек — общая для выдачи поиска и секций страницы
/// артиста.
class EntityCarousel extends StatelessWidget {
  const EntityCarousel({
    super.key,
    required this.height,
    required this.itemCount,
    required this.builder,
    this.padding = 8,
  });

  final double height;
  final int itemCount;
  final Widget Function(int index) builder;

  /// Отступ ленты от краёв экрана. По умолчанию 8 — как у списков выдачи, где
  /// строки уже отбиты своим паддингом. На главной он 16: там ленты стоят
  /// вровень с заголовками секций и карточками разделов.
  final double padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => builder(i),
      ),
    );
  }
}

/// A section title. With [onTap] it's a link to the whole of it, an arrow
/// after the words.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.onTap, this.side = 16});

  final String title;
  final VoidCallback? onTap;

  /// Off the screen's edges; 8 where the rows below pad themselves.
  final double side;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (onTap != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 2),
            child: BloomIcon(
              Bi.arrowRight,
              size: 22,
              color: context.bloom.text.withValues(alpha: 0.55),
            ),
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 18, side, 10),
      child: onTap == null
          ? row
          : Pressable(onTap: onTap, scale: 0.98, child: row),
    );
  }
}
