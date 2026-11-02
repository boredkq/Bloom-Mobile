/// Source pill in the player's header: what's playing now, being favourites, a
/// playlist, an album, an artist page or search results. A 24×24 source
/// picture, then its name, a shuffle icon when on (the list isn't in its order,
/// and that should show), and at the right edge past a hairline divider the
/// queue's track count.
///
/// Two gestures. A TAP opens the queue sheet: the pill is the only queue button
/// on screen, and the queue opens far more often than its source. A LONG press
/// goes to the source and closes the player. Sources with no page (search, a
/// home shelf, a single track) have no long press.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/marquee_text.dart';
import '../../../shared/ui/pressable.dart';
import '../../detail/detail_nav.dart';
import '../../library/ui/list_hero.dart';
import '../../profile/ui/history_sheet.dart';
import '../play_source.dart';
import 'player_sheet.dart';
import 'queue_sheet.dart';

/// Pill sizes, kept here: the header is built from these and [kHeaderControl],
/// with the pill as tall as the round buttons at its edges, or the header reads
/// as a step.
const double _iconSize = 28;
const double _gap = 10;

/// Opens the queue's source: closes the player and sheets over it and goes to
/// its page. The page goes in the CURRENT tab's navigator, not the root: from
/// search and the library these pages open under the tab bar and mini player,
/// and from here they must look the same (see [currentBranchNavigator]).
void openPlaySource(BuildContext context, PlaySource source) {
  // The navigator clears sheets over the player, but the player isn't a route:
  // it's a shell layer that folds by its own call (see `PlayerSheet`).
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  collapsePlayerSheet();
  switch (source) {
    case LibSource(listId: 'history'):
      // History is a sheet over the profile: the profile first, then the sheet
      // once it's laid out.
      bloomRouter.go(kProfileLocation);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final root = bloomRouter.routerDelegate.navigatorKey.currentContext;
        if (root != null) showHistorySheet(root);
      });
    case LibSource(:final listId):
      // A library section is a route, which also switches the tab.
      bloomRouter.go('/library/list/$listId');
    case SetSource(:final set):
      final nav = currentBranchNavigator();
      if (nav != null) openSetIn(nav, set);
    case ArtistSource(:final artist):
      final nav = currentBranchNavigator();
      if (nav != null) openArtistIn(nav, artist.id, initial: artist);
    case PlainSource():
    case WaveSource():
      // Search, a shelf, a single track, the wave: nothing to open.
      break;
  }
}

/// Whether a source has a page. [PlainSource] and [WaveSource] don't: that pill
/// draws with no ripple and catches no tap.
bool playSourceOpens(PlaySource source) =>
    source is! PlainSource && source is! WaveSource;

class SourcePill extends ConsumerWidget {
  const SourcePill({
    super.key,
    required this.source,
    required this.shuffle,
    required this.count,
    this.background,
    this.borderColor,
  });

  /// Fill. `null` is the theme's usual plate (`pill`). The player's header on
  /// its own background passes the blocks' film here: a solid plate reads as a
  /// black patch beside the translucent transport and tools.
  final Color? background;

  /// Outline, for the same reason as [CircleIconButton.borderColor].
  final Color? borderColor;

  /// Queue source. `null` means from nowhere (an old session snapshot), and the
  /// pill just calls itself the queue.
  final PlaySource? source;

  /// Shuffle, an icon after the source's name.
  final bool shuffle;

  /// Tracks in the queue, the count at the pill's right edge. Zero isn't drawn:
  /// there's no empty queue on this screen, but an old session snapshot might
  /// arrive so.
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final source = this.source;
    final label = source == null
        ? context.l.playerQueue
        : _label(context, ref, source);
    // Not every queue can go to its source; then only the tap remains.
    final opens = source != null && playSourceOpens(source);

