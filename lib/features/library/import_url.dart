/// Import by a pasted link. Only COLLECTIONS are allowed: a playlist, an album
/// or a profile's likes. A link to one track or an artist is refused: the track
/// menu is for that.
///
/// An imported collection becomes a Refresh tracks source, both for a created
/// playlist and one imported into. Nothing can be overwritten: refreshing only
/// adds new tracks on top.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers/music_provider.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';
import '../../providers/soundcloud/sc_provider.dart' show scLikesOf;

/// Where to import.
enum ImportTargetKind { create, library, favorites, playlist }

class ImportTarget {
  const ImportTarget(this.kind, {this.playlistId});

  const ImportTarget.create() : this(ImportTargetKind.create);

  final ImportTargetKind kind;

  /// Playlist id for [ImportTargetKind.playlist].
  final String? playlistId;
}

/// What the link resolved to: a collection as a source, and its tracks.
class ResolvedCollection {
  const ResolvedCollection({required this.source, required this.tracks});

  final PlSourceRef source;
  final List<Track> tracks;

  String get title => source.title;
  String? get cover => source.cover.isEmpty ? null : source.cover;
}

class ImportResult {
  const ImportResult({
    required this.title,
    required this.added,
    required this.total,
    this.createdId,
  });

  final String title;

  /// Tracks really added, with no duplicates.
  final int added;

  /// Tracks in the source.
  final int total;

  /// Created playlist's id, only for [ImportTargetKind.create].
  final String? createdId;
}

/// Why a link didn't import. A reason rather than a phrase: only the UI knows
/// the language (`describeImportFailure`).
enum ImportFailure { unrecognized, unsupported, noTracks, playlistGone }

/// A separate type, so a toast doesn't show raw network error text.
class ImportException implements Exception {
  const ImportException(this.reason);
  final ImportFailure reason;

  @override
  String toString() => 'ImportException(${reason.name})';
}

/// An import failure's reason as a phrase.
String describeImportFailure(AppLocalizations l, ImportFailure reason) =>
    switch (reason) {
      ImportFailure.unrecognized => l.iuUnrecognized,
      ImportFailure.unsupported => l.iuOnlySupported,
      ImportFailure.noTracks => l.iuNoTracks,
      ImportFailure.playlistGone => l.iuPlaylistGone,
    };

/// What an import did, for its toast.
String importResultText(AppLocalizations l, ImportResult r) =>
    r.createdId != null
    ? l.cpImported(r.title, r.added)
    : r.added == 0
    ? l.cpAllAlreadyIn
    : l.cpAdded(r.added);

/// Resolves a link to a set of tracks, for import and Refresh tracks.
Future<ResolvedCollection> resolveCollectionUrl(
  ProviderRegistry registry,
  String url,
) async {
  final found = await registry.resolveUrlAny(url.trim());
  if (found == null) {
    throw const ImportException(ImportFailure.unrecognized);
  }
  final link = url.trim();
  // A listener's link means their likes.
  final set = switch (found.resolved) {
    ResolvedSet(playlist: final p) => p,
    ResolvedArtist(:final artist)
        when artist.source == MusicSource.soundcloud =>
      scLikesOf(artist),
    ResolvedTrack() ||
    ResolvedArtist() => throw const ImportException(ImportFailure.unsupported),
  };
  final content = set.isAlbum
      ? await found.provider.getAlbum(set.id)
      : await found.provider.getPlaylist(set.id);
  if (content == null) {
    throw const ImportException(ImportFailure.unrecognized);
  }
  // The page knows title and cover better than the link.
  final page = content.playlist;
  return ResolvedCollection(
    source: PlSourceRef.of(set).copyWith(
      url: link,
      title: page.title.isEmpty ? null : page.title,
      owner: page.ownerName,
      cover: page.cover,
    ),
    tracks: content.tracks,
  );
}

/// A tied collection's tracks, by its id on its platform. `null` if the
/// platform is missing or off, or the collection wasn't found.
Future<List<Track>?> fetchSource(
  ProviderRegistry registry,
  PlSourceRef source,
) async {
  final p = registry.byId(MusicSource.fromCode(source.provider).id);
  if (p == null || !p.isEnabled) return null;
  final content = source.isAlbum
      ? await p.getAlbum(source.id)
      : await p.getPlaylist(source.id);
  return content?.tracks;
}

/// Imports a link into the chosen target; a wrapper for the UI.
Future<ImportResult> importFromUrl(
  WidgetRef ref,
  String url,
  ImportTarget target,
) => importUrlInto(
  ref.read(registryProvider),
  ref.read(libraryProvider.notifier),
  () => ref.read(libraryProvider),
  url,
  target,
);

/// The same with no Riverpod: registry, controller and state reads come from
/// outside, so tests can call it too.
Future<ImportResult> importUrlInto(
  ProviderRegistry registry,
  LibraryController library,
  LibraryState Function() read,
  String url,
  ImportTarget target,
) async {
  final source = await resolveCollectionUrl(registry, url);
  if (source.tracks.isEmpty) {
    throw const ImportException(ImportFailure.noTracks);
  }
  return importTracksInto(
    library,
    read,
    source.tracks,
    target,
    title: source.title,
    cover: source.cover,
    source: source.source,
  );
}

/// [tracks] into [target]. A collection's [source] stays linked for "Refresh
/// tracks", both on a new playlist and on the one imported into; an artist's
/// page is no source.
ImportResult importTracksInto(
  LibraryController library,
  LibraryState Function() read,
  List<Track> tracks,
  ImportTarget target, {
  required String title,
  String? cover,
  PlSourceRef? source,
}) {
  switch (target.kind) {
    case ImportTargetKind.create:
      final playlist = library.createPlaylist(
        title,
        tracks: tracks,
        cover: cover,
        source: source,
      );
      return ImportResult(
        title: title,
        added: tracks.length,
        total: tracks.length,
        createdId: playlist.id,
      );

    case ImportTargetKind.library:
      return ImportResult(
        title: title,
        added: library.addToLibrary(tracks),
        total: tracks.length,
      );

    case ImportTargetKind.favorites:
      return ImportResult(
        title: title,
        added: library.addToFavorites(tracks),
        total: tracks.length,
      );

    case ImportTargetKind.playlist:
      final id = target.playlistId!;
      // The playlist may have gone while the tracks were coming.
      if (!read().playlists.any((p) => p.id == id)) {
        throw const ImportException(ImportFailure.playlistGone);
      }
      final added = library.addTracksToPlaylist(id, tracks);
      if (source != null) library.linkSource(id, source);
      return ImportResult(
        title: title,
        added: added,
        total: tracks.length,
        createdId: id,
      );
  }
}
