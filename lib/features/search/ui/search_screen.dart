/// Страница поиска. Раскладка из референса: круглая «назад», поле-пилюля,
/// круглая кнопка площадки; под ними чипы-фильтры, ниже — выдача секциями.
///
/// О площадках экран не знает: спрашивает [ProviderRegistry.searchAll] и
/// рисует нейтральные сущности. Чипы фильтруют УЖЕ полученную выдачу, а не
/// ходят в сеть заново — провайдер отдаёт все разделы за один прогон.
///
/// Сюда же вставляют ссылки: как на десктопе, поле поиска — единственная точка
/// импорта. Похожая на ссылку строка идёт в `resolveUrlAny` вместо поиска, и
/// трек/артист/плейлист/альбом превращается в одну карточку выдачи, а ссылка
/// на аккаунт — в профиль ([ProfileView]) с плейлистами и лайками.
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
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/skeleton.dart';
import '../recent_store.dart';
import 'profile_view.dart';

/// Просвет под чипами-фильтрами: без него ряд чипов слипался с первой строкой
/// выдачи и читался как её часть.
const double _chipsGap = 14;

/// Похожа ли строка на ссылку. Домены ловим и без протокола — вставляют и так.
/// Точный разбор всё равно за площадкой, здесь только выбор ветки.
bool looksLikeUrl(String query) =>
    RegExp(r'^https?://', caseSensitive: false).hasMatch(query) ||
    RegExp(
      r'(^|\.)(soundcloud\.com|snd\.sc|music\.yandex\.[a-z]+|music\.youtube\.com|youtu\.be)/',
      caseSensitive: false,
    ).hasMatch(query);

/// Зарезолвленная ссылка → выдача из одной карточки. Профиль сюда не попадает:
/// у него свой вид.
SearchResults _resolvedToResults(ResolvedUrl resolved) => switch (resolved) {
  ResolvedTrack(:final track) => SearchResults(tracks: [track]),
  ResolvedArtist(:final artist) => SearchResults(artists: [artist]),
  ResolvedSet(:final playlist) =>
    playlist.isAlbum
        ? SearchResults(albums: [playlist])
        : SearchResults(playlists: [playlist]),
  ResolvedProfile() => SearchResults.empty,
};

enum SearchFilter {
  all(Bi.widget4),
  tracks(Bi.musicNote),
  playlists(Bi.musicLibrary2),
  albums(Bi.vinyl),
  artists(Bi.user);

  const SearchFilter(this.icon);

  String label(AppLocalizations l) => switch (this) {
    SearchFilter.all => l.searchTabAll,
    SearchFilter.tracks => l.commonTracks,
    SearchFilter.playlists => l.commonPlaylists,
    SearchFilter.albums => l.commonAlbums,
    SearchFilter.artists => l.commonArtists,
  };

  final BloomGlyph icon;
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  SearchFilter _filter = SearchFilter.all;
  SearchResults _results = SearchResults.empty;
  bool _loading = false;
  String? _error;

  /// Аккаунт, найденный по вставленной ссылке. Пока он есть, вместо выдачи (и
  /// чипов над ней) показывается профиль.
  ProfileData? _profile;

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
      _profile = null;
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
            if (found.resolved case ResolvedProfile(:final profile)) {
              _profile = profile;
              _results = SearchResults.empty;
            } else {
              _results = _resolvedToResults(found.resolved);
            }
          });
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
                      _profile = null;
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
          // У профиля своих разделов нет — чипы над ним нечего фильтровать.
          if (_profile == null) ...[
            _FilterChips(
              active: _filter,
              onPick: (f) => setState(() => _filter = f),
            ),
            const SizedBox(height: _chipsGap),
          ],
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    // Заготовка вместо полоски прогресса: она сразу занимает высоту будущей
    // выдачи, поэтому при ответе ничего не дёргается. Старые результаты при
    // новом запросе прячем — иначе непонятно, что показано.
    if (_loading) return _SearchSkeleton(filter: _filter);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.bodyMedium?.copyWith(color: t.danger),
          ),
        ),
      );
    }
    if (_profile case final profile?) return ProfileView(profile: profile);
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
      return Center(
        child: Text(text, style: theme.bodyMedium?.copyWith(color: t.muted)),
      );
    }
    return _ResultsView(results: _results, filter: _filter, query: _lastQuery);
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
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GlassBox(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: kHeaderControl,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            BloomIcon(Bi.magnifier, size: 21, color: t.muted),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                onSubmitted: (_) => onSubmit(),
                textInputAction: TextInputAction.search,
                // Запрос — того же кегля, что название раздела в соседних
                // шапках: поле стоит на их месте и обязано читаться так же.
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontSize: kHeaderTitleSize),
                cursorColor: t.accent,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: context.l.searchHint,
                  hintStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: kHeaderTitleSize,
                    color: t.muted,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : Pressable(
                      onTap: onClear,
                      child: BloomIcon(Bi.close, size: 18, color: t.muted),
                    ),
            ),
          ],
        ),
      ),
    );
  }
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

