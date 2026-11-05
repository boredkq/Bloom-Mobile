/// App shell: the tab bar, the mini player above it, the full player over
/// everything.
///
/// The bars lie over the content (`extendBody`): the margins around the mini
/// player card are clear and the list shows through. So every scroll needs
/// [bottomBarsInset] at its end, or the last rows stay under the bars.
library;

import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/l10n.dart';
import '../features/customization/ui/app_background.dart';
import '../core/store/settings_store.dart';
import '../features/player/ui/mini_player.dart';
import '../features/player/ui/player_sheet.dart';
import '../features/profile/achievements.dart';
import '../features/search/ui/search_layer.dart';
import '../features/settings/about_store.dart';
import '../features/settings/update_notes_store.dart';
import '../features/settings/ui/update_notes_sheet.dart';
import '../features/wrapped/periods.dart';
import '../core/store/play_log.dart';
import '../features/wrapped/ui/wrapped_sheet.dart';
import '../features/wrapped/wrapped_store.dart';
import '../shared/ui/atoms.dart';
import '../shared/ui/bloom_icon.dart';
import '../shared/ui/bloom_toast.dart';
import '../shared/ui/cover_hero.dart';
import '../shared/ui/glass.dart';
import '../shared/ui/pressable.dart';
import 'theme/tokens.dart';

class BloomShell extends ConsumerStatefulWidget {
  const BloomShell({super.key, required this.shell, required this.location});

  final StatefulNavigationShell shell;

  /// Where the router stands. Search leaves when this changes.
  final String location;

  @override
  ConsumerState<BloomShell> createState() => _BloomShellState();
}

class _BloomShellState extends ConsumerState<BloomShell> {
  Timer? _noticeTimer;

  /// The page keeps its size under the search field: with the keyboard it would
  /// lay out anew and lose its place. Held until the keyboard is fully gone, or
  /// the page would shrink as search closes.
  bool _holdBody = false;

  /// A tab press. Search is a layer over the open tab, not a tab of its own: any
  /// other tab closes it first, and the tab it was over just comes back as it
  /// was.
  void _onTab(NavTab tab) {
    if (tab == NavTab.search) return toggleSearch();
    final branch = kBranchTabs.indexOf(tab);
    final current = widget.shell.currentIndex;
    if (searchOpen.value) {
      closeSearch();
      if (branch != current) widget.shell.goBranch(branch);
      return;
    }
    widget.shell.goBranch(branch, initialLocation: branch == current);
  }

  /// System Back goes to what's on top. The router alone starts from the tab's
  /// navigator, so it would close the page under a sheet or under the player:
  /// sheets live in the root navigator, and the player has no route at all.
  Future<bool> _onBack() async {
    final root = Navigator.of(context, rootNavigator: true);
    if (root.canPop()) {
      await root.maybePop();
      return true;
    }
    return collapsePlayerSheet();
  }

