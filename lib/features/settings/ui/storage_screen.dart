/// Settings → Storage: how much Bloom's caches take and how to wipe them. The
/// ring is the sum of the caches against the phone's memory; each row leads to
/// a sheet with its size, what goes and a red button, since a bin in a list is
/// easy to miss with a finger.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_cache.dart';
import '../../../core/store/settings_store.dart';
import '../../../features/lyrics/lyrics_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/danger_confirm.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/subpage_header.dart';
import '../storage_stats.dart';
import 'settings_rows.dart';

class StorageSettingsScreen extends ConsumerWidget {
  const StorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final stats = ref.watch(storageStatsProvider).valueOrNull;

    return SubPage(
      title: l.setStorage,
      onBack: () => context.go('/settings'),
      children: [
        _UsageCard(stats: stats),
        const SizedBox(height: 22),
        SettingsCaption(l.stManage.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            for (final kind in CacheKind.values)
              _CacheRow(kind: kind, stat: stats?.of(kind)),
          ],
        ),
        const SizedBox(height: 12),
        SettingsGroupCard(rows: [_ClearAllRow(stats: stats)]),
        const SizedBox(height: 22),
        SettingsCaption(l.ltImportTitle.toUpperCase()),
        const SizedBox(height: 10),
        SettingsGroupCard(dividerInset: 52, rows: const [_ImportRow()]),
      ],
    );
  }
}

/// The share of ALL the phone's memory. It's tiny, so the arc has a minimum
/// length: an empty ring over "12 MB" reads as broken.
class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.stats});

  final StorageStats? stats;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final fraction = stats?.fraction;

    return GlassBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            _Ring(
              value: fraction,
              size: 168,
              stroke: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stats == null ? '—' : formatSize(l, stats!.bytes),
                    style: theme.titleLarge?.copyWith(
                      fontSize: 30,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.stUsed,
                    style: theme.bodySmall?.copyWith(color: t.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              stats == null
                  ? l.stCounting
                  : [
                      l.stItems(stats!.count),
                      // Only where the native side told the memory's size.
                      if (fraction != null && stats!.deviceTotal != null)
                        l.stUsedOf(
                          _percent(fraction),
                          formatSize(l, stats!.deviceTotal!),
                        ),
                    ].join(' · '),
              style: theme.bodySmall?.copyWith(color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon, name, and "N items · size" under it.
class _CacheRow extends ConsumerWidget {
  const _CacheRow({required this.kind, required this.stat});

  final CacheKind kind;
  final CacheStat? stat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return SettingsLinkRow(
      icon: _icon(kind),
      title: _title(l, kind),
      subtitle: stat == null ? l.stCounting : _meta(l, stat!),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      onTap: () => _openCacheSheet(context, ref, kind),
    );
  }
}

/// A plate of its own, apart from the rows.
class _ClearAllRow extends ConsumerWidget {
  const _ClearAllRow({required this.stats});

  final StorageStats? stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final empty = stats != null && stats!.count == 0;
    return SettingsRowShell(
      icon: Bi.trashBinTrash,
      iconColor: empty ? t.muted : t.danger,
      title: context.l.stClearAll,
      color: empty ? t.muted : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      trailing: BloomIcon(Bi.altArrowRight, size: 16, color: t.text2),
      onTap: empty ? null : () => _openClearAllSheet(context, ref, stats),
    );
  }
}

/// What Bloom does with a file added with the plus in "All tracks".
class _ImportRow extends ConsumerWidget {
  const _ImportRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final mode = ref.watch(settingsProvider).localImport;
    return SettingsLinkRow(
      icon: _importIcon(mode),
      title: l.ltImportTitle,
      subtitle: _importLabel(l, mode),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      onTap: () => _openImportSheet(context, ref),
    );
  }
}

/// The ring with this kind's share, what goes, and the red button.
Future<void> _openCacheSheet(
  BuildContext context,
  WidgetRef ref,
  CacheKind kind,
) async {
  final l = context.l;
  final messenger = ScaffoldMessenger.of(context);

  final yes = await showBloomSheetChild<bool>(
    context: context,
    // Live numbers: a new time limit for the lyrics drops some at once.
    child: Consumer(
      builder: (context, ref, _) {
        final stats = ref.watch(storageStatsProvider).valueOrNull;
        final stat = stats?.of(kind);
        return _ClearBody(
          icon: _icon(kind),
          title: _title(l, kind),
          subtitle: stat == null ? l.stCounting : l.stItems(stat.count),
          body: _clearBody(l, kind),
          bytes: stat?.bytes ?? 0,
          // The ring shows this kind's share of what is used.
          fraction: _share(stat?.bytes ?? 0, stats?.bytes ?? 0),
          enabled: stat != null && !stat.isEmpty,
          extra: switch (kind) {
            CacheKind.lyrics => const _LyricsKeeping(),
            CacheKind.covers => const _CoversKeeping(),
            _ => null,
          },
        );
      },
    ),
  );
  if (yes != true) return;

  final deleted = await clearCache(ref, kind);
  messenger.toast(_cleared(l, kind, deleted), kind: ToastKind.success);
}

Future<void> _openClearAllSheet(
  BuildContext context,
  WidgetRef ref,
  StorageStats? stats,
) async {
  final l = context.l;
  final messenger = ScaffoldMessenger.of(context);

  final yes = await showBloomSheetChild<bool>(
    context: context,
    child: _ClearBody(
      icon: Bi.trashBinTrash,
      title: l.stClearAll,
      subtitle: stats == null ? l.stCounting : l.stItems(stats.count),
      body: l.stClearAllBody,
      bytes: stats?.bytes ?? 0,
      fraction: 1,
      danger: true,
      enabled: stats != null && stats.count > 0,
    ),
  );
  if (yes != true) return;

  for (final kind in CacheKind.values) {
    await clearCache(ref, kind);
  }
  messenger.toast(l.stAllCleared, kind: ToastKind.success);
}

/// Two choices with a hint: there's no hovering here, so the text stands in the
/// sheet.
Future<void> _openImportSheet(BuildContext context, WidgetRef ref) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.ltImportTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            l.ltImportDesc,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.bloom.text2),
          ),
        ],
      ),
    ),
    child: const _ImportOptions(),
  );
}

