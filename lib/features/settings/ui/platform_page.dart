/// An integration's page: a big mark in the middle, content under it, actions
/// at the bottom. No header: the logo is the title, and "Back" is the last
/// button.
///
/// Collapsed it's the mark and the buttons; with [body] the mark shrinks so a
/// form stays above them. The guide sheet lives here too.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/pressable.dart';

/// One green for "all fine" on all these pages.
const Color kPlatformOk = Color(0xFF1DB954);

const Duration _kExpand = Duration(milliseconds: 280);
const Curve _kExpandCurve = Cubic(0.4, 0, 0.2, 1);

class PlatformPage extends StatelessWidget {
  const PlatformPage({
    super.key,
    this.mark,
    this.icon,
    required this.onBack,
    this.status,
    this.statusColor,
    this.body,
    this.actions = const [],
  }) : assert((mark == null) != (icon == null));

  /// A platform or a service.
  final BrandMark? mark;

  /// Or an icon, for a section with no brand.
  final BloomGlyph? icon;
  final VoidCallback onBack;

  /// Connected, not connected, or what it's set up with.
  final String? status;
  final Color? statusColor;

  /// `null` means collapsed, the mark in the centre.
  final Widget? body;

  /// "Back" is added as the last one.
  final List<Widget> actions;

  /// The mark's box, at rest and open.
  static const double _logoFull = 112;
  static const double _logoCompact = 84;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final open = body != null;

    return SafeArea(
      // The bars float above the bottom: the buttons count from them
      // ([bottomBarsInset]).
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: ConstrainedBox(
                  // While shorter than the screen the mark stays centred; a
                  // long form scrolls.
                  constraints: BoxConstraints(minHeight: box.maxHeight - 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: open ? _logoCompact : _logoFull),
                        duration: _kExpand,
                        curve: _kExpandCurve,
                        builder: (_, size, _) => icon != null
                            ? BloomIcon(icon, size: size * 0.8, color: t.text)
                            : mark!.logo(size: size),
                      ),
                      if (status case final text?) ...[
                        const SizedBox(height: 18),
                        Text(
                          text,
                          textAlign: TextAlign.center,
                          style: theme.bodySmall?.copyWith(
                            color: statusColor ?? t.muted,
                          ),
                        ),
                      ],
                      // Grows instead of jumping: the mark rides up with it.
                      AnimatedSize(
                        duration: _kExpand,
                        curve: _kExpandCurve,
                        alignment: Alignment.topCenter,
                        child: body == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: body,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              14 + bottomBarsInset(context),
            ),
            child: Column(
              children: [
                for (final action in actions) ...[
                  action,
                  const SizedBox(height: 10),
                ],
                BloomButton(
                  label: context.l.commonBack,
                  tone: ButtonTone.line,
                  pill: false,
                  height: 54,
                  onTap: onBack,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A link to the guide: mark, name, caption, an icon on the right.
class PlatformCard extends StatelessWidget {
  const PlatformCard({
    super.key,
    required this.mark,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Bi.questionCircle,
  });

  final BrandMark mark;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final BloomGlyph icon;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: GlassBox(
        borderRadius: BorderRadius.circular(t.radius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: mark.logo(size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.bodyMedium?.copyWith(
                        color: t.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: BloomIcon(icon, size: 20, color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// No lines: one word in empty space.
class OrLabel extends StatelessWidget {
  const OrLabel({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      context.l.commonOr,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.bloom.muted),
    ),
  );
}

/// The guide sheet. In [steps] `**bold**` marks addresses, keys and parameter
/// names, what the eye looks for.
Future<void> showPlatformGuide(
  BuildContext context, {
  required BrandMark mark,
  required String title,
  List<String> steps = const [],
  String? note,
}) {
  return showBloomSheetChild<void>(
    context: context,
    header: _GuideHeader(mark: mark, title: title),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (steps.isNotEmpty)
          SheetPanel(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) sheetDivider(),
                _GuideStep(index: i + 1, mark: mark, text: steps[i]),
              ],
            ],
          ),
        if (note case final text?)
          Padding(
            padding: const EdgeInsets.fromLTRB(kSheetEdge, 12, kSheetEdge, 4),
            child: Builder(
              builder: (context) => Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.bloom.text2,
                  height: 1.6,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.mark, required this.title});

  final BrandMark mark;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 10, kSheetEdge, 14),
      child: Row(
        children: [
          // A small logo gets lost without a plate.
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (mark.color ?? t.accent).withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: mark.logo(size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: theme.titleLarge)),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.index,
    required this.mark,
    required this.text,
  });

  final int index;
  final BrandMark mark;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final brand = mark.color ?? t.accent;
    final base = theme.bodyMedium?.copyWith(color: t.text2, height: 1.5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: brand.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: theme.labelSmall?.copyWith(
                color: brand,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: markupSpans(
                  text,
                  base,
                  base?.copyWith(color: t.text, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Odd pieces are the bold ones.
List<TextSpan> markupSpans(String text, TextStyle? base, TextStyle? strong) => [
  for (final (i, part) in text.split('**').indexed)
    if (part.isNotEmpty) TextSpan(text: part, style: i.isOdd ? strong : base),
];
