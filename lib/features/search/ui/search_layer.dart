/// Search as a layer over whatever is open, not a page: the field and the round
/// platform button float above the mini player, the page stays dimmed under
/// them, and once there are results they take the screen, with big tabs (all,
/// tracks, artists, albums, playlists) on top.
///
/// It is a route in the open tab's navigator, so an artist or an album opens
/// over the results, the bars stay in place and Back works step by step. What
/// was found lives in [SearchSession] and outlasts the route.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/providers/registry.dart';
import '../../../features/customization/ui/app_background.dart';
import '../../../features/detail/detail_nav.dart';
import '../../../features/player/play_source.dart';
import '../../../features/player/ui/player_sheet.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/big_tabs.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/skeleton.dart';
import '../search_session.dart';

/// Whether search is open, even under a page opened from it. The tab bar lights
/// its icon by this.
final ValueNotifier<bool> searchOpen = ValueNotifier<bool>(false);

/// Whether the field itself is on top. While it is, the shell keeps the page
/// under it from shrinking with the keyboard.
final ValueNotifier<bool> searchOnTop = ValueNotifier<bool>(false);

/// The open layer. Only one at a time: the icon is its only way in.
_SearchRoute? _route;

/// The search icon: opens search; under a page opened from it, comes back to the
/// results; on the field, closes it.
void toggleSearch() {
  final route = _route;
  if (route == null) {
    final navigator = currentBranchNavigator();
    if (navigator != null) openSearchIn(navigator);
  } else if (route.isCurrent) {
    closeSearch();
  } else {
    route.navigator?.popUntil((r) => r == route);
  }
}

/// Opens search over what [navigator] shows.
void openSearchIn(NavigatorState navigator) {
  final route = _SearchRoute();
  _route = route;
  searchOpen.value = true;
  navigator.push(route);
}

/// Closes search with the pages opened from it.
void closeSearch() {
  final route = _route;
  final navigator = route?.navigator;
  if (route == null || navigator == null) return;
  navigator
    ..popUntil((r) => r == route)
    ..pop();
}

/// The router went elsewhere while search was open: the layer leaves, and what
/// the router just opened stays. Called from a build, so it waits for the frame.
void dropSearch() {
  if (_route == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final route = _route;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  });
}

class _SearchRoute extends PageRouteBuilder<void> {
  _SearchRoute()
    : super(
        opaque: false,
        pageBuilder: (_, _, _) => const _SearchLayer(),
        transitionsBuilder: detailPageTransition,
        transitionDuration: kTabTransition,
        reverseTransitionDuration: kTabTransition,
      );

  /// Hides the page below while results cover it: under a background picture
  /// the results have no fill of their own, and nothing below should animate
  /// behind them. The route stays see-through for the field.
  void cover(bool value) {
    if (overlayEntries.isNotEmpty) overlayEntries.last.opaque = value;
  }

  void _left() {
    if (_route != this) return;
    _route = null;
    searchOpen.value = false;
    searchOnTop.value = false;
  }

  @override
  bool didPop(void result) {
    cover(false);
    FocusManager.instance.primaryFocus?.unfocus();
    _left();
    return super.didPop(result);
  }

  @override
  void dispose() {
    _left();
    super.dispose();
  }
}

/// How far the field rises as it opens.
const double _kRise = 24;

/// Results fading in and out. Shorter than the route: the field is already
/// there, and the finger waits for what it asked for.
const Duration _kPanelFade = Duration(milliseconds: 160);

class _SearchLayer extends ConsumerStatefulWidget {
  const _SearchLayer();

  @override
  ConsumerState<_SearchLayer> createState() => _SearchLayerState();
}

class _SearchLayerState extends ConsumerState<_SearchLayer> {
  late final SearchSession _session = ref.read(searchSessionProvider);
  final FocusNode _focus = FocusNode();
  _SearchRoute? _own;

