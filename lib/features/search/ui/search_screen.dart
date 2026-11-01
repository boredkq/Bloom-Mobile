/// Страница поиска: поле-пилюля и круглая кнопка площадки; под ними большие
/// вкладки (все, треки, артисты, альбомы, плейлисты), как в библиотеке и в
/// поиске на ПК, ниже — выдача.
///
/// О площадках экран не знает: спрашивает [ProviderRegistry.searchAll] и
/// рисует нейтральные сущности. Вкладки делят УЖЕ полученную выдачу, а не
/// ходят в сеть заново — провайдер отдаёт все разделы за один прогон.
///
/// Сюда же вставляют ссылки: как на десктопе, поле поиска — единственная точка
/// импорта. Похожая на ссылку строка идёт в `resolveUrlAny` вместо поиска, и
/// трек/артист/плейлист/альбом превращается в одну карточку выдачи; artist's
/// or a listener's link opens their page at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/providers/registry.dart';
import '../../../features/detail/detail_nav.dart';
import '../../../features/player/play_source.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/big_tabs.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/skeleton.dart';
import '../recent_store.dart';

/// Похожа ли строка на ссылку. Домены ловим и без протокола — вставляют и так.
/// Точный разбор всё равно за площадкой, здесь только выбор ветки.
bool looksLikeUrl(String query) =>
    RegExp(r'^https?://', caseSensitive: false).hasMatch(query) ||
    RegExp(
      r'(^|\.)(soundcloud\.com|snd\.sc|music\.yandex\.[a-z]+|music\.youtube\.com|youtu\.be)/',
      caseSensitive: false,
    ).hasMatch(query);

/// Зарезолвленная ссылка → выдача из одной карточки.
SearchResults _resolvedToResults(ResolvedUrl resolved) => switch (resolved) {
  ResolvedTrack(:final track) => SearchResults(tracks: [track]),
  ResolvedArtist(:final artist) => SearchResults(artists: [artist]),
  ResolvedSet(:final playlist) =>
    playlist.isAlbum
        ? SearchResults(albums: [playlist])
        : SearchResults(playlists: [playlist]),
};

enum SearchTab {
  all,
  tracks,
  artists,
  albums,
  playlists;

  String label(AppLocalizations l) => switch (this) {
    SearchTab.all => l.searchTabAll,
    SearchTab.tracks => l.commonTracks,
    SearchTab.artists => l.commonArtists,
    SearchTab.albums => l.commonAlbums,
    SearchTab.playlists => l.commonPlaylists,
  };

  /// How many of this kind the results hold; "all" counts as one.
  int countIn(SearchResults r) => switch (this) {
    SearchTab.all => 1,
    SearchTab.tracks => r.tracks.length,
    SearchTab.artists => r.artists.length,
    SearchTab.albums => r.albums.length,
    SearchTab.playlists => r.playlists.length,
  };
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  SearchTab _tab = SearchTab.all;
  SearchResults _results = SearchResults.empty;
  bool _loading = false;
  String? _error;

  /// Был ли уже прогон. Нужен, чтобы отличать «ещё не искали» от «искали и не
  /// нашли»: реестр гасит ошибки провайдеров в пустую выдачу, и без этого
  /// флага неудачный поиск выглядел как нетронутый экран.
  bool _searched = false;

  /// Номер запроса: ответ на устаревший поиск не должен перебить свежий.
  int _generation = 0;

  /// Запрос, по которому стоит ВЫДАЧА, — не то же, что текст в поле: его уже
  /// правят под следующий поиск, а очередь набирается из того, что на экране.
  String _lastQuery = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    // Запоминаем на старте, как на десктопе: запрос попадает в недавние даже
    // если выдача пустая — повторить его с опечаткой куда полезнее, чем
    // набирать заново.
    ref.read(recentSearchesProvider.notifier).push(query);
    final gen = ++_generation;
    setState(() {
      _lastQuery = query;
      _loading = true;
      _error = null;
    });

