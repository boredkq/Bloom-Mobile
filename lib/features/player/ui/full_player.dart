/// Full player: a header (collapse, playing from, menu), a large cover, title
/// and artist, progress, transport as its own block, and a tool row below.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/entities/entities.dart';
import '../../../core/log/bloom_log.dart';
import '../../../core/store/library_store.dart';
import '../../../features/customization/custom_store.dart';
import '../../../features/customization/ui/image_thumb.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/marquee_text.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/ui/track_flick.dart';
import '../../../shared/ui/track_swipes.dart';
import '../../../shared/util/format.dart';
import '../../detail/artists_sheet.dart';
import '../../lyrics/lyrics_store.dart';
import '../../lyrics/ui/lyrics_view.dart';
import '../../pc/pc_remote.dart';
import '../../pc/pc_store.dart';
import '../play_error.dart';
import '../player_bg_store.dart';
import '../player_controller.dart';
import '../player_style_store.dart';
import '../player_view_store.dart';
import '../sleep_timer_store.dart';
import '../slider_style_store.dart';
import '../speed_store.dart';
import 'artist_avatars.dart';
import 'play_button.dart';
import 'player_backdrop.dart';
import 'player_sheet.dart';
import 'queue_sheet.dart';
import 'sleep_sheet.dart';
import 'slider_shapes.dart';
import 'source_pill.dart';
import 'speed_sheet.dart';
import 'track_swap.dart';
import 'vinyl_disc.dart';

/// Cover radius in the player, much rounder than blocks.
const double _coverRadius = 20;

/// Gap between the source pill and the header's round buttons.
const double _headerGap = 8;

/// What a tap on the title copies: "Title — Artist". With no artist, just the
/// title, or a dangling dash stays.
String trackCopyText(Track track) {
  final artist = track.artist.trim();
  return artist.isEmpty ? track.name : '${track.name} — $artist';
}

/// Player content full screen. Not a screen or route: the panel ([PlayerSheet])
/// builds it inside the growing card and clips it until it reaches the edges.
/// So layout always counts on the FULL screen, however much shows, or it would
/// squeeze mid-expansion and jump at the end. And it closes with
/// [collapsePlayerSheet], not `pop`.
class FullPlayerBody extends ConsumerStatefulWidget {
  const FullPlayerBody({super.key});

  @override
  ConsumerState<FullPlayerBody> createState() => _FullPlayerBodyState();
}