  @override
  void didUpdateWidget(BloomShell old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location) dropSearch();
  }

  /// The app can stay open into the 1st: the date is checked on coming back.
  late final AppLifecycleListener _life = AppLifecycleListener(
    onResume: () {
      if (ref.read(wrappedDayProvider.notifier).refresh()) _wrappedNotice();
    },
  );

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _life.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _life;
    // The first run is silent: it also seeds achievements already earned. A
    // provider can't be touched from `initState`, so I wait a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync();
      _wrappedNotice(after: const Duration(seconds: 3));
      _whatsNew();
    });
  }

  /// "What's new", once after an update. Here, since the version is compared
  /// with the last run at launch, and settings may never be opened.
  Future<void> _whatsNew() async {
    await ref.read(aboutProvider.notifier).loadVersion();
    if (!mounted) return;
    final version = ref.read(aboutProvider).version;
    if (version.isEmpty) return;
    final locale = Localizations.localeOf(context).languageCode;
    final note = await ref.read(updateNotesProvider).whatsNew(version, locale);
    if (!mounted || note == null) return;
    await showUpdateNote(context, note);
  }

  /// A review is out: a toast with a way into it, once per period. I mark it
  /// before the toast, so a restart stays quiet.
  void _wrappedNotice({Duration after = Duration.zero}) {
    final entries = ref.read(wrappedEntriesProvider);
    final marks = ref.read(wrappedMarksProvider.notifier);
    final now = ref.read(playLogClockProvider)();
    final due = [
      for (final kind in scheduledPeriods(
        now,
        force: ref.read(wrappedForceProvider),
      ))
        if (entries.of(kind) case final data?
            when !marks.isNotified(data.range))
          kind,
    ];
    if (due.isEmpty) return;
    for (final kind in due) {
      marks.markNotified(entries.of(kind)!.range);
    }
    _noticeTimer = Timer(after, () {
      if (!mounted) return;
      final l = context.l;
      for (final kind in due) {
        toaster.show(
          periodTitle(l, kind),
          action: ToastAction(
            label: l.wrWatch,
            // Read again on the tap: the day may have turned.
            fn: () {
              if (!mounted) return;
              final fresh = ref.read(wrappedEntriesProvider).of(kind);
              if (fresh != null) showWrappedSheet(context, fresh);
            },
          ),
        );
      }
    });
  }

  /// Achievements are caught here, not on the profile page, or they'd only be
  /// earned once the user went there.
  void _sync() {
    final fresh = ref
        .read(unlockedAchievementsProvider.notifier)
        .sync(ref.read(achievementsProvider));
    // Toasts queue up, so they don't overlap.
    for (final item in fresh) {
      toaster.show(
        context.l.achUnlockedToast(
          item.ach.def.name(context.l),
          tierLabel(context.l, item.tier),
        ),
        kind: ToastKind.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    ref.listen(achievementsProvider, (_, _) => _sync());
    final shell = widget.shell;
    final branchTab = kBranchTabs[shell.currentIndex];
    final scaffold = ListenableBuilder(
      listenable: Listenable.merge([searchOpen, searchOnTop]),
      builder: (context, _) {
        if (searchOnTop.value) {
          _holdBody = true;
        } else if (MediaQuery.viewInsetsOf(context).bottom == 0) {
          _holdBody = false;
        }
        return Scaffold(
          // The background picture lies under the shell, which then has no
          // fill.
          backgroundColor: ref.watch(backgroundOnProvider)
              ? Colors.transparent
              : t.bg,
          extendBody: true,
          resizeToAvoidBottomInset: !_holdBody,
          body: shell,
          // The bars have their own glass group: they lie over the list, and
          // with a shared snapshot the rows passing under them wouldn't blur.
          bottomNavigationBar: GlassGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Room for the mini player card; the player panel draws the
                // card itself, growing out of it over the bars.
                const MiniCardSlot(),
                _NavBar(
                  style: ref.watch(settingsProvider).navStyle,
                  tabs: ref.watch(settingsProvider).navOrder,
                  indicator: ref.watch(settingsProvider).navIndicator,
                  labels: ref.watch(settingsProvider).navLabels,
                  active: searchOpen.value ? NavTab.search : branchTab,
                  onTap: _onTab,
                ),
              ],
            ),
          ),
        );
      },
    );

    return BackButtonListener(
      onBackButtonPressed: _onBack,
      // The panel lies OVER the shell with the bars: it is the mini player card
      // grown up, and has to cover the tab bar itself.
      child: Stack(
        fit: StackFit.expand,
        children: [
          scaffold,
          PlayerSheet(onHome: branchTab == NavTab.home),
        ],
      ),
    );
  }
}

/// Height of the tab bar panel with its bottom inset: what the screen's bottom
/// takes under the mini player card. The player panel computes its rest
/// position from this, so it must match the bar's own layout ([_NavBar.build]).
double navBarInset(BuildContext context, NavBarStyle style) => switch (style) {
  NavBarStyle.floating ||
  NavBarStyle.pill => kNavBarFloatHeight + bottomEdgeInset(context),
  _ => kNavBarHeight + bottomSafeInset(context),
};

// ─── Switching tabs ──────────────────────────────────────────────────────

/// Tab change. Half the page transition: this answers a tap, and the fade
/// should end before the finger reaches the next tab.
const Duration kTabTransition = Duration(milliseconds: 220);

