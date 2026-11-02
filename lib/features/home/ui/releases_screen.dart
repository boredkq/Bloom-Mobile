/// Releases page: all a platform's new releases as a grid. The cards are those
/// of search results (artist and type over a date), and a tap opens the album.
/// No cover header: like a chart, this is a list rather than a platform entity.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/subpage_header.dart';
import '../discover_store.dart';

class ReleasesScreen extends ConsumerWidget {
  const ReleasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final result = ref.watch(discoverProvider(DiscoverMode.newReleases));
    final albums = switch (result.value?.block) {
      DiscoverAlbums(:final albums) => albums,
      _ => const <Playlist>[],
    };
    return BloomPage(
      body: SubPage(
        title: l.homeNewReleases,
        onBack: () => Navigator.of(context).pop(),
        child: albums.isEmpty
            ? Center(
                child: result.isLoading
                    ? const BloomSpinner()
                    : CenterNote(l.setNoTracks),
              )
            : CardGrid(
                columns: 2,
                caption: setCaption(albums),
                itemCount: albums.length,
                itemBuilder: (context, i) =>
                    SetCard(set: albums[i], size: null),
              ),
      ),
    );
  }
}
