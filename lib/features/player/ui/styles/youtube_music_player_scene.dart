/// YouTube Music Player Scene: Ported faithfully from Levyra's YouTubeMusicPlayer.kt.
///
/// Features:
/// - Pure black / dark tone background.
/// - Top header with Song / Video segmented pill switch.
/// - Metadata row flanked by Thumbs Up (Favorite) & Thumbs Down buttons.
/// - Ultra sleek 2dp flat seekbar with micro thumb.
/// - 96dp transport with massive 72dp white circular play button and dot indicators.
/// - Signature YouTube Music bottom uppercase pill tabs: UP NEXT, LYRICS, RELATED.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/entities/entities.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/store/library_store.dart';
import '../../../../shared/ui/atoms.dart';
import '../../../../shared/ui/marquee_text.dart';
import '../../../../shared/ui/pressable.dart';
import '../../../../shared/ui/track_actions.dart';
import '../../../../shared/util/format.dart';
import '../../../detail/artists_sheet.dart';
import '../../../lyrics/lyrics_store.dart';
import '../../../lyrics/ui/lyrics_view.dart';
import '../../../customization/custom_store.dart';
import '../../player_bg_store.dart';
import '../../player_controller.dart';
import '../player_sheet.dart';
import '../artist_avatars.dart';
import '../queue_sheet.dart';

class YouTubeMusicPlayerScene extends ConsumerStatefulWidget {
  const YouTubeMusicPlayerScene({
    required this.state,
    required this.track,
    super.key,
  });

  final PlaybackState state;
  final Track track;

  @override
  ConsumerState<YouTubeMusicPlayerScene> createState() =>
      _YouTubeMusicPlayerSceneState();
}

class _YouTubeMusicPlayerSceneState
    extends ConsumerState<YouTubeMusicPlayerScene> {
  double? _dragMs;

  static const Color _ytmBg = Color(0xFF030303);
  static const Color _ytmTextSecondary = Color(0xFFAAAAAA);

  @override
  Widget build(BuildContext context) {
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    final lyricsMode = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
    final cover = ref.watch(playerCoverProvider);
    final extractedColor =
        ref.watch(playerBgColorProvider(cover)).value ?? const Color(0xFF1E1E1E);

    final topWash = Color.lerp(extractedColor, _ytmBg, 0.7)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topWash, _ytmBg],
          stops: const [0.0, 0.45],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, bottomEdgeInset(context)),
          child: Column(
            children: [
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
              _buildMetadataAndThumbs(context),
              const SizedBox(height: 10),
              _buildSeekbar(context),
              const SizedBox(height: 10),
              _buildTransport(context),
              const SizedBox(height: 12),
              _buildBottomTabs(context, lyricsOpen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 30,
            color: Colors.white,
          ),
          onPressed: collapsePlayerSheet,
        ),
        // YTM Song / Video Segmented Pill Switch
        Container(
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  context.l.playerSong,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Text(
                  context.l.playerVideo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.more_vert_rounded,
            size: 24,
            color: Colors.white,
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
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(
                  url: ref.watch(playerCoverProvider),
                  size: 400,
                  radius: 12,
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
      ),
    );
  }

  Widget _buildMetadataAndThumbs(BuildContext context) {
    final track = widget.track;
    final isFav = ref.watch(
      libraryProvider.select((lib) => lib.isFav(track.id)),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MarqueeText(
                track.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _ytmTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // YTM Thumbs Up / Down Row
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isFav ? Icons.thumb_up_rounded : Icons.thumb_up_alt_outlined,
                size: 24,
                color: isFav ? Colors.white : _ytmTextSecondary,
              ),
              onPressed: () =>
                  ref.read(libraryProvider.notifier).toggleFav(track),
            ),
            IconButton(
              icon: const Icon(
                Icons.thumb_down_alt_outlined,
                size: 24,
                color: _ytmTextSecondary,
              ),
              onPressed: () => ref.read(playbackProvider.notifier).next(),
            ),
          ],
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: isDragging ? 7 : 5,
              pressedElevation: 0,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
            thumbColor: Colors.white,
            trackShape: const RectangularSliderTrackShape(),
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
                  fontWeight: FontWeight.w500,
                  color: _ytmTextSecondary,
                ),
              ),
              Text(
                mmss(head.total),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _ytmTextSecondary,
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
    final isPlaying = ref.watch(playingNowProvider);
    final isLoading = state.loading;

    return SizedBox(
      height: 92,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // YTM Shuffle Toggle with White Dot
          _YtmModeToggle(
            icon: Icons.shuffle_rounded,
            active: isShuffle,
            onTap: ctrl.toggleShuffle,
          ),
          // Previous Track
          IconButton(
            icon: const Icon(
              Icons.skip_previous_rounded,
              size: 40,
              color: Colors.white,
            ),
            onPressed: ctrl.prev,
          ),
          // Massive 72dp Solid White Play/Pause Button
          Pressable(
            onTap: ctrl.toggle,
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.0,
                          color: Colors.black,
                        ),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 42,
                        color: Colors.black,
                      ),
              ),
            ),
          ),
          // Next Track
          IconButton(
            icon: const Icon(
              Icons.skip_next_rounded,
              size: 40,
              color: Colors.white,
            ),
            onPressed: ctrl.next,
          ),
          // YTM Repeat Toggle with White Dot
          _YtmModeToggle(
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

  Widget _buildBottomTabs(BuildContext context, bool lyricsOpen) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // UP NEXT TAB
        _YtmTabPill(
          label: context.l.playerUpNext.toUpperCase(),
          active: false,
          onTap: () => showQueueSheet(context),
        ),
        // LYRICS TAB
        _YtmTabPill(
          label: context.l.playerLyrics.toUpperCase(),
          active: lyricsOpen,
          onTap: () =>
              ref.read(lyricsOpenProvider.notifier).state = !lyricsOpen,
        ),
        // RELATED TAB
        _YtmTabPill(
          label: context.l.playerRelated.toUpperCase(),
          active: false,
          onTap: canOpenTrackArtist(widget.track)
              ? () => openTrackArtist(context, ref, widget.track)
              : null,
        ),
      ],
    );
  }
}

class _YtmModeToggle extends StatelessWidget {
  const _YtmModeToggle({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 3),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? Colors.white : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YtmTabPill extends StatelessWidget {
  const _YtmTabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.6,
                color: active ? Colors.white : Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
