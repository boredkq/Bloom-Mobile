/// Действия над треком: лайк, добавление в плейлист, переход к артисту.
///
/// Аналог контекстного меню трека на десктопе, только снизу — на телефоне это
/// длинный тап по строке и кнопки на обложке в плеере.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/l10n/source_label.dart';
import '../../core/entities/entities.dart';
import '../../core/store/library_store.dart';
import '../../features/detail/artists_sheet.dart';
import '../../features/library/import_url.dart';
import '../../features/library/local_tracks.dart';
import '../../features/library/switch_platform.dart';
import '../../features/offline/file_download.dart';
import '../../features/offline/offline_actions.dart';
import '../../features/offline/offline_store.dart';
import '../../features/player/play_source.dart';
import '../../features/player/player_controller.dart';
import '../../features/wave/wave_actions.dart';
import '../../features/wave/wave_store.dart';
import '../util/artists.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'bloom_sheet.dart';
import 'bloom_toast.dart';
import 'platform_logo.dart';
import 'pressable.dart';
import 'track_info_sheet.dart';
import 'track_swipes.dart';

/// [listId] — раздел библиотеки, из которого открыли строку (`all` / `fav` /
/// `history` / id плейлиста): от него зависит «Убрать из плейлиста».
/// [queueIndex] — номер строки в очереди: там убирают не из списка, а из самой
/// очереди, и один трек может стоять в ней дважды.
Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  String? listId,
  int? queueIndex,
}) async {
  final lib = ref.read(libraryProvider);
  final isFav = lib.isFav(track.id);
  final inLib = lib.isInLib(track.id);
  // Several artists lead to a sheet to pick from, not straight to a page.
  final artists = artistLinks(track);
  // Пункт показываем, только если площадка вообще отдаёт трек файлом.
  final canOffline = ref.read(offlineProvider.notifier).canDownload(track);
  final hasCover = track.cover?.isNotEmpty ?? false;
  final isDisliked = ref.read(waveStoreProvider).isDisliked(track.id);
  // Позиция в очереди: из самой очереди её передают явно (один трек может
  // стоять там дважды, и по id их не различить), из остальных мест ищем по id —
  // как `isInQueue` в десктопном меню.
  final queue = ref.read(playbackProvider).queue;
  final inQueueAt = queueIndex ?? queue.indexWhere((t) => t.id == track.id);
  // «Убрать из плейлиста» — только для пользовательского плейлиста: во «Всех
  // треках», «Любимых» и «Истории» за тем же пунктом стояло бы совсем другое
  // действие (удаление насквозь, снятие лайка, забывание записи).
  final fromPlaylist = lib.playlists.any((p) => p.id == listId) ? listId : null;
  final player = ref.read(playbackProvider.notifier);
  // Мессенджер берём здесь: шторка закрывается до вызова обработчика, и её
  // context к моменту снекбара уже отвязан от дерева.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

  await showBloomSheet(
    context: context,
    backdrop: track.cover,
    header: SheetLineHeader(
      cover: track.cover,
      title: track.name,
      subtitle: track.artist,
      // Дата — когда трек попал в библиотеку (`inLib`): в самом плейлисте
      // времени добавления не хранится, там лежат одни id.
      meta: sheetDateMeta(context, l10n.commonAddedOn, lib.inLib[track.id]),
    ),
    groups: [
      // Очередь первой группой, как на десктопе: это действие «сейчас», а не
      // над самой записью трека.
      [
        SheetAction(
          icon: Bi.inboxIn,
          label: context.l.taToQueue,
          onTap: () => messenger.toast(
            player.addToQueue(track)
                ? l10n.swAddedToQueue
                : l10n.swAlreadyInQueue,
          ),
        ),
        SheetAction(
          icon: Bi.skipNext,
          label: context.l.taPlayNext,
          onTap: () {
            player.playNext(track);
            messenger.toast(l10n.swPlaysNext);
          },
        ),
      ],
      [
        SheetAction(
          icon: isFav ? Bi.heartBold : Bi.heart,
          label: isFav
              ? context.l.taRemoveFromFavorites
              : context.l.taAddToFavorites,
          onTap: () => ref.read(libraryProvider.notifier).toggleFav(track),
        ),
        SheetAction(
          icon: Bi.musicNote,
          label: context.l.taAddToPlaylist,
          chevron: true,
          onTap: () => showAddToPlaylistSheet(context, ref, track),
        ),
        // Скачиваний два (копия внутри приложения — чтобы играло без сети, и
        // файл наружу), и оба уехали в свою шторку — как флайаут «Скачать» на
        // десктопе: в общем списке они читались одинаково и путались.
        // У своего трека скачивать нечего, кроме обложки из тегов — шторка
        // открывается и ради неё одной.
        if (canOffline || (canSaveFiles && hasCover))
          SheetAction(
            icon: Bi.downloadMinimalistic,
            label: context.l.taDownload,
            chevron: true,
            onTap: () =>
                _showDownloadSheet(context, ref, track, canOffline: canOffline),
          ),
      ],
      [
        // Волна по треку — только у площадок с радио: у остальных пункт
        // открывался бы ради отказа.
        if (canStartWaveFrom(ref, track))
          SheetAction(
            icon: Bi.soundwave,
            label: context.l.waveFromTrack,
            onTap: () => startWaveFromTrack(context, ref, track),
          ),
        SheetAction(
          icon: isDisliked ? Bi.dislikeBold : Bi.dislike,
          label: isDisliked ? context.l.waveUndislike : context.l.waveDislike,
          onTap: () => toggleWaveDislike(context, ref, track),
        ),
        // Смена площадки — про запись библиотеки, поэтому у треков из поиска и
        // у локальных файлов пункта нет (см. `canSwitchPlatform`).
        if (canSwitchPlatform(lib, ref, track))
          SheetAction(
            icon: Bi.refreshSquare,
            label: context.l.spSwitch,
            chevron: true,
            onTap: () => _showSwitchPlatformSheet(context, ref, track),
          ),
      ],
      [
        if (canOpenTrackArtist(track))
          SheetAction(
            icon: Bi.user,
            label: context.l.taGoToArtist,
            chevron: artists.length > 1,
            onTap: () => openTrackArtist(context, ref, track),
          ),
        SheetAction(
          icon: Bi.infoCircle,
          label: context.l.tiTitle,
          chevron: true,
          onTap: () =>
              showTrackInfoSheet(context, track, addedAt: lib.inLib[track.id]),
        ),
      ],
      [
        // Убрать из списка и убрать из очереди — тоже красные, как `ci red` на
        // десктопе: после них строка со своего места исчезает.
        if (fromPlaylist case final playlistId?)
          SheetAction(
            icon: Bi.close,
            label: context.l.taRemoveFromPlaylist,
            danger: true,
            onTap: () =>
                removeTrackFromList(messenger, l10n, ref, playlistId, track),
          ),
        if (inQueueAt >= 0)
          SheetAction(
            icon: Bi.close,
            label: context.l.taRemoveFromQueue,
            danger: true,
            onTap: () => unawaited(player.removeAt(inQueueAt)),
          ),
        // Удалять есть что только у трека из библиотеки: у остальных за строкой
        // ничего не стоит, они приехали из поиска.
        if (inLib)
          SheetAction(
            icon: Bi.trashBinTrash,
            label: context.l.taDeleteTrack,
            danger: true,
            onTap: () => _deleteTrack(messenger, l10n, ref, track),
          ),
      ],
    ],
  );
}