    final border = borderColor;
    return Center(
      child: Pressable(
        // Tap is the queue, always: the pill replaced the queue button in the
        // tool row and can't be dead.
        onTap: () => showQueueSheet(context),
        // Long press is the source. Feedback is a must: a long press has no
        // look of its own, and otherwise you can't tell it from a slow tap.
        onLongPress: opens
            ? () {
                HapticFeedback.selectionClick();
                openPlaySource(context, source);
              }
            : null,
        child: Material(
          color: background ?? t.pill,
          // The pill is as tall as the round buttons, so `StadiumBorder` is the
          // same radius; the shape is for the outline: `Material` takes either
          // a radius or a shape, not both.
          shape: StadiumBorder(
            side: border == null ? BorderSide.none : BorderSide(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            // More margin on the left than over the picture: the pill's edge is
            // rounded, and a square cover set evenly from it hits the curve.
            // Less on the right: the count stands there with its own outline,
            // and a double margin would push it off the edge further than the
            // picture on the left.
            padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
            child: SizedBox(
              height: kHeaderControl,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SourceIcon(source: source),
                  const SizedBox(width: _gap),
                  Flexible(
                    child: MarqueeText(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  if (shuffle) ...[
                    const SizedBox(width: 8),
                    // The source name's colour, not the accent: the icon reads
                    // as part of the name, and accent would pull more attention
                    // than the source.
                    BloomIcon(Bi.shuffle, size: 14, color: t.text),
                  ],
                  if (count > 0) ...[
                    // Hairline before the count: without it the outlined number
                    // sticks to the name and reads as part of it.
                    const SizedBox(width: 8),
                    // `ovlLine2`, not `ovlLine`: six percent suits a whole
                    // block's outline, but on a 1 px hair nothing would show.
                    Container(width: 1, height: 12, color: t.ovlLine2),
                    const SizedBox(width: 8),
                    _Count(count),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The source's caption. For library sections it's LIVE: a playlist may be
  /// renamed as it plays (see [PlaySource]).
  String _label(BuildContext context, WidgetRef ref, PlaySource source) {
    switch (source) {
      case LibSource(:final listId):
        return switch (listId) {
          'all' => context.l.commonAllTracks,
          'fav' => context.l.commonFavorites,
          'history' => context.l.commonHistory,
          _ =>
            _playlist(ref, listId)?.name ??
                // The playlist was deleted during playback: the queue plays on
                // with nothing to call it.
                context.l.commonPlaylist,
        };
      case SetSource(:final set):
        return set.title;
      case ArtistSource(:final artist):
        return artist.name;
      case PlainSource(:final label):
        return label;
      case WaveSource(:final label):
        return label;
    }
  }
}

/// Queue track count: a number in an outline, in the source name's colour.
/// Width by content: three-digit queues are common, and the name beside it
/// shrinks first.
class _Count extends StatelessWidget {
  const _Count(this.value);

  final int value;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      height: 20,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        border: Border.all(color: t.ovlLine2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
          color: t.text,
        ),
      ),
    );
  }
}

UserPlaylist? _playlist(WidgetRef ref, String id) {
  for (final playlist in ref.watch(libraryProvider).playlists) {
    if (playlist.id == id) return playlist;
  }
  return null;
}

/// Source picture: a set's cover, an artist's avatar, a playlist's collage or a
/// section's tint, just what its card shows.
class _SourceIcon extends ConsumerWidget {
  const _SourceIcon({required this.source});

  final PlaySource? source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final radius = t.radius * 0.4;

    switch (source) {
      case null:
        return _tint(t, radius, t.ovlBg, t.muted, Bi.musicNoteBold);
      case LibSource(:final listId):
        final glyph = systemListGlyph(listId);
        if (glyph != null) return _outline(t, radius, glyph);
        // Playlist: its own cover, then a collage of first tracks, as on its
        // tile.
        final lib = ref.watch(libraryProvider);
        final playlist = _playlist(ref, listId);
        return Cover(
          url: playlist?.cover,
          size: _iconSize,
          radius: radius,
          covers: playlist == null
              ? const <String?>[]
              : lib.tracksOf(playlist).map((track) => track.cover),
        );
      case WaveSource():
        // The wave isn't a list and has no cover: the icon takes the theme's
        // accent.
        return _tint(t, radius, t.ovlBg, t.accent, Bi.soundwaveBold);
      case SetSource(:final set):
        return Cover(url: set.cover, size: _iconSize, radius: radius);
      case ArtistSource(:final artist):
        return Cover(url: artist.avatar, size: _iconSize, circle: true);
      case PlainSource(:final cover, :final icon):
        if (cover != null) {
          return Cover(url: cover, size: _iconSize, radius: radius);
        }
        return switch (icon) {
          PlainSourceIcon.search => _tint(
            t,
            radius,
            t.ovlBg,
            t.text2,
            Bi.magnifier,
          ),
          PlainSourceIcon.clock => _outline(t, radius, Bi.clockCircle),
          PlainSourceIcon.chart => _tint(
            t,
            radius,
            t.sysAllTint,
            t.sysAllIco,
            Bi.chart2,
          ),
          PlainSourceIcon.note => _tint(
            t,
            radius,
            t.ovlBg,
            t.muted,
            Bi.musicNoteBold,
          ),
        };
    }
  }

  /// The library's own lists and history: their icon on an outline.
  Widget _outline(BloomTokens t, double radius, BloomGlyph icon) =>
      SizedBox.square(
        dimension: _iconSize,
        child: OutlineArt(
          icon: icon,
          iconSize: (_iconSize * 0.5).roundToDouble(),
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  Widget _tint(
    BloomTokens t,
    double radius,
    Color tint,
    Color color,
    BloomGlyph icon,
  ) => Container(
    width: _iconSize,
    height: _iconSize,
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: BloomIcon(icon, size: _iconSize * 0.54, color: color),
  );
}
