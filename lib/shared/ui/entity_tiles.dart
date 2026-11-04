/// Rows and cards of entities, shared by search, artist pages and the library.
/// They work with neutral [Track], [Artist] and [Playlist], so every platform
/// looks the same.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/entities/entities.dart';
import '../../features/detail/detail_nav.dart';
import '../../features/offline/offline_store.dart';
import '../../features/player/play_source.dart';
import '../../features/player/player_controller.dart';
import '../util/format.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'chart_trend.dart';
import 'cover_hero.dart';
import 'platform_logo.dart';
import 'pressable.dart';
import 'track_actions.dart';

/// Flight tag, one per card instance. An id won't do: one album can sit in two
/// result sections, and two `Hero`s with one tag in a tree throw when the
/// transition starts. No cover, no flight.
CoverFlight? _flightFor(String? cover, Object tag) =>
    cover == null || cover.isEmpty ? null : CoverFlight(tag: tag, image: cover);

/// Track row padding. The height matters outside: the queue opens on the
/// playing track and computes its scroll offset from it.
const EdgeInsets kTrackRowPadding = EdgeInsets.symmetric(
  horizontal: 8,
  vertical: 6,
);
const double kTrackRowCover = 52;
const double kTrackRowHeight = kTrackRowCover + 12;

/// Width of the number column that replaces the cover in an album
/// ([TrackRowShell.number]). Narrower than a cover: a two-digit number needs
/// less, and on a phone a wider gutter eats the title. The height stays, the
/// queue relies on [kTrackRowHeight].
const double kTrackRowNumber = 30;

/// History row mark: when the track was last played and how many times in all.
@immutable
class HistoryMark {
  const HistoryMark({required this.time, required this.count});

  /// Already formatted time: the format depends on locale and system settings,
  /// known only to the widget.
  final String time;

  final int count;
}

/// Track row: cover, title and artist, duration. A tap queues all of [queue],
/// so next and previous work.
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.source,
    this.dragIndex,
    this.mark,
    this.number,
    this.rank,
  });

  final Track track;
  final List<Track> queue;
  final int index;

  /// Track number instead of a cover; see [TrackRowShell.number].
  final int? number;

  /// Chart position; see [TrackRowShell.rank].
  final int? rank;

  /// Where [queue] came from; see [PlaybackState.source]. A row inside a
  /// playlist starts it whole: its tile should show the equalizer and the
  /// player's pill should name it.
  final PlaySource? source;

  /// Row index in `ReorderableList`; see [TrackRowShell.dragIndex]. `null`
  /// where the order isn't mine, like search results and platform pages.
  final int? dragIndex;

  /// Set only in history; see [HistoryMark].
  final HistoryMark? mark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrackRowShell(
      track: track,
      active: ref.watch(playbackProvider).track?.id == track.id,
      onTap: () => ref
          .read(playbackProvider.notifier)
          .playQueue(queue, index, source: source),
      // The sheet learns the library section from the list's source; it has no
      // other sign of where the row is from, and Remove from playlist depends
      // on it.
      onMenu: () => showTrackActions(
        context,
        ref,
        track,
        listId: switch (source) {
          LibSource(:final listId) => listId,
          _ => null,
        },
      ),
      dragIndex: dragIndex,
      mark: mark,
      number: number,
      rank: rank,
    );
  }
}

/// Track row with no tie to a list: the look and gestures, with actions from
/// outside. One for playlists, search results, platform pages and the queue, so
/// lists can't drift apart.
class TrackRowShell extends StatelessWidget {
  const TrackRowShell({
    super.key,
    required this.track,
    required this.active,
    required this.onTap,
    required this.onMenu,
    this.dragIndex,
    this.mark,
    this.number,
    this.rank,
  });

  final Track track;

  /// Chart position: a number and trend column BEFORE the cover, which stays,
  /// unlike with [number]. Only on the chart page.
  final int? rank;

  /// Now playing: the title in accent, an equalizer instead of the duration.
  /// The caller decides: a track can be in the queue twice, and ids can't tell
  /// them apart.
  final bool active;

  final VoidCallback onTap;

  /// Long press opens the track menu.
  final VoidCallback onMenu;