/// Заголовок блока недавнего с «Очистить» справа.
class _RecentHeader extends StatelessWidget {
  const _RecentHeader({required this.title, required this.onClear});

  final String title;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 4, 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.titleLarge)),
          // «Очистить» — второстепенное действие, поэтому текстом без
          // подложки; зону нажатия добирают отступы вокруг надписи.
          Pressable(
            onTap: onClear,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                context.l.commonClear,
                style: theme.titleMedium?.copyWith(color: t.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    final theme = Theme.of(context).textTheme;
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

    return Pressable(
      onTap: () => _openRecent(context, ref, item),
      // Убрать одну карточку — долгим тапом: крестик поверх обложки в ленте
      // читался бы как часть картинки, а места под отдельную кнопку тут нет.
      onLongPress: () => _removeRecent(context, ref, item),
      scale: 0.97,
      child: SizedBox(
        width: _size,
        child: Column(
          crossAxisAlignment: circle
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Cover(url: cover, size: _size, circle: circle),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: SourceBadge(source, size: kCardBadge),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              textAlign: circle ? TextAlign.center : TextAlign.start,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
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
  final (cover, title, subtitle, circle) = switch (item) {
    RecentTrack(:final track) => (track.cover, track.name, track.artist, false),
    RecentArtist(:final artist) => (
      artist.avatar,
      artist.name,
      context.l.commonArtist,
      true,
    ),
    RecentSet(:final set) => (
      set.cover,
      set.title,
      set.ownerName ??
          (set.isAlbum ? context.l.commonAlbum : context.l.commonPlaylist),
      false,
    ),
  };

  return showBloomSheet(
    context: context,
    backdrop: cover,
    header: SheetLineHeader(
      cover: cover,
      title: title,
      subtitle: subtitle,
      circle: circle,
    ),
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

/// Строка недавнего запроса: часы, текст, крестик. Отступы — от [TrackRow],
/// чтобы блок стоял на той же сетке, что выдача под ним.
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
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            BloomIcon(Bi.clockCircle, size: 20, color: t.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // У крестика своя зона нажатия с запасом: тап по строке уходит в
            // сеть, и промах мимо мелкого значка стоил бы лишнего запроса.
            Pressable(
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: BloomIcon(Bi.close, size: 18, color: t.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка площадки: показывает, где ищем, и открывает выбор источника.
///
/// «Все источники» — значок-мозаика вместо логотипа: ни один бренд не годится
/// на роль общего. Выключенные площадки (Яндекс без входа) в список не
/// попадают — как в дропдауне на десктопе.
class _PlatformButton extends ConsumerWidget {
  const _PlatformButton({required this.onPicked});

  /// Вызывается после смены площадки — перезапустить поиск.
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final registry = ref.watch(registryProvider);
    final activeId = ref.watch(activeProviderIdProvider);
    final provider = registry.byId(activeId);

    return Pressable(
      onTap: () => _pickSource(context, ref, onPicked),
      child: GlassBox(
        shape: const CircleBorder(),
        child: SizedBox(
          width: kHeaderControl,
          height: kHeaderControl,
          child: Center(
            child: provider == null
                ? BloomIcon(Bi.widget4, size: 23, color: t.iconFg)
                : PlatformLogo(provider.source, size: 23),
          ),
        ),
      ),
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SourceRow(
                label: context.l.searchSourceAll,
                icon: Bi.widget4,
                active: activeId == kAllProviders,
                onTap: () => Navigator.of(context).pop(kAllProviders),
              ),
              for (final p in registry.enabled)
                _SourceRow(
                  label: p.source.label10n(context.l),
                  source: p.source,
                  active: activeId == p.id,
                  onTap: () => Navigator.of(context).pop(p.id),
                ),
            ],
          ),
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

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.label,
    required this.active,
    required this.onTap,
    this.source,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final MusicSource? source;
  final BloomGlyph? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: Material(
          color: t.pill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radius),
            // Выбранная карточка обведена акцентом: галочки справа мало —
            // взгляд ищет активный пункт по силуэту, а не по значку.
            side: active
                ? BorderSide(color: t.accent.withValues(alpha: 0.55))
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Center(
                    child: source != null
                        ? PlatformLogo(source!, size: 28)
                        : BloomIcon(icon, size: 24, color: t.iconFg),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (active) BloomIcon(Bi.check, size: 22, color: t.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.active, required this.onPick});

  final SearchFilter active;
  final ValueChanged<SearchFilter> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kChipHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: SearchFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final filter = SearchFilter.values[i];
          return _Chip(
            filter: filter,
            active: filter == active,
            onTap: () => onPick(filter),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.filter,
    required this.active,
    required this.onTap,
  });

  final SearchFilter filter;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    // Активный чип — заливка акцентом с контрастной надписью, как в референсе.
    final fg = active ? t.accentText : t.text2;
    return Pressable(
      onTap: onTap,
      child: GlassBox(
        color: active ? t.accent : null,
        enabled: !active,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              BloomIcon(filter.icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                filter.label(context.l),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Сколько строк трек-листа показывать в «Всё» — как на референсе.
const int _tracksPreview = 4;

/// Записать открытую из выдачи карточку в «недавно открытые».
///
/// Зовётся из плиток выдачи — они же общие с главной и библиотекой, поэтому
/// запись идёт не внутри плитки, а через её `onOpen`: недавние копит ровно
/// поиск, как `openActions.ts` на десктопе.
void _remember(WidgetRef ref, RecentItem item) =>
    ref.read(recentItemsProvider.notifier).push(item);

/// Отступы сеток выдачи: поля экрана и просвет между ячейками.
const double _gridPad = 16;
const double _gridGap = 16;

/// Сетка плейлистов/альбомов — две колонки, подпись в две строки под обложкой.
class _SetGrid extends ConsumerWidget {
  const _SetGrid({required this.sets});

  final List<Playlist> sets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final cell = (width - _gridPad * 2 - _gridGap) / 2;

    return GridView.builder(
      // Снизу — бары каркаса: они плавают над выдачей.
      padding: EdgeInsets.fromLTRB(
        _gridPad,
        8,
        _gridPad,
        16 + bottomBarsInset(context),
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: _gridGap,
        mainAxisSpacing: 20,
        // Высота ячейки задаётся явно: обложка квадратная плюс две строки
        // подписи. Через childAspectRatio то же самое пришлось бы подбирать
        // на глаз, и на узком экране подпись обрезало бы.
        mainAxisExtent: cell + 48,
      ),
      itemCount: sets.length,
      itemBuilder: (context, i) => SetCard(
        set: sets[i],
        size: null,
        onOpen: () => _remember(ref, RecentSet(sets[i])),
      ),
    );
  }
}

/// Сетка артистов — три колонки кружков с подписью по центру.
class _ArtistGrid extends ConsumerWidget {
  const _ArtistGrid({required this.artists});

  final List<Artist> artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final cell = (width - _gridPad * 2 - _gridGap * 2) / 3;

    return GridView.builder(
      // Снизу — бары каркаса: они плавают над выдачей.
      padding: EdgeInsets.fromLTRB(
        _gridPad,
        8,
        _gridPad,
        16 + bottomBarsInset(context),
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: _gridGap,
        mainAxisSpacing: 20,
        mainAxisExtent: cell + 48,
      ),
      itemCount: artists.length,
      itemBuilder: (context, i) => ArtistCard(
        artist: artists[i],
        size: null,
        centerLabel: true,
        onOpen: () => _remember(ref, RecentArtist(artists[i])),
      ),
    );
  }
}

class _ResultsView extends ConsumerWidget {
  const _ResultsView({
    required this.results,
    required this.filter,
    required this.query,
  });

  final SearchResults results;
  final SearchFilter filter;

  /// Запрос — он же подпись источника в пилюле плеера («Поиск: …»).
  final String query;

  bool _shows(SearchFilter section) =>
      filter == SearchFilter.all || filter == section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;

    // Под своим чипом раздел разворачивается: сеты — в две колонки, артисты —
    // в три, как в референсе. Карусель остаётся только в «Всё», где она нужна,
    // чтобы раздел занимал одну строку.
    // Пустой раздел до сетки не доходит — ниже общее «ничего не нашлось».
    final grid = switch (filter) {
      SearchFilter.playlists when results.playlists.isNotEmpty => _SetGrid(
        sets: results.playlists,
      ),
      SearchFilter.albums when results.albums.isNotEmpty => _SetGrid(
        sets: results.albums,
      ),
      SearchFilter.artists when results.artists.isNotEmpty => _ArtistGrid(
        artists: results.artists,
      ),
      _ => null,
    };
    if (grid != null) return grid;

    // Заголовки нужны только в «Всё»: у одиночного фильтра подпись повторяет
    // имя чипа.
    final titled = filter == SearchFilter.all;
    final tracks = results.tracks;
    // В «Всё» треки идут первыми, поэтому показываем только начало списка:
    // иначе до артистов и плейлистов пришлось бы листать три десятка строк.
    // Весь список — под своим чипом.
    final shownTracks = titled && tracks.length > _tracksPreview
        ? _tracksPreview
        : tracks.length;

    // Порядок секций — из референса: треки, артисты, плейлисты, альбомы.
    final sections = <Widget>[
      if (_shows(SearchFilter.tracks) && tracks.isNotEmpty) ...[
        if (titled) SectionTitle(context.l.commonTracks, side: 8),
        for (var i = 0; i < shownTracks; i++)
          // Очередь — весь список, а не превью: с четвёртой строки
          // проигрывание должно ехать дальше по выдаче.
          TrackRow(
            track: tracks[i],
            queue: tracks,
            index: i,
            source: PlainSource.search(
              query,
              context.l.playerSourceSearch(query),
            ),
            onOpen: () => _remember(ref, RecentTrack(tracks[i])),
          ),
      ],
      if (_shows(SearchFilter.artists) && results.artists.isNotEmpty) ...[
        if (titled) SectionTitle(context.l.commonArtists, side: 8),
        EntityCarousel(
          height: 168,
          itemCount: results.artists.length,
          builder: (i) => ArtistCard(
            artist: results.artists[i],
            centerLabel: true,
            onOpen: () => _remember(ref, RecentArtist(results.artists[i])),
          ),
        ),
      ],
      if (_shows(SearchFilter.playlists) && results.playlists.isNotEmpty) ...[
        if (titled) SectionTitle(context.l.commonPlaylists, side: 8),
        EntityCarousel(
          height: 194,
          itemCount: results.playlists.length,
          builder: (i) => SetCard(
            set: results.playlists[i],
            onOpen: () => _remember(ref, RecentSet(results.playlists[i])),
          ),
        ),
      ],
      if (_shows(SearchFilter.albums) && results.albums.isNotEmpty) ...[
        if (titled) SectionTitle(context.l.commonAlbums, side: 8),
        EntityCarousel(
          height: 194,
          itemCount: results.albums.length,
          builder: (i) => SetCard(
            set: results.albums[i],
            onOpen: () => _remember(ref, RecentSet(results.albums[i])),
          ),
        ),
      ],
    ];

    if (sections.isEmpty) {
      return Center(
        child: Text(
          context.l.searchSectionEmpty,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: t.muted),
        ),
      );
    }

    return ListView(
      // Снизу — бары каркаса: они плавают над выдачей.
      padding: EdgeInsets.fromLTRB(8, 4, 8, 12 + bottomBarsInset(context)),
      children: sections,
    );
  }
}

/// Заготовка выдачи на время запроса: та же раскладка, что покажет активный
/// чип, поэтому при ответе плашки просто сменяются содержимым.
///
/// Заготовки не листаются: их ровно столько, сколько влезает в экран, и
/// скроллить пустые плашки незачем.
class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton({required this.filter});

  final SearchFilter filter;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: switch (filter) {
        SearchFilter.all => const _AllSkeleton(),
        SearchFilter.tracks => const _TracksSkeleton(count: 9),
        SearchFilter.playlists ||
        SearchFilter.albums => const _GridSkeleton(columns: 2, count: 6),
        SearchFilter.artists => const _GridSkeleton(
          columns: 3,
          count: 9,
          circle: true,
        ),
      },
    );
  }
}

/// Ширины «строк» подписей — по кругу, чтобы плашки не выстраивались в
/// одинаковую линейку.
const List<double> _titleWidths = [0.62, 0.48, 0.71, 0.55];
const List<double> _subWidths = [0.34, 0.42, 0.28, 0.38];

/// Плашка на месте [TrackRow]: те же отступы и обложка 48, поэтому высота
/// строки совпадает с настоящей.
class _TrackRowSkeleton extends StatelessWidget {
  const _TrackRowSkeleton({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          const SkeletonBox(width: 48, height: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(
                  widthFactor: _titleWidths[index % _titleWidths.length],
                  height: 13,
                ),
                const SizedBox(height: 7),
                SkeletonLine(
                  widthFactor: _subWidths[index % _subWidths.length],
                  height: 11,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const SkeletonBox(width: 30, height: 11, radius: 6),
        ],
      ),
    );
  }
}

class _TracksSkeleton extends StatelessWidget {
  const _TracksSkeleton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, i) => _TrackRowSkeleton(index: i),
    );
  }
}

/// Плашка на месте [SetCard]/[ArtistCard]: обложка на всю ширину ячейки и две
/// строки подписи (у артиста — одна, как и в карточке без счётчика).
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.circle, this.width});

  final bool circle;

  /// `null` — на всю ширину ячейки сетки; число — фиксированная ширина
  /// карточки в карусели.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: circle
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          SkeletonBox(
            width: box.maxWidth,
            height: box.maxWidth,
            circle: circle,
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: box.maxWidth * (circle ? 0.7 : 0.8), height: 12),
          if (!circle) ...[
            const SizedBox(height: 6),
            SkeletonBox(width: box.maxWidth * 0.5, height: 10),
          ],
        ],
      ),
    );
    return width == null ? content : SizedBox(width: width, child: content);
  }
}

