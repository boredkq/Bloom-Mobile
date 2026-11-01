/// Режим правки списка библиотеки: чекбоксы у строк, перетаскивание, нижняя
/// панель действий над выделением, правка имени и обложки плейлиста.
///
/// Всё, что меняет САМ список — состав, порядок, имя, обложку, источники
/// обновления, — копится в черновике и записывается разом по ✓; ✕ выбрасывает
/// черновик целиком. А вот «в плейлист» и «в любимые» пишут в ДРУГИЕ списки, и
/// откатывать их этим ✕ было бы нечем — они применяются сразу.
///
/// Что значит «убрать» — зависит от списка: из плейлиста трек просто уходит, из
/// «Любимых» снимается лайк, из «Истории» строка прячется (прослушивания в
/// журнале остаются), а из «Всех треков»
/// он удаляется НАСКВОЗЬ (как пункт «Удалить трек»), поэтому там перед записью
/// ещё и переспрашиваем.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../features/offline/offline_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/sticky_hero.dart';
import '../../../shared/ui/track_actions.dart';
import '../local_tracks.dart';
import 'list_hero.dart';
import 'pl_sources_editor.dart';

class ListEditor extends ConsumerStatefulWidget {
  const ListEditor({
    super.key,
    required this.listId,
    required this.title,
    required this.playlist,
    required this.tracks,
    required this.onClose,
  });

  /// `all` / `fav` либо id пользовательского плейлиста.
  final String listId;

  final String title;

  /// `null` — встроенный раздел: имя и обложка у него не правятся.
  final UserPlaylist? playlist;

  /// Исходный состав в его собственном порядке — БЕЗ поиска и сортировки:
  /// править половину списка, да ещё и не в том порядке, нельзя.
  final List<Track> tracks;

  /// Выйти из режима правки — и по ✓, и по ✕.
  final VoidCallback onClose;

