/// Settings → Storage: a ring of what each cache takes, the caches with a tick
/// and their share, how long they're kept, and one button for what's ticked. A
/// cache's tick and bar take its arc's shade, so the ring needs no legend.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_cache.dart';
import '../../../core/store/settings_store.dart';
import '../../../features/lyrics/lyrics_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/subpage_header.dart';
import '../storage_stats.dart';
import 'settings_rows.dart';
import 'settings_sheets.dart';

class StorageSettingsScreen extends ConsumerStatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  ConsumerState<StorageSettingsScreen> createState() => _StorageState();
}

class _StorageState extends ConsumerState<StorageSettingsScreen> {
  // What comes back by itself starts ticked. Downloads and one's own pictures
  // don't, they wait for a deliberate tick.
  final Set<CacheKind> _picked = {CacheKind.lyrics, CacheKind.covers};
  bool _clearing = false;

  void _toggle(CacheKind kind) => setState(() {
    if (!_picked.remove(kind)) _picked.add(kind);
  });

  Future<void> _clear(List<CacheKind> kinds) async {
    final l = context.l;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _clearing = true);
    var deleted = 0;
    for (final kind in kinds) {
      deleted = await clearCache(container, kind);
    }
    toaster.show(
      kinds.length == 1 ? _cleared(l, kinds.single, deleted) : l.stAllCleared,
      kind: ToastKind.success,
    );
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final stats = ref.watch(storageStatsProvider).valueOrNull;
    final used = stats?.bytes ?? 0;
    final kinds = [
      for (final kind in CacheKind.values)
        if (_picked.contains(kind) && !(stats?.of(kind).isEmpty ?? true)) kind,
    ];

    return SubPage(
      title: l.setStorage,
      onBack: () => context.go('/settings'),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                _UsageCard(stats: stats),
                const SizedBox(height: 22),
                SettingsCaption(l.stManage),
                const SizedBox(height: 8),
                for (final kind in CacheKind.values)
                  _CacheRow(
                    kind: kind,
                    stat: stats?.of(kind),
                    used: used,
                    picked: _picked.contains(kind),
                    onTap: () => _toggle(kind),
                  ),
                const SizedBox(height: 14),
                const _KeepCard(),
                const SizedBox(height: 22),
                SettingsCaption(l.ltImportTitle),
                const SizedBox(height: 10),
                const _ImportChoice(),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              12 + bottomBarsInset(context),
            ),
            child: _ClearButton(
              kinds: kinds,
              bytes: kinds.fold(0, (sum, k) => sum + stats!.of(k).bytes),
              busy: _clearing,
              onClear: () => _clear(kinds),
            ),
          ),
        ],
      ),
    );
  }
}

/// Used: the sum of the caches below, so clearing a row shrinks the ring.
class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.stats});

  final StorageStats? stats;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    return GlassBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox.square(
            dimension: 180,
            child: CustomPaint(
              painter: _RingPainter(
                arcs: stats?.arcs ?? const [],
                tones: [for (final kind in CacheKind.values) _tone(t, kind)],
                track: t.ovlLine2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    stats == null ? '—' : formatSize(l, stats!.bytes),
                    style: bloomText(size: 26, weight: 500, color: t.text),
                  ),
                  const SizedBox(height: 4),
                  SettingsCaption(l.stUsed),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.arcs,
    required this.tones,
    required this.track,
  });

  static const double _stroke = 6;

  final List<StorageArc> arcs;
  final List<Color> tones;
  final Color track;

  double _rad(double degrees) => degrees * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - _stroke) / 2,
    );
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = track;
    canvas.drawCircle(rect.center, rect.width / 2, pen);
    for (final arc in arcs) {
      pen.color = tones[arc.index];
      canvas.drawArc(rect, _rad(arc.start), _rad(arc.sweep), false, pen);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      !listEquals(old.arcs, arcs) ||
      !listEquals(old.tones, tones) ||
      old.track != track;
}

