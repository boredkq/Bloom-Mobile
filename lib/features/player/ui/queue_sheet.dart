/// Очередь воспроизведения — шторка поверх плеера.
///
/// Оболочка своя, не `bloom_sheet`: очередь — это длинный список, а не десяток
/// пунктов. Поэтому ни обложки фоном, ни блока вокруг списка — сплошной фон
/// темы, строки ровно те же, что в плейлистах (`TrackRow`), и шторка тянется
/// до самого верха экрана, а не до доли высоты.
///
/// Состав по десктопу (`QueueBlock.tsx`): шапка со счётчиком и очисткой,
/// плоский список с drag-reorder за обложку, смахивание убирает трек. Что
/// именно делает смахивание, задаётся в настройках («Свайпы» → «Очередь»);
/// по умолчанию оба направления удаляют, как в референсе.
///
/// Видов два, как на ПК (`queueView`, «Настройки → Плеер → Очередь»):
/// «Обычный» — плоский список, «Расширенный» — тот же список, разбитый на
/// «Прослушано» / «Сейчас играет» / «Далее». В расширенном каждая секция —
/// СВОЙ `SliverReorderableList` (на ПК — свой sortable-контейнер): перетащить
/// трек из одной секции в другую физически нельзя, а играющий стоит между ними
/// закреплённой строкой и с места не двигается. Заголовки живут отдельными
/// сливерами, поэтому в перестановке не участвуют.
///
/// Номера строк внутри секции — СВОИ, а всё остальное (запуск, меню, свайпы,
/// «Убрать из очереди») работает по номеру в ОЧЕРЕДИ: секция знает своё
/// смещение и переводит одно в другое. Без этого перевода вторая секция била бы
/// по чужим строкам.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/entities/entities.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../features/wave/wave_actions.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/ui/track_swipes.dart';
import '../player_controller.dart';
import '../player_view_store.dart';
import '../../../shared/ui/subpage_header.dart';

/// Высота заголовка секции расширенного вида. Задана числом, а не собрана из
/// отступов: по ней шторка считает, куда проматываться при открытии.
const double kQueueSectionLabel = 34;

/// Куда промотать список при открытии шторки.
///
/// Обычный вид — играющий трек с запасом в две строки сверху. Расширенный —
/// как на ПК: наверху стоит ЗАГОЛОВОК «Сейчас играет», то есть уводим за кромку
/// всю секцию «Прослушано» вместе с её заголовком. Иначе заголовок играющего
/// уезжает наверх, и непонятно, к какой секции относится первая видимая строка.
double queueScrollOffset({required int index, required bool extended}) {
  if (index <= 0) return 0;
  if (!extended) return index > 2 ? (index - 2) * kTrackRowHeight : 0;
  return index * kTrackRowHeight + kQueueSectionLabel;
}

void showQueueSheet(BuildContext context) {
  // Корневой навигатор и стекло затемнения — общие у всех наших шторок
  // (`showBloomModal`): иначе таб-бар и миниплеер остаются поверх затемнения.
  showBloomModal<void>(context: context, builder: (_) => const _QueueSheet());
}

class _QueueSheet extends ConsumerStatefulWidget {
  const _QueueSheet();

