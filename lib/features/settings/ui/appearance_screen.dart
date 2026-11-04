/// Appearance: theme, accent, transparency, font, the tab bar and the
/// background.
///
/// A theme is its three colours; the accent lives apart and survives changing
/// it. The preview uses the theme's own formulas, so the dots can't differ from
/// the result.
library;

import 'dart:math' show Random, min;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/fonts.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/settings_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/color_picker.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../customization/custom_store.dart';
import '../../customization/media_store.dart' show kBgBlurMax, kBgDimMax;
import '../transparency_store.dart';
import '../user_fonts.dart';
import 'settings_rows.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return SubPage(
      title: context.l.setAppearance,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(context.l.apTheme),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsRowShell(
              title: context.l.apThemeRow,
              subtitle: settings.autoTheme
                  ? context.l.thAutoName
                  : settings.preset.name,
              trailing: _ThemeDots(preset: settings.preset),
              onTap: () => _pickTheme(context, ref),
            ),
            // The auto theme colours the accent itself, so there's nothing to
            // choose.
            if (!settings.autoTheme)
              SettingsToggleRow(
                title: context.l.apAutoAccent,
                subtitle: context.l.apAutoAccentSub,
                value: settings.autoAccent,
                onChanged: controller.setAutoAccent,
              ),
            // Needed while the auto accent or the auto theme is on: one
            // formula.
            if (settings.autoAccent || settings.autoTheme)
              SettingsValueRow(
                glyph: BloomIcon(Bi.sun2),
                title: context.l.apAutoAccentLevel,
                value: '${(settings.autoAccentL * 100).round()} %',
                onTap: () => _pickIntValue(
                  context: context,
                  title: context.l.apAutoAccentLevel,
                  value: (settings.autoAccentL * 100).round(),
                  minValue: (kAutoAccentLMin * 100).round(),
                  max: (kAutoAccentLMax * 100).round(),
                  unit: ' %',
                  // Live, or the level is turned blind: the sheet itself wears
                  // the accent.
                  onChanged: (v) => controller.setAutoAccentL(v / 100),
                ),
              ),
            // About the accent, so it stands right after it.
            SettingsToggleRow(
              title: context.l.apBadgesTitle,
              subtitle: context.l.apBadgesSubtitle,
              value: settings.accentBadges,
              onChanged: controller.setAccentBadges,
            ),
          ],
        ),
        const SizedBox(height: 26),
        ..._transparencyGroup(context, ref),
        const SizedBox(height: 26),
        SettingsCaption(context.l.apFontCat),
        const SizedBox(height: 10),
        const SettingsGroupCard(rows: [_FontCard()]),
        const SizedBox(height: 26),
        SettingsCaption(context.l.apNavBar),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsRowShell(
              title: context.l.apNavBarRow,
              subtitle: _navStyleLabel(context.l, settings.navStyle),
              trailing: SizedBox(
                width: 46,
                height: 46 * 64 / 100,
                child: CustomPaint(
                  painter: _NavStyleGlyph(
                    style: settings.navStyle,
                    indicator: settings.navIndicator,
                    labels: settings.navLabels,
                    screen: t.bg,
                    frame: t.ovlLine2,
                    ink: t.accent,
                  ),
                ),
              ),
              onTap: () => _pickNavStyle(context, ref),
            ),
            SettingsLinkRow(
              title: context.l.apNavTabsRow,
              subtitle: [
                for (final tab in settings.navOrder)
                  _navTabLabel(context.l, tab),
              ].join(' · '),
              onTap: () => _pickNavOrder(context, ref),
            ),
            SettingsLinkRow(
              title: context.l.apNavMarkRow,
              subtitle: _navIndicatorLabel(context.l, settings.navIndicator),
              onTap: () => _pickNavIndicator(context, ref),
            ),
            // A switch: it's either the icon or the mark. Last, since it's
            // about one tab and not the bar.
            SettingsToggleRow(
              title: context.l.apNavHomeLogoRow,
              subtitle: context.l.apNavHomeLogoSub,
              value: settings.navHomeLogo,
              onChanged: controller.setNavHomeLogo,
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(context.l.apNavLabelsRow),
        const SizedBox(height: 10),
        // The whole bar with its chosen look: it gets compared to one's own.
        PickRow<NavLabels>(
          values: NavLabels.values,
          active: (value) => value == settings.navLabels,
          label: (value) => _navLabelsLabel(context.l, value),
          picture: (value, ink) => AspectRatio(
            aspectRatio: 100 / 64,
            child: CustomPaint(
              painter: _NavStyleGlyph(
                style: settings.navStyle,
                indicator: settings.navIndicator,
                labels: value,
                screen: t.bg,
                frame: t.ovlLine2,
                ink: ink,
              ),
            ),
          ),
          height: null,
          onTap: controller.setNavLabels,
        ),
        const SizedBox(height: 26),
        SettingsCaption(context.l.apBgGroup),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            // A picture set as the background overrides this.
            SettingsToggleRow(
              title: context.l.apCoverAsBg,
              subtitle: context.l.apCoverAsBgSub,
              value: settings.coverAsBg,
              onChanged: controller.setCoverAsBg,
            ),
            // Hidden while off: nothing to turn.
            if (settings.coverAsBg) ..._coverAsBgRows(context, ref),
          ],
        ),
      ],
    );
  }
}