/// Сетка заготовок — геометрия [_SetGrid] и [_ArtistGrid] один в один.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton({
    required this.columns,
    required this.count,
    this.circle = false,
  });

  final int columns;
  final int count;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cell = (width - _gridPad * 2 - _gridGap * (columns - 1)) / columns;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(_gridPad, 8, _gridPad, 16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: _gridGap,
        mainAxisSpacing: 20,
        mainAxisExtent: cell + 48,
      ),
      itemCount: count,
      itemBuilder: (context, _) => _CardSkeleton(circle: circle),
    );
  }
}

/// Заготовка «Всё»: заголовок и превью треков, затем ленты артистов и сетов —
/// тот же порядок секций, что в [_ResultsView].
class _AllSkeleton extends StatelessWidget {
  const _AllSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const _SectionTitleSkeleton(width: 84),
        for (var i = 0; i < _tracksPreview; i++) _TrackRowSkeleton(index: i),
        const _SectionTitleSkeleton(width: 104),
        const _CarouselSkeleton(height: 168, card: 104, circle: true),
        const _SectionTitleSkeleton(width: 128),
        const _CarouselSkeleton(height: 194, card: 132),
      ],
    );
  }
}

/// Плашка на месте [SectionTitle] — с его же отступами.
class _SectionTitleSkeleton extends StatelessWidget {
  const _SectionTitleSkeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
      child: SkeletonBox(width: width, height: 18, radius: 9),
    );
  }
}

/// Лента заготовок вместо [EntityCarousel]: карточек ровно столько, чтобы
/// ряд был заполнен до правого края.
class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton({
    required this.height,
    required this.card,
    this.circle = false,
  });

  final double height;
  final double card;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final count = (width / (card + 12)).ceil();

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, _) => _CardSkeleton(circle: circle, width: card),
      ),
    );
  }
}
