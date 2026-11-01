/// Swipes: four places, each with its own pair of actions. A header, a preview
/// plate, a card with the two sides; the action is picked in a sheet, one list
/// for all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../../shared/ui/track_swipes.dart';
import '../swipe_store.dart';
import 'settings_rows.dart';

class SwipesScreen extends ConsumerWidget {
  const SwipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(swipeProvider);

    return SubPage(
      title: context.l.setSwipes,
      onBack: () => context.go('/settings'),
      children: [
        for (final zone in SwipeZone.values) ...[
          if (zone != SwipeZone.values.first) const SizedBox(height: 26),
          SettingsCaption(swipeZoneLabel(context.l, zone)),
          const SizedBox(height: 10),
          _Preview(zone: zone, pair: settings.of(zone)),
          const SizedBox(height: 12),
          _SidesCard(zone: zone, pair: settings.of(zone)),
        ],
      ],
    );
  }
}

/// The place's icon, the plate's centre.
Widget _zoneIcon(BuildContext context, SwipeZone zone) {
  final color = context.bloom.muted;
  return BloomIcon(
    switch (zone) {
      SwipeZone.queue => Bi.playlistMinimalistic,
      SwipeZone.mini => Bi.musicNote,
      SwipeZone.player => Bi.play,
      SwipeZone.library => Bi.library,
    },
    size: 18,
    color: color,
  );
}

/// Icons stand on the side the move comes from: left is the right swipe's
/// action, right the left one's, the place in the middle. Quiet: a picture, not
/// buttons.
class _Preview extends StatelessWidget {
  const _Preview({required this.zone, required this.pair});

  final SwipeZone zone;
  final SwipePair pair;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GlassBox(
      child: Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            BloomIcon(swipeActionIcon(pair.right), size: 22, color: t.muted),
            const Spacer(),
            _zoneIcon(context, zone),
            const Spacer(),
            BloomIcon(swipeActionIcon(pair.left), size: 22, color: t.muted),
          ],
        ),
      ),
    );
  }
}

/// What a move left does and what a move right does.
class _SidesCard extends ConsumerWidget {
  const _SidesCard({required this.zone, required this.pair});

  final SwipeZone zone;
  final SwipePair pair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsGroupCard(
      // The line starts under the row's text.
      dividerInset: 52,
      rows: [
        _SideRow(zone: zone, isLeft: true, action: pair.left),
        _SideRow(zone: zone, isLeft: false, action: pair.right),
      ],
    );
  }
}

class _SideRow extends ConsumerWidget {
  const _SideRow({
    required this.zone,
    required this.isLeft,
    required this.action,
  });

  final SwipeZone zone;
  final bool isLeft;
  final SwipeAction action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    return SettingsRowShell(
      icon: isLeft ? Bi.arrowLeft : Bi.arrowRight,
      iconColor: t.muted,
      title: isLeft ? context.l.swLeft : context.l.swRight,
      subtitle: swipeActionLabel(context.l, action),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      trailing: BloomIcon(swipeActionIcon(action), size: 20, color: t.muted),
      onTap: () => _pickAction(context, ref, zone, isLeft, action),
    );
  }
}

/// Each action a large block of its own. No header: the row it came from stays
/// visible above.
Future<void> _pickAction(
  BuildContext context,
  WidgetRef ref,
  SwipeZone zone,
  bool isLeft,
  SwipeAction current,
) {
  final controller = ref.read(swipeProvider.notifier);
  return showBloomSheetChild<void>(
    context: context,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in SwipeAction.values)
          SheetOptionTile(
            icon: swipeActionIcon(action),
            label: swipeActionLabel(context.l, action),
            active: action == current,
            onTap: () {
              Navigator.of(context).pop();
              controller.setAction(zone, isLeft: isLeft, action: action);
            },
          ),
      ],
    ),
  );
}