/// Удаление насквозь, без переспроса: трек уходит и из любимых, и из
/// плейлистов — пункт красный, тап по нему уже и есть решение. В «Истории» его
/// запись остаётся: это журнал прослушанного, и чистит его только человек.
void _deleteTrack(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  WidgetRef ref,
  Track track,
) {
  // Офлайн-копию убираем вместе с треком: без строки в библиотеке файл остался
  // бы мусором, на который никто не ссылается. Со своим треком то же самое:
  // копия внутри приложения стирается, чужой файл остаётся на месте.
  unawaited(ref.read(offlineProvider.notifier).remove(track.id));
  unawaited(forgetLocalTracks([track]));
  ref.read(libraryProvider.notifier).deleteTrack(track.id);
  messenger.toast(l10n.taTrackDeleted);
}

/// Шторка «Скачать»: копия внутри приложения и файл наружу — порт десктопного
/// флайаута `cxdl`.
///
/// Офлайн-состояние читаем здесь заново: между открытием меню и этой шторкой
/// пакетная загрузка могла его изменить.
Future<void> _showDownloadSheet(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  required bool canOffline,
}) async {
  final isOffline = ref.read(offlineProvider).has(track.id);
  final hasCover = track.cover?.isNotEmpty ?? false;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

  // Порядок как в десктопном флайауте: трек, обложка, офлайн.
  final rows = <Widget>[
    if (canOffline && canSaveFiles)
      Builder(
        builder: (sheetContext) => _SimpleRow(
          icon: Bi.musicNote,
          label: l10n.fdDownloadFile,
          color: context.bloom.text,
          onTap: () {
            Navigator.of(sheetContext).pop();
            unawaited(saveTrackFile(messenger, l10n, ref, track));
          },
        ),
      ),
    if (canSaveFiles && hasCover)
      Builder(
        builder: (sheetContext) => _SimpleRow(
          icon: Bi.gallery,
          label: l10n.fdDownloadCover,
          color: context.bloom.text,
          onTap: () {
            Navigator.of(sheetContext).pop();
            unawaited(saveCoverFile(messenger, l10n, track));
          },
        ),
      ),
    if (canOffline)
      Builder(
        builder: (sheetContext) => _SimpleRow(
          // Дискета у офлайна и галочка у скачанного — те же значки, что на
          // ПК (голой галочки у Solar нет, поэтому в кружке).
          icon: isOffline ? Bi.trashBinTrash : Bi.downloadMinimalistic,
          label: isOffline ? l10n.taRemoveOffline : l10n.taListenOffline,
          color: isOffline ? context.bloom.accent : context.bloom.text,
          onTap: () {
            Navigator.of(sheetContext).pop();
            unawaited(toggleTrackOffline(messenger, l10n, ref, track));
          },
        ),
      ),
  ];

  await showBloomSheetChild<void>(
    context: context,
    backdrop: track.cover,
    header: SheetLineHeader(
      cover: track.cover,
      title: context.l.taDownload,
      subtitle: track.name,
    ),
    child: Builder(
      builder: (sheetContext) => SheetPanel(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) sheetDivider(),
            rows[i],
          ],
        ],
      ),
    ),
  );
}