/// The cover background's blur in pixels and dim in percent, with the same
/// limits as a library picture.
List<Widget> _coverAsBgRows(BuildContext context, WidgetRef ref) {
  final fx = ref.watch(coverAsBgFxProvider);
  final controller = ref.read(coverAsBgFxProvider.notifier);
  final l = context.l;

  return [
    SettingsValueRow(
      glyph: BloomIcon(Bi.waterdrop),
      title: l.custBlur,
      value: '${fx.blur}px',
      onTap: () => _pickIntValue(
        context: context,
        title: l.custBlur,
        value: fx.blur,
        max: kBgBlurMax.round(),
        unit: 'px',
        onChanged: controller.setBlur,
      ),
    ),
    SettingsValueRow(
      glyph: BloomIcon(Bi.moon),
      title: l.custDim,
      value: '${fx.dim}%',
      onTap: () => _pickIntValue(
        context: context,
        title: l.custDim,
        value: fx.dim,
        max: kBgDimMax.round(),
        unit: '%',
        onChanged: controller.setDim,
      ),
    ),
  ];
}

/// The transparency group. A row shows the value and opens a sheet with one
/// slider; all but the switch hides while off.
List<Widget> _transparencyGroup(BuildContext context, WidgetRef ref) {
  final tr = ref.watch(transparencyProvider);
  final controller = ref.read(transparencyProvider.notifier);
  final l = context.l;

  return [
    SettingsCaption(l.apTrGroup),
    const SizedBox(height: 10),
    SettingsGroupCard(
      rows: [
        SettingsToggleRow(
          title: l.apTrTitle,
          subtitle: tr.on ? l.apTrOn(tr.transparencyPercent) : l.apTrOff,
          value: tr.on,
          onChanged: controller.setOn,
        ),
        if (tr.on) ...[
          SettingsValueRow(
            glyph: BloomIcon(Bi.eye),
            title: l.apTrLevel,
            value: '${tr.transparencyPercent}%',
            onTap: () => _pickIntValue(
              context: context,
              title: l.apTrLevel,
              value: tr.transparencyPercent,
              max: 100,
              unit: '%',
              onChanged: controller.setTransparencyPercent,
            ),
          ),
          SettingsValueRow(
            glyph: BloomIcon(Bi.sun2),
            title: l.apTrBrightness,
            value: '${tr.glassStr}%',
            onTap: () => _pickIntValue(
              context: context,
              title: l.apTrBrightness,
              value: tr.glassStr,
              max: 100,
              unit: '%',
              onChanged: controller.setGlassStr,
            ),
          ),
          SettingsValueRow(
            glyph: BloomIcon(Bi.waterdrop),
            title: l.apTrBlur,
            value: '${tr.glassBlur}px',
            onTap: () => _pickIntValue(
              context: context,
              title: l.apTrBlur,
              value: tr.glassBlur,
              max: kTrBlurMax,
              unit: 'px',
              onChanged: controller.setGlassBlur,
            ),
          ),
          SettingsToggleRow(
            title: l.apTrOverlays,
            subtitle: l.apTrOverlaysSub,
            value: tr.overlayGlass,
            onChanged: controller.setOverlayGlass,
          ),
        ],
      ],
    ),
  ];
}

