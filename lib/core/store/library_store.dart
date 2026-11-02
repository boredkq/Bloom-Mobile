/// Library: all tracks, favourites, playlists and follows, over the `lists`,
/// `list_tracks` and `follows` tables. All tracks (`lib`), favourites (`fav`)
/// and playlists are one table of ordered lists. Each row has its own place
/// (`pos`) and add time (`added_at`): a drag changes only the place, and recent
/// likes still know when they were made.
///
/// Invariant: a track in a playlist or favourites is a track in the library
/// ([_addTo] puts it there too), and one removed from the library goes
/// everywhere.
///
/// [LibraryState] is a snapshot for screens: read synchronously, refreshed
/// after each edit. It holds only tracks in some list; a snapshot of any track
/// heard lies in the database's `tracks` (see [TrackStore]).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db.dart';
import '../db/track_store.dart';
import '../entities/entities.dart';
import '../l10n/l10n.dart';

/// Ids of the system lists.
const String kLibList = 'lib';
const String kFavList = 'fav';

/// A source for Refresh tracks: an outside collection tied to a playlist, being
/// a playlist, album or account's likes on any platform. Any number, from
/// different platforms.
///
/// Refresh goes by the collection's [id] on [provider], not by link; the link
/// is only for display. Two ties to one collection have one [id].
class PlSourceRef {
  const PlSourceRef({
    required this.id,
    required this.provider,
    this.url = '',
    this.title = '',
    this.owner = '',
    this.kind = 'playlist',
    this.cover = '',
  });

  /// A platform page's collection as a source.
  factory PlSourceRef.of(Playlist set) => PlSourceRef(
    id: set.id,
    provider: set.source.code,
    url: set.sourceUrl ?? '',
    title: set.title,
    owner: set.ownerName ?? '',
    kind: set.isAlbum ? 'album' : 'playlist',
    cover: set.cover ?? '',
  );

  /// Collection's global id: `sc:set:1`, `sc:likes:1`, `ym:album:1`,
  /// `ytm:pl:x`.
  final String id;

  /// Platform code as in the database: `sc`, `ym`, `ytm`.
  final String provider;
  final String url;

  /// Title and owner at tie time, only for the list row.
  final String title;
  final String owner;

  /// `album` or `playlist` (likes are `playlist` too).
  final String kind;
  final String cover;

  bool get isAlbum => kind == 'album';

  PlSourceRef copyWith({
    String? url,
    String? title,
    String? owner,
    String? cover,
  }) => PlSourceRef(
    id: id,
    provider: provider,
    url: url ?? this.url,
    title: title ?? this.title,
    owner: owner ?? this.owner,
    kind: kind,
    cover: cover ?? this.cover,
  );

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'owner': owner,
    'provider': provider,
    'id': id,
    'kind': kind,
    'cover': cover,
  };

  static PlSourceRef? fromJson(Object? json) {
    if (json is! Map) return null;
    String s(String key) => json[key] is String ? json[key] as String : '';
    if (s('id').isEmpty || s('provider').isEmpty) return null;
    return PlSourceRef(
      id: s('id'),
      provider: s('provider'),
      url: s('url'),
      title: s('title'),
      owner: s('owner'),
      kind: s('kind') == 'album' ? 'album' : 'playlist',
      cover: s('cover'),
    );
  }
}

class UserPlaylist {
  final String id;
  final String name;

  /// Contents by place, first on top.
  final List<String> trackIds;
  final String? cover;
  final String? description;

  /// Where Refresh tracks pulls new ones from. Empty: the playlist is the
  /// user's own, with nothing to refresh from.
  final List<PlSourceRef> sources;
  final int createdAt;

  /// Card's place on the library screen (`side_pos`); 0 if it hasn't had one.
  final int sidePos;

  /// Pinned: first in the library under any sort.
  final bool pinned;

  /// Takes part in scheduled auto-update (`auto_refresh`).
  final bool autoRefresh;