    try {
      // Ссылка — сперва резолв. Не разобрали (чужая площадка не подключена,
      // опечатка) — молча падаем в обычный поиск: строка ведь введена в поле
      // поиска, и выдача по ней полезнее пустого экрана с ошибкой.
      if (looksLikeUrl(query)) {
        final found = await ref.read(registryProvider).resolveUrlAny(query);
        if (!mounted || gen != _generation) return;
        if (found != null) {
          setState(() {
            _loading = false;
            _searched = true;
            _results = _resolvedToResults(found.resolved);
          });
          if (found.resolved case ResolvedArtist(:final artist)) {
            openArtist(context, artist.id, initial: artist);
          }
          return;
        }
      }

      final results = await ref
          .read(registryProvider)
          .searchAll(query, providerId: ref.read(activeProviderIdProvider));
      if (!mounted || gen != _generation) return;
      setState(() {
        _results = results;
        _loading = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// A kind without results is a dim tab; while a search loads they all stay
  /// lit.
  bool _has(SearchTab tab) => _loading || tab.countIn(_results) > 0;

  /// A tab the new results left empty falls back to "all".
  SearchTab get _activeTab => _has(_tab) ? _tab : SearchTab.all;

  void _go(SearchTab tab) => setState(() => _tab = tab);

  /// Тап по недавнему запросу: подставить его в поле и сразу искать.
  ///
  /// Клавиатуру убираем — она заняла бы полэкрана над свежей выдачей, а
  /// править подставленный запрос обычно и не нужно.
  void _applyRecent(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _focus.unfocus();
    _search();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                // Своим табом поиск — корень ветки, и возвращаться ему некуда:
                // стрелки тогда нет вовсе, а поле занимает всю ширину. Открытый
                // страницей главной — стрелка на месте.
                if (Navigator.of(context).canPop()) ...[
                  CircleIconButton(
                    icon: Bi.arrowLeft,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _SearchField(
                    controller: _controller,
                    focusNode: _focus,
                    onSubmit: _search,
                    onClear: () => setState(() {
                      _controller.clear();
                      _results = SearchResults.empty;
                      _error = null;
                      _searched = false;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                // Смена площадки перезапускает поиск: выдача целиком принадлежит
                // выбранному источнику, показывать под новым логотипом старые
                // строки нельзя.
                _PlatformButton(onPicked: _search),
              ],
            ),
          ),
          BigTabs<SearchTab>(
            tabs: [
              for (final tab in SearchTab.values)
                BigTab(tab, tab.label(context.l), has: _has(tab)),
            ],
            current: _activeTab,
            onPick: _go,
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final t = context.bloom;
    if (_loading) return _SearchSkeleton(tab: _activeTab);
    if (_error != null) {
      return Center(
        child: CenterNote(
          _error!,
          color: t.danger,
          padding: const EdgeInsets.all(24),
        ),
      );
    }
    if (_results.isEmpty) {
      // До первого запроса вместо заглушки — недавние. После неудачного поиска
      // их не показываем: ответ «ничего не нашлось» относится к тому, что ввели,
      // и подменять его историей значит прятать результат.
      final recents = ref.watch(recentSearchesProvider);
      final items = ref.watch(recentItemsProvider);
      if (!_searched && (recents.isNotEmpty || items.isNotEmpty)) {
        return _RecentPanel(
          queries: recents,
          items: items,
          onPick: _applyRecent,
        );
      }
      final text = _searched
          ? context.l.searchNothingFound
          : context.l.searchFindSomething;
      return Center(child: CenterNote(text));
    }
    return _ResultsView(
      results: _results,
      tab: _activeTab,
      query: _lastQuery,
      onTab: _go,
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => HeaderSearchField(
    controller: controller,
    focusNode: focusNode,
    hint: context.l.searchHint,
    action: TextInputAction.search,
    onSubmitted: (_) => onSubmit(),
    trailing: ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => value.text.isEmpty
          ? const SizedBox.shrink()
          : Pressable(
              onTap: onClear,
              child: BloomIcon(Bi.close, size: 18, color: context.bloom.muted),
            ),
    ),
  );
}

/// Недавнее на пустом экране поиска: сперва открытые карточки лентой, под ними
/// запросы строками — порт десктопного выпадающего списка истории, разложенного
/// на два блока (мешать их по свежести, как `mergedRecents` на ПК, здесь нечем:
/// времени мы не храним).
///
/// Запросы именно строками, а не чипами-пилюлями: запрос бывает длинным («бой с
/// тенью 3 саундтрек»), и в пилюлю такой влезает только многоточием — а узнают
/// прошлый запрос как раз по хвосту.
class _RecentPanel extends ConsumerWidget {
  const _RecentPanel({
    required this.queries,
    required this.items,
    required this.onPick,
  });

  final List<String> queries;
  final List<RecentItem> items;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      // Снизу — бары каркаса: они плавают над содержимым.
      padding: EdgeInsets.fromLTRB(8, 4, 8, 12 + bottomBarsInset(context)),
      children: [
        if (items.isNotEmpty) ...[
          _RecentHeader(
            title: context.l.searchRecentOpened,
            onClear: () => ref.read(recentItemsProvider.notifier).clear(),
          ),
          // Высота — как у ленты плейлистов в выдаче: карточки те же и рядом с
          // ней стоять им одинаково.
          EntityCarousel(
            height: 194,
            itemCount: items.length,
            builder: (i) => _RecentCard(item: items[i]),
          ),
        ],
        if (queries.isNotEmpty) ...[
          _RecentHeader(
            title: context.l.searchRecent,
            onClear: () => ref.read(recentSearchesProvider.notifier).clear(),
          ),
          for (final query in queries)
            _RecentRow(
              query: query,
              onTap: () => onPick(query),
              onRemove: () =>
                  ref.read(recentSearchesProvider.notifier).remove(query),
            ),
        ],
      ],
    );
  }
}

class _RecentHeader extends StatelessWidget {
  const _RecentHeader({required this.title, required this.onClear});

  final String title;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => SectionTitle(
    title,
    side: 8,
    actionLabel: context.l.commonClear,
    onAction: onClear,
  );
}

/// Карточка недавно открытого: обложка (у артиста — кружок), название и тип.
///
/// Своя, а не [SetCard]/[ArtistCard]/[TrackCard]: в одной ленте стоят разные
/// сущности, и им нужен общий силуэт и общий жест удаления. Подпись — тип, а не
/// автор: обложка с названием и так узнаются, а вот «это альбом или трек» по
/// ним не понять.
class _RecentCard extends ConsumerWidget {
  const _RecentCard({required this.item});

  final RecentItem item;

  static const double _size = 132;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final (cover, title, subtitle, source, circle) = switch (item) {
      RecentTrack(:final track) => (
        track.cover,
        track.name,
        l.commonTrack,
        track.source,
        false,
      ),
      RecentArtist(:final artist) => (
        artist.avatar,
        artist.name,
        l.commonArtist,
        artist.source,
        true,
      ),
      RecentSet(:final set) => (
        set.cover,
        set.title,
        set.isAlbum ? l.commonAlbum : l.commonPlaylist,
        set.source,
        false,
      ),
    };

    return EntityCard(
      size: _size,
      center: circle,
      title: title,
      lines: [subtitle],
      cover: (side) =>
          SourcedCover(url: cover, size: side, source: source, circle: circle),
      onTap: () => _openRecent(context, ref, item),
      onLongPress: () => _removeRecent(context, ref, item),
    );
  }
}

/// Открыть недавнее: страница артиста или сета, трек — просто играет (страницы
/// у него нет). Запись при этом поднимается наверх, как `openRecentItem` на ПК.
///
/// Повторного запроса к площадке не нужно: в списке лежит та же сущность, что
/// пришла в выдаче, — с обложкой, владельцем и `sourceData` для стрима.
void _openRecent(BuildContext context, WidgetRef ref, RecentItem item) {
  ref.read(recentItemsProvider.notifier).push(item);
  switch (item) {
    case RecentTrack(:final track):
      ref
          .read(playbackProvider.notifier)
          .playQueue([track], 0, source: PlainSource.single(track));
    case RecentArtist(:final artist):
      openArtist(context, artist.id, initial: artist);
    case RecentSet(:final set):
      openSet(context, set);
  }
}

/// Шторка одного действия — «Убрать из недавних» для карточки под долгим тапом.
Future<void> _removeRecent(
  BuildContext context,
  WidgetRef ref,
  RecentItem item,
) {
  final (cover, title, subtitle) = switch (item) {
    RecentTrack(:final track) => (track.cover, track.name, track.artist),
    RecentArtist(:final artist) => (
      artist.avatar,
      artist.name,
      context.l.commonArtist,
    ),
    RecentSet(:final set) => (
      set.cover,
      set.title,
      set.ownerName ??
          (set.isAlbum ? context.l.commonAlbum : context.l.commonPlaylist),
    ),
  };

  return showBloomSheet(
    context: context,
    header: SheetHero(cover: cover, title: title, subtitle: subtitle),
    groups: [
      [
        SheetAction(
          icon: Bi.close,
          label: context.l.searchRemoveRecent,
          danger: true,
          onTap: () => ref.read(recentItemsProvider.notifier).remove(item),
        ),
      ],
    ],
  );
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SheetRow(
      leading: BloomIcon(Bi.clockCircle, size: 20, color: t.muted),
      gap: 12,
      label: query,
      trailing: CircleIconButton(
        icon: Bi.close,
        size: 34,
        iconSize: 18,
        background: Colors.transparent,
        color: t.muted,
        onTap: onRemove,
      ),
      onTap: onTap,
    );
  }
}

class _PlatformButton extends ConsumerWidget {
  const _PlatformButton({required this.onPicked});

  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref
        .watch(registryProvider)
        .byId(ref.watch(activeProviderIdProvider));
    return CircleIconButton(
      icon: Bi.widget4,
      child: provider == null ? null : PlatformLogo(provider.source, size: 23),
      onTap: () => _pickSource(context, ref, onPicked),
    );
  }
}

/// Шторка выбора источника поиска.
///
/// Площадки идут отдельными карточками с просветом между ними, а не пунктами
/// одного блока: логотипы у брендов разноцветные и на общей панели читались как
/// каша. Заголовка нет — знак и название площадки говорят сами за себя.
Future<void> _pickSource(
  BuildContext context,
  WidgetRef ref,
  VoidCallback onPicked,
) async {
  final registry = ref.read(registryProvider);
  final picked = await showBloomSheetChild<String>(
    context: context,
    child: Consumer(
      builder: (context, ref, _) {
        final activeId = ref.watch(activeProviderIdProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetOptionTile(
              icon: Bi.widget4,
              label: context.l.searchSourceAll,
              active: activeId == kAllProviders,
              onTap: () => Navigator.of(context).pop(kAllProviders),
            ),
            for (final p in registry.enabled)
              SheetOptionTile(
                leading: PlatformLogo(p.source, size: 24),
                label: p.source.label10n(context.l),
                active: activeId == p.id,
                onTap: () => Navigator.of(context).pop(p.id),
              ),
          ],
        );
      },
    ),
  );
  if (picked == null) return;
  final controller = ref.read(activeProviderIdProvider.notifier);
  if (controller.state == picked) return;
  controller.state = picked;
  onPicked();
}

/// How many tracks "all" shows; the rest are the tab's.
const int _tracksPreview = 4;

/// The gap over a kind's own tab, as in the library.
const double _tabTop = 18;

/// Записать открытую из выдачи карточку в «недавно открытые».
///
/// Зовётся из плиток выдачи — они же общие с главной и библиотекой, поэтому
/// запись идёт не внутри плитки, а через её `onOpen`: недавние копит ровно
/// поиск, как `openActions.ts` на десктопе.
void _remember(WidgetRef ref, RecentItem item) =>
    ref.read(recentItemsProvider.notifier).push(item);

class _ResultsView extends ConsumerWidget {
  const _ResultsView({
    required this.results,
    required this.tab,
    required this.query,
    required this.onTab,
  });

