/// For you on home. The whole selection stack comes first, queueing the whole
/// strip; a single card plays only its track.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/pressable.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import '../for_you.dart';
import 'cover_fan.dart';

/// Stack geometry: the top cover is level with a neighbouring card's (132), or
/// the stack eats half the strip.
const double _k = 132 / 158;
const double _fyWidth = 272 * _k;
const double _fyHeight = 158 * _k;
const double _fyFront = 158 * _k;
const double _fyBack = 138 * _k;
const double _fyShift = 52 * _k;

class ForYouSection extends ConsumerWidget {
  const ForYouSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(forYouProvider);
    if (tracks == null || tracks.isEmpty) return const SizedBox.shrink();
    final l = context.l;
    final source = PlainSource(
      id: 'forYou',
      label: l.homeForYou,
      cover: tracks.first.cover,
    );
    // One track makes no stack, and would repeat its neighbour.
    final stack = tracks.length > 1 ? 1 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(l.homeForYou),
        EntityCarousel(
          height: 194,
          padding: 16,
          itemCount: tracks.length + stack,
          builder: (i) {
            if (i < stack) return _PlayAllCard(tracks: tracks, source: source);
            final track = tracks[i - stack];
            return TrackCard(
              track: track,
              queue: [track],
              index: 0,
              source: source,
            );
          },
        ),
      ],
    );
  }
}

/// The whole selection stack; see [CoverFan].
class _PlayAllCard extends ConsumerWidget {
  const _PlayAllCard({required this.tracks, required this.source});

  final List<Track> tracks;
  final PlaySource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final left = tracks.length > 1 ? tracks[1] : null;
    final right = tracks.length > 2 ? tracks[2] : null;
    return Pressable(
      onTap: () => ref
          .read(playbackProvider.notifier)
          .playQueue(tracks, 0, source: source),
      scale: 0.97,
      child: SizedBox(
        width: _fyWidth,
        child: Column(
          children: [
            CoverFan(
              front: tracks.first.cover,
              left: left?.cover,
              right: right?.cover,
              width: _fyWidth,
              height: _fyHeight,
              frontSize: _fyFront,
              backSize: _fyBack,
              shift: _fyShift,
            ),
            const SizedBox(height: 8),
            Text(
              context.l.homeForYouAll,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