  const UserPlaylist({
    required this.id,
    required this.name,
    this.trackIds = const [],
    this.cover,
    this.description,
    this.sources = const [],
    this.createdAt = 0,
    this.sidePos = 0,
    this.pinned = false,
    this.autoRefresh = false,
  });

  UserPlaylist copyWith({List<String>? trackIds}) => UserPlaylist(
    id: id,
    name: name,
    trackIds: trackIds ?? this.trackIds,
    cover: cover,
    description: description,
    sources: sources,
    createdAt: createdAt,
    sidePos: sidePos,
    pinned: pinned,
    autoRefresh: autoRefresh,
  );
}

class FollowedArtist {
  final Artist artist;
  final int followedAt;

  /// Card place and pin, as for a playlist, in one row with it.
  final int sidePos;
  final bool pinned;

  const FollowedArtist({
    required this.artist,
    required this.followedAt,
    this.sidePos = 0,
    this.pinned = false,
  });
}

/// Library card key: kind and id together, or a playlist and artist with one id
/// would be one card.
String libKeyOfPlaylist(String id) => 'playlist:$id';
String libKeyOfArtist(String id) => 'artist:$id';

class LibraryState {
  /// Tracks in at least one list, id to track.
  final Map<String, Track> tracks;

  /// All tracks by place, first on top.
  final List<String> libIds;

  /// Id to when the track entered the library.
  final Map<String, int> inLib;

  /// Favourites by place, first on top.
  final List<String> favIds;

  /// Id to when it was liked.
  final Map<String, int> favs;

  final List<UserPlaylist> playlists;
  final List<FollowedArtist> follows;

  const LibraryState({
    this.tracks = const {},
    this.libIds = const [],
    this.inLib = const {},
    this.favIds = const [],
    this.favs = const {},
    this.playlists = const [],
    this.follows = const [],
  });

  bool isFav(String trackId) => favs.containsKey(trackId);
  bool isInLib(String trackId) => inLib.containsKey(trackId);
  bool isFollowing(String artistId) =>
      follows.any((f) => f.artist.id == artistId);

  List<Track> get allTracks => [for (final id in libIds) ?tracks[id]];

  List<Track> get favTracks => [for (final id in favIds) ?tracks[id]];

  List<Track> tracksOf(UserPlaylist pl) => [
    for (final id in pl.trackIds) ?tracks[id],
  ];
}

final libraryProvider = NotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

class LibraryController extends Notifier<LibraryState> {
  BloomDb get _db => ref.read(dbProvider);
  TrackStore get _store => TrackStore(_db);

  @override
  LibraryState build() => _read(const {});

  /// Re-reads lists from the database. Tracks already in [known] aren't read
  /// again: an edit touches a couple of rows, not the whole library.
  LibraryState _read(Map<String, Track> known) {
    final members = <String, List<String>>{};
    final added = <String, Map<String, int>>{};
    for (final r in _db.select(
      'SELECT list_id, track_id, added_at FROM list_tracks ORDER BY list_id, pos',
    )) {
      final list = r['list_id'] as String;
      final id = r['track_id'] as String;
      (members[list] ??= []).add(id);
      (added[list] ??= {})[id] = r['added_at'] as int;
    }

    final ids = {for (final m in members.values) ...m};
    final tracks = <String, Track>{for (final id in ids) id: ?known[id]};
    final missing = [
      for (final id in ids)
        if (!tracks.containsKey(id)) id,
    ];
    for (final t in _store.get(missing)) {
      tracks[t.id] = t;
    }

    final playlists = [
      for (final r in _db.select(
        "SELECT id, name, description, cover, sources, auto_refresh, created_at, side_pos, pinned FROM lists WHERE kind = 'playlist' ORDER BY pinned DESC, side_pos, created_at",
      ))
        UserPlaylist(
          id: r['id'] as String,
          name: r['name'] as String,
          description: _text(r['description']),
          cover: _text(r['cover']),
          sources: _sources(r['sources'] as String?),
          createdAt: r['created_at'] as int,
          sidePos: r['side_pos'] as int,
          pinned: r['pinned'] == 1,
          autoRefresh: r['auto_refresh'] == 1,
          trackIds: members[r['id']] ?? const [],
        ),
    ];

    final follows = [
      for (final r in _db.select(
        'SELECT id, name, avatar, extra, at, side_pos, pinned FROM follows ORDER BY pinned DESC, side_pos, at',
      ))
        FollowedArtist(
          artist: _artistOfRow(r),
          followedAt: r['at'] as int,
          sidePos: r['side_pos'] as int,
          pinned: r['pinned'] == 1,
        ),
    ];

    return LibraryState(
      tracks: tracks,
      libIds: members[kLibList] ?? const [],
      inLib: added[kLibList] ?? const {},
      favIds: members[kFavList] ?? const [],
      favs: added[kFavList] ?? const {},
      playlists: playlists,
      follows: follows,
    );
  }