/// One slider: a big value and a wide bar. Applied as it moves, or the glass
/// has nothing to compare with.
///
/// No title: the row it came from said it; [Semantics] still gets the name.
///
/// [minValue] is the left end: the accent level has its own range.
Future<void> _pickIntValue({
  required BuildContext context,
  required String title,
  required int value,
  required int max,
  required String unit,
  required ValueChanged<int> onChanged,
  int minValue = 0,
}) async {
  var current = value;
  await showBloomSheetChild<void>(
    context: context,
    child: StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$current$unit',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 30),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: SliderComponentShape.noThumb,
                // Reaches the sheet's margins: with no thumb there's nothing to
                // reserve room for.
                trackShape: const RoundedRectSliderTrackShape(),
                padding: EdgeInsets.zero,
              ),
              child: Semantics(
                label: title,
                child: Slider(
                  value: current.toDouble(),
                  min: minValue.toDouble(),
                  max: max.toDouble(),
                  divisions: max - minValue,
                  onChanged: (v) {
                    setState(() => current = v.round());
                    onChanged(current);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Tab bar look ───────────────────────────────────────────────────────────

String _navStyleLabel(AppLocalizations l, NavBarStyle style) => switch (style) {
  NavBarStyle.bar => l.apNavBarPlain,
  NavBarStyle.rounded => l.apNavBarRounded,
  NavBarStyle.dome => l.apNavBarDome,
  NavBarStyle.floating => l.apNavBarFloating,
  NavBarStyle.pill => l.apNavBarPill,
};

/// Tiles in two columns; the last of an odd row stands alone. In a sheet: a
/// second open block would double the page. Choosing closes it: the sheet
/// covers the bar anyway.
Future<void> _pickNavStyle(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final picked = await _pickNavCard<NavBarStyle>(
    context: context,
    values: NavBarStyle.values,
    current: settings.navStyle,
    label: (style) => _navStyleLabel(context.l, style),
    // The whole bar with its chosen mark and labels: it gets compared to one's
    // own.
    paint: (style, ink) => _NavStyleGlyph(
      style: style,
      indicator: settings.navIndicator,
      labels: settings.navLabels,
      screen: context.bloom.bg,
      frame: context.bloom.ovlLine2,
      ink: ink,
    ),
  );
  if (picked != null) ref.read(settingsProvider.notifier).setNavStyle(picked);
}

Future<void> _pickNavIndicator(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final picked = await _pickNavCard<NavIndicator>(
    context: context,
    values: NavIndicator.values,
    current: settings.navIndicator,
    label: (value) => _navIndicatorLabel(context.l, value),
    paint: (value, ink) => _NavStyleGlyph(
      style: settings.navStyle,
      indicator: value,
      labels: settings.navLabels,
      screen: context.bloom.bg,
      frame: context.bloom.ovlLine2,
      ink: ink,
    ),
  );
  if (picked != null) {
    ref.read(settingsProvider.notifier).setNavIndicator(picked);
  }
}

/// A card of a two-column grid in a sheet, from the sheet's own context: the
/// page's width is wider. Margins on both sides plus the gap between columns.
double _sheetCardWidth(BuildContext sheetContext) =>
    (MediaQuery.sizeOf(sheetContext).width - kSheetEdge * 2 - 12) / 2;

/// The bar settings' sheet: screen mock-ups in two columns. No title: the row
/// it came from said it.
Future<T?> _pickNavCard<T>({
  required BuildContext context,
  required List<T> values,
  required T current,
  required String Function(T value) label,
  required CustomPainter Function(T value, Color ink) paint,
}) {
  return showBloomSheetChild<T>(
    context: context,
    // With the sheet's own context: it lives in the root navigator, the page's
    // would close Settings.
    child: Builder(
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(kSheetEdge, 6, kSheetEdge, 6),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final value in values)
              PickCard(
                width: _sheetCardWidth(sheetContext),
                active: value == current,
                label: label(value),
                picture: (ink) => AspectRatio(
                  aspectRatio: 100 / 64,
                  child: CustomPaint(painter: paint(value, ink)),
                ),
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    ),
  );
}

// ─── Tab order ──────────────────────────────────────────────────────────────

String _navTabLabel(AppLocalizations l, NavTab tab) => switch (tab) {
  NavTab.home => l.navHome,
  NavTab.search => l.navSearch,
  NavTab.library => l.navLibrary,
  NavTab.settings => l.navSettings,
};

/// The tab order sheet: a row per tab in bar order, moved by the handle on the
/// right. It applies at once, no "Done".
Future<void> _pickNavOrder(BuildContext context, WidgetRef ref) =>
    showBloomSheetChild<void>(
      context: context,
      // No title: the row it came from said it.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kSheetEdge, 6, kSheetEdge, 6),
        child: Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(settingsProvider);
            final controller = ref.read(settingsProvider.notifier);
            final t = context.bloom;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // One card row: the rows draw their dividers, or a line would
                // stay behind while dragging.
                SettingsGroupCard(
                  rows: [
                    ReorderableListView.builder(
                      // Inside a scrolling sheet: no scroll of its own, height
                      // by its content.
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      // The handle is my own, on the right.
                      buildDefaultDragHandles: false,
                      itemCount: settings.navOrder.length,
                      onReorder: controller.moveNavTab,
                      // The dragged row needs a plate, or the rows under it
                      // show through.
                      proxyDecorator: (child, _, _) => Material(
                        color: t.pill,
                        borderRadius: BorderRadius.circular(t.radius),
                        child: child,
                      ),
                      itemBuilder: (context, i) {
                        final tab = settings.navOrder[i];
                        return _NavTabRow(
                          key: ValueKey(tab),
                          index: i,
                          tab: tab,
                          // All but the first: the card draws no lines here.
                          divider: i > 0,
                        );
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: Text(
                    context.l.apNavTabsDrag,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: t.text2),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

/// A tab row in the order sheet: its name and the drag handle.
class _NavTabRow extends StatelessWidget {
  const _NavTabRow({
    super.key,
    required this.index,
    required this.tab,
    required this.divider,
  });

  /// The row's place, which `ReorderableListView` reads to know what's dragged.
  final int index;
  final NavTab tab;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (divider) const GroupDivider(indent: 16),
        SettingsRowShell(
          title: _navTabLabel(context.l, tab),
          trailing: ReorderableDragStartListener(
            index: index,
            // Padding so a finger has something to grab.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: BloomIcon(Bi.hamburgerMenu, size: 20, color: t.iconFgSb),
            ),
          ),
        ),
      ],
    );
  }
}

String _navIndicatorLabel(AppLocalizations l, NavIndicator value) =>
    switch (value) {
      NavIndicator.none => l.apNavMarkNone,
      NavIndicator.pill => l.apNavMarkPill,
      NavIndicator.dot => l.apNavMarkDot,
      NavIndicator.line => l.apNavMarkLine,
    };

String _navLabelsLabel(AppLocalizations l, NavLabels value) => switch (value) {
  NavLabels.none => l.apNavLabelsNone,
  NavLabels.always => l.apNavLabelsAlways,
  NavLabels.active => l.apNavLabelsActive,
};

/// A screen with the bar at the bottom: the frame, three list stripes and the
/// panel, from the same rectangles as the real one.
class _NavStyleGlyph extends CustomPainter {
  const _NavStyleGlyph({
    required this.style,
    required this.indicator,
    required this.labels,
    required this.screen,
    required this.frame,
    required this.ink,
  });

  final NavBarStyle style;

  /// Drawn at the middle icon, which stands for the active one.
  final NavIndicator indicator;
  final NavLabels labels;

  /// The theme's background: shows how the panel lies on it.
  final Color screen;
  final Color frame;

  /// Accent when chosen, dimmed otherwise.
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in a 100×64 grid and scaled at once.
    canvas.save();
    canvas.scale(size.width / 100, size.height / 64);

    final body = RRect.fromLTRBR(0, 0, 100, 64, const Radius.circular(8));
    final paint = Paint()..color = screen;
    canvas.drawRRect(body, paint);

    canvas.save();
    // Clipped by the frame: bottom corners round by themselves, a full-width
    // panel meets the edges.
    canvas.clipRRect(body);

    // Different lengths, so they read as rows.
    paint.color = ink.withValues(alpha: 0.22);
    const widths = [64.0, 76.0, 52.0];
    for (var i = 0; i < widths.length; i++) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          10,
          10 + i * 11,
          10 + widths[i],
          15 + i * 11,
          const Radius.circular(2.5),
        ),
        paint,
      );
    }

    final panel = switch (style) {
      // Pressed to the bottom: flat on top, the frame rounds the rest.
      NavBarStyle.bar => RRect.fromLTRBR(0, 46, 100, 66, Radius.zero),
      NavBarStyle.rounded => RRect.fromLTRBAndCorners(
        0,
        44,
        100,
        66,
        topLeft: const Radius.circular(9),
        topRight: const Radius.circular(9),
      ),
      // Twice the corners, just as in the real bar.
      NavBarStyle.dome => RRect.fromLTRBAndCorners(
        0,
        44,
        100,
        66,
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
      ),
      // Taller than the pressed ones, just as in the real bar.
      NavBarStyle.floating => RRect.fromLTRBR(
        7,
        41,
        93,
        59,
        const Radius.circular(5),
      ),
      // Same panel as floating, with corners at half its height.
      NavBarStyle.pill => RRect.fromLTRBR(
        7,
        41,
        93,
        59,
        const Radius.circular(9),
      ),
    };
    canvas.drawRRect(panel, paint..color = ink.withValues(alpha: 0.26));

    // The only thing setting a plain bar off the list.
    if (style == NavBarStyle.bar) {
      canvas.drawLine(
        const Offset(0, 46),
        const Offset(100, 46),
        Paint()
          ..color = ink.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }

    // What's really visible: pressed styles go under the frame, so the middle
    // can't be counted from them.
    final bottom = min(panel.bottom, 64);
    final half = (panel.right - panel.left) / 2 - 6;
    final step = half * 2 / 3;
    final cx = (panel.left + panel.right) / 2;
    final mid = (panel.top + bottom) / 2;
    // Whether icon [i] has a label (0, the middle, is active). With one it's
    // smaller and raised: the panel's height doesn't change.
    bool titled(int i) => switch (labels) {
      NavLabels.none => false,
      NavLabels.always => true,
      NavLabels.active => i == 0,
    };

    // Under the icons: a layer of its own in the real bar too.
    switch (indicator) {
      case NavIndicator.none:
        break;
      case NavIndicator.pill:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, mid),
              width: step + 2,
              height: bottom - panel.top - 6,
            ),
            const Radius.circular(4),
          ),
          paint..color = ink.withValues(alpha: 0.45),
        );
      case NavIndicator.dot:
        canvas.drawCircle(Offset(cx, bottom - 4), 1.4, paint..color = ink);
      case NavIndicator.line:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, bottom - 4),
              width: 10,
              height: 1.8,
            ),
            const Radius.circular(0.9),
          ),
          paint..color = ink,
        );
    }

    // Three icons as dots, label stripes under those that have one. Only the
    // tab with a label shrinks.
    for (var i = -1; i <= 1; i++) {
      final text = titled(i);
      final cy = mid - (text ? 3 : 0);
      canvas.drawCircle(
        Offset(cx + i * step, cy),
        text ? 2.2 : 2.6,
        paint..color = ink,
      );
      if (!text) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx + i * step, cy + 5.5),
            width: 11,
            height: 1.8,
          ),
          const Radius.circular(0.9),
        ),
        paint..color = ink.withValues(alpha: 0.75),
      );
    }

    canvas.restore();
    canvas.drawRRect(
      body.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = frame,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NavStyleGlyph old) =>
      old.style != style ||
      old.indicator != indicator ||
      old.labels != labels ||
      old.ink != ink ||
      old.screen != screen;
}