/// Two squares and the chosen one's hint. Stays open on choosing: the hint
/// changes with the mode and needs reading.
class _ImportOptions extends ConsumerWidget {
  const _ImportOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final mode = ref.watch(settingsProvider).localImport;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final value in LocalImportMode.values) ...[
                if (value != LocalImportMode.values.first)
                  const SizedBox(width: 10),
                Expanded(
                  child: _ModeButton(
                    value: value,
                    active: value == mode,
                    onTap: () => ref
                        .read(settingsProvider.notifier)
                        .setLocalImport(value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            mode == LocalImportMode.inPlace
                ? l.ltImportInPlaceTip
                : l.ltImportCopyTip,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.value,
    required this.active,
    required this.onTap,
  });

  final LocalImportMode value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OptionTile(
    active: active,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(vertical: 16),
    builder: (ink) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BloomIcon(_importIcon(value), size: 22, color: ink),
        const SizedBox(height: 8),
        Text(
          _importLabel(context.l, value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: ink),
        ),
      ],
    ),
  );
}

/// The ring with the size, the name, what goes, the button.
class _ClearBody extends StatelessWidget {
  const _ClearBody({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.bytes,
    required this.fraction,
    required this.enabled,
    this.danger = false,
    this.extra,
  });

  /// Settings of this kind, above the button.
  final Widget? extra;

  final BloomGlyph icon;
  final String title;
  final String subtitle;
  final String body;
  final int bytes;
  final double fraction;

  /// On an empty cache the button greys out.
  final bool enabled;

  /// "Clear all": the ring is red, not accent.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Column(
        children: [
          _Ring(
            value: enabled ? fraction : 0,
            size: 132,
            stroke: 8,
            color: danger ? t.danger : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BloomIcon(icon, size: 22, color: t.iconFg),
                const SizedBox(height: 6),
                Text(
                  formatSize(l, bytes),
                  style: theme.titleLarge?.copyWith(fontSize: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.titleLarge),
          const SizedBox(height: 4),
          Text(subtitle, style: theme.bodyMedium?.copyWith(color: t.text2)),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.bodySmall?.copyWith(color: t.text2),
          ),
          if (extra case final extra?) ...[const SizedBox(height: 18), extra],
          const SizedBox(height: 20),
          DangerSheetButton(label: l.statsClear, enabled: enabled),
        ],
      ),
    );
  }
}

