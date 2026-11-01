/// The achievements sheet: the title with how many tiers are taken, then a
/// card per achievement — its medal in the colour of the tier reached, the
/// tier dots, what it counts, the bar to the next tier, when the last came.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../achievements.dart';
import '../stats.dart';

Future<void> showAchievementsSheet(BuildContext context) =>
    showBloomSheetChild<void>(
      context: context,
      header: const _Head(),
      child: const _Cards(),
    );

/// The title, the count on a pill; stays put while the cards scroll.
class _Head extends ConsumerWidget {
  const _Head();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final list = ref.watch(achievementsProvider);
    final done = list.fold(0, (n, a) => n + a.tierReached);
    final total = list.length * kTierOrder.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 6, kSheetEdge, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l.profileAchievements,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bloomText(
                size: 18,
                weight: 700,
                color: t.text,
                letterSpacing: -0.2,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: sheetLineColor(context)),
            ),
            child: Text(
              '$done/$total',
              style: bloomText(size: 12, weight: 700, color: t.text2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cards extends ConsumerWidget {
  const _Cards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(achievementsProvider);
    final unlocked = ref.watch(unlockedAchievementsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final a in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AchCard(
                progress: a,
                // The last tier taken is the one dated.
                unlockedAt: unlocked.at[tierKey(a.def.id, a.tierReached - 1)],
              ),
            ),
        ],
      ),
    );
  }
}

class _AchCard extends StatelessWidget {
  const _AchCard({required this.progress, this.unlockedAt});

  final AchProgress progress;
  final int? unlockedAt;

  static const _gold = [Color(0xFFFFD24A), Color(0xFFFFB01F)];

  String _fmt(BuildContext context, int value) =>
      progress.def.unit == AchUnit.time
      ? fmtDurLong(context, value)
      : NumberFormat.decimalPattern(
          Localizations.localeOf(context).toString(),
        ).format(value);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final a = progress;
    final tint = a.tier == null ? t.muted : tierColor(a.tier!);
    final line = sheetLineColor(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.radius),
        border: Border.all(color: line),
      ),
      // Not reached yet: the whole card dimmed.
      child: Opacity(
        opacity: a.unlocked ? 1 : 0.5,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: a.unlocked
                    ? tint.withValues(alpha: 0.16)
                    : t.text.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: a.unlocked
                      ? tint.withValues(alpha: a.maxed ? 0.45 : 0.4)
                      : line,
                ),
              ),
              child: Center(
                child: BloomIcon(a.def.icon, size: 20, color: tint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.def.name(context.l),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: bloomText(
                            size: 14,
                            weight: 700,
                            color: t.text,
                          ),
                        ),
                      ),
                      for (var i = 0; i < kTierOrder.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < a.tierReached
                                  ? tierColor(kTierOrder[i])
                                  : t.text.withValues(alpha: 0.14),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    a.def.description(context.l),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bloomText(size: 12, weight: 500, color: t.text2),
                  ),
                  const SizedBox(height: 5),
                  _Bar(
                    ratio: a.maxed ? 1 : a.ratio,
                    fill: a.maxed ? null : t.accent,
                    gold: a.maxed ? _gold : null,
                    track: t.text.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        a.maxed
                            ? context.l.achMax.toUpperCase()
                            : '${_fmt(context, a.value)} / ${_fmt(context, a.nextTarget!)}',
                        style: bloomText(
                          size: 11,
                          weight: 700,
                          color: a.maxed ? _gold.first : t.text2,
                          letterSpacing: a.maxed ? 0.5 : null,
                        ),
                      ),
                      const Spacer(),
                      if (unlockedAt case final at?)
                        Text(
                          context.l.achUnlockedAt(_date(context, at)),
                          style: bloomText(
                            size: 11,
                            weight: 500,
                            color: t.muted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _date(BuildContext context, int ms) => DateFormat.yMMMd(
    Localizations.localeOf(context).languageCode,
  ).format(DateTime.fromMillisecondsSinceEpoch(ms));
}

/// The bar to the next tier: accent, or gold across once it's all taken.
class _Bar extends StatelessWidget {
  const _Bar({required this.ratio, required this.track, this.fill, this.gold});

  final double ratio;
  final Color track;
  final Color? fill;
  final List<Color>? gold;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.centerLeft,
      child: ratio <= 0
          ? null
          : FractionallySizedBox(
              widthFactor: ratio.clamp(0.0, 1.0),
              child: Container(
                constraints: const BoxConstraints(minWidth: 6),
                decoration: BoxDecoration(
                  color: fill,
                  gradient: gold == null ? null : LinearGradient(colors: gold!),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
    );
  }
}