class _FullPlayerBodyState extends ConsumerState<FullPlayerBody> {
  @override
  void initState() {
    super.initState();
    // Opening the player goes to the log, straight to disk. The screen is
    // heavy: blurs, the cover's shadow, animations. If the process dies
    // silently here rather than on sound, this line is the only clue.
    logInfo('ui', 'full-screen player opened', now: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final track = state.track;
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    final lyricsMode = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
    final swipes = ref.watch(swipeProvider).of(SwipeZone.player);

    return Scaffold(
      // The theme's fill stays under the player's background, which covers it
      // fully, and in none mode it's what shows. `Scaffold` can't be clear:
      // what the panel lies over would show through.
      backgroundColor: t.bg,
      // No pull down here: the panel catches it outside the content, or two
      // gestures would fight for the finger.
      //
      // The horizontal gesture is caught across the screen but moves only the
      // cover and captions: header and transport aren't about the track. The
      // progress trap below overrides it, as a nearer detector should.
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background per the player setting. Below the content and above the
          // fill: block films (`ovlBg`) must show on it.
          const PlayerBackdrop(),
          _body(context, state, track, lyricsOpen, lyricsMode, swipes),
        ],
      ),
    );
  }

  /// Player content over the background.
  Widget _body(
    BuildContext context,
    PlaybackState state,
    Track? track,
    bool lyricsOpen,
    LyricsMode lyricsMode,
    SwipePair swipes,
  ) {
    return TrackFlick(
      // The gesture must be caught ACROSS the screen, not just where
      // something's drawn: beside a square cover and in the column's gaps
      // there's no content, and `deferToChild` let it through to the panel
      // below, which with neighbours on moves as a whole card, carrying the
      // open player sideways.
      behavior: HitTestBehavior.opaque,
      onLeft: track == null || swipes.left == SwipeAction.none
          ? null
          : () => runSwipeAction(
              context,
              ref,
              swipes.left,
              track: track,
              fromFlick: true,
            ),
      onRight: track == null || swipes.right == SwipeAction.none
          ? null
          : () => runSwipeAction(
              context,
              ref,
              swipes.right,
              track: track,
              fromFlick: true,
            ),
      builder: (context, shift) => SafeArea(
        // The bottom uses [bottomEdgeInset], not `SafeArea`: the tool row must
        // end where the tab bar's edge does under a list, or opening the player
        // looks like a layout jump. The full iOS home indicator inset (34)
        // would also lift everything well above Android.
        bottom: false,
        child: track == null
            ? const SizedBox.shrink()
            : Padding(
                // Air on top: the header shouldn't stick to the status bar.
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  bottomEdgeInset(context),
                ),
                child: Column(
                  children: [
                    _Header(track: track, state: state),
                    const SizedBox(height: 16),
                    // Cover centred in the free space, or text in its place in
                    // replace mode. In over mode the cover stays and the text
                    // lies on it as a card (see `_Cover`).
                    //
                    // `Expanded`, not `Flexible`: the text panel scrolls, and
                    // under loose constraints takes its height from content.
                    // While loading that's one line, so the column collapsed
                    // and the bottom rode up.
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: lyricsOpen && lyricsMode == LyricsMode.replace
                            ? const _LyricsPane(key: ValueKey('lyrics'))
                            : Center(
                                key: const ValueKey('cover'),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: FlickSlide(
                                    shift: shift,
                                    child: _Cover(
                                      state: state,
                                      lyricsOpen:
                                          lyricsOpen &&
                                          lyricsMode == LyricsMode.overlay,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    // Equal gaps around the title: it should stand right
                    // between cover and progress. Below, the same ~24 comes
                    // from the margins around the artist's name, this eight and
                    // the upper half of the progress trap (`_Progress.slack`).
                    const SizedBox(height: 24),
                    // Captions respond half as strongly as the cover: they're
                    // narrower than the card and at its pace would fly off the
                    // edge first.
                    FlickSlide(
                      shift: shift,
                      amplitude: 0.5,
                      child: _TitleBlock(state: state),
                    ),
                    const SizedBox(height: 8),
                    const _Progress(),
                    const SizedBox(height: 16),
                    const _Transport(),
                    const SizedBox(height: 12),
                    const _Tools(),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.track, required this.state});

  /// The current track, for the three-dot menu.
  final Track track;

  /// Player state: the pill needs the queue's source and the shuffle flag.
  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    // On its own background the header takes the SAME colour as the transport
    // and tool blocks (`ovlBg` plus `ovlLine`): a solid theme plate (`pill`)
    // reads as a black patch beside the translucent bottom. With no background
    // a 3% film over the theme fill is nearly the same fill, only dimmer.
    final bg = ref.watch(playerBgProvider);
    final fill = bg.isNone ? null : t.ovlBg;
    final line = bg.isNone ? null : t.ovlLine;

    return Row(
      children: [
        CircleIconButton(
          icon: Bi.altArrowDown,
          iconSize: 23,
          background: fill,
          borderColor: line,
          // An own fill usually turns glass off, but this is a theme surface
          // rather than a state, so with transparency on the header gets glass.
          glass: true,
          // Not `pop`: the player is a shell layer, not a route (see
          // `PlayerSheet`).
          onTap: collapsePlayerSheet,
        ),
        // Source pill: the same film and height as the round buttons at the
        // edges, so the header reads as one even row. Names can be long, so it
        // takes all the remaining width and shrinks inside. Side gaps are a
        // must: otherwise a long name swells the pill against the circles, and
        // all three films merge into a strip.
        const SizedBox(width: _headerGap),
        Expanded(
          child: SourcePill(
            source: state.source,
            shuffle: state.shuffle,
            count: state.queue.length,
            background: fill,
            borderColor: line,
          ),
        ),
        const SizedBox(width: _headerGap),
        CircleIconButton(
          icon: Bi.kebab,
          background: fill,
          borderColor: line,
          glass: true,
          onTap: () => showTrackActions(context, ref, track),
        ),
      ],
    );
  }
}

/// Text in place of the cover. It takes ALL of the column's free space rather
/// than the cover's square, fitting many more lines, which is the point of this
/// mode.
class _LyricsPane extends StatelessWidget {
  const _LyricsPane({super.key});

  @override
  Widget build(BuildContext context) => const LyricsView(
    padding: EdgeInsets.fromLTRB(8, 24, 8, 24),
    // Its own layout, larger and left-aligned: the box is the screen's width,
    // not the cover's square (see `LyricsLayout`).
    layout: LyricsLayout.replace,
  );
}

class _Cover extends ConsumerWidget {
  const _Cover({required this.state, this.lyricsOpen = false});

  final PlaybackState state;

  /// The text panel over the cover is open.
  final bool lyricsOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = state.track!;
    // Vinyl: a round cover, spinning, with a dark label in the centre.
    final vinyl = ref.watch(playerStyleProvider).isVinyl;
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.biggest.shortestSide;
        // The circle is the same radius taken to half the side, so all the
        // cover frame clips (picture, text panel) turns round at once.
        final radius = vinyl ? side / 2 : _coverRadius;
        // Spins ONLY while sound plays. The state comes from the player itself,
        // not `PlaybackState`, which lacks it: a pause from the shade or
        // headset must stop the disc too.
        final spinning = ref.watch(playingNowProvider);
        return Stack(
          children: [
            // The cover's frame clips the track change layers, and pictures
            // inside have NO radius of their own, or the leaving one shows a
            // rounded corner mid-frame.
            SizedBox(
              width: side,
              height: side,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: VinylSpin(
                  // The whole stack of change layers spins, not just the
                  // current picture, or the arriving cover stands straight
                  // while the leaving one spins: two motions in one frame.
                  enabled: vinyl,
                  spinning: spinning,
                  child: TrackSwap(
                    id: track.id,
                    fade: true,
                    child: Cover(
                      // A custom cover from customization beats the track's.
                      url: ref.watch(playerCoverProvider),
                      size: side,
                      radius: 0,
                    ),
                  ),
                ),
              ),
            ),
            // The label stands OVER the cover but under the text panel, and
            // doesn't spin with the disc.
            if (vinyl)
              Positioned(
                left: 0,
                top: 0,
                width: side,
                height: side,
                child: Center(child: VinylLabel(size: side * VinylLabel.share)),
              ),
            // Text panel over the cover: the block's colour at 96%, appearing
            // with a fade and a slight zoom. ALWAYS drawn, visibility by
            // opacity, or the animation has nothing to play.
            Positioned(
              left: 0,
              top: 0,
              width: side,
              height: side,
              child: IgnorePointer(
                ignoring: !lyricsOpen,
                child: AnimatedOpacity(
                  opacity: lyricsOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: AnimatedScale(
                    scale: lyricsOpen ? 1 : 0.97,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: ColoredBox(
                        color: context.bloom.blockColor.withValues(alpha: 0.96),
                        child: LyricsView(
                          live: lyricsOpen,
                          // A disc keeps the lines off its edge: 52 on a 380
                          // disc.
                          padding: vinyl
                              ? EdgeInsets.all(side * 0.14)
                              : const EdgeInsets.fromLTRB(14, 36, 14, 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final track = state.track!;
    final theme = Theme.of(context).textTheme;

    // The artist's name leads to their page, as from the track menu; with
    // several in the row, a sheet to pick first. A playback error may stand in
    // the name's place, and then the row is plain text. A lone artist with no
    // exact id can't open either.
    final canOpen = state.error == null && canOpenTrackArtist(track);

    // Where title and artist are aligned, per the setting.
    final align = ref.watch(titleAlignProvider);

    // The state holds an error CODE, expanded to a phrase here at paint time.
    final error = state.error;
    final subtitle = Text(
      error == null ? track.artist : describePlayError(context.l, error),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align.text,
      // Larger than the shared caption (13): there's one line under the title
      // here, and it should read at arm's length.
      style: theme.bodyMedium?.copyWith(
        fontSize: 18,
        color: state.error != null ? t.danger : null,
      ),
    );

    // The touch trap is wider than the row, but only on the FREE side: an
    // aligned title must start where the progress bar and time do, and an extra
    // 20 px would pull it in. Centred, the margin stays on both sides, moving
    // nothing and just keeping the row off the edges.
    final pad = switch (align) {
      TitleAlign.left => const EdgeInsets.only(right: 20),
      TitleAlign.center => const EdgeInsets.symmetric(horizontal: 20),
      TitleAlign.right => const EdgeInsets.only(left: 20),
    };

    // Caption layers take the column's full width, or the slide counts from the
    // text's width and a short title moves much less than a long one. Where
    // rows sit inside is the column's job: a row that fits is as wide as its
    // text, and `textAlign` alone can't move it.
    return SizedBox(
      width: double.infinity,
      child: TrackSwap(
        id: track.id,
        child: Column(
          crossAxisAlignment: align.cross,
          children: [
            // A tap on the title copies "Title — Artist". The trap is wider
            // than the row at the sides, not in height: vertical gaps are
            // exact, and extra pixels would move the block.
            GestureDetector(
              onTap: () => _copy(context, track),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: pad,
                // The title scrolls if it doesn't fit: from the left while
                // moving, per the setting at rest.
                child: MarqueeText(
                  track.name,
                  align: align.text,
                  style: theme.headlineSmall?.copyWith(fontSize: 25),
                ),
              ),
            ),
            // The touch trap gives the gap to the name: one 19 px line of text
            // mid-screen is hard to hit.
            GestureDetector(
              onTap: canOpen
                  ? () => openTrackArtist(context, ref, track)
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: pad + const EdgeInsets.symmetric(vertical: 7),
                // The platform's artist avatars go before the name. A playback
                // error may stand there, and pictures don't belong to it. The
                // row shrinks to its content so it aligns as a column, while
                // the name inside stays flexible, or a long one would overflow
                // rather than ellipsize.
                child: state.error != null
                    ? subtitle
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TrackArtistAvatars(track: track),
                          Flexible(child: subtitle),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Copies "Title — Artist".
  Future<void> _copy(BuildContext context, Track track) async {
    if (track.name.isEmpty) return;
    final l = context.l;
    try {
      await Clipboard.setData(ClipboardData(text: trackCopyText(track)));
      if (context.mounted) {
        toaster.show(l.playerCopied, kind: ToastKind.success);
      }
    } catch (_) {
      if (context.mounted) {
        toaster.show(l.playerCopyError, kind: ToastKind.error);
      }
    }
  }
}

class _Progress extends ConsumerStatefulWidget {
  const _Progress();

  /// Track thickness of the standard type and the touch trap's height. A slider
  /// with no knob or halo shrinks to its track, and 5 px can't be hit by a
  /// finger. I stretch it to [hit]: the track draws centred and the press
  /// catches on the whole area.
  ///
  /// One trap for all slider types, though tracks differ (`sliderTrackHeight`,
  /// tallest is wave at 28), or changing type would shift the times and the
  /// player's bottom.
  static const double trackHeight = 5;

  /// The empty space left over and under the track inside the trap. The trap is
  /// symmetric, the air around the track isn't: below, the time row's top
  /// margin adds to it. So [slack] is kept on the lower side, and the
  /// `SizedBox` before progress makes up the top.
  static const double slack = 12;

  static const double hit = trackHeight + slack * 2;

  @override
  ConsumerState<_Progress> createState() => _ProgressState();
}

class _ProgressState extends ConsumerState<_Progress> {
  /// Position under the finger while dragging, ms. While not null, the track
  /// and left time follow it rather than the player. Otherwise the controlled
  /// `Slider` draws what the stream sends and the fill snaps back like elastic.
  /// I seek once, on release: a seek on a network stream is costly, and a drag
  /// has dozens of frames.
  double? _drag;

  Future<void> _commit(double v) async {
    await ref
        .read(playbackProvider.notifier)
        .seek(Duration(milliseconds: v.round()));
    // Released only after the seek itself: until then the stream still gives
    // the old position, and the bar would blink back.
    if (mounted) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final head =
        ref.watch(playheadProvider).value ??
        (position: Duration.zero, total: Duration.zero);

    // The knob picture decodes asynchronously: until then, or if none was
    // picked, the track has no knob.
    final thumb = ref.watch(sliderThumbProvider).value;
    final style = ref.watch(sliderStyleProvider);
    // The wave pattern is one per track; the id is the seed.
    final seed = ref.watch(playbackProvider.select((s) => s.track?.id)) ?? '';

    final max = head.total.inMilliseconds.toDouble();
    final live = max <= 0
        ? 0.0
        : head.position.inMilliseconds
              .clamp(0, head.total.inMilliseconds)
              .toDouble();
    final value = (_drag ?? live).clamp(0.0, max <= 0 ? 0.0 : max);

    return Column(
      children: [
        SizedBox(
          height: _Progress.hit,
          child: SliderTheme(
            // Track and knob look come wholly from the slider type. The
            // standard one is a 5 track (thicker than the usual: it's the
            // screen's main control), with no circle unless a knob picture was
            // picked.
            data: bloomSliderTheme(
              SliderTheme.of(context),
              style: style,
              tokens: context.bloom,
              thumbImage: thumb,
              waveSeed: seed.hashCode,
            ),
            child: Slider(
              value: value,
              max: max <= 0 ? 1 : max,
              onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
              onChangeEnd: max <= 0 ? null : _commit,
            ),
          ),
        ),
        // Times stand right under the trap: they get all the air to the track
        // from its lower half (`_Progress.slack`).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          // The Next plate is a LAYER over the time row, not a third cell in
          // it: in a row its centre would follow the times' width (1:45 against
          // 1:02:33), and it must stand mid-screen. The row gives the layer its
          // width, the plate its height.
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // The same colour as the artist under the title
                  // (`bodyMedium`).
                  Text(
                    mmss(Duration(milliseconds: value.round())),
                    style: theme.bodyMedium,
                  ),
                  Text(mmss(head.total), style: theme.bodyMedium),
                ],
              ),
              // Margins keep room for the times: a long title ellipsizes rather
              // than running over the numbers.
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 62),
                child: _NextUpPill(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Next plate under the slider: what plays after this. The queue is hidden in a
/// sheet, so this is the only way to see it. No plate when nothing's next
/// (`nextTrack`) or the setting is off, leaving no empty space.
///
/// A tap opens the queue, like the header's source pill. Cover and caption
/// match that pill, so two plates on one screen read alike.
class _NextUpPill extends ConsumerWidget {
  const _NextUpPill();

  /// Cover side. Smaller than the source pill's (28): this lives in the time
  /// row, and taller it would push the player's bottom apart.
  static const double _cover = 19;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(nextUpProvider)) return const SizedBox.shrink();
    final next = ref.watch(playbackProvider.select((s) => s.nextTrack));
    if (next == null) return const SizedBox.shrink();

    final t = context.bloom;
    return Pressable(
      onTap: () => showQueueSheet(context),
      child: Material(
        color: t.ovlBg,
        shape: StadiumBorder(side: BorderSide(color: t.ovlLine)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          // The left margin is TWICE the top and bottom, the same correction as
          // in the source pill: the plate's edge is rounded, and a cover set
          // evenly from it hits the arc with its corners. More air on the
          // right, for text.
          padding: const EdgeInsets.fromLTRB(9, 4, 13, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Cover(url: next.cover, size: _cover, radius: t.radius * 0.3),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  context.l.playerNextUp(next.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The plate under the player's buttons, with softer corners than a card's.
class _Plate extends StatelessWidget {
  const _Plate({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.ovlBg,
        border: Border.all(color: t.ovlLine),
        borderRadius: BorderRadius.circular(t.radius * 1.8),
      ),
      child: child,
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final ctrl = ref.read(playbackProvider.notifier);

    // Repeat mode shows by a badge rather than a swapped icon: the button is
    // always repeat, with a list mark for the whole queue and 1 for one track
    // at the top right.
    final repeatMark = switch (state.repeat) {
      PlayerRepeat.all => BloomIcon(Bi.list, size: 9, color: t.accentText),
      PlayerRepeat.one => Text(
        '1',
        style: TextStyle(
          fontSize: 8,
          // The digit sits optically above centre, so I press it down with line
          // height.
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: t.accentText,
        ),
      ),
      _ => null,
    };

    return _Plate(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _FlatIcon(
            icon: Bi.repeat,
            size: 24,
            active: state.repeat != PlayerRepeat.off,
            onTap: ctrl.cycleRepeat,
            mark: repeatMark,
          ),
          _FlatIcon(icon: Bi.skipPreviousBold, size: 30, onTap: ctrl.prev),
          PlayButton(
            size: 68,
            iconSize: 28,
            plainIconSize: 40,
            spinnerSize: 28,
            loading: state.loading,
            onTap: ctrl.toggle,
          ),
          _FlatIcon(icon: Bi.skipNextBold, size: 30, onTap: ctrl.next),
          _FlatIcon(
            icon: Bi.shuffle,
            size: 24,
            active: state.shuffle,
            onTap: ctrl.toggleShuffle,
          ),
        ],
      ),
    );
  }
}

/// Sleep timer button. A separate widget rather than a line in [_Tools]: a
/// running timer ticks each second, and the whole tool row shouldn't repaint
/// for it. A running timer shows time left INSTEAD of the moon, as the speed
/// button shows `1.25×`.
class _SleepButton extends ConsumerWidget {
  const _SleepButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleep = ref.watch(sleepTimerProvider);
    // Needs its own label: time left in place of an icon would read as a bare
    // 23:14 to a screen reader.
    return Semantics(
      button: true,
      label: context.l.playerSleep,
      child: _FlatIcon(
        icon: sleep.mode == SleepMode.endOfTrack
            ? Bi.moonSleepBold
            : Bi.moonSleep,
        size: 25,
        label: sleep.mode == SleepMode.timer
            ? sleepLabel(sleep.remaining)
            : null,
        active: sleep.active,
        onTap: () => showSleepSheet(context),
      ),
    );
  }
}

/// Play on (Connect): whether sound goes to this phone or the computer. There
/// only while the computer is connected, lit while sound is on it.
class _PlayOnButton extends ConsumerWidget {
  const _PlayOnButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(pcProvider.select((s) => s.live))) {
      return const SizedBox.shrink();
    }
    final onPc = ref.watch(pcRemoteProvider.select((r) => r != null));
    return Semantics(
      button: true,
      label: context.l.pcPlayOn,
      child: _FlatIcon(
        icon: Bi.monitorSmartphone,
        size: 25,
        active: onPc,
        onTap: () => _showPlayOn(context, ref, onPc),
      ),
    );
  }

  static void _showPlayOn(BuildContext context, WidgetRef ref, bool onPc) {
    final pc = ref.read(pcProvider).link?.name ?? '';
    final remote = ref.read(pcRemoteProvider.notifier);
    Widget? mark(bool on) => on ? const SheetTick() : null;
    showBloomSheetChild<void>(
      context: context,
      child: SheetActionsPanel(
        actions: [
          SheetAction(
            icon: Bi.monitor,
            label: pc.isEmpty ? context.l.setPc : pc,
            trailing: mark(onPc),
            onTap: onPc ? null : remote.playOnPc,
          ),
          SheetAction(
            icon: Bi.smartphone,
            label: context.l.pcThisPhone,
            trailing: mark(!onPc),
            onTap: onPc ? remote.playHere : null,
          ),
        ],
      ),
    );
  }
}

class _FlatIcon extends StatelessWidget {
  const _FlatIcon({
    required this.icon,
    this.onTap,
    this.size = 22,
    this.active = false,
    this.mark,
    this.label,
    this.color,
  });

  final BloomGlyph icon;
  final VoidCallback? onTap;
  final double size;
  final bool active;

  /// Own icon colour instead of the usual: a favourite's ♡ is red.
  final Color? color;

  /// A mini badge in an accent circle over the icon, telling modes apart
  /// without swapping the icon.
  final Widget? mark;

  /// A caption INSTEAD of the icon: at a speed other than 1× the button shows
  /// the value.
  final String? label;

  /// Caption box width. Fixed, not by text, or the tool row would shift on
  /// every speed change. A long value (`1.35×`) shrinks inside through
  /// [FittedBox].
  static const double _labelWidth = 34;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = this.color ?? (active ? t.accent : t.iconFg);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (label == null)
              BloomIcon(icon, size: size, color: color)
            else
              SizedBox(
                width: _labelWidth,
                height: size,
                child: FittedBox(
                  child: Text(
                    label!,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1,
                      color: color,
                    ),
                  ),
                ),
              ),
            if (mark != null)
              Positioned(
                right: -4,
                top: -3,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: mark,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tool row: two pills at the edges, left about the track (♡, ⊕ and lyrics),
/// right about listening (speed and sleep). No queue button: a tap on the
/// header's source pill opens the queue, and a long press leads to the source.
class _Tools extends ConsumerWidget {
  const _Tools();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final track = ref.watch(playbackProvider.select((s) => s.track));
    if (track == null) return const SizedBox.shrink();
    final isFav = ref.watch(
      libraryProvider.select((lib) => lib.isFav(track.id)),
    );
    // Speed: at 1× a plain speedometer; otherwise the value in its place.
    final rate = ref.watch(speedProvider).rate;
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    // No lyrics button until lyrics are found. It survives an open panel in any
    // case, or there'd be nothing to close it with.
    final lyricsFound = ref.watch(lyricsProvider).status == LyricsStatus.ready;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ToolPill(
          children: [
            _FlatIcon(
              icon: isFav ? Bi.heartBold : Bi.heart,
              size: 25,
              color: isFav ? t.sysFavIco : null,
              onTap: () => ref.read(libraryProvider.notifier).toggleFav(track),
            ),
            _FlatIcon(
              icon: Bi.addCircle,
              size: 25,
              onTap: () => showAddToPlaylistSheet(context, ref, track),
            ),
            if (lyricsFound || lyricsOpen)
              _FlatIcon(
                icon: Bi.text,
                size: 25,
                active: lyricsOpen,
                onTap: () =>
                    ref.read(lyricsOpenProvider.notifier).state = !lyricsOpen,
              ),
          ],
        ),
        _ToolPill(
          children: [
            const _PlayOnButton(),
            _FlatIcon(
              icon: Bi.speed,
              size: 25,
              label: rate == 1 ? null : speedLabel(rate),
              active: rate != 1,
              onTap: () => showSpeedSheet(context),
            ),
            const _SleepButton(),
          ],
        ),
      ],
    );
  }
}

/// A plate of the tools' row, as wide as what's on it.
class _ToolPill extends StatelessWidget {
  const _ToolPill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _Plate(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}
