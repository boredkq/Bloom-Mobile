/// "Similar to X" on home: the seed's name in its cover's hue in the title,
/// tracks and artists mixed in the row. Tapping the name opens an artist seed
/// and plays a track seed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/pressable.dart';
import '../../detail/detail_nav.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import 'cover_tones.dart';
import '../similar_to.dart';

class SimilarToSection extends ConsumerWidget {
  const SimilarToSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(similarToProvider);
    if (data == null || data.items.isEmpty) return const SizedBox.shrink();
    final seed = data.seed;
    final tones = ref.watch(coverTonesProvider(seed.cover)).valueOrNull;
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final open = _seedAction(context, ref, seed);
    final source = PlainSource(
      id: 'similarTo',
      label: '${l.homeSimilarTo} ${seed.name}',
      cover: seed.cover,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            children: [
              Text(l.homeSimilarTo, style: theme.titleLarge),
              const SizedBox(width: 6),
              Flexible(
                child: Pressable(
                  onTap: open,
                  scale: 0.98,
                  child: Text(
                    seed.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleLarge?.copyWith(
                      color: tones == null
                          ? null
                          : (t.isLight ? tones.inkLight : tones.ink),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        EntityCarousel(
          height: 194,
          padding: 16,
          itemCount: data.items.length,
          builder: (i) => switch (data.items[i]) {
            // A card plays its own track.
            SimilarTrackItem(:final track) => TrackCard(
              track: track,
              queue: [track],
              index: 0,
              source: source,
            ),
            SimilarArtistItem(:final artist) => ArtistCard(
              artist: artist,
              size: 132,
              centerLabel: true,
            ),
          },
        ),
      ],
    );
  }
}

/// What a tap on a seed does. A track seed with no track (a local file not in
/// the library) can't play, so the tap is off.
VoidCallback? _seedAction(
  BuildContext context,
  WidgetRef ref,
  SimilarSeed seed,
) => switch (seed) {
  SimilarArtistSeed(:final artist) => () => openArtist(
    context,
    artist.id,
    initial: artist,
  ),
  SimilarTrackSeed(:final track?) =>
    () => ref
        .read(playbackProvider.notifier)
        .playQueue(
          [track],
          0,
          source: PlainSource(
            id: 'similarTo:seed',
            label: track.name,
            cover: track.cover,
          ),
        ),
  SimilarTrackSeed() => null,
};
