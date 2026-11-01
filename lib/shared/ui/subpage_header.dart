/// Header of a settings subpage: a round Back and the title in a wide pill,
/// stretched to the remaining width with the title centred, so it reads as a
/// screen title.
///
/// [SubPage] nearby is the whole frame of such a page: the header is pinned and
/// only the content below scrolls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../features/customization/ui/app_background.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'glass.dart';

class SubPageHeader extends StatelessWidget {
  const SubPageHeader({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleIconButton(icon: Bi.arrowLeft, onTap: onBack),
        const SizedBox(width: 10),
        Expanded(
          child: GlassBox(
            // Fully rounded rather than the theme radius: next to the round
            // button they read as a pair.
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: kHeaderControl,
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // `titleMedium` looks lost in the taller pill, with too much
                  // air around it. A local tweak: the shared style also drives
                  // track rows and card captions.
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: kHeaderTitleSize),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A group's caption, in capitals.
class SettingsCaption extends StatelessWidget {
  const SettingsCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: context.bloom.text2),
  );
}

/// Group of settings rows: one dark container with rows split by a thin line.
/// Related rows stay together instead of separate cards with gaps: the group
/// title already says they belong, and a column of equal plates has no
/// beginning or end.
///
/// [dividerInset] is the line's left inset: it starts under the row's TEXT, so
/// lists with a leading icon use more.
class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    super.key,
    required this.rows,
    this.dividerInset = 16,
  });

  final List<Widget> rows;
  final double dividerInset;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GlassBox(
      // More rounded than smaller plates: on a box this size the theme radius
      // reads almost square. A factor rather than an addition, so radius 0
      // stays square.
      borderRadius: BorderRadius.circular(t.radius * 1.3),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) GroupDivider(indent: dividerInset),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// The line between rows of a group, from where their text starts. Half of the
/// usual line: the plate already groups them, this only hints.
class GroupDivider extends StatelessWidget {
  const GroupDivider({super.key, required this.indent});

  final double indent;

  @override
  Widget build(BuildContext context) {
    final line = context.bloom.ovlLine;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Divider(height: 1, color: line.withValues(alpha: line.a * 0.5)),
    );
  }
}

/// A page under a [SubPageHeader] that stays put: only what's below it scrolls,
/// so "back" and the title are always under the finger.
class SubPage extends StatelessWidget {
  const SubPage({
    super.key,
    required this.title,
    required this.onBack,
    this.children = const [],
    this.child,
    this.actions = const [],
  });

  final String title;
  final VoidCallback onBack;

  /// A list under the header, with the page's margins.
  final List<Widget> children;

  /// Instead of [children]: what scrolls itself.
  final Widget? child;

  /// Round buttons next to the title.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: SubPageHeader(title: title, onBack: onBack),
                ),
                for (final action in actions) ...[
                  const SizedBox(width: 8),
                  action,
                ],
              ],
            ),
          ),
          // A strut, not list padding: content cuts off this far below the
          // pill, not along its very edge.
          const SizedBox(height: 10),
          Expanded(
            child:
                child ??
                ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    24 + bottomBarsInset(context),
                  ),
                  children: children,
                ),
          ),
        ],
      ),
    );
  }
}

/// The ground of a pushed page: clear when the app has a picture behind it.
class BloomPage extends ConsumerWidget {
  const BloomPage({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: ref.watch(backgroundOnProvider)
        ? Colors.transparent
        : context.bloom.bg,
    body: body,
  );
}