  void _refresh() => state = _read(state.tracks);

  /// Re-reads all, tracks too: sync changed the rows.
  void reload() => state = _read(const {});

  static String? _text(Object? v) => v is String && v.isNotEmpty ? v : null;

  static List<PlSourceRef> _sources(String? raw) {
    try {
      final list = jsonDecode(raw ?? '[]');
      return [
        if (list is List)
          for (final s in list) ?PlSourceRef.fromJson(s),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Artist _artistOfRow(Map<String, Object?> r) {
    final id = r['id'] as String;
    Map<String, dynamic> x;
    try {
      x = (jsonDecode(r['extra'] as String? ?? '{}') as Map)
          .cast<String, dynamic>();
    } catch (_) {
      x = const {};
    }
    return Artist(
      id: id,
      name: r['name'] as String? ?? '',
      avatar: _text(r['avatar']),
      source: MusicSource.fromId(id),
      permalink: _text(x['permalink']),
      fullName: _text(x['fullName']),
      verified: x['verified'] == true,
    );
  }

  // ── Lists ───────────────────────────────────────────────────────────────

  /// Next card place on the library screen, shared by all cards.
  int _nextSidePos() =>
      (_db.value('''SELECT max(coalesce((SELECT max(side_pos) FROM lists), 0),
          coalesce((SELECT max(side_pos) FROM folders), 0),
          coalesce((SELECT max(side_pos) FROM follows), 0)) + 1''')
          as int?) ??
      1;

  bool _listExists(String list) =>
      _db.value('SELECT 1 FROM lists WHERE id = ?', [list]) != null;

  /// Puts tracks not yet there into a list, always on top, in batch order.
  /// Returns how many were added. A track in a list is a track in the library:
  /// new ones go to the start of all tracks.
  int _addTo(String list, List<Track> tracks) {
    if (!_listExists(list)) return 0;
    return _db.tx(() {
      _store.put(tracks);
      final have = {
        for (final r in _db.select(
          'SELECT track_id FROM list_tracks WHERE list_id = ?',
          [list],
        ))
          r['track_id'] as String,
      };
      final fresh = [
        for (final t in tracks)
          if (t.id.isNotEmpty && have.add(t.id)) t,
      ];
      if (fresh.isEmpty) return 0;
      final now = BloomDb.now();
      var pos =
          (_db.value(
                'SELECT coalesce(min(pos), 0) FROM list_tracks WHERE list_id = ?',
                [list],
              )
              as int) -
          fresh.length;
      final insert = _db.prepare(
        'INSERT INTO list_tracks (list_id, track_id, pos, added_at) VALUES (?, ?, ?, ?)',
      );
      try {
        for (final t in fresh) {
          insert.execute([list, t.id, pos++, now]);
        }
      } finally {
        insert.close();
      }
      _touch(list);
      if (list != kLibList) _addTo(kLibList, fresh);
      return fresh.length;
    });
  }

  /// Removes tracks from a list; from the library means from everywhere.
  void _removeFrom(String list, Iterable<String> trackIds) {
    _db.tx(() {
      for (final id in trackIds) {
        _db.exec('DELETE FROM list_tracks WHERE list_id = ? AND track_id = ?', [
          list,
          id,
        ]);
        if (list == kLibList) {
          _db.exec('DELETE FROM list_tracks WHERE track_id = ?', [id]);
        }
      }
      _touch(list);
    });
  }

  /// New list order: [ids] at places 0…n-1; what's not in [ids] leaves
  /// ([_removeFrom]). Add times stay.
  void _setOrder(String list, List<String> ids) {
    _db.tx(() {
      final was = {
        for (final r in _db.select(
          'SELECT track_id FROM list_tracks WHERE list_id = ?',
          [list],
        ))
          r['track_id'] as String,
      };
      _removeFrom(list, was.difference(ids.toSet()));
      final set = _db.prepare(
        'UPDATE list_tracks SET pos = ? WHERE list_id = ? AND track_id = ?',
      );
      try {
        for (var i = 0; i < ids.length; i++) {
          set.execute([i, list, ids[i]]);
        }
      } finally {
        set.close();
      }
      _touch(list);
    });
  }

  void _touch(String list) => _db.exec(
    'UPDATE lists SET updated_at = ? WHERE id = ?',
    [BloomDb.now(), list],
  );

  void _updateList(String id, Map<String, Object?> columns) {
    if (columns.isEmpty) return;
    final sets = [for (final c in columns.keys) '$c = ?', 'updated_at = ?'];
    _db.exec('UPDATE lists SET ${sets.join(', ')} WHERE id = ?', [
      ...columns.values,
      BloomDb.now(),
      id,
    ]);
    _refresh();
  }

  // ── Library (all tracks) ────────────────────────────────────────────────

  /// Adds tracks to the library, new on top; those present keep their place.
  /// Returns how many really got added.
  int addToLibrary(Iterable<Track> batch) {
    final n = _addTo(kLibList, batch.toList());
    _refresh();
    return n;
  }

  /// Deletes a track everywhere: library, likes, all playlists. The play log
  /// stays: that it played then remains true, and the database keeps the
  /// snapshot for history.
  void deleteTrack(String trackId) {
    _db.tx(() {
      _removeFrom(kLibList, [trackId]);
      _store.prune();
    });
    _refresh();
  }

  /// Replaces a track with another platform's version. It has a new id, and all
  /// references (list places, like, plays, dislike) follow it
  /// ([TrackStore.rekey]), with their places and add times.
  void replaceTrack(String oldId, Track next) {
    if (oldId == next.id) return;
    _db.tx(() {
      _store.rekey(oldId, next.id);
      _store.put([next]);
    });
    state = _read({
      for (final e in state.tracks.entries)
        if (e.key != oldId) e.key: e.value,
      next.id: next,
    });
  }

  /// Snapshot of the whole library, for Undo after a swipe delete.
  LibraryState snapshot() => state;

  /// Restores lists as in [snap]: contents, places and add times. Playlists
  /// gone since come back too.
  void restoreSnapshot(LibraryState snap) {
    _db.tx(() {
      _store.put(snap.tracks.values);
      void put(String list, List<String> ids, Map<String, int> added) {
        _db.exec('DELETE FROM list_tracks WHERE list_id = ?', [list]);
        final now = BloomDb.now();
        for (var i = 0; i < ids.length; i++) {
          if (!snap.tracks.containsKey(ids[i])) continue;
          _db.exec(
            'INSERT INTO list_tracks (list_id, track_id, pos, added_at) VALUES (?, ?, ?, ?)',
            [list, ids[i], i, added[ids[i]] ?? now],
          );
        }
      }

      put(kLibList, snap.libIds, snap.inLib);
      put(kFavList, snap.favIds, snap.favs);
      for (final pl in snap.playlists) {
        if (!_listExists(pl.id)) _insertPlaylist(pl);
        put(pl.id, pl.trackIds, const {});
      }
    });
    _refresh();
  }

  /// Edits all tracks as a whole: [ids] is the new contents AND order, first on
  /// top. What dropped out is deleted throughout, like [deleteTrack].
  void setLibraryTracks(List<String> ids) {
    _db.tx(() {
      _setOrder(kLibList, ids);
      _store.prune();
    });
    _refresh();
  }

  // ── Favourites ──────────────────────────────────────────────────────────

  /// Toggles a like. A new like goes on top of favourites and into the library.
  bool toggleFav(Track track) {
    final on = !state.isFav(track.id);
    if (on) {
      _addTo(kFavList, [track]);
    } else {
      _removeFrom(kFavList, [track.id]);
    }
    _refresh();
    return on;
  }

  /// Likes a batch at once (link import into favourites): on top, in batch
  /// order. Returns how many likes were added.
  int addToFavorites(List<Track> batch) {
    final n = _addTo(kFavList, batch);
    _refresh();
    return n;
  }

  /// Edits favourites as a whole: [ids] is the new contents AND order. A
  /// removed like doesn't drop the track from the library.
  void setFavTracks(List<String> ids) {
    _setOrder(kFavList, ids);
    _refresh();
  }

  // ── Playlists ───────────────────────────────────────────────────────────

  UserPlaylist createPlaylist(
    String name, {
    List<Track> tracks = const [],
    String? cover,
    String? description,
    PlSourceRef? source,
  }) {
    final pl = UserPlaylist(
      description: description?.trim().isEmpty ?? true
          ? null
          : description!.trim(),
      id: _freeId(BloomDb.now()),
      // A playlist's name is data, not UI: it stays as created. So the default
      // comes in the language of that moment and is never translated later.
      name: name.trim().isEmpty
          ? (globalL10n?.commonNewPlaylist ?? 'New playlist')
          : name.trim(),
      cover: cover ?? (tracks.isEmpty ? null : tracks.first.cover),
      // The collection a playlist came from becomes its first refresh source;
      // others are tied by hand in the editor.
      sources: [?source],
      createdAt: BloomDb.now(),
    );
    _db.tx(() {
      _insertPlaylist(pl);
      _addTo(pl.id, tracks);
    });
    _refresh();
    return state.playlists.firstWhere((p) => p.id == pl.id);
  }

  void _insertPlaylist(UserPlaylist pl) {
    final now = BloomDb.now();
    _db.exec(
      "INSERT INTO lists (id, kind, name, description, cover, sources, auto_refresh, created_at, updated_at, side_pos, pinned) VALUES (?, 'playlist', ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [
        pl.id,
        pl.name,
        pl.description ?? '',
        pl.cover ?? '',
        jsonEncode([for (final s in pl.sources) s.toJson()]),
        pl.autoRefresh ? 1 : 0,
        pl.createdAt == 0 ? now : pl.createdAt,
        now,
        // A restored one (Undo) returns to its old place.
        pl.sidePos > 0 ? pl.sidePos : _nextSidePos(),
        pl.pinned ? 1 : 0,
      ],
    );
  }

  /// A free playlist id: `pl` plus the time in base36, or the next number if
  /// taken (several in one millisecond, on file import).
  String _freeId(int at) {
    var n = at;
    while (_listExists('pl${n.toRadixString(36)}')) {
      n++;
    }
    return 'pl${n.toRadixString(36)}';
  }

  void renamePlaylist(String id, String name) {
    if (name.trim().isEmpty) return;
    _updateList(id, {'name': name.trim()});
  }

  /// Sets or removes (`null`) the cover.
  void setPlaylistCover(String id, String? cover) =>
      _updateList(id, {'cover': cover ?? ''});

  /// Refresh ties as a whole, edited in the playlist editor.
  void setPlaylistSources(String id, List<PlSourceRef> sources) =>
      _updateList(id, {
        'sources': jsonEncode([for (final s in sources) s.toJson()]),
      });

  /// Ties a collection to a playlist if it isn't there; `false` if it was (or
  /// no playlist).
  bool linkSource(String id, PlSourceRef source) {
    final pl = state.playlists.where((p) => p.id == id).firstOrNull;
    if (pl == null || pl.sources.any((s) => s.id == source.id)) return false;
    setPlaylistSources(id, [...pl.sources, source]);
    return true;
  }

  /// Deletes a playlist; its tracks stay in the library.
  void deletePlaylist(String id) {
    if (id == kLibList || id == kFavList) return;
    _db.exec("DELETE FROM lists WHERE id = ? AND kind = 'playlist'", [id]);
    _refresh();
  }

  /// Restores a deleted playlist, for Undo in the toast. If one was created
  /// with that id meanwhile, nothing to restore.
  void restorePlaylist(UserPlaylist playlist) {
    if (_listExists(playlist.id)) return;
    _db.tx(() {
      _insertPlaylist(playlist);
      _addTo(playlist.id, [
        for (final id in playlist.trackIds) ?state.tracks[id],
      ]);
    });
    _refresh();
  }

  /// Puts tracks into a playlist on top, in batch order, skipping those
  /// present. Returns how many were added: Refresh tracks counts new ones this
  /// way.
  int addTracksToPlaylist(String id, List<Track> batch) {
    final n = _addTo(id, batch);
    _refresh();
    return n;
  }

  void addTrackToPlaylist(String id, Track track) =>
      addTracksToPlaylist(id, [track]);

  void removeTrackFromPlaylist(String id, String trackId) {
    _removeFrom(id, [trackId]);
    _refresh();
  }

  /// Edits a playlist as a whole: [trackIds] is the new contents AND order.
  void setPlaylistTracks(String id, List<String> trackIds) {
    _setOrder(id, trackIds);
    _refresh();
  }

  /// Marks playlists for scheduled auto-update, or unmarks them.
  void setAutoRefresh(Iterable<String> ids, bool on) {
    _db.tx(() {
      for (final id in ids) {
        _db.exec(
          "UPDATE lists SET auto_refresh = ? WHERE id = ? AND kind = 'playlist'",
          [on ? 1 : 0, id],
        );
      }
    });
    _refresh();
  }

  // ── Library cards ───────────────────────────────────────────────────────

  /// Where a card keeps place and pin: a playlist in `lists`, an artist in
  /// `follows`. The key is [libKeyOfPlaylist] or [libKeyOfArtist].
  ({String table, String id})? _card(String key) {
    final i = key.indexOf(':');
    if (i < 0) return null;
    final id = key.substring(i + 1);
    return switch (key.substring(0, i)) {
      'playlist' => (table: 'lists', id: id),
      'artist' => (table: 'follows', id: id),
      _ => null,
    };
  }

  /// Pins a card (on top under any sort) or unpins it.
  void setPinned(String key, bool pinned) {
    final card = _card(key);
    if (card == null) return;
    _db.exec('UPDATE ${card.table} SET pinned = ? WHERE id = ?', [
      pinned ? 1 : 0,
      card.id,
    ]);
    _refresh();
  }

  /// New order of cards, playlists and artists mixed as dragged: places 1…n in
  /// one `side_pos` row.
  void reorderCards(List<String> keys) {
    _db.tx(() {
      for (var i = 0; i < keys.length; i++) {
        final card = _card(keys[i]);
        if (card == null) continue;
        _db.exec('UPDATE ${card.table} SET side_pos = ? WHERE id = ?', [
          i + 1,
          card.id,
        ]);
      }
    });
    _refresh();
  }

  // ── Follows ─────────────────────────────────────────────────────────────

  bool toggleFollow(Artist artist) {
    final on = !state.isFollowing(artist.id);
    if (on) {
      _db.exec(
        'INSERT OR IGNORE INTO follows (id, provider, name, avatar, extra, at, side_pos) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          artist.id,
          artist.source.code,
          artist.name,
          artist.avatar ?? '',
          jsonEncode({
            if (artist.permalink != null) 'permalink': artist.permalink,
            if (artist.fullName != null) 'fullName': artist.fullName,
            if (artist.verified) 'verified': true,
          }),
          BloomDb.now(),
          _nextSidePos(),
        ],
      );
    } else {
      _db.exec('DELETE FROM follows WHERE id = ?', [artist.id]);
    }
    _refresh();
    return on;
  }
}
