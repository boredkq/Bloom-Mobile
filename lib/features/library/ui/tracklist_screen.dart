/// Список треков раздела библиотеки: встроенные «Все треки» / «Любимые» и
/// пользовательские плейлисты — один экран на всё.
///
/// Раскладка: hero-обложка во всю ширину, название и счётчик поверх неё, ряд
/// «Воспроизвести» + шафл + правка, ниже трек-лист. Карандаш переводит экран в
/// режим правки — он живёт в [ListEditor] и заменяет собой всю страницу.
///
/// У встроенных разделов своей обложки нет, поэтому берётся коллаж 2×2 из
/// первых треков (как `.home-quick-card` на десктопе), а если и их не хватает —
/// плоский тинт раздела с его цветной иконкой.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../core/store/play_stats.dart';
import '../../../core/store/text_files.dart';
import '../../../features/offline/file_download.dart';
import '../../../features/offline/offline_actions.dart';
import '../../../features/offline/offline_store.dart';
import '../../../features/player/play_source.dart';
import '../../../features/player/player_controller.dart';
import '../../../features/settings/data_transfer.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/detail_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/sticky_hero.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/ui/track_swipes.dart';
import '../dups.dart';
import '../local_tracks.dart';
import '../refresh_playlist.dart';
import 'convert_screen.dart';
import 'dups_view.dart';
import 'list_edit.dart';
import 'list_meta.dart';
import 'merge_sheet.dart';
import 'list_hero.dart';
import 'now_playing_jump.dart';

/// Верхний отступ трек-листа под шапкой. По нему пилюля «Сейчас играет»
/// считает, где стоит строка, — число обязано быть тем же, что у `SliverPadding`.
const double _listPadTop = 10;

/// Сортировка трек-листа — все режимы десктопного `TrackSortMode` и вдобавок
/// «Скачанные»: этот не сортирует, а оставляет в списке только то, что уже
/// лежит на устройстве. Повторный тап выворачивает отбор — остаются как раз НЕ
/// скачанные (этого на ПК нет).
///
/// Порядок значений — порядок пунктов в шторке, как в десктопном `SortPage`:
/// сперва сортировки, под чертой «По умолчанию» и «Скачанные».
enum TrackSort {
  name(Bi.sort),
  artist(Bi.user),
  duration(Bi.clockCircle),
  date(Bi.calendar),
  plays(Bi.play),
  album(Bi.album),
  manual(Bi.repeat),
  downloaded(Bi.downloadMinimalistic);

  const TrackSort(this.icon);
  final BloomGlyph icon;

  /// [desc] у «Скачанных» значит вывернутый отбор — «Не скачанные».
  String label(AppLocalizations l, {bool desc = false}) => switch (this) {
    TrackSort.manual => l.tlSortManual,
    TrackSort.name => l.tlSortName,
    TrackSort.artist => l.tlSortArtist,
    TrackSort.album => l.tlSortAlbum,
    TrackSort.duration => l.tlSortDuration,
    TrackSort.date => l.tlSortDate,
    TrackSort.plays => l.tlSortPlays,
    TrackSort.downloaded => desc ? l.tlSortNotDownloaded : l.tlSortDownloaded,
  };

  /// Порядок разворачивается повторным тапом — кроме тех режимов, где своего
  /// порядка нет: «По порядку» отдаёт список как есть, «Скачанные» только
  /// отсеивают лишнее.
  bool get directional =>
      this != TrackSort.manual && this != TrackSort.downloaded;

  /// Что-то меняет повторный тап: у направленных режимов — порядок, у
  /// «Скачанных» — сам отбор (скачанные ↔ не скачанные).
  bool get flips => directional || this == TrackSort.downloaded;

  /// С какого конца режим начинается: у даты и прослушиваний сверху свежее и
  /// частое — как `defaultDir` в десктопном сторе.
  bool get descFirst => this == TrackSort.date || this == TrackSort.plays;
}

class TracklistScreen extends ConsumerStatefulWidget {
  const TracklistScreen({super.key, required this.listId, this.flight});

  /// `all` / `fav` либо id пользовательского плейлиста.
  final String listId;

  /// Обложка плитки библиотеки, с которой сюда пришли: она перелетает в шапку.
  /// `null` — у плитки обложки не было (в шапке коллаж или тинт раздела) или
  /// список открыт не с плитки.
  final CoverFlight? flight;

