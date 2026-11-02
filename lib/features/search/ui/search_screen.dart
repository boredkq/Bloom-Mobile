/// Search page: a pill field and a round platform button; big tabs under them
/// (all, tracks, artists, albums, playlists), and results below.
///
/// The screen knows nothing of platforms: it asks [ProviderRegistry.searchAll]
/// and draws neutral entities. Tabs split results ALREADY received, with no
/// network trip: a provider gives all sections in one run.
///
/// Links get pasted here too: a string that looks like a link goes to
/// `resolveUrlAny` instead of search, and a track, playlist or album becomes
/// one result card; an artist's or a listener's link opens their page at once.
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
import '../../recognition/ui/recognition_sheet.dart';
import '../recent_store.dart';

/// Whether a string looks like a link. Domains get caught with no protocol too,
/// since that's how they get pasted. The exact parsing is the platform's; this
/// only picks the branch.
bool looksLikeUrl(String query) =>
    RegExp(r'^https?://', caseSensitive: false).hasMatch(query) ||
    RegExp(
      r'(^|\.)(soundcloud\.com|snd\.sc|music\.yandex\.[a-z]+|music\.youtube\.com|youtu\.be)/',
      caseSensitive: false,
    ).hasMatch(query);

/// A resolved link as results of one card.
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

  /// Whether there's been a run, telling not searched yet from found nothing:
  /// the registry turns provider errors into empty results, and with no flag a
  /// failed search looks like an untouched screen.
  bool _searched = false;

  /// Query number: an answer to a stale search mustn't override a fresh one.
  int _generation = 0;

  /// Query the RESULTS stand for, not the field's text: that's being edited for
  /// the next search, and the queue comes from what's on screen.
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
    // Remembered at the start, so a query lands in recents even with empty
    // results: repeating a typo beats typing it all again.
    ref.read(recentSearchesProvider.notifier).push(query);
    final gen = ++_generation;
    setState(() {
      _lastQuery = query;
      _loading = true;
      _error = null;
    });

    try {
      // A link resolves first. If unparsed (a platform not connected, a typo)
      // it silently falls to ordinary search: the string was typed in a search
      // field, and results beat an empty error screen.
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

  /// A tap on a recent query: fills the field and searches right away. The
  /// keyboard goes: it would take half the screen over fresh results, and a
  /// filled query rarely needs editing.
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
                // As its own tab search is a branch root with nowhere to
                // return: no arrow, and the field takes the whole width. Opened
                // as a page, the arrow is there.
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
                const SizedBox(width: 8),
                CircleIconButton(
                  icon: Bi.soundwave,
                  onTap: () => showRecognitionSheet(context, ref),
                ),
                const SizedBox(width: 8),
                // A platform change restarts the search: results belong wholly
                // to the chosen source, and old rows can't show under a new
                // logo.
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
      // Before the first query, recents in place of a stand-in. Not after a
      // failed search: nothing found answers what was typed, and swapping in
      // history hides that result.
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

/// Recent on an empty search screen: opened cards as a strip first, queries as
/// rows below.
///
/// Queries are rows rather than pills: a query can be long (бой с тенью 3
/// саундтрек), a pill shows only an ellipsis, and a past query gets recognised
/// by its tail.
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
      // Room below for the shell's bars, floating over the content.
      padding: EdgeInsets.fromLTRB(8, 4, 8, 12 + bottomBarsInset(context)),
      children: [
        if (items.isNotEmpty) ...[
          _RecentHeader(
            title: context.l.searchRecentOpened,
            onClear: () => ref.read(recentItemsProvider.notifier).clear(),
          ),
          // Height as in the results' playlist strip: the same cards, standing
          // alike.
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

/// A recently opened card: a cover (a circle for an artist), a title and type.
/// Its own rather than [SetCard], [ArtistCard] or [TrackCard]: one strip holds
/// different entities, needing one silhouette and one remove gesture. The
/// caption is the type, not the author: cover and title are recognisable, but
/// not whether it's an album or a track.
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

/// Opens a recent item: an artist or set page, while a track just plays. The
/// entry rises to the top. No request to the platform: the list holds the
/// entity from results, with cover, owner and `sourceData`.
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

/// One-action sheet: Remove from recent, for a long-pressed card.
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
      iconSize: 20,
      child: provider == null
          ? null
          : Center(
              child: ClipOval(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: Center(
                    child: PlatformLogo(provider.source, size: 18),
                  ),
                ),
              ),
            ),
      onTap: () => _pickSource(context, ref, onPicked),
    );
  }
}

/// Search source picker sheet. Platforms are separate cards with gaps rather
/// than one block's items: brand logos are multicoloured, and on one panel read
/// as mush. No title: the mark and name say it.
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

/// Records a card opened from results. Called from result tiles, which home and
/// the library share, so through its `onOpen` rather than inside: only search
/// keeps recents.
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

  /// The query, also the source caption in the player's pill.
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

/// Skeleton for All: a caption and track previews, then artist and album
/// strips, in [_ResultsView]'s section order.
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
