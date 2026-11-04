/// The profile: the banner across the top, under it the avatar with the
/// level's shield and the nick, status, bio and since when; four small
/// numbers; rows into the stats, history and achievements sheets; the
/// activity ring.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/history_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/sticky_hero.dart';
import '../../wrapped/ui/wrapped_sheet.dart';
import '../../wrapped/wrapped_store.dart';
import '../achievements.dart';
import '../profile_store.dart';
import '../stats.dart';
import 'achievements_sheet.dart';
import 'activity_ring.dart';
import 'history_sheet.dart';
import 'level_sheet.dart';
import 'profile_avatar.dart';
import 'profile_banner.dart';
import 'stats_sheet.dart';
import '../../settings/ui/settings_rows.dart';

/// The avatar beside the nick.
const double kProfileAvatarSize = 84;

/// The banner's height under the status bar. The editor's preview and the
/// cropper's frame go by it too.
const double kProfileBannerStrip = 168;

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.flight});

  /// The avatar flies here from the button in home's header.
  final CoverFlight? flight;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Kept here: `extra` lives for the whole location, and once the editor is
  /// opened from here the page rebuilds without it — the avatar would have
  /// nowhere to fly back to.
  late CoverFlight? _flight = widget.flight;

  @override
  void didUpdateWidget(ProfileScreen old) {
    super.didUpdateWidget(old);
    if (widget.flight != null) _flight = widget.flight;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final profile = ref.watch(profileProvider);
    final flying = _flight != null;
    final bio = profile.bio.trim();

    return CustomScrollView(
      slivers: [
        ProfileBannerHero(
          profile: profile,
          flying: flying,
          bar: Row(
            children: [
              GlassIconButton(
                icon: Bi.arrowLeft,
                white: true,
                onTap: () => context.go('/home'),
              ),
              const Spacer(),
              GlassIconButton(
                icon: Bi.pen,
                white: true,
                onTap: () => context.go('$kProfileLocation/edit'),
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileWho(
                  profile: profile,
                  flightTag: _flight?.tag,
                  flying: flying,
                  onNick: () =>
                      _copyNick(context, profile.displayName(context.l)),
                ),
                HeroContent(
                  flying: flying,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          bio,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: bloomText(
                            size: 15,
                            weight: 500,
                            color: t.text2,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const _Since(),
                      const SizedBox(height: 24),
                      const _Numbers(),
                      const SizedBox(height: 18),
                      const _Entries(),
                      const SizedBox(height: 26),
                      const Center(child: ActivityRing()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverBottomBarsInset(),
      ],
    );
  }

  void _copyNick(BuildContext context, String name) {
    Clipboard.setData(ClipboardData(text: name));
    toaster.show(context.l.profileNickCopied, kind: ToastKind.success);
  }
}

/// The banner across the top, the buttons on it staying put while the page
/// scrolls; pulled past the top it stretches. The editor shows the same one.
class ProfileBannerHero extends StatelessWidget {
  const ProfileBannerHero({
    super.key,
    required this.profile,
    required this.bar,
    this.flying = false,
    this.onTap,
  });

  final UserProfile profile;
  final Widget bar;
  final bool flying;

  /// The editor: a tap on the banner changes it.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = Stack(
      fit: StackFit.expand,
      children: [
        ProfileBannerFill(profile: profile),
        // The buttons and the status bar's clock need a shade on a light
        // picture, whatever the picture is.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.45),
                Colors.black.withValues(alpha: 0),
              ],
              stops: const [0, 0.45],
            ),
          ),
        ),
      ],
    );
    return StickyHero(
      height: kProfileBannerStrip + MediaQuery.paddingOf(context).top,
      flying: flying,
      background: onTap == null
          ? fill
          : GestureDetector(onTap: onTap, child: fill),
      barHeight: kHeaderControl,
      bar: bar,
      body: const SizedBox.shrink(),
    );
  }
}

/// Who: the avatar, beside it the level's shield and the nick, under them
/// the status after an opening quote mark. The editor passes its draft.
class ProfileWho extends StatelessWidget {
  const ProfileWho({
    super.key,
    required this.profile,
    this.flightTag,
    this.flying = false,
    this.onAvatar,
    this.onNick,
  });

  final UserProfile profile;
  final Object? flightTag;
  final bool flying;
  final VoidCallback? onAvatar;

  /// A tap on the nick: copies it on the page.
  final VoidCallback? onNick;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final nick = profile.displayName(context.l);
    final said = profile.status.trim();
    final avatar = ProfileAvatar(
      profile: profile,
      size: kProfileAvatarSize,
      flightTag: flightTag,
    );