/// A tick in its arc's shade, the name and size, the share of what's used. An
/// empty cache has nothing to clear: its tick fades and the row doesn't press.
class _CacheRow extends StatelessWidget {
  const _CacheRow({
    required this.kind,
    required this.stat,
    required this.used,
    required this.picked,
    required this.onTap,
  });

  final CacheKind kind;
  final CacheStat? stat;
  final int used;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final tone = _tone(t, kind);
    final bytes = stat?.bytes ?? 0;
    final empty = stat?.isEmpty ?? true;
    final on = picked && !empty;

    return Semantics(
      checked: on,
      enabled: !empty,
      child: Pressable(
        onTap: empty ? null : onTap,
        scale: 0.98,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Opacity(
                opacity: empty ? 0.35 : 1,
                child: _Tick(on: on, color: tone),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  // The bar takes its track's width from here.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _title(l, kind),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          stat == null ? '—' : formatSize(l, bytes),
                          style: theme.bodySmall?.copyWith(color: t.text2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    BloomBar(
                      // A cache too small to see still gets a sliver.
                      value: bytes > 0
                          ? (bytes / math.max(used, 1)).clamp(0.015, 1.0)
                          : 0,
                      color: tone,
                      track: t.ovlLine2,
                      height: 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.on, required this.color});

  final bool on;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: 26,
    height: 26,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on ? color : Colors.transparent,
      border: Border.all(color: color, width: 1.6),
    ),
    alignment: Alignment.center,
    child: on
        ? BloomIcon(
            Bi.check,
            size: 15,
            // The shades run from the text's colour to grey: either ink can
            // be the one that shows.
            color: color.computeLuminance() > 0.18
                ? Colors.black
                : Colors.white,
          )
        : null,
  );
}

/// Clears what's ticked and says how much. It asks with a second press, and a
/// new set of ticks asks again: the press was about the old one.
class _ClearButton extends StatelessWidget {
  const _ClearButton({
    required this.kinds,
    required this.bytes,
    required this.busy,
    required this.onClear,
  });

  final List<CacheKind> kinds;
  final int bytes;
  final bool busy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return SecondTap(
      key: ValueKey(kinds.fold(0, (mask, k) => mask | 1 << k.index)),
      onConfirm: onClear,
      builder: (armed, tap) => BloomButton(
        label: kinds.isEmpty
            ? l.commonClear
            : armed
            ? l.stClearSure
            : l.stClearSize(formatSize(l, bytes)),
        tone: armed ? ButtonTone.danger : ButtonTone.ink,
        height: 52,
        busy: busy,
        onTap: kinds.isEmpty ? null : tap,
      ),
    );
  }
}

/// Keeping lyrics, and for how long lyrics and covers stay. A new time limit
/// applies at once. With the switch off, the period stays in view, dimmed.
class _KeepCard extends ConsumerWidget {
  const _KeepCard();

  Future<void> _pick(
    BuildContext context,
    String title,
    CacheKeep current,
    ValueChanged<CacheKeep> apply,
  ) {
    final l = context.l;
    return pickOneSheet<CacheKeep>(
      context: context,
      title: title,
      values: CacheKeep.values,
      current: current,
      label: (keep) => _keepLabel(l, keep),
      apply: apply,
    );
  }