  @override
  ConsumerState<ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends ConsumerState<ListEditor> {
  late final List<String> _idsWas = [for (final t in widget.tracks) t.id];

  late final List<Track> _tracks = [...widget.tracks];
  late String _name = widget.title;
  late String? _cover = widget.playlist?.cover;
  late List<PlSourceRef> _sources = widget.playlist?.sources ?? const [];

  final Set<String> _selected = {};

  /// Идёт правка названия — нижняя панель на это время становится полем ввода.
  bool _renaming = false;

  /// ✕ по черновику спрашивает вторым нажатием — как очистка статистики в
  /// профиле: модалок в приложении нет.
  bool _armedCancel = false;

  /// ✓ спрашивает так же, но только во «Всех треках» и только если из списка
  /// что-то убрали: там это удаление насквозь.
  bool _armedPurge = false;

  /// Трек, который тянут прямо сейчас. `null` — не тянут.
  String? _dragId;

  UserPlaylist? get _playlist => widget.playlist;

  List<String> get _ids => [for (final t in _tracks) t.id];

  List<Track> get _selectedTracks => [
    for (final t in _tracks)
      if (_selected.contains(t.id)) t,
  ];

  bool get _allSelected =>
      _tracks.isNotEmpty && _selected.length == _tracks.length;

  /// Сколько строк уедет текущим перетаскиванием: тянут выделенную — весь
  /// блок, любую другую — её одну.
  int get _dragGroup {
    final id = _dragId;
    return id != null && _selected.contains(id) ? _selected.length : 1;
  }

  /// Строка едет вместе с блоком, но прокси у списка ровно один, и под пальцем
  /// её нет.
  bool _movingWithDrag(String id) =>
      _dragGroup > 1 && id != _dragId && _selected.contains(id);

  /// Лайк стоит у ВСЕХ выделенных — тогда сердечко в панели залито и следующее
  /// нажатие лайк снимет. Ради этого и слушаем библиотеку: лайк идёт мимо
  /// черновика, сразу в «Любимые».
  bool get _selectedAllFav {
    final lib = ref.watch(libraryProvider);
    return _selected.isNotEmpty &&
        _selectedTracks.every((t) => lib.isFav(t.id));
  }

  bool get _dirty =>
      _name != widget.title ||
      _cover != _playlist?.cover ||
      !listEquals(_ids, _idsWas) ||
      _sourcesChanged;

  /// Источники сравниваем по id коллекций: название площадка могла отдать
  /// другое, а привязка от этого не изменилась.
  bool get _sourcesChanged => !listEquals(
    [for (final s in _sources) s.id],
    [for (final s in _playlist?.sources ?? const <PlSourceRef>[]) s.id],
  );

  // ── Правка ────────────────────────────────────────────────────────────────

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  void _toggleAll() => setState(() {
    final all = _allSelected;
    _selected.clear();
    if (!all) _selected.addAll(_ids);
  });

  /// Тащат выделенную строку — едет всё выделение разом, одним блоком: иначе
  /// собранные по всему списку треки пришлось бы носить по одному.
  ///
  /// Считаем не по индексам, а по «якорю» — первой строке ниже точки сброса,
  /// которая сама никуда не едет: у блока изъятие сдвигает индексы вокруг, и
  /// поправка `to--` тут уже не спасает.
  void _reorder(int from, int to) => setState(() {
    final dragged = _tracks[from];
    final group = _selected.contains(dragged.id) && _selected.length > 1
        ? {..._selected}
        : {dragged.id};
    String? anchor;
    for (var i = to; i < _tracks.length; i++) {
      if (!group.contains(_tracks[i].id)) {
        anchor = _tracks[i].id;
        break;
      }
    }
    final moving = [
      for (final t in _tracks)
        if (group.contains(t.id)) t,
    ];
    _tracks.removeWhere((t) => group.contains(t.id));
    // Якоря нет — сбросили ниже всех оставшихся строк, блок уходит в конец.
    _tracks.insertAll(
      anchor == null
          ? _tracks.length
          : _tracks.indexWhere((t) => t.id == anchor),
      moving,
    );
  });

  void _removeSelected() => setState(() {
    _tracks.removeWhere((t) => _selected.contains(t.id));
    _selected.clear();
  });

  /// Лайк выделенному — сразу, не в черновик: «Любимые» это другой список.
  ///
  /// Переключатель: пока хоть один выделенный трек без лайка — дожимаем
  /// остальных, а когда лайк уже у всех, то же нажатие его снимает. Выделение
  /// при этом НЕ сбрасывается: снимать было бы нечем.
  void _favSelected() {
    final lib = ref.read(libraryProvider.notifier);
    final was = ref.read(libraryProvider);
    final batch = _selectedTracks;
    if (batch.isEmpty) return;
    final off = batch.every((t) => was.isFav(t.id));
    var n = 0;
    for (final track in batch) {
      if (was.isFav(track.id) != off) continue;
      lib.toggleFav(track);
      n++;
    }
    final tracks = context.l.tracksCount(n);
    showToast(
      context,
      off
          ? context.l.leRemovedFromFavorites(tracks)
          : context.l.leAddedToFavorites(tracks),
      kind: off ? ToastKind.warn : ToastKind.success,
    );
  }

  /// Источники — шторкой из шапки: на самой странице секция стояла между
  /// обложкой и треками и читалась как часть первой строки списка.
  void _openSources() {
    unawaited(
      showPlSourcesSheet(
        context,
        sources: _sources,
        onChanged: (next) => setState(() => _sources = next),
      ),
    );
  }

  Future<void> _addSelectedToPlaylist() async {
    final batch = _selectedTracks;
    await showAddTracksToPlaylistSheet(context, ref, batch, newName: _name);
    if (!mounted) return;
    setState(_selected.clear);
  }

  /// Новая обложка сохраняется файлом сразу, поэтому предыдущий ВЫБОР (не
  /// исходную обложку плейлиста) чистим тут же: он уже никому не нужен.
  Future<void> _pickCover() async {
    final picked = await pickCover();
    if (picked == null || !mounted) return;
    final stale = _cover != _playlist?.cover ? _cover : null;
    setState(() => _cover = picked);
    unawaited(deleteCover(stale));
  }

  /// Снять обложку: плейлист вернётся к мозаике из обложек треков. Своя
  /// картинка ПЛЕЙЛИСТА при этом ещё жива — её файл удалит только ✓ (иначе
  /// ✕ возвращал бы обложку, которой уже нет на диске); а вот только что
  /// выбранный, но не записанный файл чистим тут же, как и в [_pickCover].
  void _removeCover() {
    final stale = _cover != _playlist?.cover ? _cover : null;
    setState(() => _cover = null);
    unawaited(deleteCover(stale));
  }

  // ── Выход ─────────────────────────────────────────────────────────────────

  void _commit() {
    final lib = ref.read(libraryProvider.notifier);
    final left = _ids.toSet();
    final gone = [
      for (final id in _idsWas)
        if (!left.contains(id)) id,
    ];

    switch (widget.listId) {
      case 'all':
        // Тут удаление НАСКВОЗЬ (десктопный `deleteUploadedTrack` на это место
        // ставит `confirm()`), поэтому ✓ спрашивает вторым нажатием.
        if (gone.isNotEmpty && !_armedPurge) {
          setState(() => _armedPurge = true);
          showToast(
            context,
            context.l.leDeleteArm(context.l.tracksCount(gone.length)),
            kind: ToastKind.warn,
          );
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _armedPurge = false);
          });
          return;
        }
        // Офлайн-копии удалённых треков — мусор, на который никто не сошлётся.
        final offline = ref.read(offlineProvider.notifier);
        for (final id in gone) {
          unawaited(offline.remove(id));
        }
        // То же со своими файлами — и обязательно ДО правки списка: после неё
        // треков в хранилище уже нет, и узнать, за какими из них стояла копия,
        // будет нечем.
        unawaited(
          forgetLocalTracks(localTracksOf(ref.read(libraryProvider), gone)),
        );
        lib.setLibraryTracks(_ids);
      case 'fav':
        lib.setFavTracks(_ids);
      default:
        final pl = _playlist;
        if (pl != null) {
          lib.setPlaylistTracks(pl.id, _ids);
          if (_name.trim().isNotEmpty) lib.renamePlaylist(pl.id, _name);
          if (_sourcesChanged) lib.setPlaylistSources(pl.id, _sources);
          if (_cover != pl.cover) {
            lib.setPlaylistCover(pl.id, _cover);
            // Старая своя картинка живёт файлом в каталоге приложения.
            unawaited(deleteCover(pl.cover));
          }
        }
    }
    widget.onClose();
  }

  void _cancel() {
    // Пустой черновик выбрасывать нечего — такой ✕ выходит сразу.
    if (_dirty && !_armedCancel) {
      setState(() => _armedCancel = true);
      showToast(context, context.l.leDiscardArm, kind: ToastKind.warn);
      // Само остывает, как взведённый крестик у своей темы: иначе он так и
      // ждёт случайного второго тапа.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armedCancel = false);
      });
      return;
    }
    // Выбранная, но не записанная обложка — файл, на который теперь никто не
    // ссылается.
    if (_cover != _playlist?.cover) unawaited(deleteCover(_cover));
    widget.onClose();
  }

  // ── Раскладка ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final width = MediaQuery.sizeOf(context).width;
    // Панель правки плавает над списком, а под ней — миниплеер и таб-бар
    // каркаса: их высоту она обходит сверху, а список — снизу.
    final inset = bottomBarsInset(context);

    return PopScope(
      // Системное «назад» в режиме правки — это ✕, а не выход со страницы.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _EditHero(
                listId: widget.listId,
                name: _name,
                cover: _cover,
                tracks: _tracks,
                // Своя обложка и своё имя есть только у плейлиста.
                editable: _playlist != null,
                height: width * 0.62,
                cancelArmed: _armedCancel,
                doneArmed: _armedPurge,
                onCancel: _cancel,
                onDone: _commit,
                onCover: _pickCover,
                // Убирать нечего, пока обложки нет: у списка без своей
                // картинки в шапке и так мозаика из треков.
                onCoverRemove: (_cover?.isEmpty ?? true) ? null : _removeCover,
                onRename: () => setState(() => _renaming = true),
                // Источники есть только у плейлиста: встроенным разделам тянуть
                // треки неоткуда.
                sources: _playlist == null ? null : _sources.length,
                onSources: _openSources,
              ),
              SliverPadding(
                // Снизу — место под плавающую панель и бары каркаса: последняя
                // строка не должна оставаться под ними.
                padding: EdgeInsets.fromLTRB(8, 10, 8, 92 + inset),
                sliver: SliverReorderableList(
                  itemCount: _tracks.length,
                  onReorder: _reorder,
                  // Кто именно едет — знаем только мы: список тащит одну
                  // строку и про выделение ничего не слышал.
                  onReorderStart: (i) =>
                      setState(() => _dragId = _tracks[i].id),
                  onReorderEnd: (_) => setState(() => _dragId = null),
                  proxyDecorator: (child, _, _) {
                    final card = Material(
                      color: t.pill,
                      elevation: 6,
                      borderRadius: BorderRadius.circular(t.radius * 0.85),
                      child: child,
                    );
                    final n = _dragGroup;
                    return n < 2 ? card : _DragDeck(count: n, child: card);
                  },
                  itemBuilder: (context, i) {
                    final track = _tracks[i];
                    return _EditRow(
                      key: ValueKey(track.id),
                      index: i,
                      track: track,
                      selected: _selected.contains(track.id),
                      // Уедет с блоком, но под пальцем её нет — гасим, чтобы
                      // было видно, что строка уже «в руке».
                      ghost: _movingWithDrag(track.id),
                      onTap: () => _toggle(track.id),
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + inset,
            child: _renaming
                ? _RenameBar(
                    initial: _name,
                    onCancel: () => setState(() => _renaming = false),
                    onDone: (value) => setState(() {
                      final name = value.trim();
                      if (name.isNotEmpty) _name = name;
                      _renaming = false;
                    }),
                  )
                : _EditBar(
                    count: _selected.length,
                    total: _tracks.length,
                    allSelected: _allSelected,
                    // В «Любимых» лайк уже стоит у каждой строки — там его
                    // место занимает корзина, она же «снять лайк».
                    canFav: widget.listId != 'fav',
                    favOn: _selectedAllFav,
                    onToggleAll: _tracks.isEmpty ? null : _toggleAll,
                    onAdd: _addSelectedToPlaylist,
                    onFav: _favSelected,
                    onRemove: _removeSelected,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Шапка режима правки: та же обложка, но вместо «назад/сортировка/поиск» —
/// ✕ и ✓, по центру кнопка выбора картинки, у названия карандаш. Ряда
/// «Воспроизвести» здесь нет, но высота шапки та же, что и на обычном экране:
/// вход в правку не должен её дёргать. Название с подписью просто опускаются
/// на освободившееся место — к нижнему краю обложки.
///
/// Как и обычная шапка списка — слайвер: ряд ✕/✓ остаётся у верхнего края.
class _EditHero extends StatelessWidget {
  const _EditHero({
    required this.listId,
    required this.name,
    required this.cover,
    required this.tracks,
    required this.editable,
    required this.height,
    required this.cancelArmed,
    required this.doneArmed,
    required this.onCancel,
    required this.onDone,
    required this.onCover,
    required this.onCoverRemove,
    required this.onRename,
    required this.sources,
    required this.onSources,
  });

  final String listId;
  final String name;
  final String? cover;
  final List<Track> tracks;

  /// Можно ли править имя и обложку (только у плейлиста).
  final bool editable;

  final double height;

  /// ✕ взведён — следующий тап выбросит черновик.
  final bool cancelArmed;

  /// ✓ взведён — следующий тап удалит убранные треки насквозь.
  final bool doneArmed;

  final VoidCallback onCancel;
  final VoidCallback onDone;
  final VoidCallback onCover;

  /// Снять обложку. `null` — снимать нечего: своей картинки у списка нет.
  final VoidCallback? onCoverRemove;

  final VoidCallback onRename;

  /// Сколько источников привязано. `null` — это встроенный раздел, и кнопки
  /// источников у него нет вовсе.
  final int? sources;

  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return StickyHero(
      // Те же `+ 76`, что и у обычной шапки списка (ряд «Воспроизвести»): её
      // высота считается от одной и той же [height].
      height: height + 76,
      background: Stack(
        fit: StackFit.expand,
        children: [
          HeroCover(
            child: ListHeroBackground(
              listId: listId,
              cover: cover,
              tracks: tracks,
            ),
          ),
          if (editable)
            Center(
              // Корзина рядом, а не крестиком на самой кнопке: цель размером
              // с ноготь на обложке промахивается чаще, чем попадает.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassIconButton(
                    icon: Bi.gallery,
                    size: 66,
                    iconSize: 28,
                    onTap: onCover,
                  ),
                  if (onCoverRemove case final remove?) ...[
                    const SizedBox(width: 14),
                    GlassIconButton(
                      icon: Bi.trashBinTrash,
                      size: 52,
                      iconSize: 23,
                      onTap: remove,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
      // ✕ и ✓ остаются наверху: закончить правку длинного списка иначе можно
      // только пролистав его обратно.
      barHeight: kHeaderControl,
      // Взведённая кнопка — красная, как корзина в панели правки: без модалки
      // это единственное, что показывает, чем кончится второй тап.
      bar: Row(
        children: [
          _BarButton(icon: Bi.close, armed: cancelArmed, onTap: onCancel),
          const Spacer(),
          _BarButton(icon: Bi.check, armed: doneArmed, onTap: onDone),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.headlineSmall?.copyWith(fontSize: 30),
                ),
              ),
              if (editable) ...[
                const SizedBox(width: 8),
                // Карандаш прямо у названия, без подложки: это часть
                // заголовка, а не ещё одна кнопка шапки.
                Pressable(
                  onTap: onRename,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: BloomIcon(Bi.pen, size: 21, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(context.l.tracksCount(tracks.length), style: theme.bodyMedium),
          if (sources case final count?) ...[
            const SizedBox(height: 10),
            _SourcesButton(count: count, onTap: onSources),
          ],
        ],
      ),
    );
  }
}

/// Кнопка источников в шапке правки: стеклянная пилюля со счётчиком привязок.
/// Стекло, а не плашка темы, — она стоит на обложке, как и кнопки шапки.
class _SourcesButton extends StatelessWidget {
  const _SourcesButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return Pressable(
      onTap: onTap,
      child: GlassSurface(
        shape: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BloomIcon(Bi.link, size: 18, color: Colors.white),
              const SizedBox(width: 9),
              Text(
                context.l.psTitle,
                style: theme.titleMedium?.copyWith(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              // Ноль не показываем: пустой счётчик у кнопки, которая как раз и
              // заводит первую привязку, только сбивает.
              if (count > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: theme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const BloomIcon(
                Bi.altArrowRight,
                size: 20,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка шапки правки. Взведённая — красная: следующий тап уже что-то теряет.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.armed,
    required this.onTap,
  });

  final BloomGlyph icon;
  final bool armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GlassIconButton(
      icon: icon,
      color: armed ? t.danger : null,
      background: armed ? t.danger.withValues(alpha: 0.16) : null,
      onTap: onTap,
    );
  }
}

/// Строка списка в режиме правки: чекбокс, обложка, название и длительность.
/// Тап по строке выделяет её, а не заводит трек, — играть из режима правки
/// нечего. Тянучка — обложка, как в обычном списке и в очереди: отдельной ручке
/// в строке уже нечего делать.
class _EditRow extends StatelessWidget {
  const _EditRow({
    super.key,
    required this.index,
    required this.track,
    required this.selected,
    required this.ghost,
    required this.onTap,
  });

  /// Номер строки для перетаскивания. `null` — порядок этого списка не свой
  /// («История» стоит по времени прослушивания), и тащить строку некуда.
  final int? index;
  final Track track;
  final bool selected;

  /// Строка «в руке» вместе с блоком выделенных: пока её тащат, она гаснет на
  /// своём старом месте.
  final bool ghost;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final drag = index;
    final Widget cover = Cover(url: track.cover, size: 52);

    return AnimatedOpacity(
      opacity: ghost ? 0.3 : 1,
      duration: const Duration(milliseconds: 120),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius * 0.85),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              BloomCheck(on: selected),
              const SizedBox(width: 12),
              if (drag == null)
                cover
              else
                ReorderableDelayedDragStartListener(index: drag, child: cover),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall?.copyWith(color: t.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              DurationPill(track: track, active: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка перетаскивания, когда едет целый блок выделенных строк: под ней
/// выглядывают ещё плашки, в углу — сколько строк уедет.
///
/// Нужна потому, что прокси у `SliverReorderableList` ровно один: под пальцем
/// в любом случае будет одна строка, и без колоды перенос блока выглядит как
/// перенос единственного трека.
class _DragDeck extends StatelessWidget {
  const _DragDeck({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final shape = BorderRadius.circular(t.radius * 0.85);

    // Плашка ростом с саму карточку, сдвинутая вниз на [inset]: наружу торчит
    // ровно этот сдвиг. Прокси размером со строку её не обрежет — оверлей
    // режет только по краю экрана.
    Widget sheet(double inset, Color color) => Positioned(
      left: inset,
      right: inset,
      top: inset,
      bottom: -inset,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: shape),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Дальняя плашка — только если в блоке правда больше двух строк.
        if (count > 2) sheet(13, Color.lerp(t.pill, t.bg, 0.55)!),
        sheet(6.5, Color.lerp(t.pill, t.bg, 0.28)!),
        child,
        Positioned(
          top: -9,
          right: -4,
          child: Material(
            color: t.accent,
            elevation: 6,
            shadowColor: Colors.black,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              child: Text(
                '$count',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: t.accentText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Плавающая панель режима правки: слева «выбрать все» со счётчиком выделения,
/// справа действия над ним. Пока никого не выбрали, действий нет — им не над
/// чем работать, — и панель показывает один счёт строк.
class _EditBar extends StatelessWidget {
  const _EditBar({
    required this.count,
    required this.total,
    required this.allSelected,
    required this.canFav,
    required this.favOn,
    required this.onToggleAll,
    required this.onAdd,
    required this.onFav,
    required this.onRemove,
  });

  final int count;
  final int total;
  final bool allSelected;
  final bool canFav;

  /// Лайк стоит у всех выделенных — сердечко залито, и оно снимает лайк.
  final bool favOn;

  final VoidCallback? onToggleAll;
  final VoidCallback onAdd;
  final VoidCallback onFav;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final some = count > 0;

    return _BarShell(
      child: Row(
        children: [
          _BarIcon(
            icon: allSelected
                ? Bi.checklistMinimalisticBold
                : Bi.checklistMinimalistic,
            color: allSelected ? t.accent : null,
            onTap: onToggleAll,
          ),
          const SizedBox(width: 4),
          // Знаменатель приглушён: считают тут выделенные, а всего строк — это
          // только мерка, насколько выделение близко к полному.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$count',
                  style: TextStyle(color: some ? t.text : t.text2),
                ),
                TextSpan(
                  text: '/$total',
                  style: TextStyle(color: t.text2),
                ),
              ],
            ),
            style: theme.titleLarge,
          ),
          const Spacer(),
          if (some) ...[
            _BarIcon(icon: Bi.add, onTap: onAdd),
            if (canFav)
              _BarIcon(
                icon: favOn ? Bi.heartBold : Bi.heart,
                color: favOn ? t.sysFavIco : null,
                onTap: onFav,
              ),
            const SizedBox(width: 4),
            _BarIcon(
              icon: Bi.trashBinTrash,
              color: t.danger,
              background: t.danger.withValues(alpha: 0.16),
              onTap: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

/// Та же панель, ставшая полем ввода: ✕ бросает правку названия, ✓ принимает.
class _RenameBar extends StatefulWidget {
  const _RenameBar({
    required this.initial,
    required this.onCancel,
    required this.onDone,
  });

  final String initial;
  final VoidCallback onCancel;
  final ValueChanged<String> onDone;

  @override
  State<_RenameBar> createState() => _RenameBarState();
}

class _RenameBarState extends State<_RenameBar> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _BarShell(
      child: Row(
        children: [
          _BarIcon(icon: Bi.close, onTap: widget.onCancel),
          const SizedBox(width: 8),
          Expanded(
            child: BloomField(
              controller: _controller,
              autofocus: true,
              action: TextInputAction.done,
              onSubmitted: widget.onDone,
            ),
          ),
          const SizedBox(width: 8),
          _BarIcon(
            icon: Bi.check,
            onTap: () => widget.onDone(_controller.text),
          ),
        ],
      ),
    );
  }
}

/// Пилюля, в которой живут обе нижние панели.
class _BarShell extends StatelessWidget {
  const _BarShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      // Сплошная подложка «хрома», как у кнопок шапки: панель висит над
      // списком, и просвечивающие сквозь неё строки читались бы кашей.
      color: t.pill,
      elevation: 8,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.onTap,
    this.color,
    this.background,
  });

  final BloomGlyph icon;
  final VoidCallback? onTap;
  final Color? color;

  /// Своя заливка — у корзины: удаление в этой панели единственное опасное.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: onTap,
      child: Material(
        color: background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 44,
          height: 44,
          child: BloomIcon(
            icon,
            size: 23,
            color: onTap == null ? t.muted : (color ?? t.text),
          ),
        ),
      ),
    );
  }
}
