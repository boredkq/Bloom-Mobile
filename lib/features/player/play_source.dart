/// Queue source: where what's playing came from, being a library section, a
/// platform album or playlist, an artist page, search results, a home shelf or
/// a single track.
///
/// The session stores it as a map `{kind, id, name, cover, …}`: `playlist` (own
/// lists, `lib`, `fav`), `history`, `collection`, `artist`, `wave` (plus
/// `mode`), `search`, `track` and shelves. An unknown kind reads as
/// [PlainSource] by `name`.
///
/// For library sections memory holds ONLY the id, and the pill takes caption
/// and picture from the library: a playlist can be renamed during playback. The
/// session adds name and cover to the map on write. Platform sets are the
/// reverse: a snapshot is a must, with no way to re-read a SoundCloud album
/// offline.
library;

import '../../core/entities/entities.dart';
import '../wave/wave_types.dart';

sealed class PlaySource {
  const PlaySource();

  /// The key to whether THIS list is playing, used by set tiles and list rows
  /// for the equalizer. For things with no tile it just matches nothing.
  String get id;

  Map<String, dynamic> toJson();

  static PlaySource? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = json['kind'];
    final id = json['id'] is String ? json['id'] as String : '';
    final name = json['name'] is String ? json['name'] as String : '';
    final cover = switch (json['cover']) {
      final String c when c.isNotEmpty => c,
      _ => null,
    };
    switch (kind) {
      case 'playlist':
        if (id.isEmpty) return null;
        return LibSource(id == 'lib' ? 'all' : id);
      case 'history':
        return const LibSource('history');
      case 'collection':
        if (id.isEmpty) return null;
        return SetSource(
          Playlist(
            id: id,
            title: name,
            cover: cover,
            source: MusicSource.fromId(id),
            isAlbum: json['album'] == true || id.contains(':album:'),
          ),
        );
      case 'artist':
        if (id.isEmpty) return null;
        return ArtistSource(
          Artist(
            id: id,
            name: name,
            source: MusicSource.fromId(id),
            avatar: cover,
          ),
        );
      case 'wave':
        return WaveSource(
          label: name,
          mode:
              WaveMode.values
                  .where((m) => m.name == json['mode'])
                  .firstOrNull ??
              WaveMode.personal,
        );
      case final String kind when kind.isNotEmpty:
        return PlainSource(
          id: id.isEmpty ? kind : id,
          label: name,
          cover: cover,
        );
      default:
        return null;
    }
  }
}

/// Library section: `all`, `fav`, `history` or a user playlist. Opens by route
/// `/library/list/:id`. In the map all tracks is `lib`.
final class LibSource extends PlaySource {
  const LibSource(this.listId);

  final String listId;

  @override
  String get id => listId;

  @override
  Map<String, dynamic> toJson() => switch (listId) {
    'all' => {'kind': 'playlist', 'id': 'lib', 'glyph': 'note'},
    'fav' => {'kind': 'playlist', 'id': 'fav', 'glyph': 'heart'},
    'history' => {'kind': 'history'},
    _ => {'kind': 'playlist', 'id': listId},
  };
}

/// Platform album or playlist: the same [Playlist] that opened the page, and
/// the pill returns to it.
final class SetSource extends PlaySource {
  const SetSource(this.set);

  final Playlist set;

  @override
  String get id => set.id;

  /// `album` is a key only this app writes: album and playlist pages load by
  /// different requests, and on SoundCloud ids can't tell them apart.
  @override
  Map<String, dynamic> toJson() => {
    'kind': 'collection',
    'id': set.id,
    'name': set.title,
    'cover': set.cover ?? '',
    if (set.isAlbum) 'album': true,
  };
}

/// Artist page: Play, the popular carousel, the track list.
final class ArtistSource extends PlaySource {
  const ArtistSource(this.artist);

  final Artist artist;

  @override
  String get id => artist.id;

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'artist',
    'id': artist.id,
    'name': artist.name,
    'cover': artist.avatar ?? '',
    'round': true,
  };
}

/// The wave: picks fill the queue, not a list. It has no page, so [id] matches
/// no tile; [mode] resumes the session after a restart the way it began.
///
/// The caption comes translated: the pill may draw from a snapshot taken a day
/// earlier.
final class WaveSource extends PlaySource {
  const WaveSource({required this.label, required this.mode});

  final String label;
  final WaveMode mode;

  @override
  String get id => 'wave:${mode.name}';

  @override
  Map<String, dynamic> toJson() => {
    'kind': 'wave',
    'mode': mode.name,
    'name': label,
    'glyph': 'wave',
  };
}

/// Icon of a source with no picture.
enum PlainSourceIcon { search, clock, chart, note }

/// A source with no page: search results, a home shelf, a single track. The
/// caption comes translated: the pill may draw a day after the track was
/// started.
///
/// The kind is the start of [id] before the colon: `search:…`, `wrapped:…`,
/// `discover:…`, `forYou`; a single track is `track`.
final class PlainSource extends PlaySource {
  const PlainSource({required this.id, required this.label, this.cover});

  /// Search results. [label] is the caption with the query.
  PlainSource.search(String query, String label)
    : this(id: 'search:$query', label: label);

  /// A single track started outside a list (profile top, track menu).
  PlainSource.single(Track track)
    : this(id: 'track:${track.id}', label: track.name, cover: track.cover);

  @override
  final String id;

  final String label;

  /// Own picture if any (a single track's cover).
  final String? cover;

  String get kind => id.split(':').first;

  PlainSourceIcon get icon => switch (kind) {
    'search' => PlainSourceIcon.search,
    'recent' || 'history' => PlainSourceIcon.clock,
    'discover' || 'wrapped' || 'chart' => PlainSourceIcon.chart,
    _ => PlainSourceIcon.note,
  };

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'name': label,
    'cover': cover ?? '',
  };
}
