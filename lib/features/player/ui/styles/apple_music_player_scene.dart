/// Apple Music Player Scene: Ported faithfully from Levyra's AppleMusicPlayer.kt.
///
/// Features:
/// - Liquid blur ambient mesh backdrop with Apple dark surface.
/// - Apple Music top grabber pill (36x5dp).
/// - Dynamic interactive pause scale animation: Artwork smoothly scales down to
///   0.82x on pause and expands to 1.0x on play with elevation shadow.
/// - Apple SF Pro typography rhythm (-0.6 tracking, semi-bold/bold).
/// - Apple Music seekbar (7dp resting, 11dp dragging, remaining time with minus '-mm:ss',
///   and audio quality badge 'Lossless').
/// - Apple Music transport: FastRewind / FastForward double triangle icons,
///   and squircle mode toggles with tertiary background highlight.
/// - Apple Music dock: Quotes lyrics button, AirPlay route, and Queue button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/tokens.dart';
import '../../../../core/entities/entities.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/store/cover_store.dart';
import '../../../../core/store/library_store.dart';
import '../../../../shared/ui/atoms.dart';
import '../../../../shared/ui/marquee_text.dart';
import '../../../../shared/ui/pressable.dart';
import '../../../../shared/ui/track_actions.dart';
import '../../../../shared/util/format.dart';
import '../../../detail/artists_sheet.dart';
import '../../../lyrics/lyrics_store.dart';
import '../../../lyrics/ui/lyrics_view.dart';
import '../../player_bg_store.dart';
import '../../player_controller.dart';
import '../../player_sheet.dart';
import '../artist_avatars.dart';
import '../queue_sheet.dart';
import '../sleep_sheet.dart';
import '../source_pill.dart';

class AppleMusicPlayerScene extends ConsumerStatefulWidget {
  const AppleMusicPlayerScene({
    required this.state,
    required this.track,
    super.key,
  });

  final PlaybackState state;
  final Track track;

  @override
  ConsumerState<AppleMusicPlayerScene> createState() =>
      _AppleMusicPlayerSceneState();
}

class _AppleMusicPlayerSceneState extends ConsumerState<AppleMusicPlayerScene> {
  double? _dragMs;

  static const Color _appleBg = Color(0xFF1C1C1E);
  static const Color _appleVibrantPrimary = Color(0xF0FFFFFF);
  static const Color _appleVibrantSecondary = Color(0x73FFFFFF);
  static const Color _appleVibrantTertiary = Color(0x2EFFFFFF);