  void _stale(WidgetRef ref, AppLocalizations l, int gone) {
    ref.invalidate(storageStatsProvider);
    if (gone > 0) toaster.show(l.stStaleRemoved(gone));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final lyrics = ref.watch(lyricsPrefsProvider);
    final covers = ref.watch(coverKeepProvider);

    return SettingsGroupCard(
      rows: [
        SettingsRowShell(
          title: l.stLyricsKeep,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          trailing: BloomSwitch(
            value: lyrics.cache,
            onChanged: ref.read(lyricsPrefsProvider.notifier).setCache,
          ),
        ),
        SettingsRow(
          title: l.stLyricsKeepFor,
          value: _keepLabel(l, lyrics.keep),
          enabled: lyrics.cache,
          onTap: () => _pick(context, l.stLyricsKeepFor, lyrics.keep, (keep) {
            _stale(
              ref,
              l,
              ref.read(lyricsPrefsProvider.notifier).setKeep(keep),
            );
          }),
        ),
        SettingsRow(
          title: l.stCoversKeep,
          value: _keepLabel(l, covers),
          onTap: () => _pick(context, l.stCoversKeep, covers, (keep) async {
            final gone = await ref.read(coverKeepProvider.notifier).set(keep);
            if (context.mounted) _stale(ref, l, gone);
          }),
        ),
      ],
    );
  }
}

/// What Bloom does with a file added with the plus in "All tracks". The chosen
/// way's words stand under the cards.
class _ImportChoice extends ConsumerWidget {
  const _ImportChoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final mode = ref.watch(settingsProvider).localImport;
    final note = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.bloom.text2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.ltImportDesc, style: note),
        const SizedBox(height: 12),
        PickRow<LocalImportMode>(
          values: LocalImportMode.values,
          active: (v) => v == mode,
          label: (v) => _importLabel(l, v),
          picture: (v, _) => BloomIcon(_importIcon(v)),
          onTap: ref.read(settingsProvider.notifier).setLocalImport,
        ),
        const SizedBox(height: 12),
        Text(
          mode == LocalImportMode.inPlace
              ? l.ltImportInPlaceTip
              : l.ltImportCopyTip,
          style: note,
        ),
      ],
    );
  }
}

/// Shades of the theme's text towards the block: white to grey on a dark theme,
/// black to grey on a light one. The last still stands off the track.
Color _tone(BloomTokens t, CacheKind kind) => Color.lerp(
  t.text,
  t.blockColor,
  const {
    CacheKind.lyrics: 0.0,
    CacheKind.covers: 0.28,
    CacheKind.offline: 0.5,
    CacheKind.custom: 0.7,
  }[kind]!,
)!;

String _keepLabel(AppLocalizations l, CacheKeep keep) => switch (keep) {
  CacheKeep.never => l.stKeepNever,
  CacheKeep.restart => l.stKeepRestart,
  CacheKeep.day => l.stKeepDay,
  CacheKeep.days3 => l.stKeep3Days,
  CacheKeep.week => l.stKeepWeek,
  CacheKeep.month => l.stKeepMonth,
};

String _title(AppLocalizations l, CacheKind kind) => switch (kind) {
  CacheKind.lyrics => l.stLyrics,
  CacheKind.covers => l.stCovers,
  CacheKind.offline => l.stOfflineCache,
  CacheKind.custom => l.stCustom,
};

String _cleared(AppLocalizations l, CacheKind kind, int count) =>
    switch (kind) {
      CacheKind.lyrics => l.stLyricsCleared,
      CacheKind.covers => l.stCoversCleared,
      CacheKind.offline => l.stCleared(count),
      CacheKind.custom => l.stCustomCleared,
    };

BloomGlyph _importIcon(LocalImportMode mode) =>
    mode == LocalImportMode.inPlace ? Bi.folder : Bi.downloadMinimalistic;

String _importLabel(AppLocalizations l, LocalImportMode mode) =>
    mode == LocalImportMode.inPlace ? l.ltImportInPlace : l.ltImportCopy;

/// Kilobytes for small things, then megabytes and gigabytes with a decimal.
String formatSize(AppLocalizations l, int bytes) {
  final mb = bytes / 1048576;
  if (mb >= 1024) return l.stGigabytes((mb / 1024).toStringAsFixed(1));
  if (mb >= 1) return l.stMegabytes(mb.toStringAsFixed(1));
  final kb = bytes > 0 ? math.max(1, (bytes / 1024).round()) : 0;
  return l.stKilobytes('$kb');
}