/// Holds the shell's branches; tabs replace each other with a fade.
/// `StatefulShellRoute.indexedStack` switches in one frame. This works the same
/// way (all branches stay in the tree, `Offstage` and `TickerMode` on inactive
/// ones, state survives), but two show during the transition.
///
/// Curves are shared with pages ([kPageFadeIn], [kPageFadeOut]), the length is
/// its own, [kTabTransition]. No slide on purpose: tabs share no axis, and it
/// would fight a cover flight (see `detailPageTransition`).
class BranchCrossfade extends StatefulWidget {
  const BranchCrossfade({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<BranchCrossfade> createState() => _BranchCrossfadeState();
}

class _BranchCrossfadeState extends State<BranchCrossfade>
    with SingleTickerProviderStateMixin {
  // Starts finished: on the app's first frame the tab is already in place.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: kTabTransition,
    value: 1,
  );

  /// The branch being left, still drawn until [_fade] ends.
  int _leaving = 0;

  @override
  void didUpdateWidget(BranchCrossfade old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      _leaving = old.index;
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Laid out like `IndexedStack`: loose constraints, aligned to the start.
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [for (var i = 0; i < widget.children.length; i++) _branch(i)],
      ),
    );
  }

  Widget _branch(int i) {
    final active = i == widget.index;
    final opacity = active
        ? kPageFadeIn.transform(_fade.value)
        : i == _leaving
        ? kPageFadeOut.transform(_fade.value)
        : 0.0;

    return Offstage(
      // The leaving branch fades over the first quarter; after that there's no
      // reason to lay it out or paint it.
      offstage: opacity == 0,
      child: TickerMode(
        enabled: active,
        child: IgnorePointer(
          ignoring: !active,
          // `Opacity` at 1 makes no layer, so at rest this is an ordinary
          // branch.
          child: Opacity(opacity: opacity, child: widget.children[i]),
        ),
      ),
    );
  }
}

/// A tab: its icon at rest and its bold one while open.
class _NavSpec {
  const _NavSpec({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.motion = _NavMotion.wiggle,
  });

  /// The label resolves at paint time: the tab table is static and outlives a
  /// language change.
  final String Function(AppLocalizations l) label;
  final BloomGlyph icon;
  final BloomGlyph activeIcon;

  /// How the icon answers its tab being picked; see [_NavMotion].
  final _NavMotion motion;
}

/// Height of the icon row in edge-hugging styles.
const double kNavBarHeight = 58;

/// Height of floating styles. Taller on purpose: the panel stops short of the
/// edges, and at 58 it reads smaller against the empty margins than a
/// full-width bar.
const double kNavBarFloatHeight = 68;

/// Glyph size in the bar. Larger in floating styles, following the panel
/// height, or the extra goes to empty space above the icons and the bar looks
/// loose.
const double _kNavIcon = 24;
const double _kNavFloatIcon = 27;