  final SearchResults results;
  final SearchTab tab;

  /// Запрос — он же подпись источника в пилюле плеера («Поиск: …»).
  final String query;

  /// A section's caption in "all" leads to its kind's tab.
  final ValueChanged<SearchTab> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    Widget setGrid(List<Playlist> sets) => CardGrid(
      columns: 2,
      caption: setCaption(sets),
      top: _tabTop,
      itemCount: sets.length,
      itemBuilder: (context, i) => SetCard(
        set: sets[i],
        size: null,
        onOpen: () => _remember(ref, RecentSet(sets[i])),
      ),
    );
    final artists = results.artists;
    switch (tab) {
      case SearchTab.albums:
        return setGrid(results.albums);
      case SearchTab.playlists:
        return setGrid(results.playlists);
      case SearchTab.artists:
        return CardGrid(
          columns: 3,
          caption: 48,
          top: _tabTop,
          itemCount: artists.length,
          itemBuilder: (context, i) => ArtistCard(
            artist: artists[i],
            size: null,
            centerLabel: true,
            onOpen: () => _remember(ref, RecentArtist(artists[i])),
          ),
        );
      case SearchTab.all || SearchTab.tracks:
        break;
    }

    final all = tab == SearchTab.all;
    final tracks = results.tracks;
    // "All" shows the first few tracks, or the artists and the sets would be
    // three dozen rows down; the whole list is the tab's.
    final shownTracks = all && tracks.length > _tracksPreview
        ? _tracksPreview
        : tracks.length;
    final source = PlainSource.search(query, l.playerSourceSearch(query));