  @override
  ConsumerState<TracklistScreen> createState() => _TracklistScreenState();
}

class _TracklistScreenState extends ConsumerState<TracklistScreen> {
  TrackSort _sort = TrackSort.manual;

  /// Порядок развёрнут — обратный тому, с которого режим начинается.
  bool _desc = false;

  bool _searchOpen = false;
  String _query = '';

  /// Экран отдан [ListEditor]: список правится, а не листается.
  bool _editing = false;

  /// Режим дублей включён на ЭТОМ списке — снимок последнего кадра.
  ///
  /// Нужен в [dispose], а спросить там уже некого: `ref` после снятия виджета
  /// бросает `Cannot use "ref" after the widget was disposed`, и вместе с ним
  /// падал весь `dispose` — режим так и оставался включённым для следующего
  /// открытия, а журнал засыпало ошибками. Значение берём из `build`, где
  /// провайдер и так под `watch`: измениться незаметно оно не может.
  bool _dupsHere = false;

  /// Сам стор — тоже заранее: он переживает виджет, и гасить режим им можно
  /// уже после снятия.
  late final DupsController _dups = ref.read(dupsProvider.notifier);

  /// Свой контроллер прокрутки: по нему пилюля «Сейчас играет» понимает, видна
  /// ли строка играющего трека, и возвращает список к ней.
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _dups; // взять стор, пока `ref` ещё жив
  }

  @override
  void dispose() {
    // Уходя со списка, гасим режим дублей: он про ЭТОТ плейлист, и остаться
    // включённым для следующего открытия не должен (на десктопе то же делает
    // эффект в `LibTracklist`).
    if (_dupsHere) _dups.exit();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    // Режим дублей включён для этого списка — вместо строк идут группы
    // повторов. Читаем в самом начале, до всех ранних возвратов: снимок нужен
    // ещё и в [dispose], см. [_dupsHere].
    final dups = _dupsHere = ref.watch(dupsProvider) == widget.listId;

    // id плейлистов теперь как на ПК (`plmvio1qa0`), без приставки — ищем
    // всегда, встроенные `all`/`fav` просто не найдутся.
    UserPlaylist? playlist;
    for (final p in lib.playlists) {
      if (p.id == widget.listId) {
        playlist = p;
        break;
      }
    }

    final (String title, List<Track> source) = switch (widget.listId) {
      'all' => (context.l.commonAllTracks, lib.allTracks),
      'fav' => (context.l.commonFavorites, lib.favTracks),
      _ => (
        playlist?.name ?? context.l.commonPlaylist,
        playlist == null ? <Track>[] : lib.tracksOf(playlist),
      ),
    };

    if (_editing) {
      return ListEditor(
        listId: widget.listId,
        title: title,
        playlist: playlist,
        // Правится ВЕСЬ список в его собственном порядке: сортировка и поиск
        // на входе в режим сбрасываются.
        tracks: source,
        onClose: () => setState(() => _editing = false),
      );
    }

    // Офлайн-состав спрашиваем, только когда он на экран влияет: индекс дёргается
    // на каждом проценте пакетной загрузки, и подписываться на него ради списка,
    // который её не показывает, значит перестраивать его без повода.
    final offline = _sort == TrackSort.downloaded
        ? ref.watch(offlineProvider)
        : null;
    // Статистику — тоже только когда она на экран влияет: она пересчитывается
    // на каждое засчитанное прослушивание.
    final stats = _sort == TrackSort.plays
        ? ref.watch(playStatsProvider)
        : null;
    final tracks = _apply(source, lib, offline, stats);
    // Ключи нужны не только перетаскиванию: строку можно смахнуть, а список
    // тут не анимированный — без ключа состояние жеста досталось бы соседу,
    // который встал на освободившееся место.
    final keys = trackRowKeys(tracks);
    final width = MediaQuery.of(context).size.width;

    // Геометрия для пилюли «Сейчас играет»: сколько от верха списка закрыто
    // прилипшей шапкой и где в координатах прокрутки лежит его первая строка.
    // Строки играющего трека в дереве может не быть (список ленивый), поэтому
    // её место считается по модели, как `win.offsetOf` на десктопе.
    final barHeight = _searchOpen ? kHeaderControl * 2 + 10 : kHeaderControl;
    final collapsed = StickyHero.collapsedHeight(context, barHeight);
    final heroExtent = math.max(width * 0.62 + 76, collapsed);

    double? rowTopOf(String id) {
      // Режим дублей подменяет собой весь список — строк трека там нет.
      if (dups) return null;
      final i = tracks.indexWhere((t) => t.id == id);
      return i < 0 ? null : heroExtent + _listPadTop + i * kTrackRowHeight;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomScrollView(
          controller: _scroll,
          slivers: [
            _Hero(
              listId: widget.listId,
              title: title,
              playlist: playlist,
              tracks: source,
              visible: tracks,
              // Летим только на свою обложку: коллаж 2×2 собирается из чужих
              // картинок, и обложке плитки в нём места нет.
              flight: playlist?.cover == null ? null : widget.flight,
              height: width * 0.62 + 76,
              sort: _sort,
              desc: _desc,
              onSort: _pickSort,
              searchOpen: _searchOpen,
              query: _query,
              onToggleSearch: () => setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) _query = '';
              }),
              onQuery: (q) => setState(() => _query = q),
              onEdit: () => setState(() {
                _editing = true;
                _searchOpen = false;
                _query = '';
                _sort = TrackSort.manual;
                _desc = false;
              }),
            ),
            // Ход пакетной загрузки больше не строка под шапкой: он в тосте
            // (`BatchToastBody`) и виден с любого экрана, а не только отсюда.
            //
            // «Найти дубли» подменяет собой ТОЛЬКО список: шапка с обложкой и
            // кнопками остаётся на месте, как в десктопном `DupsInline`. Пул для
            // поиска — весь состав списка, а не видимая часть: искать повторы в
            // отфильтрованном поиском списке значит их не найти.
            if (dups)
              DupsSliver(listId: widget.listId, tracks: source)
            else if (tracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CenterNote(
                    _query.isNotEmpty
                        ? context.l.tlNothingFound
                        // Список не пуст — просто в нём нечего показать под
                        // отбором: об этом и говорим, иначе «Плейлист пуст»
                        // на полном плейлисте выглядит поломкой.
                        : _sort == TrackSort.downloaded
                        ? (_desc
                              ? context.l.tlNothingNotDownloaded
                              : context.l.tlNothingDownloaded)
                        : switch (widget.listId) {
                            'fav' => context.l.tlEmptyFav,
                            'all' => context.l.tlEmptyAll,
                            _ => context.l.tlEmptyPlaylist,
                          },
                    padding: const EdgeInsets.symmetric(vertical: 60),
                  ),
                ),
              )
            // Свой порядок списка — строки можно двигать: зажать обложку и тащить,
            // как в очереди и на десктопе.
            else if (_canReorder)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, _listPadTop, 8, 12),
                sliver: SliverReorderableList(
                  itemCount: tracks.length,
                  onReorder: (from, to) => _reorder(source, from, to),
                  proxyDecorator: (child, _, _) =>
                      trackRowDragged(context, child),
                  itemBuilder: (context, i) => TrackSwipe(
                    key: keys[i],
                    zone: SwipeZone.library,
                    track: tracks[i],
                    listId: widget.listId,
                    child: TrackRow(
                      track: tracks[i],
                      queue: tracks,
                      index: i,
                      source: LibSource(widget.listId),
                      dragIndex: i,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, _listPadTop, 8, 12),
                sliver: SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => TrackSwipe(
                    key: keys[i],
                    zone: SwipeZone.library,
                    track: tracks[i],
                    listId: widget.listId,
                    child: TrackRow(
                      track: tracks[i],
                      queue: tracks,
                      index: i,
                      source: LibSource(widget.listId),
                    ),
                  ),
                ),
              ),
            // Хвост под бары каркаса — общий для всех веток выше: они плавают
            // над списком, и последняя строка иначе не вылезает из-под
            // миниплеера.
            const SliverBottomBarsInset(),
          ],
        ),
        // Пилюля «Сейчас играет» лежит ВНЕ прокрутки и потому висит на одном
        // месте (на ПК она так же стоит абсолютом в `.lib-content`, а не внутри
        // скролл-контейнера). Справа над миниплеером — так на его скриншоте.
        Positioned(
          right: 16,
          bottom: bottomBarsInset(context) + 12,
          child: NowPlayingJump(
            controller: _scroll,
            rowTopOf: rowTopOf,
            topInset: collapsed,
          ),
        ),
      ],
    );
  }

  /// Выбор в шторке сортировки. Повторный тап по уже выбранному режиму
  /// разворачивает порядок — как на десктопе, где та же строка меню показывает
  /// ↑/↓ и переключает их.
  void _pickSort(TrackSort next) {
    setState(() {
      if (next == _sort && next.flips) {
        _desc = !_desc;
      } else {
        _sort = next;
        _desc = next.descFirst;
      }
    });
  }

  /// Тянуть строки можно, только когда на экране собственный порядок списка:
  /// при сортировке и поиске видно не его, и перестановка легла бы не туда.
  bool get _canReorder => _sort == TrackSort.manual && _query.isEmpty;

  /// Ключи строк: один трек может стоять в списке дважды, а `ReorderableList`
  /// на дублях падает — дописываем номер вхождения (как в очереди).
  void _reorder(List<Track> source, int from, int to) {
    // Индекс вставки считается ДО изъятия строки — всё, что ниже, уже сдвинуто.
    if (to > from) to--;
    final next = [...source];
    next.insert(to, next.removeAt(from));
    final ids = [for (final track in next) track.id];
    final lib = ref.read(libraryProvider.notifier);
    switch (widget.listId) {
      case 'all':
        lib.setLibraryTracks(ids);
      case 'fav':
        lib.setFavTracks(ids);
      default:
        lib.setPlaylistTracks(widget.listId, ids);
    }
  }

  /// Поиск, отбор и сортировка применяются к копии: исходный порядок плейлиста
  /// трогать нельзя, «По порядку» должен уметь вернуть его как было.
  ///
  /// [offline] приходит только в режиме «Скачанные», [stats] — только в «По
  /// прослушиваниям»: остальным они не нужны.
  List<Track> _apply(
    List<Track> source,
    LibraryState lib,
    OfflineState? offline,
    PlayStats? stats,
  ) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? [...source]
        : source
              .where(
                (t) =>
                    t.name.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q),
              )
              .toList();

    if (_sort == TrackSort.downloaded) {
      // Порядок остаётся своим — режим только отсеивает то, чего на устройстве
      // нет. Качающиеся сейчас треки не в счёт: файла ещё нет, играть нечего.
      // Свои треки — файлы с телефона, и в офлайн-индексе их нет (качать
      // нечего): без них список «скачанного» врал бы про свою же музыку.
      // Вывернутый отбор ([_desc]) оставляет ровно остальное — то, что без
      // сети не заиграет, включая качающееся сейчас.
      list.removeWhere((t) {
        final onDevice =
            t.source == MusicSource.local || offline?.has(t.id) == true;
        return _desc ? onDevice : !onDevice;
      });
      return list;
    }
    if (!_sort.directional) return list;

    // Время добавления берём из того раздела, который на экране: в «Любимых»
    // это время лайка (на ПК то же деление по `libMode`).
    int addedAt(Track t) => switch (widget.listId) {
      'fav' => lib.favs[t.id] ?? 0,
      _ => lib.inLib[t.id] ?? 0,
    };

    // Прослушивания — свои, из журнала.
    final int dir = _desc ? -1 : 1;
    list.sort((a, b) {
      final c = switch (_sort) {
        TrackSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        TrackSort.artist => a.artist.toLowerCase().compareTo(
          b.artist.toLowerCase(),
        ),
        TrackSort.album => (a.album ?? '').toLowerCase().compareTo(
          (b.album ?? '').toLowerCase(),
        ),
        TrackSort.duration => a.duration.compareTo(b.duration),
        TrackSort.date => addedAt(a).compareTo(addedAt(b)),
        TrackSort.plays => (stats?.playCount(a.id) ?? 0).compareTo(
          stats?.playCount(b.id) ?? 0,
        ),
        TrackSort.manual || TrackSort.downloaded => 0,
      };
      return dir * c;
    });
    return list;
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.listId,
    required this.title,
    required this.playlist,
    required this.tracks,
    required this.visible,
    required this.flight,
    required this.height,
    required this.sort,
    required this.desc,
    required this.onSort,
    required this.searchOpen,
    required this.query,
    required this.onToggleSearch,
    required this.onQuery,
    required this.onEdit,
  });

  final String listId;
  final String title;
  final UserPlaylist? playlist;

  /// Полный состав — по нему считается счётчик и запускается воспроизведение.
  final List<Track> tracks;

  /// То, что реально показано (после поиска и сортировки).
  final List<Track> visible;

  /// Обложка плитки, с которой пришли, — цель перелёта.
  final CoverFlight? flight;

  /// Полная высота шапки — вместе с полосой названия и ряда действий под
  /// обложкой. Считается снаружи: по ней пилюля «Сейчас играет» знает, с какого
  /// места начинается список.
  final double height;
  final TrackSort sort;
  final bool desc;
  final ValueChanged<TrackSort> onSort;
  final bool searchOpen;
  final String query;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQuery;

  /// Уйти в режим правки — карандаш в ряду действий.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return StickyHero(
      height: height,
      flying: flight != null,
      // Обложка на всю шапку, включая ряд действий: её скруглённый нижний
      // край и есть граница со списком.
      background: HeroCover(
        child: CoverHero(
          tag: flight?.tag,
          shape: BorderRadius.vertical(bottom: Radius.circular(t.radius * 1.5)),
          child: ListHeroBackground(
            listId: listId,
            cover: playlist?.cover,
            tracks: tracks,
          ),
        ),
      ),
      // Открытый поиск едет вместе с кнопками: искать по списку, глядя на него,
      // и есть смысл только в прокрученном виде.
      barHeight: searchOpen ? kHeaderControl * 2 + 10 : kHeaderControl,
      bar: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlassIconButton(
                icon: Bi.arrowLeft,
                onTap: () => context.go('/library'),
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: Bi.sort,
                background: sort != TrackSort.manual ? t.accent : null,
                color: sort != TrackSort.manual ? t.accentText : null,
                onTap: () => showSortSheet(context, sort, desc, onSort),
              ),
              const Spacer(),
              // Плюс — только во «Всех треках», как `libUploadBtn` на ПК
              // (`mode === 'all'`): в «Любимых» состав не свой, а в плейлист
              // трек добавляют из шторки самого трека.
              if (listId == 'all') ...[
                const _AddLocalButton(),
                const SizedBox(width: 8),
              ],
              GlassIconButton(
                icon: searchOpen ? Bi.close : Bi.magnifier,
                onTap: onToggleSearch,
              ),
              if (playlist != null) ...[
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: Bi.kebab,
                  onTap: () =>
                      showPlaylistMenu(context, ref, playlist!, tracks),
                ),
              ],
            ],
          ),
          if (searchOpen) ...[
            const SizedBox(height: 10),
            _InlineSearch(query: query, onQuery: onQuery),
          ],
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.headlineSmall?.copyWith(fontSize: 30),
          ),
          const SizedBox(height: 4),
          // Счётчик, офлайн-тег и общее время.
          ListMeta(
            tracks: tracks,
            style: theme.bodyMedium,
            showOffline: playlist != null,
          ),
          const SizedBox(height: 14),
          _Actions(
            listId: listId,
            tracks: visible.isEmpty ? tracks : visible,
            onEdit: onEdit,
          ),
        ],
      ),
    );
  }
}