/// The font card: a title with "+", tiles in three columns, each in its own
/// font. One's own come last; their cross shows always and asks with a second
/// press.
class _FontCard extends ConsumerWidget {
  const _FontCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final current = ref.watch(uiFontProvider);
    final userFonts = ref.watch(userFontsProvider);
    final settings = ref.read(settingsProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l.apFontTitle, style: theme.titleMedium),
                    const SizedBox(height: 3),
                    Text(context.l.apFontDesc, style: theme.bodySmall),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: context.l.apFontAdd,
                child: Pressable(
                  onTap: () => _addFonts(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 0, 8),
                    child: BloomIcon(Bi.addCircle, size: 22, color: t.muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 8 * 2) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in kBuiltinFonts)
                    _FontTile(
                      width: width,
                      name: f.name,
                      family: f.family,
                      active: current == f.family,
                      onTap: () => settings.setFontFamily(f.family),
                    ),
                  for (final f in userFonts)
                    _FontTile(
                      key: ValueKey(f.id),
                      width: width,
                      name: f.name,
                      family: f.family,
                      active: current == f.family,
                      onTap: () => settings.setFontFamily(f.family),
                      onDelete: () =>
                          ref.read(userFontsProvider.notifier).remove(f.id),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// No filter by extension: .ttf/.otf often have no MIME on Android and the
/// system picker would hide them. The store checks.
Future<void> _addFonts(BuildContext context, WidgetRef ref) async {
  final List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles();
  } catch (e) {
    if (context.mounted) {
      toaster.show(context.l.apFontReadErr, kind: ToastKind.error);
    }
    return;
  }
  if (picked.isEmpty) return;
  final res = await ref.read(userFontsProvider.notifier).addFiles([
    for (final p in picked)
      (name: p.name, size: p.lengthSync(), read: p.readAsBytes),
  ]);
  if (!context.mounted) return;
  final l = context.l;
  if (res.added > 1) toaster.show(l.apFontAdded(res.added));
  if (res.errors.contains(FontAddError.format)) {
    toaster.show(l.apFontBadFormat, kind: ToastKind.warn);
  }
  if (res.errors.contains(FontAddError.size)) {
    toaster.show(
      l.apFontTooBig(kMaxFontBytes ~/ (1024 * 1024)),
      kind: ToastKind.warn,
    );
  }
  if (res.errors.contains(FontAddError.read)) {
    toaster.show(l.apFontReadErr, kind: ToastKind.error);
  }
}

/// "Aa" in its font and the name under it.
class _FontTile extends StatelessWidget {
  const _FontTile({
    super.key,
    required this.width,
    required this.name,
    required this.family,
    required this.active,
    required this.onTap,
    this.onDelete,
  });