  @override
  void initState() {
    super.initState();
    // Typing replaces the last query.
    final text = _session.controller;
    text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.text.length,
    );
    _session.addListener(_onSession);
    playerSheetOpen.addListener(_onPlayer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_own == null) {
      _own = ModalRoute.of(context)! as _SearchRoute;
      _own!.animation!.addStatusListener(_onRouteStatus);
    }
    final top = ModalRoute.isCurrentOf(context) ?? true;
    // Back from a page gives focus back to the field, and the keyboard would
    // jump over the results.
    if (!top) _focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _route == _own) searchOnTop.value = top;
    });
  }

  @override
  void dispose() {
    _own?.animation?.removeStatusListener(_onRouteStatus);
    _session.removeListener(_onSession);
    playerSheetOpen.removeListener(_onPlayer);
    _focus.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!_session.showing) _own?.cover(false);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status.isCompleted && _session.showing) _own?.cover(true);
  }

  void _onPanelFaded() {
    if (_session.showing && (_own?.animation?.isCompleted ?? false)) {
      _own?.cover(true);
    }
  }

  /// The player comes up over the layer, and the keyboard would stay over it.
  void _onPlayer() {
    if (playerSheetOpen.value) _focus.unfocus();
  }

  Future<void> _run() async {
    final artist = await _session.run();
    if (artist != null && mounted) {
      openArtist(context, artist.id, initial: artist);
    }
  }

  /// A tap beside the field: with nothing typed there's nothing to lose, so it
  /// closes; otherwise only the keyboard goes, and the text stays.
  void _tapAside() {
    if (_session.controller.text.trim().isEmpty) {
      closeSearch();
    } else {
      _focus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final animation = ModalRoute.of(context)!.animation!;
    // The keyboard covers the bars, so the field goes up with it.
    final floor =
        math.max(bottomBarsInset(context), media.viewInsets.bottom) + kFloatGap;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tapAside,
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
        ),
        ListenableBuilder(
          listenable: _session,
          builder: (context, _) => AnimatedOpacity(
            opacity: _session.showing ? 1 : 0,
            duration: _kPanelFade,
            onEnd: _onPanelFaded,
            child: IgnorePointer(
              ignoring: !_session.showing,
              // Lists keep clear of the field by the inset they already read.
              child: MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    bottom: floor + kHeaderControl,
                  ),
                ),
                child: _Panel(
                  session: _session,
                  onScroll: _focus.unfocus,
                  onTapEmpty: _focus.unfocus,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: kFloatGap,
          right: kFloatGap,
          bottom: floor,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                0,
                _kRise * (1 - Curves.easeOutCubic.transform(animation.value)),
              ),
              child: child,
            ),
            // Its own group: the bar lies over the results' glass.
            child: GlassGroup(
              child: _SearchBar(
                session: _session,
                focus: _focus,
                onSubmit: _run,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The field and the platform button. It floats over any page, so both carry
/// the same line as the other floating bars.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.session,
    required this.focus,
    required this.onSubmit,
  });

  final SearchSession session;
  final FocusNode focus;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final controller = session.controller;
    return Row(
      children: [
        Expanded(
          child: HeaderSearchField(
            controller: controller,
            focusNode: focus,
            hint: context.l.searchHint,
            action: TextInputAction.search,
            borderSide: BorderSide(color: t.ovlLine),
            // An emptied field drops the results.
            onChanged: (text) {
              if (text.trim().isEmpty) session.clear();
            },
            onSubmitted: (_) => onSubmit(),
            trailing: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : Pressable(
                      onTap: () {
                        controller.clear();
                        session.clear();
                        focus.requestFocus();
                      },
                      child: BloomIcon(Bi.close, size: 18, color: t.muted),
                    ),
            ),
          ),
        ),
        const SizedBox(width: kFloatGap),
        // A platform change restarts the search: results belong wholly to the
        // chosen source, and old rows can't show under a new logo.
        _PlatformButton(onPicked: onSubmit),
      ],
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
      borderColor: context.bloom.ovlLine,
      child: provider == null ? null : PlatformLogo(provider.source, size: 23),
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

/// The results over the page, on the page's own fill.
class _Panel extends ConsumerWidget {
  const _Panel({
    required this.session,
    required this.onScroll,
    required this.onTapEmpty,
  });

  final SearchSession session;

  /// Scrolling means the typing is over: the keyboard goes.
  final VoidCallback onScroll;
  final VoidCallback onTapEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = session.activeTab;
    return Material(
      color: ref.watch(backgroundOnProvider)
          ? Colors.transparent
          : context.bloom.bg,
      child: GlassGroup(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTapEmpty,
          child: NotificationListener<UserScrollNotification>(
            onNotification: (_) {
              onScroll();
              return false;
            },
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  BigTabs<SearchTab>(
                    tabs: [
                      for (final tab in SearchTab.values)
                        BigTab(
                          tab,
                          tab.label(context.l),
                          has: session.has(tab),
                        ),
                    ],
                    current: tab,
                    onPick: session.pick,
                  ),
                  Expanded(child: _body(context, tab)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SearchTab tab) {
    final t = context.bloom;
    if (session.loading) return _SearchSkeleton(tab: tab);
    final error = session.error;
    if (error != null) {
      return Center(
        child: CenterNote(
          error,
          color: t.danger,
          padding: const EdgeInsets.all(24),
        ),
      );
    }
    if (!session.searched) return const SizedBox.shrink();
    if (session.results.isEmpty) {
      return Center(child: CenterNote(context.l.searchNothingFound));
    }
    return _ResultsView(
      results: session.results,
      tab: tab,
      query: session.lastQuery,
      onTab: session.pick,
    );
  }
}

/// How many tracks "all" shows; the rest are the tab's.
const int _tracksPreview = 4;

/// The gap over a kind's own tab, as in the library.
const double _tabTop = 18;

class _ResultsView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l = context.l;
    Widget setGrid(List<Playlist> sets) => CardGrid(
      columns: 2,
      caption: setCaption(sets),
      top: _tabTop,
      itemCount: sets.length,
      itemBuilder: (context, i) => SetCard(set: sets[i], size: null),
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
          itemBuilder: (context, i) =>
              ArtistCard(artist: artists[i], size: null, centerLabel: true),
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
      builder: (i) => SetCard(set: sets[i]),
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
            ),
          ),
      ],
      if (all && results.artists.isNotEmpty) ...[
        label(SearchTab.artists),
        EntityCarousel(
          height: 168,
          padding: 16,
          itemCount: results.artists.length,
          builder: (i) =>
              ArtistCard(artist: results.artists[i], centerLabel: true),
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
      // The sections keep to the sides themselves; under them the bars and the
      // field float over the results.
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
        const CarouselSkeleton(height: 212, card: kCardWidth),
      ],
    );
  }
}
