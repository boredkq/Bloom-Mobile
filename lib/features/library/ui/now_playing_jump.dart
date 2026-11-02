/// Floating Now playing pill over a track list. It pops up when the playing
/// track leaves the visible part, and a tap scrolls back to it. The row may not
/// be in the tree (the list is lazy), so its place is computed from the model
/// (`rowTopOf`) rather than looked up by key.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../features/player/player_controller.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/pressable.dart';

/// How far a row must leave the visible part for the pill to show. A row and a
/// half of margin, so it doesn't blink at the boundary.
const double kJumpShowGap = kTrackRowHeight * 1.5;

/// Gap above the row on return: it lands with context, not right under the
/// stuck header.
const double kJumpScrollMargin = kTrackRowHeight;

/// Beyond this a smooth scroll takes indecently long, so I jump.
const double kJumpSmoothMax = 4000;

/// Where the playing row went: `0` visible with no pill needed, `-1` above the
/// visible part, `1` below.
///
/// [rowTop] is the row's top in scroll coordinates; `null` if the track isn't
/// in the list. The visible part is cut by the stuck header ([topInset]) and
/// the shell's bars ([bottomInset]): a row under the mini player isn't visible.
int nowPlayingJumpDir({
  required double? rowTop,
  required double offset,
  required double viewport,
  required double topInset,
  required double bottomInset,
}) {
  if (rowTop == null || viewport <= 0) return 0;
  final top = offset + topInset;
  final bottom = offset + viewport - bottomInset;
  if (rowTop + kTrackRowHeight < top - kJumpShowGap) return -1;
  if (rowTop > bottom + kJumpShowGap) return 1;
  return 0;
}

/// Scroll at which row [rowTop] lands under the stuck header, with
/// [kJumpScrollMargin] above it.
double nowPlayingJumpTarget({
  required double rowTop,
  required double topInset,
  required double min,
  required double max,
}) => (rowTop - topInset - kJumpScrollMargin).clamp(min, math.max(min, max));

class NowPlayingJump extends ConsumerStatefulWidget {
  const NowPlayingJump({
    super.key,
    required this.controller,
    required this.rowTopOf,
    required this.topInset,
  });

  /// Controller of the list the pill hangs over.
  final ScrollController controller;

  /// A track row's top in scroll coordinates; `null` if it isn't in the list.
  final double? Function(String trackId) rowTopOf;

  /// Collapsed header height: stuck on top, it covers the list's start.
  final double topInset;

  @override
  ConsumerState<NowPlayingJump> createState() => _NowPlayingJumpState();
}

class _NowPlayingJumpState extends ConsumerState<NowPlayingJump> {
  /// Last computed direction; see [nowPlayingJumpDir].
  int _dir = 0;

  /// Bottom bars' height from the last frame: scrolling happens between frames,
  /// where `MediaQuery` can't be asked.
  double _bottomInset = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(NowPlayingJump old) {
    super.didUpdateWidget(old);
    if (old.controller == widget.controller) return;
    old.controller.removeListener(_onScroll);
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  /// A scroll rebuilds the widget ONLY when the direction changes: a pill with
  /// a live equalizer shouldn't rebuild per pixel.
  void _onScroll() {
    final next = _eval(ref.read(playbackProvider).track);
    if (next != _dir) setState(() => _dir = next);
  }

  int _eval(Track? cur) {
    final c = widget.controller;
    if (cur == null || !c.hasClients) return 0;
    final pos = c.position;
    // The first frame builds BEFORE the list's layout: the controller has a
    // position with no dimensions, and asking for them throws. I recount after
    // the frame; see [build].
    if (!pos.hasPixels || !pos.hasViewportDimension) return 0;
    return nowPlayingJumpDir(
      rowTop: widget.rowTopOf(cur.id),
      offset: pos.pixels,
      viewport: pos.viewportDimension,
      topInset: widget.topInset,
      bottomInset: _bottomInset,
    );
  }

  void _jump() {
    final cur = ref.read(playbackProvider).track;
    final c = widget.controller;
    if (cur == null || !c.hasClients) return;
    final pos = c.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) return;
    final rowTop = widget.rowTopOf(cur.id);
    if (rowTop == null) return;
    final target = nowPlayingJumpTarget(
      rowTop: rowTop,
      topInset: widget.topInset,
      min: pos.minScrollExtent,
      max: pos.maxScrollExtent,
    );
    if ((target - pos.pixels).abs() > kJumpSmoothMax) {
      c.jumpTo(target);
      return;
    }
    c.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final cur = ref.watch(playbackProvider).track;
    final playing = ref.watch(playingProvider).value ?? false;
    _bottomInset = bottomBarsInset(context);
    _dir = _eval(cur);
    final show = _dir != 0;
    // The first frame builds before the list's layout, where [_eval] returns 0.
    // A scroll that would recount may never come (the list opened already
    // scrolled), so I count again after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });

    return IgnorePointer(
      ignoring: !show,
      child: AnimatedSlide(
        offset: show ? Offset.zero : const Offset(0, 0.45),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          // Fully rounded rather than the theme radius: it's a pill, like the
          // header's.
          child: Pressable(
            onTap: _jump,
            child: GlassBox(
              shape: StadiumBorder(side: BorderSide(color: t.ovlLine)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                child: SizedBox(
                  height: 38,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The equalizer freezes with the music, showing pause or
                      // play too.
                      EqualizerBars(playing: show && playing),
                      const SizedBox(width: 10),
                      Text(
                        context.l.tlJumpToNow,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      BloomIcon(
                        _dir < 0 ? Bi.arrowUp : Bi.arrowDown,
                        size: 17,
                        color: t.text2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
