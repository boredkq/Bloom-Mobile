/// Level on the profile. [LevelBadge] is an accent shield with the number
/// before the nick; a tap opens the sheet: the shield, Level N, a line about
/// it, an XP bar with the next level's shield at its end, how far to go, and
/// where XP comes from with each source's amount. No rewards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../level.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../settings/ui/settings_rows.dart';

Future<void> showLevelSheet(BuildContext context) =>
    showBloomSheetChild<void>(context: context, child: const LevelSheet());

/// Shield with a number. Only the number changes; long numbers get a smaller
/// font, and the shield doesn't grow.
class LevelBadge extends ConsumerWidget {
  const LevelBadge({super.key, this.size = 28, this.level, this.onTap});

  final double size;

  /// Own number: the next level's shield on the bar; `null` is the current.
  final int? level;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final n = level ?? ref.watch(levelProvider.select((l) => l.level));
    final digits = '$n'.length;
    final fs = size * (digits < 2 ? 0.42 : (digits < 3 ? 0.36 : 0.29));
    final badge = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          BloomIcon(Bi.shieldMinimalisticBold, size: size, color: t.accent),
          // The shield is heavier on top: the number stands a bit above the
          // middle.
          Transform.translate(
            offset: Offset(0, -size * 0.03),
            child: Text(
              '$n',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: t.accentText,
                fontSize: fs.roundToDouble(),
                height: 1,
                letterSpacing: -0.02 * fs,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return badge;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: badge,
    );
  }
}

class LevelSheet extends ConsumerWidget {
  const LevelSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final lv = ref.watch(levelProvider);
    final into = lv.xp - lv.from;
    final span = lv.to - lv.from;
    final rest = span - into;
    final fmt = NumberFormat.decimalPattern(
      Localizations.localeOf(context).languageCode,
    ).format;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Center(child: LevelBadge(size: 56)),
        const SizedBox(height: 14),
        Text(
          l.levelTitle(lv.level),
          textAlign: TextAlign.center,
          style: theme.titleLarge,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            l.levelDesc,
            textAlign: TextAlign.center,
            style: theme.bodyMedium?.copyWith(color: t.text2, height: 1.35),
          ),
        ),
        const SizedBox(height: 22),
        // The bar: progress through this level, with the next one's shield at
        // the end.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: sheetPanelColor(context),
              borderRadius: BorderRadius.circular(t.radius * 0.8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (into / span).clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.text.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(t.radius * 0.8),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.levelXp(fmt(into), fmt(span)),
                          style: theme.titleSmall,
                        ),
                      ),
                      LevelBadge(size: 24, level: lv.level + 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(
            '${l.levelToNext(lv.level + 1, fmt(rest))} · '
            '${l.levelTracks((rest / kXpPerPlay).ceil())}',
            style: theme.bodySmall?.copyWith(color: t.muted),
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: SettingsCaption(l.levelHow),
        ),
        _Source(
          icon: Bi.headphonesRound,
          title: l.levelPlays,
          sub: l.levelPlaysSub(kXpPerPlay),
          xp: fmt(lv.plays),
        ),
        _Source(
          icon: Bi.calendar,
          title: l.levelDays,
          sub: l.levelDaysSub(kXpPerDay),
          xp: fmt(lv.days),
        ),
        _Source(
          icon: Bi.medalRibbonsStar,
          title: l.levelAch,
          sub: l.levelAchSub(kTierXp[0], kTierXp[1], kTierXp[2]),
          xp: fmt(lv.ach),
        ),
        if (lv.banked > 0)
          _Source(
            icon: Bi.chart2,
            title: l.levelBanked,
            sub: l.levelBankedSub,
            xp: fmt(lv.banked),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: BloomButton(
            label: l.levelOk,
            tone: ButtonTone.plate,
            overlay: true,
            height: 46,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}

class _Source extends StatelessWidget {
  const _Source({
    required this.icon,
    required this.title,
    required this.sub,
    required this.xp,
  });

  final BloomGlyph icon;
  final String title;
  final String sub;
  final String xp;

  @override
  Widget build(BuildContext context) => SettingsRowShell(
    icon: icon,
    title: title,
    subtitle: sub,
    subtitleLines: 1,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    trailing: Text(
      '$xp XP',
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(color: context.bloom.text2),
    ),
  );
}
