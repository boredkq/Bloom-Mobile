/// The home shelves shared by everyone: Releases and the Chart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../player/play_source.dart';
import '../discover_store.dart';
import 'chart_screen.dart';
import 'releases_screen.dart';

/// Places of the chart on home; the whole chart is on its page.
const int _homeChartMax = 10;

/// Releases on home; the rest are a grid on their page.
const int _homeReleasesMax = 10;

/// A platform shelf. Nothing is shown until its data comes: no skeleton, no
/// error.
class DiscoverSection extends ConsumerWidget {
  const DiscoverSection({super.key, required this.mode});

  final DiscoverMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(discoverProvider(mode)).value;
    if (result == null) return const SizedBox.shrink();
    final block = result.block;
    final charts = mode == DiscoverMode.charts;
    final title = charts ? context.l.homeCharts : context.l.homeNewReleases;
    final source = PlainSource(id: 'discover:${mode.name}', label: title);
    // SoundCloud's new releases come as tracks: there's no grid page for them.
    final Widget? page = charts
        ? const ChartScreen()
        : block is DiscoverAlbums
        ? const ReleasesScreen()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title,
          onTap: page == null
              ? null
              : () => Navigator.of(
                  context,
                ).push(detailPageRoute<void>((_) => page)),
        ),
        switch (block) {
          // A row plays its own track; the chart page plays the whole list.
          DiscoverTracks(:final tracks) when charts => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                for (final (i, track) in tracks.take(_homeChartMax).indexed)
                  TrackRow(
                    track: track,
                    queue: [track],
                    index: 0,
                    source: source,
                    rank: track.chartPos ?? i + 1,
                  ),
              ],
            ),
          ),
          DiscoverAlbums(:final albums) => EntityCarousel(
            height: setRowHeight(albums),
            padding: 16,
            itemCount: albums.length.clamp(0, _homeReleasesMax),
            builder: (i) => SetCard(set: albums[i]),
          ),
          DiscoverTracks(:final tracks) => EntityCarousel(
            height: 194,
            padding: 16,
            itemCount: tracks.length,
            builder: (i) => TrackCard(
              track: tracks[i],
              queue: tracks,
              index: i,
              source: source,
            ),
          ),
        },
      ],
    );
  }
}