/// Плюс в шапке «Всех треков»: системный выбор аудиофайлов и добавление их в
/// библиотеку своими треками (порт `libUploadBtn` → `importTracks`).
///
/// Пока идёт диалог и разбор выбранного, кнопка показывает кольцо: копирование
/// большого файла и чтение тегов занимают заметное время, и без этого второй
/// тап открыл бы второй диалог (нативная сторона такой запрос отбивает).
class _AddLocalButton extends ConsumerStatefulWidget {
  const _AddLocalButton();

  @override
  ConsumerState<_AddLocalButton> createState() => _AddLocalButtonState();
}

class _AddLocalButtonState extends ConsumerState<_AddLocalButton> {
  bool _busy = false;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Мессенджер и переводы берём до похода в диалог: он системный, экран за
    // это время может уехать, и `context` после await уже не годится.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l;
    final result = await importLocalTracks(ref, l10n);
    if (mounted) setState(() => _busy = false);
    switch (result.status) {
      case LocalImportStatus.cancelled:
        break; // диалог просто закрыли — молчим, как на ПК
      case LocalImportStatus.nothing:
        messenger.toast(l10n.ltNothingAdded);
      case LocalImportStatus.added:
        messenger.toast(l10n.ltAdded(result.added), kind: ToastKind.success);
      case LocalImportStatus.failed:
        messenger.toast(l10n.ltImportFailed, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) => GlassIconButton(
    icon: Bi.add,
    onTap: _add,
    child: _busy
        ? const Center(child: BloomSpinner(size: 18, color: Colors.white))
        : null,
  );
}

/// Выбор сортировки списка — такая же нижняя шторка, как по удержанию трека, а
/// не всплывающее меню: на телефоне до низа экрана рука достаёт, до угла шапки
/// нет.
///
/// Повторный тап по выбранному режиму разворачивает порядок — стрелка справа
/// показывает, каким концом список идёт сейчас.
Future<void> showSortSheet(
  BuildContext context,
  TrackSort sort,
  bool desc,
  ValueChanged<TrackSort> onSort,
) {
  final t = context.bloom;
  SheetAction item(TrackSort s) => SheetAction(
    icon: s.icon,
    label: s.label(context.l, desc: s == sort && desc),
    onTap: () => onSort(s),
    trailing: s != sort
        ? null
        : BloomIcon(
            switch (s) {
              _ when s.directional =>
                desc ? Bi.altArrowDownBold : Bi.altArrowUpBold,
              // Вывернутый отбор «Скачанных» — «Не скачанные»: галочка тут
              // читалась бы как «скачано», поэтому крестик.
              TrackSort.downloaded when desc => Bi.close,
              _ => Bi.check,
            },
            size: 18,
            color: t.accent,
          ),
  );
  // Черта отделяет сортировки от «По умолчанию» и отбора — как `cx-sep` на ПК.
  return showBloomSheet(
    context: context,
    groups: [
      [
        for (final s in TrackSort.values)
          if (s.directional) item(s),
      ],
      [
        for (final s in TrackSort.values)
          if (!s.directional) item(s),
      ],
    ],
  );
}

class _InlineSearch extends StatelessWidget {
  const _InlineSearch({required this.query, required this.onQuery});

  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) => HeaderSearchField(
    hint: context.l.tlSearchHint,
    overPicture: true,
    onChanged: onQuery,
  );
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.listId,
    required this.tracks,
    required this.onEdit,
  });

  /// `all` / `fav` / id плейлиста — он же источник очереди.
  final String listId;

  final List<Track> tracks;

  /// Карандаш есть у каждого списка библиотеки, кроме «Истории»: из неё ничего
  /// не убирается, а порядок задаёт время (как на ПК). Во встроенных разделах
  /// правятся состав и порядок, просто имя с обложкой там не свои.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = tracks.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: HeroPlayButton(
            sourceId: listId,
            onPlay: enabled
                ? () => ref
                      .read(playbackProvider.notifier)
                      .playQueue(tracks, 0, source: LibSource(listId))
                : null,
          ),
        ),
        const SizedBox(width: 10),
        GlassIconButton(
          icon: Bi.shuffle,
          size: 46,
          onTap: enabled
              ? () => ref
                    .read(playbackProvider.notifier)
                    .playQueueShuffled(tracks, source: LibSource(listId))
              : null,
        ),
        const SizedBox(width: 10),
        GlassIconButton(icon: Bi.pen, size: 46, onTap: onEdit),
      ],
    );
  }
}

