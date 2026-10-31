/// Страница альбома или плейлиста площадки: шапка с обложкой и трек-лист.
///
/// Библиотечный плейлист живёт на другом экране (`TracklistScreen`): там свои
/// обложка, сортировка и правка состава. Здесь всё приходит из сети и трогать
/// его нельзя — можно только слушать и сохранить копию к себе, как это делает
/// импорт по ссылке.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/library_store.dart';
import '../../../features/customization/ui/app_background.dart';
import '../../../features/player/play_source.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/detail_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/util/format.dart';

class SetScreen extends ConsumerStatefulWidget {
  const SetScreen({super.key, required this.set, this.flight});

  /// Сет из карточки: шапка рисуется до ответа сети.
  final Playlist set;

  /// Обложка карточки, с которой пришли: она перелетает в шапку.
  final CoverFlight? flight;

  @override
  ConsumerState<SetScreen> createState() => _SetScreenState();
}

class _SetScreenState extends ConsumerState<SetScreen> {
  late Playlist _set;
  List<Track> _tracks = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _set = widget.set;
    _load();
  }

  Future<void> _load() async {
    final provider = ref.read(registryProvider).forEntity(widget.set.id);
    if (provider == null) {
      setState(() {
        _loading = false;
        _error = context.l.setSourceNotConnected;
      });
      return;
    }
    try {
      final content = widget.set.isAlbum
          ? await provider.getAlbum(widget.set.id)
          : await provider.getPlaylist(widget.set.id);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (content == null) {
          _error = widget.set.isAlbum
              ? context.l.setAlbumNotFound
              : context.l.setPlaylistNotFound;
          return;
        }
        // Обложку и владельца из карточки не теряем: у SoundCloud полная
        // выдача сета иногда приходит без них.
        _set = Playlist(
          id: content.playlist.id,
          title: content.playlist.title,
          cover: content.playlist.cover ?? widget.set.cover,
          releaseDate: content.playlist.releaseDate ?? widget.set.releaseDate,
          trackCount: content.playlist.trackCount ?? content.tracks.length,
          ownerName: content.playlist.ownerName ?? widget.set.ownerName,
          ownerAvatar: content.playlist.ownerAvatar ?? widget.set.ownerAvatar,
          year: content.playlist.year ?? widget.set.year,
          isAlbum: content.playlist.isAlbum,
          duration: content.playlist.duration ?? widget.set.duration,
          sourceUrl: content.playlist.sourceUrl ?? widget.set.sourceUrl,
          source: content.playlist.source,
        );
        _tracks = content.tracks;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _kindWord(BuildContext context) =>
      _set.isAlbum ? context.l.commonAlbum : context.l.commonPlaylist;

  void _play() {
    if (_tracks.isEmpty) return;
    ref
        .read(playbackProvider.notifier)
        .playQueue(_tracks, 0, source: SetSource(_set));
  }

  void _shuffle() {
    if (_tracks.isEmpty) return;
    ref
        .read(playbackProvider.notifier)
        .playQueueShuffled(_tracks, source: SetSource(_set));
  }

  /// Есть ли уже сохранённая копия — плейлист, к которому эта коллекция
  /// привязана источником (тем же, из которого «Обновить треки» тянет новые
  /// треки), как на ПК.
  static bool _savedIn(LibraryState lib, Playlist set) =>
      lib.playlists.any((p) => p.sources.any((s) => s.id == set.id));

  bool get _saved => _savedIn(ref.read(libraryProvider), _set);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final queue = _tracks;
    final saved = _savedIn(ref.watch(libraryProvider), _set);

    return Scaffold(
      // Под страницей может лежать картинка фона — тогда своей заливки нет.
      backgroundColor: ref.watch(backgroundOnProvider)
          ? Colors.transparent
          : t.bg,
      body: CustomScrollView(
        slivers: [
          DetailHero(
            image: _set.cover,
            title: _set.title,
            owner: _set.ownerName,
            subtitle: _subtitle(),
            flight: widget.flight,
            onMenu: _menu,
            actions: HeroActions(
              sourceId: _set.id,
              onPlay: queue.isEmpty ? null : _play,
              trailing: [
                GlassIconButton(
                  icon: Bi.shuffle,
                  size: 46,
                  onTap: queue.isEmpty ? null : _shuffle,
                ),
                GlassIconButton(
                  icon: saved ? Bi.check : Bi.addCircle,
                  size: 46,
                  background: saved ? t.accent : null,
                  color: saved ? t.accentText : null,
                  onTap: queue.isEmpty ? null : () => _save(saved),
                ),
              ],
            ),
          ),
          if (_loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
            )
          else if (_error case final message?)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: t.danger),
                ),
              ),
            )
          else if (_tracks.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    context.l.setNoTracks,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: t.muted),
                  ),
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              sliver: SliverList.builder(
                itemCount: _tracks.length,
                itemBuilder: (context, i) => TrackRow(
                  track: _tracks[i],
                  queue: _tracks,
                  index: i,
                  source: SetSource(_set),
                  // В альбоме обложка у всех треков одна — на её месте номер,
                  // как в десктопном `PlaylistBody numbered`. У плейлиста
                  // треки разношёрстные, там обложка и остаётся.
                  number: _set.isAlbum ? i + 1 : null,
                ),
              ),
            ),
            if (_releaseLabel() case final release?)
              SliverToBoxAdapter(child: _ReleaseBlock(date: release)),
          ],
          // Хвост под бары каркаса: они плавают над списком, и последняя строка
          // иначе остаётся под миниплеером.
          const SliverBottomBarsInset(),
        ],
      ),
    );
  }

  /// Подпись под названием: год, число треков, общая длительность — как в
  /// шапке сета на десктопе. Полная дата выхода у альбома стоит отдельным
  /// блоком «Релиз» под треклистом (см. [_releaseLabel]), в шапке — только год.
  /// A playlist has no date at all: when it was made says nothing.
  String _subtitle() {
    final count = _tracks.isNotEmpty ? _tracks.length : _set.trackCount;
    final total = _tracks.isEmpty
        ? _set.duration
        : _tracks.fold(Duration.zero, (sum, x) => sum + x.duration);
    final year = _set.isAlbum ? _year() : null;
    return [
      _kindWord(context),
      ?year,
      if (count case final n?) context.l.tracksCount(n),
      if (total case final d? when d > Duration.zero) mmss(d),
    ].join(' · ');
  }

  /// Год: от площадки, иначе из даты выхода, иначе самый частый среди треков.
  String? _year() {
    if (_set.year case final y? when y.isNotEmpty) return y;
    final date = _set.releaseDate;
    if (date != null && date.length >= 4) return date.substring(0, 4);
    final counts = <String, int>{};
    for (final t in _tracks) {
      if (t.year case final y? when y.isNotEmpty) {
        counts[y] = (counts[y] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return (counts.entries.toList()..sort((a, b) => b.value - a.value))
        .first
        .key;
  }

  /// Подпись блока «Релиз» под треклистом (порт `albumRelease` десктопного
  /// `DetailView`, 3.0): полная дата от площадки («13 мая 2024»), иначе год —
  /// SoundCloud и YouTube Music отдают только его. Только у альбома; нет ни
  /// того ни другого — блока нет.
  String? _releaseLabel() {
    if (!_set.isAlbum) return null;
    return releaseDateLabel(
          _set.releaseDate,
          Localizations.localeOf(context).toString(),
        ) ??
        _year();
  }

  void _save(bool alreadySaved) {
    if (alreadySaved) {
      _toast(context.l.commonAlreadyInLibrary, ToastKind.warn);
      return;
    }
    ref
        .read(libraryProvider.notifier)
        .createPlaylist(
          _set.title,
          tracks: _tracks,
          cover: _set.cover,
          source: PlSourceRef.of(_set),
        );
    _toast(
      context.l.addedToast(_set.title, context.l.tracksCount(_tracks.length)),
      ToastKind.success,
    );
  }

  Future<void> _menu() async {
    final saved = _saved;

    await showBloomSheet(
      context: context,
      backdrop: _set.cover,
      header: SheetCoverHeader(
        cover: _set.cover,
        title: _set.title,
        subtitle: _subtitle(),
      ),
      groups: [
        [
          SheetAction(
            icon: Bi.playBold,
            label: context.l.commonPlay,
            onTap: _tracks.isEmpty ? null : _play,
          ),
          SheetAction(
            icon: Bi.shuffle,
            label: context.l.commonShuffle,
            onTap: _tracks.isEmpty ? null : _shuffle,
          ),
        ],
        [
          SheetAction(
            icon: saved ? Bi.check : Bi.import,
            label: saved
                ? context.l.commonAlreadyInLibrary
                : context.l.setSaveToLibrary,
            onTap: _tracks.isEmpty ? null : () => _save(saved),
          ),
        ],
      ],
    );
  }

  void _toast(String message, [ToastKind kind = ToastKind.info]) {
    if (!mounted) return;
    showToast(context, message, kind: kind);
  }
}

/// Блок «Релиз» под треклистом альбома — десктопный `.sp-am-release`: тонкая
/// линия сверху, приглушённая подпись и крупная дата.
class _ReleaseBlock extends StatelessWidget {
  const _ReleaseBlock({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.ovlLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l.setRelease,
            style: theme.labelLarge?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.text2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            date,
            style: theme.headlineSmall?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.26,
              color: t.text,
            ),
          ),
        ],
      ),
    );
  }
}
