/// Страница «Релизы» — все новинки площадки сеткой. Порт ветки `releases`
/// десктопного `DetailView` (`ReleasesBody`).
///
/// Карточки те же, что в выдаче поиска («артист · сингл» над датой), тап
/// открывает альбом. Шапки с обложкой нет — как и у чарта, это не сущность
/// площадки, а список.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../customization/ui/app_background.dart';
import '../discover_store.dart';

const double _gap = 12;
const double _side = 16;

class ReleasesScreen extends ConsumerWidget {
  const ReleasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final result = ref.watch(discoverProvider(DiscoverMode.newReleases));
    final albums = switch (result.value?.block) {
      DiscoverAlbums(:final albums) => albums,
      _ => const <Playlist>[],
    };
    final cell = (MediaQuery.sizeOf(context).width - _side * 2 - _gap) / 2;

    return Scaffold(
      backgroundColor: ref.watch(backgroundOnProvider)
          ? Colors.transparent
          : t.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SubPageHeader(
                title: l.homeNewReleases,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: albums.isEmpty
                  ? Center(
                      child: result.isLoading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: t.accent,
                              ),
                            )
                          : Text(
                              l.setNoTracks,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(color: t.muted),
                            ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        _side,
                        4,
                        _side,
                        16 + bottomBarsInset(context),
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: _gap,
                        mainAxisSpacing: 16,
                        mainAxisExtent: cell + setCaption(albums),
                      ),
                      itemCount: albums.length,
                      itemBuilder: (context, i) =>
                          SetCard(set: albums[i], size: null),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