    Widget label(SearchTab kind) =>
        SectionLabel(kind.label(l), onTap: () => onTab(kind));
    Widget sets(List<Playlist> sets) => EntityCarousel(
      height: setRowHeight(sets),
      padding: 16,
      itemCount: sets.length,
      builder: (i) => SetCard(
        set: sets[i],
        onOpen: () => _remember(ref, RecentSet(sets[i])),
      ),
    );

    final sections = <Widget>[
      if (tracks.isNotEmpty) ...[
        if (all) label(SearchTab.tracks) else const SizedBox(height: 12),
        for (var i = 0; i < shownTracks; i++)
          // A track plays alone.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TrackRow(
              track: tracks[i],
              queue: [tracks[i]],
              index: 0,
              source: source,
              onOpen: () => _remember(ref, RecentTrack(tracks[i])),
            ),
          ),
      ],
      if (all && results.artists.isNotEmpty) ...[
        label(SearchTab.artists),
        EntityCarousel(
          height: 168,
          padding: 16,
          itemCount: results.artists.length,
          builder: (i) => ArtistCard(
            artist: results.artists[i],
            centerLabel: true,
            onOpen: () => _remember(ref, RecentArtist(results.artists[i])),
          ),
        ),
      ],
      if (all && results.albums.isNotEmpty) ...[
        label(SearchTab.albums),
        sets(results.albums),
      ],
      if (all && results.playlists.isNotEmpty) ...[
        label(SearchTab.playlists),
        sets(results.playlists),
      ],
    ];

    if (sections.isEmpty) {
      return Center(child: CenterNote(context.l.searchSectionEmpty));
    }
    return ListView(
      // The sections keep to the sides themselves; under them the shell's
      // bars float over the results.
      padding: EdgeInsets.only(bottom: 12 + bottomBarsInset(context)),
      children: sections,
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton({required this.tab});

  final SearchTab tab;

  @override
  Widget build(BuildContext context) {
    Widget grid(int columns, int count, {bool circle = false}) => CardGrid(
      columns: columns,
      caption: 48,
      top: _tabTop,
      bottom: 16,
      scrolls: false,
      itemCount: count,
      itemBuilder: (context, _) => CardSkeleton(circle: circle),
    );
    return SkeletonPulse(
      child: switch (tab) {
        SearchTab.all => const _AllSkeleton(),
        SearchTab.tracks => ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 9,
          itemBuilder: (context, i) => TrackRowSkeleton(index: i),
        ),
        SearchTab.albums || SearchTab.playlists => grid(2, 6),
        SearchTab.artists => grid(3, 9, circle: true),
      },
    );
  }
}

/// Заготовка «Всё»: подпись и превью треков, затем ленты артистов и альбомов —
/// тот же порядок секций, что в [_ResultsView].
class _AllSkeleton extends StatelessWidget {
  const _AllSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const SectionLabelSkeleton(width: 48),
        for (var i = 0; i < _tracksPreview; i++) TrackRowSkeleton(index: i),
        const SectionLabelSkeleton(width: 62),
        const CarouselSkeleton(height: 168, card: 104, circle: true),
        const SectionLabelSkeleton(width: 58),
        const CarouselSkeleton(height: 212, card: 132),
      ],
    );
  }
}