  /// Row index in `ReorderableList`. When set, the cover becomes the drag
  /// handle, and the menu moves from the cover to the rest of the row: two long
  /// presses in one place fight in the arena and the menu wins over the drag.
  final int? dragIndex;

  /// Set only in history; see [HistoryMark].
  final HistoryMark? mark;

  /// Track number in an album. When set it replaces the cover: on an album page
  /// every row has the same one.
  final int? number;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final drag = dragIndex;
    final Widget plain = switch (number) {
      final n? => _Number(number: n, active: active),
      null => SourcedCover(
        url: track.cover,
        size: kTrackRowCover,
        source: track.source,
        small: true,
      ),
    };
    final Widget cover = switch (rank) {
      final r? => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Rank(rank: r, track: track, active: active),
          const SizedBox(width: 6),
          plain,
        ],
      ),
      null => plain,
    };

    return InkWell(
      onTap: onTap,
      onLongPress: drag == null ? onMenu : null,
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Padding(
        padding: kTrackRowPadding,
        child: Row(
          children: [
            if (drag == null)
              cover
            else
              ReorderableDelayedDragStartListener(index: drag, child: cover),
            const SizedBox(width: 12),
            Expanded(
              child: _Rest(
                track: track,
                active: active,
                onMenu: drag == null ? null : onMenu,
                mark: mark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A cover with the platform's badge in its corner.
class SourcedCover extends StatelessWidget {
  const SourcedCover({
    super.key,
    required this.url,
    required this.size,
    required this.source,
    this.small = false,
    this.flight,
    this.overlay,
  });

  final String? url;
  final double size;
  final MusicSource source;

  /// In a row: a smaller badge, closer to the edge.
  final bool small;
  final CoverFlight? flight;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final edge = small ? 3.0 : 6.0;
    return Stack(
      children: [
        Cover(url: url, size: size, flight: flight, overlay: overlay),
        Positioned(
          right: edge,
          bottom: edge,
          child: SourceBadge(source, size: small ? kRowBadge : kCardBadge),
        ),
      ],
    );
  }
}

/// Track number in the cover's place: a muted digit in tabular figures so 9 and
/// 10 line up, in accent for the playing track. No equalizer here: it already
/// sits in the duration frame, and a second one is noise.
class _Number extends StatelessWidget {
  const _Number({required this.number, required this.active});

  final int number;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      width: kTrackRowNumber,
      height: kTrackRowCover,
      child: Center(
        child: Text(
          '$number',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: active ? t.accent : t.text2,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Chart position and its trend: the number with ▲2 under it.
class _Rank extends StatelessWidget {
  const _Rank({required this.rank, required this.track, required this.active});

  final int rank;
  final Track track;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      width: kTrackRowNumber + 4,
      height: kTrackRowCover,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$rank',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: active ? t.accent : t.text,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          ChartTrend(track: track),
        ],
      ),
    );
  }
}

/// The row minus the cover: text, offline mark, duration. A separate piece
/// because in draggable rows the long press lives on it.
class _Rest extends StatelessWidget {
  const _Rest({
    required this.track,
    required this.active,
    this.onMenu,
    this.mark,
  });

  final Track track;
  final bool active;
  final VoidCallback? onMenu;
  final HistoryMark? mark;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final mark = this.mark;

    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: active
                          ? theme.titleMedium?.copyWith(color: t.accent)
                          : theme.titleMedium,
                    ),
                  ),
                  // Play count only above one: everything in history has been
                  // played once.
                  if (mark != null && mark.count > 1) ...[
                    const SizedBox(width: 6),
                    CountBadge(mark.count),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Brighter than a usual caption: in a track row the artist
                // reads on a par with the title.
                style: theme.bodySmall?.copyWith(color: t.text2),
              ),
            ],
          ),
        ),
        _OfflineMark(trackId: track.id),
        if (mark != null) ...[
          const SizedBox(width: 10),
          Text(
            mark.time,
            style: theme.bodySmall?.copyWith(color: t.muted, fontSize: 11),
          ),
        ],
        const SizedBox(width: 10),
        DurationPill(track: track, active: active),
      ],
    );

    if (onMenu == null) return row;
    // `opaque`, so the menu also opens from the gap between the text and the
    // duration. The tap stays with the row's `InkWell`, since this detector has
    // no tap of its own and the highlight covers the whole row.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onMenu,
      child: row,
    );
  }
}

