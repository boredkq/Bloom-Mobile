/// Settings of the mini player, the card above the tab bar. Few choices stand
/// right on the page as cards, the rest open in sheets.
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
    final ctrl = ref.read(miniStyleProvider.notifier);
    final l = context.l;

    return SubPage(
      title: l.setMiniPlayer,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.pvMiniBgRow),
        const SizedBox(height: 10),
        PickRow<MiniBg>(
          values: MiniBg.values,
          active: (bg) => bg == mini.bg,
          label: (bg) => _miniBgLabel(l, bg),
          picture: (bg, _) => BloomIcon(_miniBgIcon(bg)),
          onTap: ctrl.setBg,
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvMiniShapeRow),
        const SizedBox(height: 10),
        PickRow<MiniCoverShape>(
          values: MiniCoverShape.values,
          active: (shape) => shape == mini.shape,
          label: (shape) => _miniShapeLabel(l, shape),
          picture: (shape, _) => BloomIcon(_miniShapeIcon(shape)),
          onTap: ctrl.setShape,
        ),
        const SizedBox(height: 22),
        SettingsGroupCard(
          rows: [
            SettingsValueRow(
              title: l.pvMiniRadiusRow,
              value: _miniRadiusLabel(l, mini.radius),
              glyph: BloomIcon(_miniRadiusIcon(mini.radius)),
              onTap: () => _openMiniRadius(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvMiniProgressRow),
        const SizedBox(height: 10),
        PickRow<MiniProgressKind>(
          values: MiniProgressKind.values,
          active: mini.has,
          label: (kind) => _miniProgressLabel(l, kind),
          picture: (kind, _) => BloomIcon(_miniProgressIcon(kind)),
          onTap: (kind) => ctrl.toggleProgress(kind, !mini.has(kind)),
        ),
        const SizedBox(height: 12),
        SettingsGroupCard(
          rows: [
            SettingsToggleRow(
              title: l.pvMiniProgressTint,
              subtitle: l.pvMiniProgressTintSub,
              value: mini.progressTint,
              enabled: mini.progressTintUseful,
              onChanged: ctrl.setProgressTint,
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
          ],
        ),
        const SizedBox(height: 22),
        SettingsCaption(l.pvMiniNeighborsRow),
        const SizedBox(height: 10),
        PickRow<bool>(
          values: const [false, true],
          active: (on) => on == mini.neighbors,
          label: (on) => _miniNeighborsLabel(l, on),
          picture: (on, _) => BloomIcon(_miniNeighborsIcon(on)),
          onTap: ctrl.setNeighbors,
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

/// A set: any, or none at all, and then the card is its cover and caption.
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
