/// Playlist auto-update sheet: the title with the switch and how things stand
/// under it, the period and check at launch, the playlists with sources, and
/// Update now. That button closes the sheet: a live toast shows progress.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/pressable.dart';
import '../pl_auto_store.dart';

/// Period caption.
String _fmtEvery(AppLocalizations l, int min) =>
    min < 60 ? l.paEveryMinutes(min) : l.paEveryHours((min / 60).round());

/// When a playlist last updated, as time ago.
String _ago(AppLocalizations l, int at) {
  final min = ((DateTime.now().millisecondsSinceEpoch - at) / 60000)
      .round()
      .clamp(0, 1 << 31);
  if (min < 1) return l.paJustNow;
  if (min < 60) return l.paMinutesAgo(min);
  final h = (min / 60).round();
  if (h < 24) return l.paHoursAgo(h);
  return l.paDaysAgo((h / 24).round());
}

Future<void> showPlAutoSheet(BuildContext context, WidgetRef ref) {
  final auto = ref.read(plAutoProvider.notifier);
  // First opening: I mark all that can update. An empty target list would mean
  // an inactive Update now out of nowhere, with nowhere else to pick targets.
  final candidates = auto.candidates();
  if (ref.read(plAutoProvider).lastRun == 0 &&
      !candidates.any((p) => p.autoRefresh)) {
    ref
        .read(libraryProvider.notifier)
        .setAutoRefresh(candidates.map((p) => p.id), true);
  }
  return showBloomSheetChild<void>(
    context: context,
    child: const _PlAutoBody(),
  );
}

class _PlAutoBody extends ConsumerWidget {
  const _PlAutoBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(plAutoProvider);
    final auto = ref.read(plAutoProvider.notifier);
    final lib = ref.watch(libraryProvider);
    final candidates = lib.playlists
        .where((p) => p.sources.isNotEmpty)
        .toList();
    final selected = candidates.where((p) => p.autoRefresh).length;
    final library = ref.read(libraryProvider.notifier);
    final allSelected = candidates.isNotEmpty && selected == candidates.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          context.l.paTitle,
          subtitle: _status(context.l, state, selected, candidates.length),
          bottom: 12,
          trailing: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: BloomSwitch(
              value: state.enabled,
              onChanged: auto.setEnabled,
            ),
          ),
        ),
        SheetPanel(
          children: [
            _IntervalRow(
              value: state.everyMin,
              enabled: state.enabled,
              onPick: auto.setEveryMin,
            ),
            sheetDivider(indent: 16),
            SheetSwitchRow(
              label: context.l.paOnStartTitle,
              value: state.onStart,
              // Nothing to check at launch without a schedule.
              enabled: state.enabled,
              onChanged: auto.setOnStart,
              padding: const EdgeInsets.all(16),
            ),
          ],
        ),
        SheetCaption(
          context.l.paPlaylistsWithSources,
          color: t.muted,
          trailing: candidates.length < 2
              ? null
              : Pressable(
                  onTap: state.running
                      ? null
                      : () => library.setAutoRefresh(
                          candidates.map((p) => p.id),
                          !allSelected,
                        ),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l.paSelectAll,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: t.text2),
                        ),
                        const SizedBox(width: 10),
                        BloomCheck(on: allSelected),
                      ],
                    ),
                  ),
                ),
        ),
        if (candidates.isEmpty)
          CenterNote(
            context.l.paNothingToRefresh,
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
          )
        else
          SheetPanel(
            children: [
              for (var i = 0; i < candidates.length; i++) ...[
                if (i > 0) sheetDivider(),
                _CandidateRow(
                  playlist: candidates[i],
                  tracks: lib.tracksOf(candidates[i]).length,
                  covers: lib
                      .tracksOf(candidates[i])
                      .map((track) => track.cover),
                  selected: candidates[i].autoRefresh,
                  busy: state.busy == candidates[i].id,
                  run: state.runs[candidates[i].id],
                  onTap: state.running
                      ? null
                      : () => library.setAutoRefresh([
                          candidates[i].id,
                        ], !candidates[i].autoRefresh),
                ),
              ],
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: SizedBox(
            width: double.infinity,
            child: SheetButton(
              label: context.l.paRefreshNow,
              icon: Bi.refresh,
              tone: ButtonTone.accent,
              onTap: !state.running && selected > 0
                  ? () {
                      Navigator.of(context).pop();
                      auto.runSweep();
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// How things stand, the one line under the title.
String _status(
  AppLocalizations l,
  PlAutoState state,
  int selected,
  int candidates,
) {
  if (state.running) return l.paRefreshing;
  if (!state.enabled) return l.paOff;
  if (selected == 0) return l.paNoneSelected;
  final left =
      state.lastRun +
      state.everyMin * 60 * 1000 -
      DateTime.now().millisecondsSinceEpoch;
  final next = left <= 0
      ? l.paSoon
      : l.paNextIn(_fmtEvery(l, (left / 60000).ceil()));
  return '${l.paSelected(selected, candidates)} · $next';
}

class _IntervalRow extends StatelessWidget {
  const _IntervalRow({
    required this.value,
    required this.enabled,
    required this.onPick,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l.paPeriod,
            style: theme.titleMedium?.copyWith(
              color: enabled ? t.text : t.muted,
            ),
          ),
          const SizedBox(height: 10),
          IgnorePointer(
            ignoring: !enabled,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Row(
                children: [
                  for (final min in kPlAutoIntervals) ...[
                    Expanded(
                      child: OptionTile.label(
                        _fmtEvery(context.l, min),
                        size: 13,
                        height: 38,
                        active: min == value,
                        onTap: () => onPick(min),
                      ),
                    ),
                    if (min != kPlAutoIntervals.last) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.playlist,
    required this.tracks,
    required this.covers,
    required this.selected,
    required this.busy,
    required this.run,
    required this.onTap,
  });

  final UserPlaylist playlist;
  final int tracks;
  final Iterable<String?> covers;
  final bool selected;
  final bool busy;
  final PlAutoRun? run;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final last = busy
        ? context.l.paRunUpdating
        : run == null
        ? null
        : '${run!.failed
              ? context.l.paRunError
              : run!.added > 0
              ? '+${run!.added}'
              : context.l.paRunNoChanges} · ${_ago(context.l, run!.at)}';

    return SheetRow(
      leading: Cover(url: playlist.cover, size: 40, covers: covers),
      gap: 12,
      label: playlist.name,
      subtitle: last == null
          ? context.l.tracksCount(tracks)
          : '${context.l.tracksCount(tracks)} · $last',
      color: context.bloom.text,
      trailing: busy ? const BloomSpinner(size: 20) : BloomCheck(on: selected),
      onTap: onTap,
    );
  }
}