  @override
  Widget build(BuildContext context) {
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    final lyricsMode = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
    final cover = ref.watch(playerCoverProvider);
    final extractedColor =
        ref.watch(playerBgColorProvider(cover)).value ?? const Color(0xFF3A3A3C);

    final field = extractedColor;
    final deepField = Color.lerp(field, _appleBg, 0.72)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [field, deepField, _appleBg],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottomEdgeInset(context)),
          child: Column(
            children: [
              _buildGrabber(),
              const SizedBox(height: 8),
              _buildHeader(context),
              const SizedBox(height: 12),
              Expanded(
                child: lyricsOpen && lyricsMode == LyricsMode.replace
                    ? const LyricsView(
                        padding: EdgeInsets.fromLTRB(8, 20, 8, 20),
                        layout: LyricsLayout.replace,
                      )
                    : _buildArtwork(context, lyricsOpen, lyricsMode),
              ),
              const SizedBox(height: 16),
              _buildMetadata(context),
              const SizedBox(height: 12),
              _buildSeekbar(context),
              const SizedBox(height: 12),
              _buildTransport(context),
              const SizedBox(height: 12),
              _buildDock(context, lyricsOpen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrabber() {
    return Center(
      child: Container(
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: _appleVibrantSecondary,
          borderRadius: BorderRadius.circular(2.5),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 30,
            color: _appleVibrantPrimary,
          ),
          onPressed: collapsePlayerSheet,
        ),
        Expanded(
          child: Center(
            child: SourcePill(
              source: widget.state.source,
              shuffle: widget.state.shuffle,
              count: widget.state.queue.length,
              background: _appleVibrantTertiary,
              borderColor: Colors.transparent,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.more_horiz_rounded,
            size: 26,
            color: _appleVibrantPrimary,
          ),
          onPressed: () => showTrackActions(context, ref, widget.track),
        ),
      ],
    );
  }

  Widget _buildArtwork(
    BuildContext context,
    bool lyricsOpen,
    LyricsMode lyricsMode,
  ) {
    final playing = widget.state.playing;

    // Apple Music paused scale animation: 0.82 on pause, 1.0 on play
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: playing ? 1.0 : 0.82),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: playing ? 0.48 : 0.28,
                      ),
                      blurRadius: playing ? 32 : 16,
                      offset: Offset(0, playing ? 16 : 8),
                      spreadRadius: playing ? 2 : 0,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Cover(
                        url: ref.watch(playerCoverProvider),
                        size: 400,
                        radius: 24,
                      ),
                      if (lyricsOpen && lyricsMode == LyricsMode.overlay)
                        const LyricsView(
                          padding: EdgeInsets.all(16),
                          layout: LyricsLayout.overlay,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetadata(BuildContext context) {
    final track = widget.track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarqueeText(
          track.name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: _appleVibrantPrimary,
          ),
        ),
        const SizedBox(height: 3),
        GestureDetector(
          onTap: canOpenTrackArtist(track)
              ? () => openTrackArtist(context, ref, track)
              : null,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TrackArtistAvatars(track: track),
              Flexible(
                child: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                    color: _appleVibrantSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: _appleVibrantSecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeekbar(BuildContext context) {
    final head =
        ref.watch(playheadProvider).value ??
        (position: Duration.zero, total: Duration.zero);
    final maxMs = head.total.inMilliseconds.toDouble();
    final posMs = head.position.inMilliseconds
        .clamp(0, head.total.inMilliseconds)
        .toDouble();
    final currentMs = (_dragMs ?? posMs).clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);
    final isDragging = _dragMs != null;

    final remainingMs = (maxMs - currentMs).clamp(0.0, maxMs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: isDragging ? 10 : 7,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 0,
              disabledThumbRadius: 0,
              elevation: 0,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: isDragging
                ? _appleVibrantPrimary
                : _appleVibrantPrimary.withValues(alpha: 0.75),
            inactiveTrackColor: _appleVibrantTertiary,
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: currentMs,
            max: maxMs <= 0 ? 1.0 : maxMs,
            onChanged: maxMs <= 0
                ? null
                : (v) => setState(() => _dragMs = v),
            onChangeEnd: maxMs <= 0
                ? null
                : (v) async {
                    await ref
                        .read(playbackProvider.notifier)
                        .seek(Duration(milliseconds: v.round()));
                    if (mounted) setState(() => _dragMs = null);
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                mmss(Duration(milliseconds: currentMs.round())),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _appleVibrantSecondary,
                ),
              ),
              // Apple Music Audio Quality Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _appleVibrantTertiary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  context.l.playerLossless,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: _appleVibrantPrimary,
                  ),
                ),
              ),
              Text(
                '-${mmss(Duration(milliseconds: remainingMs.round()))}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _appleVibrantSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransport(BuildContext context) {
    final state = widget.state;
    final ctrl = ref.read(playbackProvider.notifier);
    final isShuffle = state.shuffle;
    final repeatMode = state.repeat;
    final isRepeat = repeatMode != PlayerRepeat.off;
    final isPlaying = state.playing;
    final isLoading = state.loading;

    return SizedBox(
      height: 80,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Apple Squircle Mode Toggle: Shuffle
          _AppleSquircleToggle(
            icon: Icons.shuffle_rounded,
            active: isShuffle,
            onTap: ctrl.toggleShuffle,
          ),
          // Center Transport: FastRewind, Play/Pause, FastForward
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.fast_rewind_rounded,
                  size: 42,
                  color: _appleVibrantPrimary,
                ),
                onPressed: ctrl.prev,
              ),
              const SizedBox(width: 14),
              Pressable(
                onTap: ctrl.toggle,
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: Center(
                    child: isLoading
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.8,
                              color: _appleVibrantPrimary,
                            ),
                          )
                        : Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 52,
                            color: _appleVibrantPrimary,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              IconButton(
                icon: const Icon(
                  Icons.fast_forward_rounded,
                  size: 42,
                  color: _appleVibrantPrimary,
                ),
                onPressed: ctrl.next,
              ),
            ],
          ),
          // Apple Squircle Mode Toggle: Repeat
          _AppleSquircleToggle(
            icon: repeatMode == PlayerRepeat.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            active: isRepeat,
            onTap: ctrl.cycleRepeat,
          ),
        ],
      ),
    );
  }

  Widget _buildDock(BuildContext context, bool lyricsOpen) {
    final isFav = ref.watch(
      libraryProvider.select((lib) => lib.isFav(widget.track.id)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Apple Music Quotes / Lyrics Button
          Pressable(
            onTap: () =>
                ref.read(lyricsOpenProvider.notifier).state = !lyricsOpen,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: lyricsOpen ? _appleVibrantPrimary : Colors.transparent,
              ),
              child: Icon(
                Icons.format_quote_rounded,
                size: 22,
                color: lyricsOpen ? Colors.black : _appleVibrantSecondary,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 24,
              color: isFav ? context.bloom.sysFavIco : _appleVibrantSecondary,
            ),
            onPressed: () =>
                ref.read(libraryProvider.notifier).toggleFav(widget.track),
          ),
          IconButton(
            icon: const Icon(
              Icons.airplay_rounded,
              size: 24,
              color: _appleVibrantSecondary,
            ),
            onPressed: () => showSleepSheet(context),
          ),
          IconButton(
            icon: const Icon(
              Icons.queue_music_rounded,
              size: 26,
              color: _appleVibrantSecondary,
            ),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}

class _AppleSquircleToggle extends StatelessWidget {
  const _AppleSquircleToggle({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  static const Color _appleVibrantPrimary = Color(0xF0FFFFFF);
  static const Color _appleVibrantSecondary = Color(0x73FFFFFF);
  static const Color _appleVibrantTertiary = Color(0x2EFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: active ? _appleVibrantTertiary : Colors.transparent,
        ),
        child: Center(
          child: Icon(
            icon,
            size: 22,
            color: active ? _appleVibrantPrimary : _appleVibrantSecondary,
          ),
        ),
      ),
    );
  }
}