/// Mark for a track kept on the device, before the duration. While downloading,
/// a progress ring takes its place, indefinite if the CDN gave no size.
///
/// `select`, because a list has hundreds of rows and they shouldn't redraw on
/// each tick of another track's progress.
class _OfflineMark extends ConsumerWidget {
  const _OfflineMark({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final status = ref.watch(
      offlineProvider.select(
        (s) => (
          saved: s.has(trackId),
          pending: s.isPending(trackId),
          progress: s.progressOf(trackId),
        ),
      ),
    );

    if (status.pending) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: BloomSpinner(
          size: 14,
          stroke: 1.6,
          color: t.accent,
          value: status.progress,
          trackColor: t.ovlLine,
        ),
      );
    }
    if (!status.saved) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: BloomIcon(Bi.diskette, size: 14, color: t.text2),
    );
  }
}

/// Track duration in a frame: rounder than the theme (0.85) with the quietest
/// line (`ovlLine`), so it doesn't compete with the title. The playing track
/// shows an equalizer in the same frame instead of digits.
class DurationPill extends ConsumerWidget {
  const DurationPill({super.key, required this.track, required this.active});

  final Track track;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    // Only the playing row asks for the play/pause stream; extra subscriptions
    // in a long list are pointless.
    final child = active
        ? EqualizerBars(playing: ref.watch(playingNowProvider))
        : Text(
            mmss(track.duration),
            style: theme.bodySmall?.copyWith(
              color: t.text2,
              fontWeight: FontWeight.w600,
            ),
          );

    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      height: 30,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.ovlLine),
        borderRadius: BorderRadius.circular(t.radius * 0.85),
      ),
      child: child,
    );
  }
}

/// Equalizer of the playing set, an overlay for its card's cover. The cover
/// dims slightly so the bars show on a busy picture.
///
/// A set that isn't playing returns nothing rather than no overlay: the overlay
/// decides, or every tile in a grid would need its own subscription to the
/// player.
class SetEqualizer extends ConsumerWidget {
  const SetEqualizer({super.key, required this.setId});

  /// The same id that goes into `playQueue(sourceId:)`: a platform set or a
  /// library list.
  final String setId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playingSet = ref.watch(
      playbackProvider.select((s) => s.sourceId == setId),
    );
    if (!playingSet) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, box) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.32),
        child: Center(
          // The bars are sized for a track row: larger on a big tile, unchanged
          // on a small one.
          child: EqualizerBars(
            playing: ref.watch(playingNowProvider),
            scale: (box.maxWidth / 56).clamp(1.0, 3.0),
          ),
        ),
      ),
    );
  }
}

/// Album or playlist row: cover, title, owner. For sets in a list rather than a
/// carousel, as in an artist's reposts.
class SetRow extends StatefulWidget {
  const SetRow({super.key, required this.set});

  final Playlist set;

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final t = context.bloom;
    final flight = _flightFor(set.cover, _tag);
    final sub = [
      set.isAlbum ? context.l.commonAlbum : context.l.commonPlaylist,
      set.ownerName,
      if (set.trackCount != null) context.l.tracksCount(set.trackCount!),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: () => openSet(context, set, flight: flight),
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            SourcedCover(
              url: set.cover,
              size: 48,
              source: set.source,
              small: true,
              flight: flight,
              overlay: SetEqualizer(setId: set.id),
            ),
            const SizedBox(width: 12),
            Expanded(child: TwoLines(set.title, sub)),
          ],
        ),
      ),
    );
  }
}

/// A card: a square on top, a title and lines under it, all of it pressing.
class EntityCard extends StatelessWidget {
  const EntityCard({
    super.key,
    required this.cover,
    this.title = '',
    this.head,
    this.titleStyle,
    this.lines = const [],
    this.size,
    this.center = false,
    this.onTap,
    this.onLongPress,
  });

  /// Gets the card's width.
  final Widget Function(double side) cover;
  final String title;

  /// Instead of [title]: a line with marks around the name.
  final Widget? head;

