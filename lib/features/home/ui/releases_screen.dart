/// Страница «Релизы» — все новинки площадки сеткой. Порт ветки `releases`
/// десктопного `DetailView` (`ReleasesBody`).
///
/// Карточки те же, что в выдаче поиска («артист · сингл» над датой), тап
/// открывает альбом. Шапки с обложкой нет — как и у чарта, это не сущность
/// площадки, а список.
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