  final double width;
  final String name;
  final String family;
  final bool active;
  final VoidCallback onTap;

  /// Only one's own fonts.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final ovl = t.text;
    final font = TextStyle(
      fontFamily: family,
      fontFamilyFallback: const [kDefaultFont],
    );
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        decoration: BoxDecoration(
          color: ovl.withValues(alpha: active ? 0.12 : 0.04),
          borderRadius: BorderRadius.circular(t.radius * 0.7),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Aa',
                  textAlign: TextAlign.center,
                  style: font.copyWith(
                    fontSize: 22,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: font.copyWith(fontSize: 10, color: t.muted),
                ),
              ],
            ),
            if (onDelete != null)
              Positioned(
                top: -10,
                right: -2,
                child: Semantics(
                  button: true,
                  label: context.l.apFontRemove,
                  child: SecondTap(
                    onConfirm: onDelete!,
                    builder: (armed, tap) => Pressable(
                      onTap: tap,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: BloomIcon(
                          armed ? Bi.trashBinTrash : Bi.close,
                          size: 14,
                          color: armed ? t.danger : t.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Presets in two columns, one's own under a line. The sheet's shell does the
/// scrolling.
Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(settingsProvider.notifier);

  await showBloomSheetChild<void>(
    context: context,
    // The theme changes live under the sheet, so the header reads its colours
    // in its own context, not in the screen's at the time it opened.
    header: Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(kSheetEdge, 6, kSheetEdge, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l.apThemeRow,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            CircleIconButton(
              icon: Bi.addCircle,
              size: 40,
              iconSize: 22,
              background: sheetPanelColor(context),
              color: context.bloom.text,
              onTap: () => _createTheme(context, ref),
            ),
          ],
        ),
      ),
    ),
    child: Consumer(
      builder: (context, ref, _) {
        // Read inside: a theme applies at once and new ones appear here,
        // without closing.
        final settings = ref.watch(settingsProvider);
        final cardWidth = _sheetCardWidth(context);
        Widget card(ThemePreset preset) => _PresetCard(
          preset: preset,
          width: cardWidth,
          active: preset.id == settings.themeId,
          onTap: () => controller.setTheme(preset.id),
          onDelete: preset.custom
              ? () => _deleteTheme(context, ref, preset)
              : null,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(kSheetEdge, 0, kSheetEdge, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A mode, not a palette: a full row above the pairs. Its dots are
              // what's taken from the cover right now.
              _AutoThemeCard(
                preset: ThemePreset(
                  id: kAutoThemeId,
                  name: context.l.thAutoCard,
                  bg: settings.preset.bg,
                  blockColor: settings.preset.blockColor,
                  accent: settings.tokens.accent,
                ),
                active: settings.autoTheme,
                onTap: () => controller.setTheme(kAutoThemeId),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final p in kThemePresets) card(p)],
              ),
              if (settings.customThemes.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1, color: sheetLineColor(context)),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [for (final p in settings.customThemes) card(p)],
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

/// Asks with a second press on the cross itself.
void _deleteTheme(BuildContext context, WidgetRef ref, ThemePreset preset) {
  ref.read(settingsProvider.notifier).deleteCustomTheme(preset.id);
  toaster.show(context.l.thDeleted);
}

/// Name, three colours, random and save. A new theme applies at once and the
/// picker stays open under it.
Future<void> _createTheme(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  final draft = await showBloomSheetChild<_ThemeDraft>(
    context: context,
    header: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Text(
          context.l.thNew,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    ),
    // From the current theme's colours: that's what one usually starts from.
    child: _ThemeCreator(initial: settings.preset),
  );
  if (draft == null || !context.mounted) return;
  final created = ref
      .read(settingsProvider.notifier)
      .createCustomTheme(
        name: draft.name.isEmpty ? context.l.thNameDefault : draft.name,
        bg: draft.bg,
        blockColor: draft.blockColor,
        accent: draft.accent,
      );
  toaster.show(context.l.thCreated(created.name));
}

/// What the creator closes with.
class _ThemeDraft {
  const _ThemeDraft({
    required this.name,
    required this.bg,
    required this.blockColor,
    required this.accent,
  });

  final String name;
  final Color bg;
  final Color blockColor;
  final Color accent;
}

class _ThemeCreator extends StatefulWidget {
  const _ThemeCreator({required this.initial});

  final ThemePreset initial;

  @override
  State<_ThemeCreator> createState() => _ThemeCreatorState();
}

class _ThemeCreatorState extends State<_ThemeCreator> {
  late final TextEditingController _name = TextEditingController();
  late Color _bg = widget.initial.bg;
  late Color _block = widget.initial.blockColor;
  late Color _accent = widget.initial.accent;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// A dark background, a block a bit lighter in that hue, an accent in a
  /// clearly different one.
  void _random() {
    final rnd = Random();
    final h = rnd.nextDouble() * 360;
    final bgL = (5 + rnd.nextDouble() * 5) / 100;
    setState(() {
      _bg = HSLColor.fromAHSL(1, h, 0.18, bgL).toColor();
      _block = HSLColor.fromAHSL(1, h, 0.16, bgL + 0.05).toColor();
      _accent = HSLColor.fromAHSL(
        1,
        (h + 20 + rnd.nextDouble() * 320) % 360,
        0.65,
        0.58,
      ).toColor();
    });
  }

  Future<void> _pick(Color current, ValueChanged<Color> apply) async {
    final picked = await showBloomColorPicker(context, current);
    if (picked != null) setState(() => apply(picked));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final width = MediaQuery.of(context).size.width;
    final preview = ThemePreset(
      id: 'draft',
      name: _name.text.trim().isEmpty
          ? context.l.thNameDefault
          : _name.text.trim(),
      bg: _bg,
      blockColor: _block,
      accent: _accent,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BloomField(
            controller: _name,
            hint: context.l.thNameDefault,
            hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
            maxLength: 24,
            style: theme.titleMedium,
            // The name shows in the preview.
            onChanged: (_) => setState(() {}),
            fill: t.pill,
            radius: t.radius * 0.7,
            padding: const EdgeInsets.all(14),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ColorSlot(
                label: context.l.thSlotBg,
                color: _bg,
                onTap: () => _pick(_bg, (c) => _bg = c),
              ),
              const SizedBox(width: 10),
              _ColorSlot(
                label: context.l.thSlotCard,
                color: _block,
                onTap: () => _pick(_block, (c) => _block = c),
              ),
              const SizedBox(width: 10),
              _ColorSlot(
                label: context.l.thSlotAccent,
                color: _accent,
                onTap: () => _pick(_accent, (c) => _accent = c),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // The same card the grid will get.
          Center(
            child: _PresetCard(
              preset: preview,
              width: width - 40,
              active: false,
              onTap: () {},
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SheetButton(
                  label: context.l.thRandom,
                  icon: Bi.magicStick,
                  onTap: _random,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SheetButton(
                  label: context.l.commonSave,
                  tone: ButtonTone.accent,
                  onTap: () => Navigator.of(context).pop(
                    _ThemeDraft(
                      name: _name.text.trim(),
                      bg: _bg,
                      blockColor: _block,
                      accent: _accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorSlot extends StatelessWidget {
  const _ColorSlot({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          ColorChip(color: color, onTap: onTap),
        ],
      ),
    );
  }
}

/// Background, block, accent. They overlap, so each has an outline of the
/// plate's colour, or dark themes merge.
class _ThemeDots extends StatelessWidget {
  const _ThemeDots({required this.preset, this.size = 22, this.ring});

  final ThemePreset preset;
  final double size;

  /// The plate under the dots; the current theme's film by default.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final preview = preset.tokens();
    final colors = [preview.bg, preview.pill, preview.accent];
    final step = size * 0.68;
    return SizedBox(
      width: step * (colors.length - 1) + size,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < colors.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: ring ?? t.pill, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The plate under a theme: a film, a stronger one for the chosen theme.
BoxDecoration _themePlate(BuildContext context, bool active) {
  final t = context.bloom;
  return BoxDecoration(
    color: t.text.withValues(alpha: active ? 0.12 : 0.04),
    borderRadius: BorderRadius.circular(t.radius),
  );
}

/// A full row above the presets. No colours of its own: it wears the ones on
/// screen, taken from the cover.
class _AutoThemeCard extends StatelessWidget {
  const _AutoThemeCard({
    required this.preset,
    required this.active,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = preset.tokens();
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: _themePlate(context, active),
        child: Row(
          children: [
            _ThemeDots(preset: preset, size: 24, ring: preview.bg),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                preset.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (active) const SheetTick(),
          ],
        ),
      ),
    );
  }
}

/// A plate with a little window of the theme, dots in it, the name below.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.width,
    required this.active,
    required this.onTap,
    this.onDelete,
  });

  final ThemePreset preset;
  final double width;
  final bool active;
  final VoidCallback onTap;

  /// Only one's own themes.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final preview = preset.tokens();
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: Container(
        width: width,
        height: 150,
        padding: const EdgeInsets.all(8),
        decoration: _themePlate(context, active),
        child: Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                alignment: Alignment.topCenter,
                decoration: BoxDecoration(
                  color: preview.bg,
                  borderRadius: BorderRadius.circular(t.radius * 0.7),
                ),
                child: Row(
                  children: [
                    _ThemeDots(preset: preset, size: 24, ring: preview.bg),
                    const Spacer(),
                    if (active)
                      BloomIcon(Bi.check, size: 18, color: preview.accent),
                    if (onDelete != null)
                      // A larger hit area: the cross is small. Armed it's a red
                      // bin, so the next tap's meaning shows.
                      SecondTap(
                        onConfirm: onDelete!,
                        builder: (armed, tap) => Pressable(
                          onTap: tap,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: BloomIcon(
                              armed ? Bi.trashBinTrash : Bi.close,
                              size: 18,
                              color: armed ? preview.danger : preview.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}
