/// Spotify Player Scene: Ported faithfully from Levyra's SpotifyPlayer.kt.
///
/// Features:
/// - Distinctive vertical gradient backdrop (cover tone -> Spotify black).
/// - Spotify typography rhythm: bold headline, subdued metadata.
/// - Signature Spotify layout: left-aligned metadata with Heart/Favorite on the right.
/// - Micro-thumb 4dp seekbar with green drag accent.
/// - 88dp transport with 64dp solid white circular play button, black icons,
///   and green dot state indicators for shuffle & repeat.
/// - Spotify dock with Devices, Add, Lyrics, and Queue actions.
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
import '../../../customization/custom_store.dart';
import '../../player_bg_store.dart';
import '../../player_controller.dart';
import '../player_sheet.dart';
import '../artist_avatars.dart';
import '../queue_sheet.dart';
import '../sleep_sheet.dart';
import '../speed_sheet.dart';

class SpotifyPlayerScene extends ConsumerStatefulWidget {
  const SpotifyPlayerScene({
    required this.state,
    required this.track,
    super.key,
  });

  final PlaybackState state;
  final Track track;

  @override
  ConsumerState<SpotifyPlayerScene> createState() => _SpotifyPlayerSceneState();
}

class _SpotifyPlayerSceneState extends ConsumerState<SpotifyPlayerScene> {
  double? _dragMs;

  static const Color _spotifyBase = Color(0xFF121212);
  static const Color _spotifyGreen = Color(0xFF1ED760);
  static const Color _spotifySubdued = Color(0xFFB3B3B3);

  @override
  Widget build(BuildContext context) {
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    final lyricsMode = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
    final cover = ref.watch(playerCoverProvider);
    final extractedColor =
        ref.watch(playerBgColorProvider(cover)).value ?? const Color(0xFF2C3E50);

    // Spotify dynamic vertical gradient from cover tone
    final tone = extractedColor;
    final midTone = Color.lerp(tone, _spotifyBase, 0.65)!;
    final bottomTone = Color.lerp(tone, _spotifyBase, 0.88)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tone, midTone, bottomTone, _spotifyBase],
          stops: const [0.0, 0.38, 0.72, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, bottomEdgeInset(context)),
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
              const SizedBox(height: 18),
              _buildMetadataAndHeart(context),
              const SizedBox(height: 10),
              _buildSeekbar(context),
              const SizedBox(height: 12),
              _buildTransport(context),
              const SizedBox(height: 10),
              _buildDock(context, lyricsOpen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l = context.l;
    final src = widget.state.source;
    final sourceName = src?.name(l) ?? l.libQueue;

    return Row(
      children: [
        IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 32,
            color: Colors.white,
          ),
          onPressed: collapsePlayerSheet,
          tooltip: l.playerBack,
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PLAYING FROM PLAYLIST'.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: _spotifySubdued,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sourceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
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
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 12),
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(
                  url: ref.watch(playerCoverProvider),
                  size: 400,
                  radius: 10,
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

  Widget _buildMetadataAndHeart(BuildContext context) {
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
                  letterSpacing: -0.4,
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
                          fontWeight: FontWeight.w400,
                          color: _spotifySubdued,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          icon: Icon(
            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 28,
            color: isFav ? _spotifyGreen : _spotifySubdued,
          ),
          onPressed: () => ref.read(libraryProvider.notifier).toggleFav(track),
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
            trackHeight: 4,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: isDragging ? 7 : 5,
              pressedElevation: 0,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: isDragging ? _spotifyGreen : Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
            thumbColor: Colors.white,
            overlayColor: _spotifyGreen.withValues(alpha: 0.16),
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
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                mmss(Duration(milliseconds: currentMs.round())),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _spotifySubdued,
                ),
              ),
              Text(
                mmss(head.total),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _spotifySubdued,
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
      height: 84,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Spotify Shuffle Toggle with Dot Indicator
          _SpotifyToggle(
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
          // Signature Spotify 64dp Solid White Play/Pause Button
          Pressable(
            onTap: ctrl.toggle,
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: Colors.black,
                        ),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 38,
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
          // Spotify Repeat Toggle with Dot Indicator
          _SpotifyToggle(
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(
              Icons.devices_rounded,
              size: 22,
              color: _spotifySubdued,
            ),
            tooltip: context.l.pcPlayOn,
            onPressed: () => showSleepSheet(context),
          ),
          IconButton(
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              size: 22,
              color: _spotifySubdued,
            ),
            onPressed: () =>
                showAddToPlaylistSheet(context, ref, widget.track),
          ),
          IconButton(
            icon: Icon(
              Icons.lyrics_rounded,
              size: 24,
              color: lyricsOpen ? _spotifyGreen : _spotifySubdued,
            ),
            onPressed: () =>
                ref.read(lyricsOpenProvider.notifier).state = !lyricsOpen,
          ),
          IconButton(
            icon: const Icon(
              Icons.speed_rounded,
              size: 22,
              color: _spotifySubdued,
            ),
            onPressed: () => showSpeedSheet(context),
          ),
          IconButton(
            icon: const Icon(
              Icons.playlist_play_rounded,
              size: 28,
              color: _spotifySubdued,
            ),
            tooltip: context.l.playerQueue,
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}

class _SpotifyToggle extends StatelessWidget {
  const _SpotifyToggle({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  static const Color _spotifyGreen = Color(0xFF1ED760);
  static const Color _spotifySubdued = Color(0xFFB3B3B3);

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
              size: 26,
              color: active ? _spotifyGreen : _spotifySubdued,
            ),
            const SizedBox(height: 3),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? _spotifyGreen : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
