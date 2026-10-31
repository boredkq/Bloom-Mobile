/// Настройки → «Хранилище»: сколько места занимают кеши Bloom и как их стереть.
///
/// Порт десктопной секции `TelemetrySection` — раскладка та же: сверху кольцо
/// «Занято» (сумма кешей на фоне памяти телефона), под ним строки категорий с
/// их объёмом и отдельная строка «Очистить всё».
///
/// Отличие от ПК одно и оно от пальца: там у каждой строки своя корзина и
/// подтверждение системным `confirm()`, здесь строка ведёт в шторку — в ней и
/// объём крупно, и что именно пропадёт, и красная кнопка. Промахнуться по
/// корзине в списке легко, по шторке — нет.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../features/lyrics/lyrics_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/danger_confirm.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/subpage_header.dart';
import '../storage_stats.dart';

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

/// Карточка «Занято»: кольцо с общим объёмом кешей.
///
/// Кольцо заполняется долей от ВСЕЙ памяти телефона — как на ПК, где
/// знаменатель берётся из квоты вебвью. Доля эта крошечная, поэтому у дуги есть
/// минимальная видимая длина: пустое кольцо над цифрой «12 МБ» читалось бы
/// сломанным индикатором.
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
                      // Доля есть только там, где нативная сторона сказала
                      // объём памяти телефона.
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

/// Строка категории: иконка, название и «N файлов · размер» под ним.
class _CacheRow extends ConsumerWidget {
  const _CacheRow({required this.kind, required this.stat});

  final CacheKind kind;
  final CacheStat? stat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;

    return Pressable(
      onTap: () => _openCacheSheet(context, ref, kind),
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: BloomIcon(_icon(kind), size: 20, color: t.iconFg),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_title(l, kind), style: theme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    stat == null ? l.stCounting : _meta(l, stat!),
                    style: theme.bodySmall?.copyWith(color: t.text2),
                  ),
                ],
              ),
            ),
            BloomIcon(Bi.altArrowRight, size: 16, color: t.text2),
          ],
        ),
      ),
    );
  }
}

/// «Очистить всё» — своей плашкой, как на десктопе, где кнопка стоит отдельно
/// от списка строк.
class _ClearAllRow extends ConsumerWidget {
  const _ClearAllRow({required this.stats});

  final StorageStats? stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final empty = stats != null && stats!.count == 0;

    return Pressable(
      onTap: empty ? null : () => _openClearAllSheet(context, ref, stats),
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: BloomIcon(
                Bi.trashBinTrash,
                size: 20,
                color: empty ? t.muted : t.danger,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                l.stClearAll,
                style: theme.titleMedium?.copyWith(
                  color: empty ? t.muted : t.text,
                ),
              ),
            ),
            BloomIcon(Bi.altArrowRight, size: 16, color: t.text2),
          ],
        ),
      ),
    );
  }
}

/// Строка «Свои треки»: что Bloom делает с файлом, добавленным плюсом во «Всех
/// треках». Порт десктопной карточки `settings.library.import` (там она про
/// папки, у нас про одиночные файлы) — выбор уехал в шторку, чтобы страница
/// осталась списком строк.
class _ImportRow extends ConsumerWidget {
  const _ImportRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final mode = ref.watch(settingsProvider).localImport;

    return Pressable(
      onTap: () => _openImportSheet(context, ref),
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: BloomIcon(_importIcon(mode), size: 20, color: t.iconFg),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.ltImportTitle, style: theme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    _importLabel(l, mode),
                    style: theme.bodySmall?.copyWith(color: t.text2),
                  ),
                ],
              ),
            ),
            BloomIcon(Bi.altArrowRight, size: 16, color: t.text2),
          ],
        ),
      ),
    );
  }
}

/// Шторка категории: кольцо с её долей от занятого, что именно пропадёт и
/// красная кнопка.
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
          extra: kind == CacheKind.lyrics ? const _LyricsKeeping() : null,
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

/// Шторка выбора режима импорта: два варианта с подсказкой под каждым.
///
/// Подсказку на ПК показывает тултип по наведению; на телефоне наводить нечем,
/// поэтому текст стоит прямо в строке варианта.
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

/// Два квадрата выбора и подсказка выбранного под ними — та же карточка, что
/// стояла на странице, и тот же вид, что у выбора анимации в настройках плеера.
///
/// Шторка по выбору НЕ закрывается: подсказка под квадратами меняется вместе с
/// режимом, и её надо успеть прочитать.
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

/// Тело шторки очистки: кольцо с объёмом, название, что пропадёт, кнопка.
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

  /// Есть ли что стирать — на пустом кеше кнопка гаснет.
  final bool enabled;

  /// «Очистить всё»: кольцо красное, а не акцентное.
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

