/// Recent in search: queries and opened cards. Queries are plain strings, with
/// no timestamp: they're two separate blocks here, each in its own order.
///
/// Opened ones are WHOLE entities: `Track`, `Artist` and `Playlist` already do
/// JSON, and such an entry opens a page by the same call as from results, with
/// cover, owner and `sourceData`, and no request to the platform.
///
/// This is HISTORY, not a setting: its keys aren't in `kSettingsKeys`, so a
/// settings reset leaves them and only a full reset erases them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/entities/entities.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;

/// Queries remembered.
const int kRecentSearchMax = 8;

/// Opened cards remembered.
const int kRecentItemMax = 12;

const String _key = 'recentSearches';
const String _itemsKey = 'recentItems';

final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
      RecentSearchesController.new,
    );

class RecentSearchesController extends Notifier<List<String>> {
  @override
  List<String> build() =>
      ref.read(jsonStoreProvider).readList(_key).whereType<String>().toList();

  void _save() => ref.read(jsonStoreProvider).write(_key, state);

  /// Remembers a query: on top, no duplicates, up to [kRecentSearchMax]. A
  /// repeat is found ignoring case, but the LATEST spelling stays: the user
  /// just typed it.
  void push(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final lower = q.toLowerCase();
    state = [
      q,
      ...state.where((x) => x.toLowerCase() != lower),
    ].take(kRecentSearchMax).toList();
    _save();
  }

  void remove(String query) {
    final next = state.where((x) => x != query).toList();
    if (next.length == state.length) return;
    state = next;
    _save();
  }

  void clear() {
    if (state.isEmpty) return;
    state = const [];
    _save();
  }
}

/// A card opened from results. Tracks land here too, with opening meaning
/// starting: a track has no page.
sealed class RecentItem {
  const RecentItem();

  /// Dedupe key. The type is a must: on Yandex an album's and its title track's
  /// ids differ only by the entity prefix, and on SoundCloud a playlist and
  /// track count from separate counters and may match.
  String get key;

  Map<String, dynamic> toJson();

  static RecentItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final data = json['data'];
    switch (json['kind']) {
      case 'track':
        final track = Track.fromJson(data);
        return track == null ? null : RecentTrack(track);
      case 'artist':
        final artist = Artist.fromJson(data);
        return artist == null ? null : RecentArtist(artist);
      case 'set':
        final set = Playlist.fromJson(data);
        return set == null ? null : RecentSet(set);
      default:
        return null;
    }
  }
}

final class RecentTrack extends RecentItem {
  const RecentTrack(this.track);

  final Track track;

  @override
  String get key => 'track:${track.id}';

  @override
  Map<String, dynamic> toJson() => {'kind': 'track', 'data': track.toJson()};
}

final class RecentArtist extends RecentItem {
  const RecentArtist(this.artist);

  final Artist artist;

  @override
  String get key => 'artist:${artist.id}';

  @override
  Map<String, dynamic> toJson() => {'kind': 'artist', 'data': artist.toJson()};
}

/// Album or playlist, one entity as everywhere, flagged by [Playlist.isAlbum].
final class RecentSet extends RecentItem {
  const RecentSet(this.set);

  final Playlist set;

  @override
  String get key => 'set:${set.id}';

  @override
  Map<String, dynamic> toJson() => {'kind': 'set', 'data': set.toJson()};
}

final recentItemsProvider =
    NotifierProvider<RecentItemsController, List<RecentItem>>(
      RecentItemsController.new,
    );

class RecentItemsController extends Notifier<List<RecentItem>> {
  @override
  List<RecentItem> build() => ref
      .read(jsonStoreProvider)
      .readList(_itemsKey)
      .map(RecentItem.fromJson)
      .nonNulls
      .toList();

  void _save() => ref.read(jsonStoreProvider).write(_itemsKey, [
    for (final item in state) item.toJson(),
  ]);

  /// Remembers what's opened: on top, no duplicates, up to [kRecentItemMax]. A
  /// fresh entry overwrites the old whole: a card from results usually has more
  /// fields than the same entity a week ago.
  void push(RecentItem item) {
    state = [
      item,
      ...state.where((x) => x.key != item.key),
    ].take(kRecentItemMax).toList();
    _save();
  }

  void remove(RecentItem item) {
    final next = state.where((x) => x.key != item.key).toList();
    if (next.length == state.length) return;
    state = next;
    _save();
  }

  void clear() {
    if (state.isEmpty) return;
    state = const [];
    _save();
  }
}
