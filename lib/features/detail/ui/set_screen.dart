/// A platform's album or playlist: the header and the rows. It comes from the
/// network and can't be edited, only listened to and imported; the library's
/// own lists have a page of their own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/library_store.dart';
import '../../../features/library/import_url.dart';
import '../../../features/player/play_source.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/detail_hero.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/util/artists.dart';
import '../../../shared/util/format.dart';
import '../detail_nav.dart';
import 'detail_parts.dart';
import '../../../shared/ui/subpage_header.dart';

class SetScreen extends ConsumerStatefulWidget {
  const SetScreen({super.key, required this.set, this.flight});

  /// The card's set: the header shows before the network answers.
  final Playlist set;

  /// The card's cover, flying into the header.
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
        // I keep the card's cover and owner: a full answer comes without
        // them at times.
        _set = Playlist(
          id: content.playlist.id,
          title: content.playlist.title,
          cover: content.playlist.cover ?? widget.set.cover,
          releaseDate: content.playlist.releaseDate ?? widget.set.releaseDate,
          trackCount: content.playlist.trackCount ?? content.tracks.length,
          ownerName: content.playlist.ownerName ?? widget.set.ownerName,
          ownerAvatar: content.playlist.ownerAvatar ?? widget.set.ownerAvatar,
          ownerId: content.playlist.ownerId ?? widget.set.ownerId,
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

  /// Where a tap on the owner leads: an artist of the platform. A playlist's
  /// owner is often just someone, a link only when they're an artist on it.
  String? _ownerLink() {
    final owner = _set.ownerName;
    if (owner == null || owner.isEmpty) return null;
    if (_set.ownerId case final id? when id.isNotEmpty) return id;
    final name = owner.toLowerCase();
    for (final track in _tracks) {
      for (final a in artistLinks(track)) {
        if (a.id != null && a.name.toLowerCase() == name) return a.id;
      }
    }
    return null;
  }

  /// The owner's face: the platform's, else a track's (SoundCloud).
  String? _ownerAvatar() {
    if (_set.ownerAvatar case final url? when url.isNotEmpty) return url;
    final name = _set.ownerName?.toLowerCase();
    for (final track in _tracks) {
      if (track.artist.toLowerCase() == name) return ownArtistAvatar(track);
    }
    return null;
  }

  void _openOwner() {
    final id = _ownerLink();
    if (id == null) return;
    openArtist(
      context,
      id,
      initial: Artist(
        id: id,
        name: _set.ownerName ?? '',
        avatar: _ownerAvatar(),
        source: _set.source,
      ),
    );
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

  /// Saved already: a playlist has this collection linked as its source.
  static bool _savedIn(LibraryState lib, Playlist set) =>
      lib.playlists.any((p) => p.sources.any((s) => s.id == set.id));

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final queue = _tracks;
    final saved = _savedIn(ref.watch(libraryProvider), _set);

    return BloomPage(
      body: CustomScrollView(
        slivers: [
          DetailHero(
            image: _set.cover,
            title: _set.title,
            owner: _set.ownerName,
            ownerAvatar: _ownerAvatar(),
            onOwner: _ownerLink() == null ? null : _openOwner,
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
            const SliverToBoxAdapter(child: DetailSkeleton(artist: false))
          else if (_error case final message?)
            SliverToBoxAdapter(
              child: CenterNote(
                message,
                color: context.bloom.danger,
                padding: const EdgeInsets.all(24),
              ),
            )
          else if (_tracks.isEmpty)
            SliverToBoxAdapter(child: CenterNote(context.l.setNoTracks))
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              sliver: SliverList.builder(
                itemCount: _tracks.length,
                itemBuilder: (context, i) => DetailRow(
                  track: _tracks[i],
                  number: _set.isAlbum ? i + 1 : null,
                ),
              ),
            ),
            if (_releaseLabel() case final release?)
              SliverToBoxAdapter(child: _ReleaseBlock(date: release)),
          ],
          // The bars float over the list: the last row clears them.
          const SliverBottomBarsInset(),
        ],
      ),
    );
  }

  /// Under the title: the kind, an album's year, the count and the length; the
  /// full date stands under the rows. A playlist has no date at all: when it
  /// was made says nothing.
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
      if (total case final d? when d.inMinutes > 0) totalDur(context.l, d),
    ].join(' · ');
  }

  /// The platform's year, else the release date's, else the tracks' commonest.
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

  /// An album's release under its rows: the full date when the platform gave
  /// one, else the year.
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
    final canPlay = _tracks.isNotEmpty;
    await showBloomSheet(
      context: context,
      header: SheetHero(
        cover: _set.cover,
        title: _set.title,
        subtitle: _subtitle(),
      ),
      bar: [
        SheetAction(
          icon: Bi.playBold,
          label: context.l.commonPlay,
          onTap: canPlay ? _play : null,
        ),
        SheetAction(
          icon: Bi.shuffle,
          label: context.l.commonShuffle,
          onTap: canPlay ? _shuffle : null,
        ),
        ...queueSheetActions(context, ref, _tracks, source: SetSource(_set)),
      ],
      groups: [
        [
          SheetAction(
            icon: Bi.import,
            label: context.l.artistImport,
            subtitle: context.l.artistImportHint,
            onTap: canPlay ? _import : null,
          ),
        ],
      ],
    );
  }

  /// The whole list into the library; the collection stays linked as the
  /// playlist's source.
  Future<void> _import() async {
    final target = await pickImportTarget(
      context,
      title: _set.title,
      cover: _set.cover,
    );
    if (target == null || !mounted) return;
    try {
      final result = importTracksInto(
        ref.read(libraryProvider.notifier),
        () => ref.read(libraryProvider),
        _tracks,
        target,
        title: _set.title,
        cover: _set.cover,
        source: PlSourceRef.of(_set),
      );
      _toast(
        importResultText(context.l, result),
        result.added == 0 ? ToastKind.info : ToastKind.success,
      );
    } on ImportException catch (e) {
      _toast(describeImportFailure(context.l, e.reason), ToastKind.warn);
    }
  }

  void _toast(String message, [ToastKind kind = ToastKind.info]) {
    if (!mounted) return;
    showToast(context, message, kind: kind);
  }
}

/// "Release" under an album's rows: a thin line, a dim label, the date large.
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