  /// `titleSmall` when not set.
  final TextStyle? titleStyle;
  final List<String> lines;

  /// `null`: the whole width of a grid's cell.
  final double? size;
  final bool center;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final align = center ? TextAlign.center : TextAlign.start;
    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          cover(box.maxWidth),
          const SizedBox(height: 8),
          head ??
              Text(
                title,
                maxLines: 1,
                textAlign: align,
                overflow: TextOverflow.ellipsis,
                style: titleStyle ?? theme.titleSmall,
              ),
          const SizedBox(height: 2),
          for (final line in lines)
            Text(
              line,
              maxLines: 1,
              textAlign: align,
              overflow: TextOverflow.ellipsis,
              style: theme.bodySmall,
            ),
        ],
      ),
    );
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.97,
      child: size == null ? content : SizedBox(width: size, child: content),
    );
  }
}

/// Track card for a carousel. A tap queues all of [queue], like a track row.
class TrackCard extends ConsumerWidget {
  const TrackCard({
    super.key,
    required this.track,
    required this.queue,
    required this.index,
    this.source,
    this.size = 132,
  });

  final Track track;
  final List<Track> queue;
  final int index;
  final PlaySource? source;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(playbackProvider).track?.id == track.id;
    return EntityCard(
      size: size,
      title: track.name,
      titleStyle: active
          ? Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: context.bloom.accent)
          : null,
      lines: [track.artist],
      cover: (side) =>
          SourcedCover(url: track.cover, size: side, source: track.source),
      onTap: () => ref
          .read(playbackProvider.notifier)
          .playQueue(queue, index, source: source),
      onLongPress: () => showTrackActions(context, ref, track),
    );
  }
}

/// Artist card: round avatar, name and Artist (Profile for a SoundCloud
/// listener). A tap opens the artist page.
///
/// With a `null` [size] it fills the grid cell; a number is a fixed carousel
/// width.
class ArtistCard extends StatefulWidget {
  const ArtistCard({
    super.key,
    required this.artist,
    this.size = 104,
    this.centerLabel = false,
    this.pinned = false,
  });

  final Artist artist;
  final double? size;

  /// A pin after the name.
  final bool pinned;

  /// Centred labels, as in artist grids and library follows.
  final bool centerLabel;

  @override
  State<ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<ArtistCard> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    final theme = Theme.of(context).textTheme;
    final flight = _flightFor(artist.avatar, _tag);
    return EntityCard(
      size: widget.size,
      center: widget.centerLabel,
      head: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              artist.name,
              maxLines: 1,
              textAlign: widget.centerLabel
                  ? TextAlign.center
                  : TextAlign.start,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall,
            ),
          ),
          if (widget.pinned) ...[
            const SizedBox(width: 4),
            BloomIcon(Bi.pin, size: 13, color: context.bloom.text2),
          ],
        ],
      ),
      lines: [
        artist.profile ? context.l.commonProfile : context.l.commonArtist,
      ],
      cover: (side) =>
          Cover(url: artist.avatar, size: side, circle: true, flight: flight),
      onTap: () =>
          openArtist(context, artist.id, initial: artist, flight: flight),
    );
  }
}

/// A release's type as the platform says it; an album unless it says otherwise.
String releaseKind(AppLocalizations l, String? albumType) =>
    switch (albumType) {
      'single' => l.relSingle,
      'ep' => l.relEp,
      'compilation' => l.relCompilation,
      'podcast' => l.relPodcast,
      _ => l.relAlbum,
    };

/// The lines under an album's or a playlist's title: an album's "artist ·
/// type" over its date (the year when that's all the platform says), a
/// playlist's owner.
List<String> setLines(BuildContext context, Playlist set) {
  final owner = set.ownerName ?? '';
  if (!set.isAlbum) return [if (owner.isNotEmpty) owner];
  final date =
      releaseDayShort(
        set.releaseDate,
        Localizations.localeOf(context).toString(),
      ) ??
      set.year ??
      '';
  return [
    [
      owner,
      releaseKind(context.l, set.albumType),
    ].where((s) => s.isNotEmpty).join(' · '),
    if (date.isNotEmpty) date,
  ];
}

