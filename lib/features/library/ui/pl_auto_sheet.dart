/// Шторка «Авто-обновление плейлистов» — порт десктопного `PlAutoDrawer`.
///
/// Состав тот же: расписание (тумблер, период, «проверять при запуске»), список
/// плейлистов с источниками и «Обновить сейчас». Отличие одно — кнопка обхода
/// закрывает шторку: прогресс на телефоне показывает живой тост, а он лежит
/// ПОД шторкой и из-под неё не виден.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../pl_auto_store.dart';
import '../../settings/ui/settings_rows.dart';

/// «30 мин» / «3 ч» — подпись периода (десктопный `fmtEvery`).
String _fmtEvery(AppLocalizations l, int min) =>
    min < 60 ? l.paEveryMinutes(min) : l.paEveryHours((min / 60).round());

/// «2 ч назад» — когда плейлист обновлялся в последний раз.
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
  // Первое открытие: отмечаем всё, что можно обновлять. Пустой список целей
  // означал бы неактивную кнопку «Обновить сейчас» на ровном месте — на ПК
  // цели набираются мышью в сайдбаре, здесь набирать их неоткуда.
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
        _Hero(selected: selected, candidates: candidates.length),
        SheetPanel(
          children: [
            SettingsToggleRow(
              title: context.l.paAutoTitle,
              subtitle: context.l.paAutoSubtitle,
              value: state.enabled,
              onChanged: auto.setEnabled,
            ),
            sheetDivider(),
            _IntervalRow(
              value: state.everyMin,
              enabled: state.enabled,
              onPick: auto.setEveryMin,
            ),
            sheetDivider(),
            SettingsToggleRow(
              title: context.l.paOnStartTitle,
              subtitle: context.l.paOnStartSubtitle,
              value: state.onStart,
              // Nothing to check at launch without a schedule.
              enabled: state.enabled,
              onChanged: auto.setOnStart,
            ),
          ],
        ),
        SheetCaption(
          context.l.paPlaylistsWithSources,
          color: t.muted,
          trailing: candidates.isEmpty
              ? null
              : BloomButton(
                  label: allSelected
                      ? context.l.paDeselectAll
                      : context.l.paSelectAll,
                  height: 24,
                  onTap: state.running
                      ? null
                      : () => library.setAutoRefresh(
                          candidates.map((p) => p.id),
                          !allSelected,
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
        _Footer(
          hint: state.running
              ? context.l.paRefreshing
              : state.lastRun == 0
              ? context.l.paNeverRefreshed
              : context.l.paLastRun(_ago(context.l, state.lastRun)),
          canRun: !state.running && selected > 0,
          onRun: () {
            Navigator.of(context).pop();
            auto.runSweep();
          },
        ),
      ],
    );
  }
}

/// Шапка: иконка обновления, заголовок и чипы состояния — как `mpl-hero` на ПК.
class _Hero extends ConsumerWidget {
  const _Hero({required this.selected, required this.candidates});

  final int selected;
  final int candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(plAutoProvider);
    String? next() {
      if (!state.enabled || selected == 0) return null;
      final left =
          state.lastRun +
          state.everyMin * 60 * 1000 -
          DateTime.now().millisecondsSinceEpoch;
      if (left <= 0) return context.l.paSoon;
      final min = (left / 60000).ceil();
      return context.l.paNextIn(_fmtEvery(context.l, min));
    }

    final chips = [
      context.l.paSelected(selected, candidates),
      if (state.enabled) _fmtEvery(context.l, state.everyMin),
      ?next(),
    ];
    return SheetTitle(
      context.l.paTitle,
      bottom: 12,
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: t.sysAllTint,
          borderRadius: BorderRadius.circular(t.radius),
        ),
        child: BloomIcon(
          Bi.refresh,
          size: 24,
          color: state.running ? t.accent : t.sysAllIco,
        ),
      ),
      line: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final chip in chips) BloomTag(text: chip, active: false),
          ],
        ),
      ),
    );
  }
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
                      child: OptionTile(
                        active: min == value,
                        height: 36,
                        onTap: () => onPick(min),
                        builder: (ink) => Text(
                          _fmtEvery(context.l, min),
                          style: theme.bodySmall?.copyWith(color: ink),
                        ),
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
      leading: Cover(url: playlist.cover, size: 44, covers: covers),
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

class _Footer extends StatelessWidget {
  const _Footer({
    required this.hint,
    required this.canRun,
    required this.onRun,
  });

  final String hint;
  final bool canRun;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        children: [
          Text(hint, style: theme.bodySmall?.copyWith(color: t.muted)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: BloomButton(
              label: context.l.paRefreshNow,
              tone: ButtonTone.accent,
              height: 46,
              onTap: canRun ? onRun : null,
            ),
          ),
        ],
      ),
    );
  }
}