/// Шторка «трёх точек» плейлиста — общая для его страницы и плитки в
/// библиотеке.
Future<void> showPlaylistMenu(
  BuildContext context,
  WidgetRef ref,
  UserPlaylist playlist,
  List<Track> tracks,
) async {
  void play({bool shuffle = false}) {
    if (tracks.isEmpty) return;
    final ctrl = ref.read(playbackProvider.notifier);
    if (shuffle) {
      ctrl.playQueueShuffled(tracks, source: LibSource(playlist.id));
    } else {
      ctrl.playQueue(tracks, 0, source: LibSource(playlist.id));
    }
  }

  // У плейлиста без своей обложки её роль играет первый трек — так же, как в
  // hero экрана.
  final cover = playlist.cover ?? (tracks.isEmpty ? null : tracks.first.cover);

  // Офлайн-состав считаем до открытия шторки: в её обработчиках `watch` уже
  // недоступен, а `read` внутри пункта дал бы состояние на момент нажатия.
  final offlineStatus = listOfflineState(
    ref.read(offlineProvider),
    ref.read(offlineProvider.notifier),
    tracks,
  );
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

  await showBloomSheet(
    context: context,
    header: SheetHero(
      cover: cover,
      title: playlist.name,
      // The same line as on the library's card.
      subtitleWidget: ListMeta(
        tracks: tracks,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
      ),
      meta: sheetDateMeta(context, l10n.commonCreatedOn, playlist.createdAt),
    ),
    bar: [
      SheetAction(
        icon: Bi.playBold,
        label: context.l.commonPlay,
        onTap: tracks.isEmpty ? null : play,
      ),
      SheetAction(
        icon: Bi.shuffle,
        label: context.l.commonShuffle,
        onTap: tracks.isEmpty ? null : () => play(shuffle: true),
      ),
      ...queueSheetActions(
        context,
        ref,
        tracks,
        source: LibSource(playlist.id),
      ),
    ],
    groups: [
      [
        // Пакет ЭТОГО плейлиста качается прямо сейчас — единственное, что
        // здесь уместно, это его остановить. Чужой пакет пунктов не меняет:
        // остановить его отсюда было бы неожиданно, а `downloadAll` сам
        // ответит, что уже качает другой список.
        if (ref.read(offlineProvider).batch?.sourceId == playlist.id)
          SheetAction(
            icon: Bi.close,
            label: context.l.tlStopSaving,
            onTap: () => ref.read(offlineProvider.notifier).cancelBatch(),
          )
        // Скачать целиком есть смысл, пока в списке остались несохранённые
        // треки; когда всё на устройстве — пункт становится «убрать».
        else if (offlineStatus.total > 0) ...[
          SheetAction(
            icon: offlineStatus.all
                ? Bi.trashBinTrash
                : Bi.downloadMinimalistic,
            label: offlineStatus.all
                ? context.l.tlRemoveOffline
                : context.l.tlListenOffline(
                    offlineStatus.total - offlineStatus.cached,
                  ),
            subtitle: offlineStatus.all ? null : context.l.tlOfflineHint,
            onTap: () => offlineStatus.all
                ? removeListOffline(messenger, l10n, ref, tracks)
                : downloadListOffline(
                    messenger,
                    l10n,
                    ref,
                    playlist.id,
                    tracks,
                  ),
          ),
          if (canSaveFiles)
            SheetAction(
              icon: Bi.downloadMinimalistic,
              label: context.l.tlDownloadFiles(offlineStatus.total),
              subtitle: context.l.tlFilesHint,
              onTap: () =>
                  saveListFiles(messenger, l10n, ref, playlist.id, tracks),
            ),
        ],
        // Тот же «Обновить треки», что кнопкой в шапке: в шторку он попадает
        // и с плитки библиотеки, где шапки нет.
        if (playlist.sources.isNotEmpty)
          SheetAction(
            icon: Bi.refresh,
            label: context.l.tlRefreshTracks,
            subtitle: context.l.tlRefreshHint,
            onTap: () => refreshOnePlaylist(messenger, l10n, ref, playlist),
          ),
        SheetAction(
          icon: Bi.pin,
          label: playlist.pinned ? context.l.commonUnpin : context.l.commonPin,
          subtitle: playlist.pinned ? null : context.l.commonPinHint,
          onTap: () => ref
              .read(libraryProvider.notifier)
              .setPinned(libKeyOfPlaylist(playlist.id), !playlist.pinned),
        ),
        SheetAction(
          icon: Bi.import,
          label: context.l.tlMergeWith,
          subtitle: context.l.tlMergeHint,
          onTap: () => showMergeSheet(context, ref, playlist),
        ),
        // Перенос — копия плейлиста с треками другой площадки. Пустой плейлист
        // переносить нечего.
        if (tracks.isNotEmpty)
          SheetAction(
            icon: Bi.arrowRight,
            label: context.l.tlConvert,
            subtitle: context.l.tlConvertHint,
            onTap: () => showConvertSheet(context, ref, playlist, tracks),
          ),
        // Поиск повторов включается прямо в списке — поэтому сперва открываем
        // сам плейлист, иначе режим включился бы там, где его не видно.
        if (tracks.isNotEmpty)
          SheetAction(
            icon: Bi.copy,
            label: context.l.tlFindDups,
            subtitle: context.l.tlFindDupsHint,
            onTap: () {
              context.go('/library/list/${playlist.id}');
              ref.read(dupsProvider.notifier).enter(playlist.id);
            },
          ),
        // Файл переноса на один плейлист — тем же форматом, что «Настройки →
        // Система → Экспорт»: обратно его читает тот же импорт.
        SheetAction(
          icon: Bi.export,
          label: context.l.tlExportPlaylist,
          subtitle: context.l.tlExportHint,
          onTap: () => _exportPlaylist(messenger, l10n, ref, playlist),
        ),
        // Имя и обложка правятся только в режиме правки: там они видны сразу
        // на шапке, и отменить их можно тем же ✕, что и остальные изменения.
      ],
      [
        SheetAction(
          icon: Bi.trashBinTrash,
          label: context.l.tlDeletePlaylist,
          danger: true,
          onTap: () {
            // Удаляем сразу и даём «Отменить» в тосте — как `PlMenu` на ПК:
            // плейлист это всего лишь список id, вернуть его дёшево, а сами
            // треки в библиотеке не трогаются.
            final lib = ref.read(libraryProvider.notifier);
            lib.deletePlaylist(playlist.id);
            context.go('/library');
            messenger.toast(
              l10n.tlPlaylistDeleted(playlist.name),
              action: ToastAction(
                fn: () => lib.restorePlaylist(playlist),
                // Своя обложка живёт файлом в каталоге приложения; удаляем её
                // только когда отменять уже нечего, иначе возвращённый
                // плейлист остался бы без картинки.
                onExpire: () => deleteCover(playlist.cover),
              ),
            );
          },
        ),
        // «И треки» — отдельным пунктом, а не переспросом у первого: разница
        // между «убрать список» и «стереть музыку» слишком велика, чтобы
        // прятать её за одинаковыми словами.
        if (tracks.isNotEmpty)
          SheetAction(
            icon: Bi.trashBinTrash,
            label: context.l.tlDeletePlaylistWithTracks,
            danger: true,
            onTap: () {
              context.go('/library');
              _deletePlaylistWithTracks(messenger, l10n, ref, playlist, tracks);
            },
          ),
      ],
    ],
  );
}