/// The same glyphs with a label under them. The panel height doesn't change
/// with labels, so the icon itself makes room: the bar keeps its line and lists
/// below don't shift.
///
/// With [NavLabels.active] only the active tab shrinks. Small glyphs with no
/// label under them read as a glitch.
const double _kNavIconText = 19;
const double _kNavFloatIconText = 21;

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.style,
    required this.tabs,
    required this.indicator,
    required this.labels,
    required this.active,
    required this.onTap,
  });

  final NavBarStyle style;

  /// The tabs in display order, see [NavTab].
  final List<NavTab> tabs;

  /// What marks the active tab; see [_NavMark].
  final NavIndicator indicator;

  /// Labels under the icons; see [NavLabels].
  final NavLabels labels;

  /// The lit tab, not a slot in the bar: the order is a setting.
  final NavTab active;

  final ValueChanged<NavTab> onTap;

  /// An inactive tab is outline, the active one bold.
  static final _items = <NavTab, _NavSpec>{
    NavTab.home: _NavSpec(
      label: (l) => l.navHome,
      icon: Bi.homeAngle2,
      activeIcon: Bi.homeAngle2Bold,
    ),
    NavTab.search: _NavSpec(
      label: (l) => l.navSearch,
      icon: Bi.magnifier,
      activeIcon: Bi.magnifierBold,
    ),
    NavTab.library: _NavSpec(
      label: (l) => l.navLibrary,
      icon: Bi.library,
      activeIcon: Bi.libraryBold,
    ),
    NavTab.settings: _NavSpec(
      label: (l) => l.navSettings,
      icon: Bi.settings,
      activeIcon: Bi.settingsBold,
      motion: _NavMotion.spin,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final floating = style == NavBarStyle.floating || style == NavBarStyle.pill;
    final height = floating ? kNavBarFloatHeight : kNavBarHeight;
    final slot = tabs.indexOf(active);

    // Edge-hugging styles differ only in the top corner radius. Dome's is twice
    // the theme's and at least 28, or on a small radius it would repeat
    // Rounded.
    final topRadius = switch (style) {
      NavBarStyle.rounded => math.max(t.radius, 10.0),
      NavBarStyle.dome => math.max(t.radius * 2, 28.0),
      _ => 0.0,
    };
    final radius = switch (style) {
      NavBarStyle.bar || NavBarStyle.rounded || NavBarStyle.dome =>
        BorderRadius.vertical(top: Radius.circular(topRadius)),
      // A capsule is round by definition: its corners are always half the
      // height, not the theme radius.
      NavBarStyle.pill => BorderRadius.circular(height / 2),
      NavBarStyle.floating => BorderRadius.circular(t.radius),
    };
    // Panel rounding as one number, repeated by the active tab's plate. A flat
    // bar has no corners, so the plate takes the theme radius like other
    // plates.
    final corner = switch (style) {
      NavBarStyle.bar => t.radius,
      NavBarStyle.rounded || NavBarStyle.dome => topRadius,
      NavBarStyle.pill => height / 2,
      NavBarStyle.floating => t.radius,
    };

    // One row for all styles: tabs split the width evenly. A capsule differs
    // from the floating panel only by radius, with icons in the same places.
    final row = Row(
      children: [
        for (var i = 0; i < tabs.length; i++)
          Expanded(
            child: _NavItem(
              spec: _items[tabs[i]]!,
              active: i == slot,
              iconSize: floating ? _kNavFloatIcon : _kNavIcon,
              textIconSize: floating ? _kNavFloatIconText : _kNavIconText,
              labels: labels,
              onTap: () => onTap(tabs[i]),
            ),
          ),
      ],
    );

    // The row with the active tab's mark. The mark lies UNDER the icons and
    // travels between tabs itself, so a switch reads as the selection moving,
    // not two flashes. Off, it's a bare row.
    final content = SizedBox(
      height: height,
      child: indicator == NavIndicator.none
          ? row
          : Stack(
              fit: StackFit.expand,
              children: [
                _NavMark(
                  kind: indicator,
                  slot: slot,
                  count: tabs.length,
                  corner: corner,
                ),
                row,
              ],
            ),
    );

    switch (style) {
      // Edge-hugging: the fill goes under the system inset, and the bottom
      // padding lifts the icon row out of it ([bottomSafeInset]).
      case NavBarStyle.bar:
      case NavBarStyle.rounded:
      case NavBarStyle.dome:
        final rounded = topRadius > 0;
        // One fill for all styles, `pill`: bars have to read as UI elements,
        // not a continuation of the background. In glass it's translucent and
        // the list shows through.
        return GlassBox(
          // At least 10 for Rounded: at a theme radius of zero it would look
          // like the plain bar.
          borderRadius: radius,
          // A rounded shape needs an equal border on all sides, and the bottom
          // one goes off screen anyway; the straight bar has a line only on
          // top, so it needs its own shape.
          borderSide: rounded ? BorderSide(color: t.ovlLine) : null,
          shape: rounded ? null : Border(top: BorderSide(color: t.ovlLine)),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomSafeInset(context)),
            child: content,
          ),
        );

      // Floating: the panel stops short of the bottom, and the system inset
      // goes to the gap under it ([bottomEdgeInset]), or it would sit on the
      // gesture bar.
      case NavBarStyle.floating:
      case NavBarStyle.pill:
        return Padding(
          padding: EdgeInsets.fromLTRB(
            kFloatGap,
            0,
            kFloatGap,
            bottomEdgeInset(context),
          ),
          child: GlassBox(
            borderSide: BorderSide(color: t.ovlLine),
            borderRadius: radius,
            child: content,
          ),
        );
    }
  }
}

// ─── Active tab mark ─────────────────────────────────────────────────────

/// Plate margin inside a tab's share, one for all sides: the plate takes nearly
/// the whole share, with an even gap to neighbours and panel edges. No width
/// cap, the share is its measure.
const double _kPillPad = 5;

/// Gap from the row's bottom edge to the dot and line. The row's edge rather
/// than the panel's, so the mark stays the same distance from the icons in
/// every style.
const double _kMarkGap = 5;

/// Dot under the icon.
const double _kDotSize = 5;

/// Line under the icon. Short and centred: in Capsule and Dome the panel's
/// rounding would cut the outer ones.
const Size _kLineSize = Size(22, 3);

/// Active tab mark: a plate, dot or line per [NavIndicator]. A separate layer
/// under the icon row rather than a tab's background, so it travels in one
/// motion, in step with the tab change ([kTabTransition]).
class _NavMark extends StatelessWidget {
  const _NavMark({
    required this.kind,
    required this.slot,
    required this.count,
    required this.corner,
  });

  /// Mark kind; [NavIndicator.none] never gets here, it has no layer.
  final NavIndicator kind;