/// Keeping lyrics and for how long. Off, the periods stay in view, dimmed.
class _LyricsKeeping extends ConsumerWidget {
  const _LyricsKeeping();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final prefs = ref.watch(lyricsPrefsProvider);
    final ctrl = ref.read(lyricsPrefsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(l.stLyricsKeep, style: theme.titleMedium)),
            BloomSwitch(value: prefs.cache, onChanged: ctrl.setCache),
          ],
        ),
        const SizedBox(height: 12),
        IgnorePointer(
          ignoring: !prefs.cache,
          child: AnimatedOpacity(
            opacity: prefs.cache ? 1 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: _KeepTiles(
              value: prefs.keep,
              onPick: (keep) {
                final gone = ctrl.setKeep(keep);
                ref.invalidate(storageStatsProvider);
                if (gone > 0) {
                  ScaffoldMessenger.of(context).toast(l.stStaleRemoved(gone));
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// How long downloaded covers stay.
class _CoversKeeping extends ConsumerWidget {
  const _CoversKeeping();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final ctrl = ref.read(coverKeepProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.stCoversKeep, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _KeepTiles(
          value: ref.watch(coverKeepProvider),
          onPick: (keep) async {
            final messenger = ScaffoldMessenger.of(context);
            final gone = await ctrl.set(keep);
            if (!context.mounted) return;
            ref.invalidate(storageStatsProvider);
            if (gone > 0) messenger.toast(l.stStaleRemoved(gone));
          },
        ),
      ],
    );
  }
}

class _KeepTiles extends StatelessWidget {
  const _KeepTiles({required this.value, required this.onPick});

  final CacheKeep value;
  final ValueChanged<CacheKeep> onPick;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    return GridView(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 48,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        for (final keep in CacheKeep.values)
          OptionTile(
            active: value == keep,
            onTap: () => onPick(keep),
            builder: (ink) => Text(
              _keepLabel(l, keep),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall?.copyWith(color: ink),
            ),
          ),
      ],
    );
  }
}

String _keepLabel(AppLocalizations l, CacheKeep keep) => switch (keep) {
  CacheKeep.never => l.stKeepNever,
  CacheKeep.restart => l.stKeepRestart,
  CacheKeep.day => l.stKeepDay,
  CacheKeep.days3 => l.stKeep3Days,
  CacheKeep.week => l.stKeepWeek,
  CacheKeep.month => l.stKeepMonth,
};

/// A track and an arc. Size and thickness come from outside.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.value,
    required this.size,
    required this.stroke,
    required this.child,
    this.color,
  });

  /// 0..1; `null` while counting, no arc.
  final double? value;
  final double size;
  final double stroke;
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value ?? 0,
          stroke: stroke,
          track: t.track,
          fill: color ?? t.accent,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.fill,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.shortestSide - stroke) / 2,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(rect.center, rect.width / 2, base);
    if (value <= 0) return;

    // At least this much: the share of the phone's memory is a fraction of a
    // percent, and an honest arc would be shorter than its own rounding.
    final sweep = 6.28318530718 * value.clamp(0.02, 1.0);
    canvas.drawArc(rect, -1.5707963268, sweep, false, base..color = fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      old.track != track ||
      old.fill != fill;
}

BloomGlyph _icon(CacheKind kind) => switch (kind) {
  CacheKind.offline => Bi.downloadMinimalistic,
  CacheKind.lyrics => Bi.microphone3,
  CacheKind.covers => Bi.gallery,
  CacheKind.custom => Bi.palette,
};

String _title(AppLocalizations l, CacheKind kind) => switch (kind) {
  CacheKind.offline => l.stOfflineCache,
  CacheKind.lyrics => l.stLyrics,
  CacheKind.covers => l.stCovers,
  CacheKind.custom => l.stCustom,
};

String _clearBody(AppLocalizations l, CacheKind kind) => switch (kind) {
  CacheKind.offline => l.stClearBody,
  CacheKind.lyrics => l.stClearLyricsBody,
  CacheKind.covers => l.stClearCoversBody,
  CacheKind.custom => l.stClearCustomBody,
};

String _cleared(AppLocalizations l, CacheKind kind, int count) =>
    switch (kind) {
      CacheKind.offline => l.stCleared(count),
      CacheKind.lyrics => l.stLyricsCleared,
      CacheKind.covers => l.stCoversCleared,
      CacheKind.custom => l.stCustomCleared,
    };

/// "N items · size"; an empty cache shows no size, it's always "0 B".
String _meta(AppLocalizations l, CacheStat stat) => stat.isEmpty
    ? l.stItems(0)
    : '${l.stItems(stat.count)} · ${formatSize(l, stat.bytes)}';

BloomGlyph _importIcon(LocalImportMode mode) =>
    mode == LocalImportMode.inPlace ? Bi.folder : Bi.downloadMinimalistic;

String _importLabel(AppLocalizations l, LocalImportMode mode) =>
    mode == LocalImportMode.inPlace ? l.ltImportInPlace : l.ltImportCopy;

/// This kind's share of what's used; nothing stored, an empty ring.
double _share(int bytes, int total) =>
    total <= 0 || bytes <= 0 ? 0 : (bytes / total).clamp(0.0, 1.0);

/// Fractions of a percent are usual here, and a rounded zero would look like an
/// error.
String _percent(double fraction) {
  final pct = fraction * 100;
  if (pct >= 10) return pct.toStringAsFixed(0);
  if (pct >= 1) return pct.toStringAsFixed(1);
  return pct.toStringAsFixed(2);
}

/// Kilobytes for small things, then megabytes and gigabytes.
String formatSize(AppLocalizations l, int bytes) {
  if (bytes < 1024) return l.stBytes('$bytes');
  final kb = bytes / 1024;
  if (kb < 1024) return l.stKilobytes(kb.toStringAsFixed(0));
  final mb = kb / 1024;
  if (mb < 1024) return l.stMegabytes(mb.toStringAsFixed(mb < 10 ? 1 : 0));
  final gb = mb / 1024;
  return l.stGigabytes(gb.toStringAsFixed(gb < 100 ? 1 : 0));
}
