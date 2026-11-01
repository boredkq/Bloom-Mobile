/// Страница «Чарт» — полный чарт площадки списком. Порт ветки `chart`
/// десктопного `DetailView`.
///
/// Шапки с обложкой нет: чарт — не сущность площадки, а список, и обложка
/// первого места с «Яндекс.Музыкой» ничего бы не сообщили. Остаются «← Чарт»
/// и пара play / перемешать — иначе запустить весь список нечем. Слева в
/// строках — место и его динамика.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../customization/ui/app_background.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import '../discover_store.dart';

class ChartScreen extends ConsumerWidget {
  const ChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final result = ref.watch(discoverProvider(DiscoverMode.charts));
    final tracks = switch (result.value?.block) {
      DiscoverTracks(:final tracks) => tracks,
      _ => const <Track>[],
    };
    final source = PlainSource(id: 'discover:charts', label: l.homeCharts);
    final playback = ref.read(playbackProvider.notifier);

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
              child: Row(
                children: [
                  Expanded(
                    child: SubPageHeader(
                      title: l.homeCharts,
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Те же кружки поверхности, что и «назад» слева: под ними не
                  // обложка, а фон страницы, и светлое стекло `GlassIconButton`
                  // читалось на нём парой заплаток рядом с шапкой.
                  CircleIconButton(
                    icon: Bi.playBold,
                    onTap: tracks.isEmpty
                        ? null
                        : () => playback.playQueue(tracks, 0, source: source),
                  ),
                  const SizedBox(width: 8),
                  CircleIconButton(
                    icon: Bi.shuffle,
                    onTap: tracks.isEmpty
                        ? null
                        : () => playback.playQueueShuffled(
                            tracks,
                            source: source,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: result.isLoading
                          ? BloomSpinner(size: 22, color: t.accent)
                          : Text(
                              l.setNoTracks,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(color: t.muted),
                            ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        8,
                        4,
                        8,
                        16 + bottomBarsInset(context),
                      ),
                      itemCount: tracks.length,
                      itemBuilder: (context, i) => TrackRow(
                        track: tracks[i],
                        queue: tracks,
                        index: i,
                        source: source,
                        // Место — с самого трека (площадка может отдать чарт с
                        // пропусками), порядковый номер — только запасной.
                        rank: tracks[i].chartPos ?? i + 1,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