    return Row(
      children: [
        if (onAvatar == null)
          avatar
        else
          Pressable(onTap: onAvatar, child: avatar),
        const SizedBox(width: 14),
        Expanded(
          child: HeroContent(
            flying: flying,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LevelBadge(size: 28, onTap: () => showLevelSheet(context)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: GestureDetector(
                        onTap: onNick,
                        child: Text(
                          nick,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: bloomText(
                            size: 24,
                            weight: 700,
                            color: t.text,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (said.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // The mark's ink hangs high in its box: brought down onto
                      // the status's lowercase letters.
                      Transform.translate(
                        offset: const Offset(0, 5),
                        child: Text(
                          '“',
                          style: bloomText(
                            size: 26,
                            weight: 700,
                            color: t.muted,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          said,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: bloomText(
                            size: 15,
                            weight: 500,
                            color: t.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "With us since …": when Bloom first ran on this device.
class _Since extends ConsumerWidget {
  const _Since();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final date = DateFormat.yMMMMd(
      Localizations.localeOf(context).toString(),
    ).format(ref.watch(profileSinceProvider));
    return Row(
      children: [
        BloomIcon(Bi.calendar, size: 16, color: t.muted),
        const SizedBox(width: 7),
        Text(
          context.l.profileSince(date),
          style: bloomText(size: 13, weight: 500, color: t.muted),
        ),
      ],
    );
  }
}

/// Four numbers, two by two, no plates.
class _Numbers extends ConsumerWidget {
  const _Numbers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(profileStatsProvider);
    final l = context.l;
    final cells = [
      _Num(Bi.musicNote, '${s.totalPlays}', l.profileSumPlays(s.totalPlays)),
      _Num(Bi.clockCircle, fmtDurLong(context, s.listenSec), l.profileSumTime),
      _Num(Bi.fire, '${s.streak}', l.profileSumStreak(s.streak)),
      _Num(Bi.user, '${s.uniqueArtists}', l.profileSumArtists(s.uniqueArtists)),
    ];
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: cells[row * 2]),
              const SizedBox(width: 10),
              Expanded(child: cells[row * 2 + 1]),
            ],
          ),
        ],
      ],
    );
  }
}

/// A number with its icon, what it counts under it.
class _Num extends StatelessWidget {
  const _Num(this.icon, this.value, this.label);

  final BloomGlyph icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bloomText(
                  size: 22,
                  weight: 700,
                  color: t.text,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const SizedBox(width: 6),
            BloomIcon(icon, size: 17, color: t.iconFgSb),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bloomText(size: 13, weight: 500, color: t.muted),
        ),
      ],
    );
  }
}

/// The ways into the sheets. The year's review (only Dec 21–31) goes first;
/// from the 1st, until it's watched, the month's review stands in for the
/// stats row; through the 7th the stats' value swaps with the review's name
/// now and then (a tap still opens the stats: the review's button is in
/// their foot).
class _Entries extends ConsumerWidget {
  const _Entries();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final s = ref.watch(profileStatsProvider);
    final wrapped = ref.watch(wrappedEntriesProvider);
    final year = wrapped.year;
    final month = wrapped.month;
    final history = ref.watch(historyProvider.select((h) => h.length));
    final ach = ref.watch(achievementsProvider);
    final done = ach.fold(0, (n, a) => n + a.tierReached);

    return Column(
      children: [
        if (year != null)
          _Entry(
            icon: Bi.stars,
            label: l.wrYear,
            fresh: wrapped.yearUnseen,
            onTap: () => showWrappedSheet(context, year),
          ),
        if (month != null && wrapped.monthUnseen)
          _Entry(
            icon: Bi.stars,
            label: l.wrMonth,
            fresh: true,
            onTap: () => showWrappedSheet(context, month),
          )
        else
          _Entry(
            icon: Bi.chart2,
            label: l.profileEntryStats,
            value: fmtDurLong(context, s.listenSec),
            alt: wrapped.monthHint ? l.wrMonth : null,
            onTap: () => showStatsSheet(context),
          ),
        _Entry(
          icon: Bi.history,
          label: l.commonHistory,
          value: '$history',
          onTap: () => showHistorySheet(context),
        ),
        _Entry(
          icon: Bi.medalRibbonsStar,
          label: l.profileAchievements,
          value: '$done ${l.profileEntryOf(ach.length * kTierOrder.length)}',
          onTap: () => showAchievementsSheet(context),
        ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.label,
    this.value = '',
    required this.onTap,
    this.alt,
    this.fresh = false,
  });

  final BloomGlyph icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  /// Takes turns with [value].
  final String? alt;

  /// Not seen yet: a NEW pill before the value.
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final style = bloomText(size: 15, weight: 500, color: t.text2);
    final alt = this.alt;
    return SettingsRowShell(
      leading: BloomIcon(icon, size: 22, color: t.iconFgSb),
      title: label,
      titleStyle: bloomText(size: 16, weight: 500, color: t.text),
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fresh) ...[const _NewPill(), const SizedBox(width: 8)],
          if (alt == null)
            Text(value, style: style)
          else
            _SwapValue(
              first: Text(value, style: style),
              second: Text(alt, style: style),
            ),
          const SizedBox(width: 6),
          BloomIcon(Bi.altArrowRight, size: 16, color: t.muted),
        ],
      ),
    );
  }
}

/// "New" on a way into a review not watched yet.
class _NewPill extends StatelessWidget {
  const _NewPill();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.text,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.l.wrNew.toUpperCase(),
        style: bloomText(
          size: 10,
          weight: 700,
          color: t.bg,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// A slot that every 10 s swaps [first] for [second] and back: the leaving
/// one goes up and out, the coming one up from below. The first showing
/// isn't animated.
class _SwapValue extends StatefulWidget {
  const _SwapValue({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  State<_SwapValue> createState() => _SwapValueState();
}

class _SwapValueState extends State<_SwapValue>
    with SingleTickerProviderStateMixin {
  static const Curve _curve = Cubic(0.22, 0.61, 0.36, 1);
  static const double _height = 20;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    value: 1,
  );
  late final Timer _timer;
  int _phase = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _swap());
  }

  void _swap() {
    setState(() => _phase ^= 1);
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // As wide as the wider of the two, so the row doesn't jump.
    return ClipRect(
      child: SizedBox(
        height: _height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final p = _curve.transform(_c.value);
            Widget layer(int i, Widget child) {
              final incoming = _phase == i;
              return Opacity(
                opacity: incoming ? p : 1 - p,
                child: FractionalTranslation(
                  translation: Offset(0, incoming ? 1 - p : -p),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: child,
                  ),
                ),
              );
            }

            return Stack(
              alignment: AlignmentDirectional.centerEnd,
              children: [layer(0, widget.first), layer(1, widget.second)],
            );
          },
        ),
      ),
    );
  }
}