  @override
  ConsumerState<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends ConsumerState<_QueueSheet> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Открываемся на играющем треке, а не в начале очереди: на сотне треков
    // иначе непонятно, где ты находишься.
    final index = ref.read(playbackProvider).index;
    _scroll = ScrollController(
      initialScrollOffset: queueScrollOffset(
        index: index,
        extended: ref.read(queueViewProvider).isExtended,
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Ключи строк. Один трек может стоять в очереди дважды (повтор в
  /// плейлисте), а `ReorderableListView` падает на дублях — поэтому к id
  /// дописываем номер вхождения.
  List<Widget> _slivers({
    required List<Track> queue,
    required List<Key> keys,
    required int current,
    required bool extended,
    required PlaybackController ctrl,
  }) {
    // Играющего в очереди нет (пустая очередь, сбитый номер) — делить нечего,
    // показываем плоский список: пустая секция «Сейчас играет» врала бы.
    final split = extended && current >= 0 && current < queue.length;
    if (!split) {
      return [
        _section(
          queue: queue,
          keys: keys,
          current: current,
          ctrl: ctrl,
          offset: 0,
          count: queue.length,
        ),
      ];
    }

    final l = context.l;
    return [
      if (current > 0) ...[
        _label(l.queueSecPlayed),
        _section(
          queue: queue,
          keys: keys,
          current: current,
          ctrl: ctrl,
          offset: 0,
          count: current,
        ),
      ],
      _label(l.queueSecNow),
      // Играющий — статичная строка: на ПК он тоже закреплён и в перестановке
      // не участвует. `dragIndex` не задан, поэтому меню возвращается на долгий
      // тап по всей строке (см. `TrackRowShell`).
      SliverToBoxAdapter(
        child: _swipeRow(
          queue: queue,
          keys: keys,
          global: current,
          drag: null,
          current: true,
        ),
      ),
      if (current < queue.length - 1) ...[
        _label(l.queueSecNext),
        _section(
          queue: queue,
          keys: keys,
          current: current,
          ctrl: ctrl,
          offset: current + 1,
          count: queue.length - current - 1,
        ),
      ],
    ];
  }

  /// Заголовок секции — порт десктопного `QueueSectionLabel`.
  Widget _label(String text) => SliverToBoxAdapter(
    child: SizedBox(
      height: kQueueSectionLabel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SettingsCaption(text),
        ),
      ),
    ),
  );

  /// Одна перетаскиваемая секция. [offset] — с какой строки очереди она
  /// начинается: внутри секции номера свои, наружу уходят номера очереди.
  Widget _section({
    required List<Track> queue,
    required List<Key> keys,
    required int current,
    required PlaybackController ctrl,
    required int offset,
    required int count,
  }) => SliverReorderableList(
    itemCount: count,
    // Перестановка внутри секции не пересекает играющий трек, поэтому его
    // номер после неё сохраняется сам — контроллеру уходит обычный реордер
    // очереди, просто в номерах очереди.
    onReorder: (from, to) => ctrl.reorder(from + offset, to + offset),
    proxyDecorator: (child, _, _) =>
        Material(color: Colors.white.withValues(alpha: 0.06), child: child),
    itemBuilder: (context, i) => _swipeRow(
      queue: queue,
      keys: keys,
      global: offset + i,
      // Тянучке нужен номер В СЕКЦИИ: `SliverReorderableList` считает свои
      // строки от нуля, и с номером очереди вторая секция хваталась бы за
      // чужую строку.
      drag: i,
      current: offset + i == current,
    ),
  );

  /// Строка очереди со свайпами. Ключ у неё общий на оба вида — по нему
  /// `SliverReorderableList` узнаёт строку при перестановке.
  Widget _swipeRow({
    required List<Track> queue,
    required List<Key> keys,
    required int global,
    required int? drag,
    required bool current,
  }) => TrackSwipe(
    key: keys[global],
    zone: SwipeZone.queue,
    track: queue[global],
    queueIndex: global,
    child: _QueueRow(
      track: queue[global],
      index: global,
      dragIndex: drag,
      current: current,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final ctrl = ref.read(playbackProvider.notifier);
    final queue = state.queue;
    final keys = trackRowKeys(queue);

    // Смахнули последний трек — очередь пуста, показывать в шторке нечего.
    // Плеер под нами закроется сам (см. `FullPlayerPage`), но закрыться первой
    // должна шторка: действие произошло в ней.
    ref.listen(playbackProvider, (_, next) {
      if (next.queue.isNotEmpty) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
      }
    });

    return SheetShell(
      scrolls: false,
      header: SheetTitle(
        context.l.playerQueue,
        right: 12,
        bottom: 12,
        line: Row(
          children: [
            Text(
              context.l.tracksCount(queue.length),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (state.shuffle) ...[
              const SizedBox(width: 8),
              BloomIcon(Bi.shuffle, size: 14, color: context.bloom.accent),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // It carries the queue on with a pick. The sheet closes: the list
            // under it is about to change whole.
            CircleIconButton(
              icon: Bi.soundwave,
              iconSize: 20,
              onTap: queue.isEmpty
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      startWaveFromQueue(context, ref, queue);
                    },
            ),
            const SizedBox(width: 8),
            CircleIconButton(
              icon: Bi.trashBinTrash,
              iconSize: 20,
              onTap: queue.length > 1 ? ctrl.clearExceptCurrent : null,
            ),
          ],
        ),
      ),
      child: CustomScrollView(
        controller: _scroll,
        shrinkWrap: true,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            sliver: SliverMainAxisGroup(
              slivers: _slivers(
                queue: queue,
                keys: keys,
                current: state.index,
                extended: ref.watch(queueViewProvider).isExtended,
                ctrl: ctrl,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({
    required this.track,
    required this.index,
    required this.current,
    required this.dragIndex,
  });

  final Track track;

  /// Номер строки В ОЧЕРЕДИ: по нему запускаем и по нему же шторка трека
  /// убирает строку из очереди.
  final int index;

  final bool current;

  /// Номер строки В СВОЕЙ СЕКЦИИ — тянучка обложки. `null` у играющего трека:
  /// он закреплён и не двигается.
  final int? dragIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: TrackRowShell(
        track: track,
        // Не по id: один трек может стоять в очереди дважды, играет — тот, что
        // стоит на текущей позиции.
        active: current,
        onTap: () => ref.read(playbackProvider.notifier).jumpTo(index),
        // Номер строки, а не поиск по id: один трек может стоять в очереди
        // дважды, и «Убрать из очереди» обязано убрать именно эту строку.
        onMenu: () => showTrackActions(context, ref, track, queueIndex: index),
        dragIndex: dragIndex,
      ),
    );
  }
}
