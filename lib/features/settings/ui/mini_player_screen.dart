/// Settings of the mini player, the card above the tab bar. Choices are lists
/// in sheets, not tiles: labels here are long.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../features/player/mini_style_store.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/subpage_header.dart';
import 'settings_rows.dart';
import 'settings_sheets.dart';

class MiniPlayerSettingsScreen extends ConsumerWidget {
  const MiniPlayerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mini = ref.watch(miniStyleProvider);
    final l = context.l;

    return SubPage(
      title: l.setMiniPlayer,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.pvGroupLook),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvMiniBgRow,
              value: _miniBgLabel(l, mini.bg),
              glyph: BloomIcon(_miniBgIcon(mini.bg)),
              onTap: () => _openMiniBg(context, ref),
            ),
            SettingsValueRow(
              title: l.pvMiniShapeRow,
              value: _miniShapeLabel(l, mini.shape),
              glyph: BloomIcon(_miniShapeIcon(mini.shape)),
              onTap: () => _openMiniShape(context, ref),
            ),
            SettingsValueRow(
              title: l.pvMiniRadiusRow,
              value: _miniRadiusLabel(l, mini.radius),
              glyph: BloomIcon(_miniRadiusIcon(mini.radius)),
              onTap: () => _openMiniRadius(context, ref),
            ),
            SettingsValueRow(
              title: l.pvMiniProgressRow,
              value: _miniProgressSummary(l, mini),
              // A set: the icon is about the progress as such.
              glyph: const BloomIcon(Bi.soundwave),
              onTap: () => _openMiniProgress(context),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvGroupMiniControls),
        const SizedBox(height: 10),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvMiniButtonsRow,
              value: _miniButtonsSummary(l, mini),
              // A set: the icon is about the buttons.
              glyph: const BloomIcon(Bi.gamepad),
              onTap: () => _openMiniButtons(context),
            ),
            SettingsValueRow(
              title: l.pvMiniNeighborsRow,
              value: _miniNeighborsLabel(l, mini.neighbors),
              glyph: BloomIcon(_miniNeighborsIcon(mini.neighbors)),
              onTap: () => _openMiniNeighbors(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Look ─────────────────────────────────────────────────────────────────────

String _miniBgLabel(AppLocalizations l, MiniBg bg) => switch (bg) {
  MiniBg.theme => l.pvMiniBgTheme,
  MiniBg.coverColor => l.pvMiniBgCoverColor,
  MiniBg.cover => l.pvMiniBgCover,
};

BloomGlyph _miniBgIcon(MiniBg bg) => switch (bg) {
  MiniBg.theme => Bi.paintRoller,
  MiniBg.coverColor => Bi.palette,
  MiniBg.cover => Bi.gallery,
};

String _miniShapeLabel(AppLocalizations l, MiniCoverShape shape) =>
    switch (shape) {
      MiniCoverShape.rounded => l.pvMiniShapeRounded,
      MiniCoverShape.circle => l.pvMiniShapeCircle,
    };

BloomGlyph _miniShapeIcon(MiniCoverShape shape) => switch (shape) {
  MiniCoverShape.rounded => Bi.stop,
  MiniCoverShape.circle => Bi.record,
};

String _miniRadiusLabel(AppLocalizations l, MiniRadius radius) =>
    switch (radius) {
      MiniRadius.none => l.pvMiniRadiusNone,
      MiniRadius.soft => l.pvMiniRadiusSoft,
      MiniRadius.rounded => l.pvMiniRadiusRounded,
      MiniRadius.pill => l.pvMiniRadiusPill,
    };

BloomGlyph _miniRadiusIcon(MiniRadius radius) => switch (radius) {
  MiniRadius.none => Bi.stop,
  MiniRadius.soft => Bi.widget,
  MiniRadius.rounded => Bi.widget2,
  MiniRadius.pill => Bi.record,
};

String _miniProgressLabel(AppLocalizations l, MiniProgressKind kind) =>
    switch (kind) {
      MiniProgressKind.line => l.pvMiniProgressLine,
      MiniProgressKind.fill => l.pvMiniProgressFill,
      MiniProgressKind.ring => l.pvMiniProgressRing,
    };

BloomGlyph _miniProgressIcon(MiniProgressKind kind) => switch (kind) {
  MiniProgressKind.line => Bi.minus,
  MiniProgressKind.fill => Bi.stop,
  MiniProgressKind.ring => Bi.refreshCircle,
};

/// What's on, in the sheet's order. Commas: it's a set, not one of several.
String _miniProgressSummary(AppLocalizations l, MiniStyle mini) {
  final parts = [
    for (final kind in MiniProgressKind.values)
      if (mini.has(kind)) _miniProgressLabel(l, kind),
  ];
  return parts.isEmpty ? l.pvMiniProgressNone : parts.join(', ');
}

Future<void> _openMiniBg(BuildContext context, WidgetRef ref) => pickOneSheet(
  context: context,
  title: context.l.pvMiniBgRow,
  subtitle: context.l.pvMiniBgSub,
  values: MiniBg.values,
  current: ref.read(miniStyleProvider).bg,
  icon: _miniBgIcon,
  label: (bg) => _miniBgLabel(context.l, bg),
  apply: ref.read(miniStyleProvider.notifier).setBg,
);

Future<void> _openMiniShape(BuildContext context, WidgetRef ref) =>
    pickOneSheet(
      context: context,
      title: context.l.pvMiniShapeRow,
      values: MiniCoverShape.values,
      current: ref.read(miniStyleProvider).shape,
      icon: _miniShapeIcon,
      label: (shape) => _miniShapeLabel(context.l, shape),
      apply: ref.read(miniStyleProvider.notifier).setShape,
    );

Future<void> _openMiniRadius(BuildContext context, WidgetRef ref) =>
    pickOneSheet(
      context: context,
      title: context.l.pvMiniRadiusRow,
      values: MiniRadius.values,
      current: ref.read(miniStyleProvider).radius,
      icon: _miniRadiusIcon,
      label: (radius) => _miniRadiusLabel(context.l, radius),
      apply: ref.read(miniStyleProvider.notifier).setRadius,
    );

/// A set: rows toggle in place and the sheet stays open.
Future<void> _openMiniProgress(BuildContext context) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: SheetTitle(l.pvMiniProgressRow, subtitle: l.pvMiniProgressSub),
    child: Consumer(
      builder: (context, ref, _) {
        final mini = ref.watch(miniStyleProvider);
        final ctrl = ref.read(miniStyleProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in MiniProgressKind.values)
              SheetOptionTile(
                icon: _miniProgressIcon(kind),
                label: _miniProgressLabel(l, kind),
                active: mini.has(kind),
                check: true,
                onTap: () => ctrl.toggleProgress(kind, !mini.has(kind)),
              ),
          ],
        );
      },
    ),
  );
}