  /// Active tab's place in the row; −1 when the bar has no active tab.
  final int slot;
  final int count;

  /// The bar panel's rounding, repeated by the plate: a capsule's is a capsule,
  /// a dome's a dome, and a flat bar keeps a calm rectangle.
  final double corner;

  @override
  Widget build(BuildContext context) {
    if (slot < 0) return const SizedBox.shrink();
    final t = context.bloom;

    return LayoutBuilder(
      builder: (context, box) {
        final cell = box.maxWidth / count;
        if (cell <= 0 || box.maxHeight <= 0) return const SizedBox.shrink();

        return Stack(
          children: [
            // The whole tab share travels, with the mark placed inside it. One
            // motion for all three kinds.
            AnimatedPositioned(
              duration: kTabTransition,
              curve: Curves.easeOutCubic,
              left: cell * slot,
              top: 0,
              width: cell,
              height: box.maxHeight,
              child: switch (kind) {
                NavIndicator.pill => Padding(
                  padding: const EdgeInsets.all(_kPillPad),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // The `iconBg` film, as under the header's round buttons:
                      // the plate has to read as part of the bar, not a second
                      // bar inside it.
                      color: t.iconBg,
                      // Capped at half the height: past that the rounding hits
                      // a capsule anyway, and Dome's panel radius is much
                      // larger than the plate.
                      borderRadius: BorderRadius.circular(
                        math.min(
                          corner,
                          math.max(box.maxHeight - _kPillPad * 2, 0) / 2,
                        ),
                      ),
                    ),
                  ),
                ),
                // Dot and line use the accent, not a film: a big plate can do
                // with a faint fill, a five-pixel mark can't.
                NavIndicator.dot => _Mark(
                  size: const Size(_kDotSize, _kDotSize),
                  radius: _kDotSize / 2,
                  color: t.accent,
                ),
                NavIndicator.line => _Mark(
                  size: _kLineSize,
                  radius: _kLineSize.height / 2,
                  color: t.accent,
                ),
                NavIndicator.none => const SizedBox.shrink(),
              },
            ),
          ],
        );
      },
    );
  }
}

/// Dot or line at the bottom edge of a tab's share.
class _Mark extends StatelessWidget {
  const _Mark({required this.size, required this.radius, required this.color});

  final Size size;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: const EdgeInsets.only(bottom: _kMarkGap),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    ),
  );
}

// ─── Bar icon motion ─────────────────────────────────────────────────────

/// Outline to bold and colour blend. In step with the tab change
/// ([kTabTransition]), or the glyph finishes filling over the new page.
const Duration kNavMorph = kTabTransition;

/// How the icon answers its tab being picked. Per glyph: one motion on every
/// icon looks like the bar twitching, not one icon responding.
enum _NavMotion {
  /// A damped wiggle. The house and library box stand on the ground, so they
  /// suit a nudge.
  wiggle,

  /// A turn around the centre, for the settings gear: it's round and symmetric,
  /// so a wiggle would read as a skew.
  spin,
}

/// Lasts longer than the blend: it answers the finger and can finish after the
/// tab has settled.
const Duration kNavWiggle = Duration(milliseconds: 380);
const Duration kNavSpin = Duration(milliseconds: 520);

/// Amplitude of the wiggle's first swing.
const double kWiggleMax = 9 * math.pi / 180;

/// Damped wiggle: three half-swings. The sine gives the swings and `(1 − t)`
/// damps them to exactly zero at the end, so the icon settles with no jump.
double _wiggleAngle(double t) =>
    kWiggleMax * math.sin(t * math.pi * 3) * (1 - t);

/// A turn that runs out: fast start, slowing to the end, like a gear flicked by
/// a finger. A full circle: its teeth are dense, and after half a turn the eye
/// can't tell it came back.
double _spinAngle(double t) => 2 * math.pi * Curves.easeOutCubic.transform(t);

/// Label under the icon, the smallest text there is: a word like Settings would
/// ellipsize at the usual small size.
const double _kNavLabelSize = 10.5;

