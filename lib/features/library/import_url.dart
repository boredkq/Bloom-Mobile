/// Импорт по вставленной ссылке — порт десктопного `importFromUrl.ts`.
///
/// Разрешены только КОЛЛЕКЦИИ: плейлист, альбом и лайки профиля. Ссылка на
/// одиночный трек или артиста отклоняется — на ПК так же: импортировать «в
/// плейлист» одну песню незачем, для этого есть меню трека.
///
/// Импортированная коллекция становится источником «Обновить треки» — и у
/// созданного плейлиста, и у того, в который импортировали (привязок может быть
/// сколько угодно, с разных площадок). Затереть этим ничего нельзя: обновление
/// только подмешивает новые треки наверх (`refreshPlaylistFromSource`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers/music_provider.dart';
import '../../core/providers/registry.dart';
import '../../core/store/library_store.dart';
import '../../providers/soundcloud/sc_provider.dart' show scLikesOf;

/// Куда импортировать.
enum ImportTargetKind { create, library, favorites, playlist }

class ImportTarget {
  const ImportTarget(this.kind, {this.playlistId});

  const ImportTarget.create() : this(ImportTargetKind.create);

  final ImportTargetKind kind;

  /// id плейлиста для [ImportTargetKind.playlist].
  final String? playlistId;
}

/// Что нашлось по ссылке: коллекция как источник и её треки.
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

  /// Сколько треков реально прибавилось (без дублей).
  final int added;

  /// Сколько треков было в источнике.
  final int total;

  /// id созданного плейлиста — только для [ImportTargetKind.create].
  final String? createdId;
}

/// Почему ссылка не импортировалась. Причина, а не готовая фраза: текст знает
/// только UI, где есть язык интерфейса (`describeImportFailure`).
enum ImportFailure { unrecognized, unsupported, noTracks, playlistGone }

/// Отдельный тип, чтобы не показывать в тосте сырой текст сетевой ошибки.
class ImportException implements Exception {
  const ImportException(this.reason);
  final ImportFailure reason;

  @override
  String toString() => 'ImportException(${reason.name})';
}

/// Причина отказа импорта — фразой.
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

/// Резолв ссылки в набор треков. Общая точка для импорта и «обновить треки».
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
  // Название и обложку страница знает лучше, чем ссылка.
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

/// Треки привязанной коллекции — по её id у её площадки, как на ПК
/// (`Provider::collection`). `null` — площадки нет, она выключена или
/// коллекция не нашлась.
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

/// Импортировать ссылку в выбранную цель. Обёртка для UI.
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

/// То же самое без Riverpod-обвязки: реестр, контроллер и чтение состояния
/// приходят снаружи. Так импорт зовётся и из тестов.
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