// ── Controls ─────────────────────────────────────────────────────────────────

String _miniButtonLabel(AppLocalizations l, MiniButton button) =>
    switch (button) {
      MiniButton.prev => l.pvMiniButtonPrev,
      MiniButton.play => l.pvMiniButtonPlay,
      MiniButton.next => l.pvMiniButtonNext,
      MiniButton.fav => l.pvMiniButtonFav,
    };

BloomGlyph _miniButtonIcon(MiniButton button) => switch (button) {
  MiniButton.prev => Bi.skipPrevious,
  MiniButton.play => Bi.play,
  MiniButton.next => Bi.skipNext,
  MiniButton.fav => Bi.heart,
};

/// What's on, in the card's own order.
String _miniButtonsSummary(AppLocalizations l, MiniStyle mini) {
  final parts = [
    for (final button in MiniButton.values)
      if (mini.hasButton(button)) _miniButtonLabel(l, button),
  ];
  return parts.isEmpty ? l.pvMiniButtonsNone : parts.join(', ');
}

/// A set too: any, or none at all, and then the card is its cover and caption.
Future<void> _openMiniButtons(BuildContext context) {
  final l = context.l;
  return showBloomSheetChild<void>(
    context: context,
    header: SheetTitle(l.pvMiniButtonsRow, subtitle: l.pvMiniButtonsSub),
    child: Consumer(
      builder: (context, ref, _) {
        final mini = ref.watch(miniStyleProvider);
        final ctrl = ref.read(miniStyleProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final button in MiniButton.values)
              SheetOptionTile(
                icon: _miniButtonIcon(button),
                label: _miniButtonLabel(l, button),
                active: mini.hasButton(button),
                check: true,
                onTap: () => ctrl.toggleButton(button, !mini.hasButton(button)),
              ),
          ],
        );
      },
    ),
  );
}

String _miniNeighborsLabel(AppLocalizations l, bool on) =>
    on ? l.pvMiniNeighborsOn : l.pvMiniNeighborsOff;

BloomGlyph _miniNeighborsIcon(bool on) => on ? Bi.transferHorizontal : Bi.stop;

/// A choice of two, not a switch: it reads like its neighbours in this card.
Future<void> _openMiniNeighbors(BuildContext context, WidgetRef ref) =>
    pickOneSheet<bool>(
      context: context,
      title: context.l.pvMiniNeighborsRow,
      subtitle: context.l.pvMiniNeighborsSub,
      values: const [false, true],
      current: ref.read(miniStyleProvider).neighbors,
      icon: _miniNeighborsIcon,
      label: (on) => _miniNeighborsLabel(context.l, on),
      apply: ref.read(miniStyleProvider.notifier).setNeighbors,
    );