/// Шторка «Сменить площадку»: список площадок, куда трек можно переставить.
/// Нынешней в нём нет — переставлять туда, где трек уже есть, нечего.
Future<void> _showSwitchPlatformSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final targets = switchTargets(ref, track);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;

  await showBloomSheetChild<void>(
    context: context,
    backdrop: track.cover,
    header: SheetLineHeader(
      cover: track.cover,
      title: context.l.spSwitch,
      subtitle: track.name,
    ),
    // Закрывать шторку надо её же навигатором: снаружи `Navigator.of` найдёт
    // навигатор вкладки и захлопнет страницу, а не шторку.
    child: Builder(
      builder: (sheetContext) => SheetPanel(
        children: [
          for (var i = 0; i < targets.length; i++) ...[
            if (i > 0) sheetDivider(),
            PlatformRow(
              source: targets[i],
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(
                  switchTrackPlatform(messenger, l10n, ref, track, targets[i]),
                );
              },
            ),
          ],
        ],
      ),
    ),
  );
}

/// Platform row of a sheet: its logo and name.
class PlatformRow extends StatelessWidget {
  const PlatformRow({super.key, required this.source, required this.onTap});

  final MusicSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            PlatformLogo(source, size: 22),
            const SizedBox(width: 16),
            Text(
              source.label10n(context.l),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Шторка «Добавить в …»: сперва библиотека, потом плейлисты — порядок как в
/// десктопном `AddPopup` («В библиотеку» первым пунктом над списком).
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) => showAddTracksToPlaylistSheet(context, ref, [track]);

/// Та же шторка для пачки треков — выделение из режима правки списка.
///
/// [newName] — имя, которое подставится в «Новый плейлист»: у одного трека это
/// его название, у пачки — имя списка, откуда её взяли.
Future<void> showAddTracksToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  String? newName,
}) async {
  if (tracks.isEmpty) return;
  final one = tracks.length == 1 ? tracks.first : null;
  final cover = tracks.first.cover;

  await showBloomSheetChild(
    context: context,
    backdrop: cover,
    header: SheetLineHeader(
      cover: cover,
      title: context.l.taAddToPlaylist,
      subtitle: one?.name ?? context.l.tracksCount(tracks.length),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        final t = context.bloom;
        final lib = ref.watch(libraryProvider);
        final playlists = lib.playlists;
        final outside = [
          for (final track in tracks)
            if (!lib.isInLib(track.id)) track,
        ];

        return SheetPanel(
          children: [
            // Того, что уже в библиотеке, пункт не касается — он прячется,
            // когда добавлять нечего (`canAddToLib` на десктопе). Убрать трек
            // можно только «Удалить трек» из шторки действий, насквозь.
            if (outside.isNotEmpty) ...[
              _SimpleRow(
                icon: Bi.downloadMinimalistic,
                label: context.l.commonAddToLibrary,
                color: t.accent,
                onTap: () {
                  // Мессенджер берём до pop: после него context шторки уже
                  // отвязан от дерева и до Scaffold по нему не дойти.
                  final messenger = ScaffoldMessenger.of(context);
                  final l10n = context.l;
                  ref.read(libraryProvider.notifier).addToLibrary(outside);
                  Navigator.of(context).pop();
                  messenger.toast(
                    l10n.taAddedToLibrary,
                    kind: ToastKind.success,
                  );
                },
              ),
              sheetDivider(),
            ],
            _SimpleRow(
              icon: Bi.plus,
              label: context.l.commonNewPlaylist,
              color: t.accent,
              onTap: () {
                ref
                    .read(libraryProvider.notifier)
                    .createPlaylist(newName ?? one?.name ?? '', tracks: tracks);
                Navigator.of(context).pop();
              },
            ),
            for (final pl in playlists) ...[
              // Текст строки плейлиста: 12 + обложка 40 + 12.
              sheetDivider(indent: 64),
              _PlaylistRow(playlist: pl, tracks: tracks),
            ],
          ],
        );
      },
    ),
  );
}

