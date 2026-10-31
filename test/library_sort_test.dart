/// Library order: three sorts, the dragged order and the pinned. Place and pin
/// live in the rows; sort, tab and view are settings.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/library/lib_order_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

/// A library card as the sort sees it.
class _Card {
  const _Card(this.name, this.sidePos, this.pinned);
  final String name;
  final int sidePos;
  final bool pinned;
}

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Two playlists and a follow, made in this order.
({String beta, String alpha}) _seed(ProviderContainer c) {
  final lib = c.read(libraryProvider.notifier);
  final beta = lib.createPlaylist('Бета').id;
  final alpha = lib.createPlaylist('Альфа').id;
  lib.toggleFollow(
    const Artist(
      id: 'sc:artist:1',
      name: 'Гамма',
      source: MusicSource.soundcloud,
    ),
  );
  return (beta: beta, alpha: alpha);
}

/// Each kind laid out as on the library screen, by names.
List<String> _names(ProviderContainer c) {
  final lib = c.read(libraryProvider);
  final order = c.read(libOrderProvider);
  List<String> arrange(List<_Card> cards) => order
      .arrange(
        cards,
        name: (e) => e.name,
        sidePos: (e) => e.sidePos,
        pinned: (e) => e.pinned,
      )
      .map((e) => e.name)
      .toList();
  return [
    ...arrange([
      for (final p in lib.playlists) _Card(p.name, p.sidePos, p.pinned),
    ]),
    ...arrange([
      for (final f in lib.follows) _Card(f.artist.name, f.sidePos, f.pinned),
    ]),
  ];
}

const _artistKey = 'artist:sc:artist:1';

void main() {
  test('by default new cards stand in the order they were made', () {
    final c = _container(JsonStore.memory());
    _seed(c);
    expect(_names(c), ['Бета', 'Альфа', 'Гамма']);
  });

  test('dragging writes the places and survives a restart', () {
    final store = JsonStore.memory();
    final first = _container(store);
    final ids = _seed(first);
    first.read(libraryProvider.notifier).reorderCards([
      libKeyOfPlaylist(ids.alpha),
      libKeyOfPlaylist(ids.beta),
    ]);
    expect(_names(first), ['Альфа', 'Бета', 'Гамма']);

    expect(_names(_container(store)), ['Альфа', 'Бета', 'Гамма']);
  });

  test('the name sort goes both ways', () {
    final c = _container(JsonStore.memory());
    _seed(c);
    final order = c.read(libOrderProvider.notifier);

    order.setSort(LibSort.nameAsc);
    expect(_names(c), ['Альфа', 'Бета', 'Гамма']);

    order.setSort(LibSort.nameDesc);
    expect(_names(c), ['Бета', 'Альфа', 'Гамма']);
  });

  test('the pinned lead in any sort and are kept in the rows', () {
    final store = JsonStore.memory();
    final c = _container(store);
    final ids = _seed(c);
    final lib = c.read(libraryProvider.notifier);
    final alpha = libKeyOfPlaylist(ids.alpha);
    lib.setPinned(alpha, true);

    expect(_names(c).first, 'Альфа');

    c.read(libOrderProvider.notifier).setSort(LibSort.nameDesc);
    expect(_names(c).first, 'Альфа');
    expect(_names(_container(store)).first, 'Альфа');

    // Unpinned, it goes back to its place.
    lib.setPinned(alpha, false);
    expect(_names(c), ['Бета', 'Альфа', 'Гамма']);
  });

  test('pinning an artist goes through its row too', () {
    final c = _container(JsonStore.memory());
    _seed(c);
    c.read(libraryProvider.notifier).setPinned(_artistKey, true);
    expect(c.read(libraryProvider).follows.single.pinned, isTrue);
  });

  test('sort, tab and view survive a restart', () {
    final store = JsonStore.memory();
    _container(store).read(libOrderProvider.notifier)
      ..setSort(LibSort.nameDesc)
      ..setTab(LibTab.artists)
      ..setGrid(true);

    final state = _container(store).read(libOrderProvider);
    expect(state.sort, LibSort.nameDesc);
    expect(state.tab, LibTab.artists);
    expect(state.grid, isTrue);
  });

  test('with nothing saved: "all" as rows', () {
    final state = _container(JsonStore.memory()).read(libOrderProvider);
    expect(state.tab, LibTab.all);
    expect(state.grid, isFalse);
  });
}