/// Выгрузить один плейлист файлом `.bloomplaylist` (десктопный
/// `exportPlaylistFile`). Отмена системного диалога — тихая, как и везде.
Future<void> _exportPlaylist(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  WidgetRef ref,
  UserPlaylist playlist,
) async {
  final ok = await saveTextFile(
    playlistFileName(playlist.name),
    await buildExportBundle(playlist, ref.read(libraryProvider)),
  );
  if (ok) messenger.toast(l10n.sysExported, kind: ToastKind.success);
}

/// Удалить плейлист ВМЕСТЕ с его треками — насквозь, как `removePlWithTracks` на
/// ПК: треки уходят из библиотеки, лайков и остальных плейлистов. В «Истории»
/// их записи остаются — она переживает удаление треков.
///
/// Переспроса нет, но есть «Отменить»: возвращается снимок всей библиотеки —
/// по частям такое удаление не собрать (см. [LibraryController.snapshot]).
/// Файлы (офлайн-копии, свои треки, обложка плейлиста) стираем только когда
/// отменять уже поздно.
void _deletePlaylistWithTracks(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  WidgetRef ref,
  UserPlaylist playlist,
  List<Track> tracks,
) {
  final lib = ref.read(libraryProvider.notifier);
  final offline = ref.read(offlineProvider.notifier);
  final before = lib.snapshot();
  final own = localTracksOf(ref.read(libraryProvider), [
    for (final track in tracks) track.id,
  ]);

  for (final track in tracks) {
    lib.deleteTrack(track.id);
  }
  lib.deletePlaylist(playlist.id);

  messenger.toast(
    l10n.tlPlaylistAndTracksDeleted(playlist.name),
    action: ToastAction(
      fn: () => lib.restoreSnapshot(before),
      onExpire: () {
        for (final track in tracks) {
          unawaited(offline.remove(track.id));
        }
        unawaited(forgetLocalTracks(own));
        unawaited(deleteCover(playlist.cover));
      },
    ),
  );
}