/// "To the queue" and "Play next" for a whole list: a track's two items, for
/// all of [tracks].
List<SheetAction> queueSheetActions(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  PlaySource? source,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l;
  final player = ref.read(playbackProvider.notifier);
  return [
    SheetAction(
      icon: Bi.inboxIn,
      label: l10n.tlToQueue,
      onTap: tracks.isEmpty
          ? null
          : () {
              final added = player.queueTracks(tracks, source: source);
              messenger.toast(
                added > 0 ? l10n.tlQueuedTracks(added) : l10n.swAlreadyInQueue,
              );
            },
    ),
    SheetAction(
      icon: Bi.skipNext,
      label: l10n.tlPlayNext,
      onTap: tracks.isEmpty
          ? null
          : () {
              final moved = player.queueTracksNext(tracks, source: source);
              if (moved > 0) messenger.toast(l10n.tlQueuedNext(moved));
            },
    ),
  ];
}

/// Where a page's whole list goes: a new playlist named as the page, all
/// tracks, liked, or one of the playlists.
Future<ImportTarget?> pickImportTarget(
  BuildContext context, {
  required String title,
  String? cover,
  bool circle = false,
}) => showBloomSheetChild<ImportTarget>(
  context: context,
  backdrop: cover,
  header: SheetLineHeader(
    cover: cover,
    title: context.l.artistImport,
    subtitle: title,
    circle: circle,
  ),
  child: Consumer(
    builder: (context, ref, _) {
      final t = context.bloom;
      void pick(ImportTarget target) => Navigator.of(context).pop(target);
      return SheetPanel(
        children: [
          _SimpleRow(
            icon: Bi.plus,
            label: context.l.commonCreatePlaylist,
            color: t.accent,
            onTap: () => pick(const ImportTarget.create()),
          ),
          sheetDivider(),
          _SimpleRow(
            icon: Bi.musicNote,
            label: context.l.commonAllTracks,
            color: t.text,
            onTap: () => pick(const ImportTarget(ImportTargetKind.library)),
          ),
          sheetDivider(),
          _SimpleRow(
            icon: Bi.heartBold,
            label: context.l.commonFavorites,
            color: t.text,
            onTap: () => pick(const ImportTarget(ImportTargetKind.favorites)),
          ),
          for (final pl in ref.watch(libraryProvider).playlists) ...[
            sheetDivider(indent: 64),
            _PlaylistRow(
              playlist: pl,
              tracks: const [],
              onTap: () => pick(
                ImportTarget(ImportTargetKind.playlist, playlistId: pl.id),
              ),
            ),
          ],
        ],
      );
    },
  ),
);

/// Строка шторки без обложки — под высоту строки плейлиста.
class _SimpleRow extends StatelessWidget {
  const _SimpleRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final BloomGlyph icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            BloomIcon(icon, size: 22, color: color),
            const SizedBox(width: 16),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistRow extends ConsumerWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.tracks,
    this.onTap,
  });

  final UserPlaylist playlist;
  final List<Track> tracks;

  /// Instead of adding [tracks] here.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final lib = ref.watch(libraryProvider);
    // Галочка — «всё это уже здесь»: у пачки половина треков в плейлисте ещё
    // не отметка, добавить остальные по-прежнему есть смысл.
    final ids = playlist.trackIds.toSet();
    final has =
        tracks.isNotEmpty && tracks.every((track) => ids.contains(track.id));

    return Pressable(
      onTap:
          onTap ??
          () {
            ref
                .read(libraryProvider.notifier)
                .addTracksToPlaylist(playlist.id, tracks);
            Navigator.of(context).pop();
          },
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Cover(
              url: playlist.cover,
              size: 40,
              covers: playlist.trackIds.map((id) => lib.tracks[id]?.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (has) BloomIcon(Bi.check, size: 18, color: t.accent),
          ],
        ),
      ),
    );
  }
}
