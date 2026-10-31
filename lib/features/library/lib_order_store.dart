/// How the library is shown: sort, tab and list or grid. Settings, not data:
/// a card's place and pin live in its own row ([LibOrderState.arrange] lays
/// them out). "Default" is the order made by dragging; the pinned always lead.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../../core/store/library_store.dart' show UserPlaylist;
import '../../shared/ui/bloom_icon.dart';

enum LibSort { manual, nameAsc, nameDesc }

enum LibTab { all, playlists, artists }

extension LibTabMeta on LibTab {
  String label(AppLocalizations l) => switch (this) {
    LibTab.all => l.libTabAll,
    LibTab.playlists => l.commonPlaylists,
    LibTab.artists => l.libTabArtists,
  };
}

LibTab _tabFromId(Object? id) =>
    LibTab.values.firstWhere((t) => t.name == id, orElse: () => LibTab.all);

extension LibSortMeta on LibSort {
  String label(AppLocalizations l) => switch (this) {
    LibSort.manual => l.libSortManual,
    LibSort.nameAsc => l.libSortNameAsc,
    LibSort.nameDesc => l.libSortNameDesc,
  };

  BloomGlyph get icon => switch (this) {
    LibSort.manual => Bi.reorder,
    LibSort.nameAsc => Bi.sortFromTopToBottom,
    LibSort.nameDesc => Bi.sortFromBottomToTop,
  };

  String get id => switch (this) {
    LibSort.manual => 'default',
    LibSort.nameAsc => 'name-asc',
    LibSort.nameDesc => 'name-desc',
  };
}

LibSort _sortFromId(Object? id) =>
    LibSort.values.firstWhere((s) => s.id == id, orElse: () => LibSort.manual);

class LibOrderState {
  const LibOrderState({
    this.sort = LibSort.manual,
    this.tab = LibTab.all,
    this.grid = false,
  });

  final LibSort sort;
  final LibTab tab;

  /// Cards instead of rows.
  final bool grid;

  LibOrderState copyWith({LibSort? sort, LibTab? tab, bool? grid}) =>
      LibOrderState(
        sort: sort ?? this.sort,
        tab: tab ?? this.tab,
        grid: grid ?? this.grid,
      );

  /// Lays out one kind of cards: pinned first, then by the sort. I compare the
  /// original places last, since Dart's sort isn't stable.
  List<T> arrange<T>(
    List<T> items, {
    required String Function(T) name,
    required int Function(T) sidePos,
    required bool Function(T) pinned,
  }) {
    final indexed = [
      for (var i = 0; i < items.length; i++) (item: items[i], at: i),
    ];
    int byName(T a, T b) =>
        name(a).toLowerCase().compareTo(name(b).toLowerCase());
    indexed.sort((a, b) {
      final by = switch (sort) {
        LibSort.manual => sidePos(a.item).compareTo(sidePos(b.item)),
        LibSort.nameAsc => byName(a.item, b.item),
        LibSort.nameDesc => byName(b.item, a.item),
      };
      return by != 0 ? by : a.at.compareTo(b.at);
    });
    final sorted = indexed.map((e) => e.item).toList();
    return [...sorted.where(pinned), ...sorted.where((e) => !pinned(e))];
  }

  List<UserPlaylist> arrangePlaylists(List<UserPlaylist> playlists) => arrange(
    playlists,
    name: (p) => p.name,
    sidePos: (p) => p.sidePos,
    pinned: (p) => p.pinned,
  );
}

final libOrderProvider = NotifierProvider<LibOrderController, LibOrderState>(
  LibOrderController.new,
);

class LibOrderController extends Notifier<LibOrderState> {
  @override
  LibOrderState build() {
    final raw = ref.read(jsonStoreProvider).readMap('libOrder');
    return LibOrderState(
      sort: _sortFromId(raw['sort']),
      tab: _tabFromId(raw['tab']),
      grid: raw['grid'] == true,
    );
  }

  void _set(LibOrderState next) {
    state = next;
    ref.read(jsonStoreProvider).write('libOrder', {
      'sort': next.sort.id,
      'tab': next.tab.name,
      'grid': next.grid,
    });
  }

  void setSort(LibSort sort) {
    if (sort != state.sort) _set(state.copyWith(sort: sort));
  }

  void setTab(LibTab tab) {
    if (tab != state.tab) _set(state.copyWith(tab: tab));
  }

  void setGrid(bool grid) {
    if (grid != state.grid) _set(state.copyWith(grid: grid));
  }
}