/// Keeping lyrics on the phone and for how long — the PC's switch and
/// dropdown on its lyrics row. Off, the periods stay in view, dimmed.
class _LyricsKeeping extends ConsumerWidget {
  const _LyricsKeeping();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final prefs = ref.watch(lyricsPrefsProvider);
    final ctrl = ref.read(lyricsPrefsProvider.notifier);

    void pick(LyricsKeep keep) {
      final gone = ctrl.setKeep(keep);
      ref.invalidate(storageStatsProvider);
      if (gone > 0) {
        ScaffoldMessenger.of(context).toast(l.stStaleRemoved(gone));
      }
    }

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
            child: GridView(
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
                for (final keep in LyricsKeep.values)
                  OptionTile(
                    active: prefs.keep == keep,
                    onTap: () => pick(keep),
                    builder: (ink) => Text(
                      _keepLabel(l, keep),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleSmall?.copyWith(color: ink),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _keepLabel(AppLocalizations l, LyricsKeep keep) => switch (keep) {
  LyricsKeep.never => l.stKeepNever,
  LyricsKeep.restart => l.stKeepRestart,
  LyricsKeep.day => l.stKeepDay,
  LyricsKeep.days3 => l.stKeep3Days,
  LyricsKeep.week => l.stKeepWeek,
  LyricsKeep.month => l.stKeepMonth,
};

/// Кольцо-индикатор: дорожка плюс дуга занятого. Общее у карточки страницы и
/// шторок — размер и толщина задаются снаружи.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.value,
    required this.size,
    required this.stroke,
    required this.child,
    this.color,
  });

  /// Доля 0..1; `null` — считаем (дуги нет).
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

    // Минимум дуги: занятое от памяти телефона — это доли процента, и честная
    // дуга была бы короче собственного скругления, то есть невидима.
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
  CacheKind.custom => Bi.palette,
};

String _title(AppLocalizations l, CacheKind kind) => switch (kind) {
  CacheKind.offline => l.stOfflineCache,
  CacheKind.lyrics => l.stLyrics,
  CacheKind.custom => l.stCustom,
};

String _clearBody(AppLocalizations l, CacheKind kind) => switch (kind) {
  CacheKind.offline => l.stClearBody,
  CacheKind.lyrics => l.stClearLyricsBody,
  CacheKind.custom => l.stClearCustomBody,
};

String _cleared(AppLocalizations l, CacheKind kind, int count) =>
    switch (kind) {
      CacheKind.offline => l.stCleared(count),
      CacheKind.lyrics => l.stLyricsCleared,
      CacheKind.custom => l.stCustomCleared,
    };

/// «N файлов · размер»; у пустого кеша размер не пишем — там всегда «0 Б».
String _meta(AppLocalizations l, CacheStat stat) => stat.isEmpty
    ? l.stItems(0)
    : '${l.stItems(stat.count)} · ${formatSize(l, stat.bytes)}';

BloomGlyph _importIcon(LocalImportMode mode) =>
    mode == LocalImportMode.inPlace ? Bi.folder : Bi.downloadMinimalistic;

String _importLabel(AppLocalizations l, LocalImportMode mode) =>
    mode == LocalImportMode.inPlace ? l.ltImportInPlace : l.ltImportCopy;

/// Доля категории в занятом; пустое хранилище — пустое кольцо.
double _share(int bytes, int total) =>
    total <= 0 || bytes <= 0 ? 0 : (bytes / total).clamp(0.0, 1.0);

/// «0.4» / «7» — доли процента у кешей на фоне памяти телефона обычное дело, и
/// округлённый до целого ноль выглядел бы ошибкой.
String _percent(double fraction) {
  final pct = fraction * 100;
  if (pct >= 10) return pct.toStringAsFixed(0);
  if (pct >= 1) return pct.toStringAsFixed(1);
  return pct.toStringAsFixed(2);
}

/// Размер по-человечески: килобайты для мелочи, дальше мегабайты и гигабайты.
String formatSize(AppLocalizations l, int bytes) {
  if (bytes < 1024) return l.stBytes('$bytes');
  final kb = bytes / 1024;
  if (kb < 1024) return l.stKilobytes(kb.toStringAsFixed(0));
  final mb = kb / 1024;
  if (mb < 1024) return l.stMegabytes(mb.toStringAsFixed(mb < 10 ? 1 : 0));
  final gb = mb / 1024;
  return l.stGigabytes(gb.toStringAsFixed(gb < 100 ? 1 : 0));
}
