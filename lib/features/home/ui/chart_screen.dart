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

import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import '../discover_store.dart';

class ChartScreen extends ConsumerWidget {
  const ChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final result = ref.watch(discoverProvider(DiscoverMode.charts));
    final tracks = switch (result.value?.block) {
      DiscoverTracks(:final tracks) => tracks,
      _ => const <Track>[],
    };
    final source = PlainSource(id: 'discover:charts', label: l.homeCharts);
    final playback = ref.read(playbackProvider.notifier);
    return BloomPage(
      body: SubPage(
        title: l.homeCharts,
        onBack: () => Navigator.of(context).pop(),
        actions: [
          CircleIconButton(
            icon: Bi.playBold,
            onTap: tracks.isEmpty
                ? null
                : () => playback.playQueue(tracks, 0, source: source),
          ),
          CircleIconButton(
            icon: Bi.shuffle,
            onTap: tracks.isEmpty
                ? null
                : () => playback.playQueueShuffled(tracks, source: source),
          ),
        ],
        child: tracks.isEmpty
            ? Center(
                child: result.isLoading
                    ? const BloomSpinner()
                    : CenterNote(l.setNoTracks),
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
                  rank: tracks[i].chartPos ?? i + 1,
                ),
              ),
      ),
    );
  }
}