/// An album card's caption is a line taller than a playlist's: its height
/// under the cover, for the rows and grids that size their cells.
double setCaption(Iterable<Playlist> sets) =>
    sets.any((s) => s.isAlbum) ? 66 : 48;

/// A carousel of [SetCard]s at their default width: the cover, the caption
/// and some air under it.
double setRowHeight(Iterable<Playlist> sets) => 146 + setCaption(sets);

/// Playlist or album card: cover, title and [setLines].
///
/// With a `null` [size] it fills the grid cell; a number is a fixed carousel
/// width.
class SetCard extends StatefulWidget {
  const SetCard({super.key, required this.set, this.size = 132});

  final Playlist set;
  final double? size;

  @override
  State<SetCard> createState() => _SetCardState();
}

class _SetCardState extends State<SetCard> {
  final _tag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final flight = _flightFor(set.cover, _tag);
    return EntityCard(
      size: widget.size,
      title: set.title,
      lines: setLines(context, set),
      cover: (side) => SourcedCover(
        url: set.cover,
        size: side,
        source: set.source,
        flight: flight,
        overlay: SetEqualizer(setId: set.id),
      ),
      onTap: () => openSet(context, set, flight: flight),
    );
  }
}

/// A grid of cards over the whole width: a cell's height is its width plus
/// [caption].
class CardGrid extends StatelessWidget {
  const CardGrid({
    super.key,
    required this.columns,
    required this.caption,
    required this.itemCount,
    required this.itemBuilder,
    this.top = 4,
    this.bottom,
    this.scrolls = true,
  });

  final int columns;
  final double caption;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double top;

  /// Clear of the bars when not set.
  final double? bottom;
  final bool scrolls;

  static const double _side = 16;
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cell = (width - _side * 2 - _gap * (columns - 1)) / columns;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        _side,
        top,
        _side,
        bottom ?? 16 + bottomBarsInset(context),
      ),
      physics: scrolls ? null : const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: _gap,
        mainAxisSpacing: 20,
        mainAxisExtent: cell + caption,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

/// Keys for rows of a list where a track may repeat.
List<Key> trackRowKeys(List<Track> tracks) {
  final seen = <String, int>{};
  return [
    for (final track in tracks)
      ValueKey('${track.id}#${seen[track.id] = (seen[track.id] ?? -1) + 1}'),
  ];
}

/// How a track row looks in the finger while being dragged.
Widget trackRowDragged(BuildContext context, Widget child) {
  final t = context.bloom;
  return Material(
    color: t.pill,
    elevation: 6,
    borderRadius: BorderRadius.circular(t.radius * 0.85),
    child: child,
  );
}

/// Horizontal strip of cards, for search results and artist page sections.
class EntityCarousel extends StatelessWidget {
  const EntityCarousel({
    super.key,
    required this.height,
    required this.itemCount,
    required this.builder,
    this.padding = 8,
  });

  final double height;
  final int itemCount;
  final Widget Function(int index) builder;

  /// Strip inset from the screen edges. 8 by default, as in result lists, where
  /// rows already have padding; on the home page it's 16, level with section
  /// titles.
  final double padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => builder(i),
      ),
    );
  }
}

/// A section title. With [onTap] it's a link to the whole of it, an arrow
/// after the words.
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.onTap,
    this.side = 16,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final VoidCallback? onTap;

  /// A small link at the right ("Show all").
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Off the screen's edges; 8 where the rows below pad themselves.
  final double side;

  @override
  Widget build(BuildContext context) {
    final action = onAction == null ? null : actionLabel;
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleLarge,
    );
    final row = Row(
      children: [
        if (action == null) Flexible(child: text) else Expanded(child: text),
        if (onTap != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 2),
            child: BloomIcon(
              Bi.arrowRight,
              size: 22,
              color: context.bloom.text.withValues(alpha: 0.55),
            ),
          ),
        if (action case final label?) ...[
          Pressable(
            onTap: onAction,
            scale: 0.97,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 15,
                  color: context.bloom.text2,
                ),
              ),
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 18, side, 10),
      child: onTap == null
          ? row
          : Pressable(onTap: onTap, scale: 0.98, child: row),
    );
  }
}