/// Gap between glyph and label.
const double _kNavLabelGap = 3;

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.spec,
    required this.active,
    required this.iconSize,
    required this.textIconSize,
    required this.labels,
    required this.onTap,
  });

  final _NavSpec spec;
  final bool active;

  /// Glyph with no label under it.
  final double iconSize;

  /// Glyph with a label under it, smaller; see [_kNavIconText].
  final double textIconSize;

  /// Labels under the icons; see [NavLabels].
  final NavLabels labels;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with TickerProviderStateMixin {
  /// 0 is rest, 1 the active tab. Starts finished: on the first frame there's
  /// nothing to blend from.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: kNavMorph,
    value: widget.active ? 1 : 0,
  );

  /// The icon's gesture: wiggle or turn, per [_NavSpec.motion].
  late final AnimationController _react = AnimationController(
    vsync: this,
    duration: widget.spec.motion == _NavMotion.spin ? kNavSpin : kNavWiggle,
  );

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _morph.forward();
      _react.forward(from: 0);
    } else {
      _morph.reverse();
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _react.dispose();
    super.dispose();
  }

  void _tap() {
    // A second tap on the current tab doesn't change `active`, so
    // `didUpdateWidget` plays nothing, but it does reset the branch to its
    // root. I answer with the same gesture, or the tap looks lost.
    if (widget.active) _react.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.spec.label(context.l),
      // No plate or ripple: the active tab shows by the bold glyph and accent,
      // and a ripple on a bare background reads as a stray circle.
      child: Pressable(
        onTap: _tap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_morph, _react]),
          builder: (context, _) {
            // At rest the controller is at 1, and both forms give the same
            // picture as at 0: the wiggle is damped to zero and the turn is a
            // full circle. No separate rest state needed.
            final angle = widget.spec.motion == _NavMotion.spin
                ? _spinAngle(_react.value)
                : _wiggleAngle(_react.value);
            // Only the glyph turns and wiggles, not the column with the label:
            // tilted text reads as a layout glitch.
            final glyph = Transform.rotate(
              angle: angle,
              child: _icons(t, _iconSize()),
            );
            if (widget.labels == NavLabels.none) return Center(child: glyph);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [glyph, _label(t)],
            );
          },
        ),
      ),
    );
  }

  /// Glyph size. With [NavLabels.active] it moves between normal and shrunk
  /// along with the blend ([kNavMorph]): the tab gaining a label makes room
  /// itself, the one left returns. One controller drives both, so they can't
  /// drift apart.
  double _iconSize() => switch (widget.labels) {
    NavLabels.none => widget.iconSize,
    NavLabels.always => widget.textIconSize,
    NavLabels.active =>
      widget.iconSize +
          (widget.textIconSize - widget.iconSize) * _morph.value.clamp(0, 1),
  };

  /// Label under the glyph. With [NavLabels.active] labels under inactive tabs
  /// take NO room: an empty gap under a small glyph reads as an icon hanging in
  /// the air. The label opens with the glyph from zero height.
  Widget _label(BloomTokens t) {
    final m = _morph.value.clamp(0.0, 1.0);
    final open = widget.labels == NavLabels.always ? 1.0 : m;
    if (open == 0) return const SizedBox.shrink();

    return ClipRect(
      child: Align(
        // Top-aligned to the glyph: the label comes down from under the icon,
        // rather than clipped on both sides.
        alignment: Alignment.topCenter,
        heightFactor: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, _kNavLabelGap, 2, 0),
          child: Opacity(
            // The text follows the opening: halfway it has its room but is
            // still pale, or it enters the row fully formed and hits the eye.
            opacity: open,
            child: Text(
              widget.spec.label(context.l),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _kNavLabelSize,
                height: 1.15,
                fontWeight: FontWeight.w500,
                // The glyph's colour blend: label and icon are one thing.
                color: Color.lerp(t.text, t.accent, m),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Two layers: bold fades in over outline. The curves overlap: outline holds
  /// full opacity for the first third and leaves once the fill has weight, or
  /// the combined alpha dips and the icon dims for a frame.
  Widget _icons(BloomTokens t, double size) {
    final m = _morph.value;
    // Full contrast at rest (`text`), not muted `iconFgSb`: dim glyphs read as
    // disabled. The active tab shows by its fill and accent anyway.
    final color = Color.lerp(t.text, t.accent, m)!;
    final fill = Curves.easeOut.transform(m);
    final line = 1 - const Interval(0.35, 1).transform(m);
    final spec = widget.spec;

    return Stack(
      alignment: Alignment.center,
      children: [
        if (line > 0) _layer(spec.icon, color, line, size),
        if (fill > 0) _layer(spec.activeIcon, color, fill, size),
      ],
    );
  }

  Widget _layer(BloomGlyph glyph, Color color, double opacity, double size) =>
      Opacity(
        opacity: opacity.clamp(0, 1),
        child: BloomIcon(glyph, size: size, color: color),
      );
}
