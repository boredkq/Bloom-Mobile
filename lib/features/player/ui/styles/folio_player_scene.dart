/// Folio Player Scene: Ported faithfully from Levyra's PlayerDeckFolio.kt.
///
/// Features:
/// - Editorial magazine layout with two-tone architectural paper backdrop.
/// - Uppercase album eyebrow caption above the track title.
/// - Distinctive asymmetric artwork corners (38dp on topLeft & bottomRight,
///   12dp on topRight & bottomLeft) with fine border.
/// - Editorial high-contrast typography rhythm.
/// - Hairline minimalist transport controls and geometric tool dock.
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

class FolioPlayerScene extends ConsumerStatefulWidget {
  const FolioPlayerScene({
    required this.state,
    required this.track,
    super.key,
  });

  final PlaybackState state;
  final Track track;

  @override
  ConsumerState<FolioPlayerScene> createState() => _FolioPlayerSceneState();
}

class _FolioPlayerSceneState extends ConsumerState<FolioPlayerScene> {
  double? _dragMs;

  static const Color _folioPaperBase = Color(0xFF141416);
  static const Color _folioPaperElevated = Color(0xFF1E1E22);

  @override
  Widget build(BuildContext context) {
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    final lyricsMode = ref.watch(lyricsPrefsProvider.select((p) => p.mode));
    final cover = ref.watch(playerCoverProvider);
    final extractedColor =
        ref.watch(playerBgColorProvider(cover)).value ?? const Color(0xFF26262B);

    final paperTint = Color.lerp(extractedColor, _folioPaperBase, 0.78)!;

    return Container(
      decoration: BoxDecoration(
        color: _folioPaperBase,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [paperTint, _folioPaperBase],
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
              const SizedBox(height: 18),
              _buildEditorialMetadata(context),
              const SizedBox(height: 12),
              _buildSeekbar(context),
              const SizedBox(height: 12),
              _buildHairlineTransport(context),
              const SizedBox(height: 12),
              _buildToolDock(context, lyricsOpen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final queue = widget.state.queue;
    final trackId = widget.track.id;
    final index = queue.indexWhere((t) => t.id == trackId);
    final posLabel = index >= 0 && queue.length > 1
        ? '${(index + 1).toString().padLeft(2, '0')} / ${queue.length.toString().padLeft(2, '0')}'
        : '';

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
        if (posLabel.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              posLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: Colors.white70,
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        IconButton(
          icon: const Icon(
            Icons.more_horiz_rounded,
            size: 26,
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
    const radius = BorderRadius.only(
      topLeft: Radius.circular(38),
      bottomRight: Radius.circular(38),
      topRight: Radius.circular(12),
      bottomLeft: Radius.circular(12),
    );

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(
                  url: ref.watch(playerCoverProvider),
                  size: 400,
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

  Widget _buildEditorialMetadata(BuildContext context) {
    final track = widget.track;
    final album = track.album.trim().toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (album.isNotEmpty && !album.contains(track.name.toUpperCase())) ...[
          Text(
            album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.2,
              color: context.bloom.accent.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 4),
        ],
        MarqueeText(
          track.name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
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
                    letterSpacing: 0.2,
                    color: Colors.white70,
                  ),
                ),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: isDragging ? 6 : 4,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            activeTrackColor: context.bloom.accent,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
            thumbColor: Colors.white,
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
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60,
                ),
              ),
              Text(
                mmss(head.total),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHairlineTransport(BuildContext context) {
    final state = widget.state;
    final ctrl = ref.read(playbackProvider.notifier);
    final isShuffle = state.shuffle;
    final repeatMode = state.repeat;
    final isRepeat = repeatMode != PlayerRepeat.off;
    final isPlaying = ref.watch(playingNowProvider);
    final isLoading = state.loading;
    final t = context.bloom;

    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _folioPaperElevated,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
          topRight: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              Icons.shuffle_rounded,
              size: 22,
              color: isShuffle ? t.accent : Colors.white60,
            ),
            onPressed: ctrl.toggleShuffle,
          ),
          IconButton(
            icon: const Icon(
              Icons.skip_previous_rounded,
              size: 34,
              color: Colors.white,
            ),
            onPressed: ctrl.prev,
          ),
          Pressable(
            onTap: ctrl.toggle,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.accent, width: 1.5),
                color: t.accent.withValues(alpha: 0.15),
              ),
              child: Center(
                child: isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: t.accent,
                        ),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.skip_next_rounded,
              size: 34,
              color: Colors.white,
            ),
            onPressed: ctrl.next,
          ),
          IconButton(
            icon: Icon(
              repeatMode == PlayerRepeat.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              size: 22,
              color: isRepeat ? t.accent : Colors.white60,
            ),
            onPressed: ctrl.cycleRepeat,
          ),
        ],
      ),
    );
  }

  Widget _buildToolDock(BuildContext context, bool lyricsOpen) {
    final track = widget.track;
    final isFav = ref.watch(
      libraryProvider.select((lib) => lib.isFav(track.id)),
    );
    final t = context.bloom;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _folioPaperElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 22,
              color: isFav ? t.sysFavIco : Colors.white70,
            ),
            onPressed: () => ref.read(libraryProvider.notifier).toggleFav(track),
          ),
          IconButton(
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              size: 22,
              color: Colors.white70,
            ),
            onPressed: () => showAddToPlaylistSheet(context, ref, track),
          ),
          IconButton(
            icon: Icon(
              Icons.lyrics_rounded,
              size: 22,
              color: lyricsOpen ? t.accent : Colors.white70,
            ),
            onPressed: () =>
                ref.read(lyricsOpenProvider.notifier).state = !lyricsOpen,
          ),
          IconButton(
            icon: const Icon(
              Icons.speed_rounded,
              size: 22,
              color: Colors.white70,
            ),
            onPressed: () => showSpeedSheet(context),
          ),
          IconButton(
            icon: const Icon(
              Icons.playlist_play_rounded,
              size: 26,
              color: Colors.white70,
            ),
            onPressed: () => showQueueSheet(context),
          ),
        ],
      ),
    );
  }
}
