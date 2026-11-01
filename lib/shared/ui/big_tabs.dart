/// Big text tabs over a page: the current one in the text color, one with
/// something in it grey, an empty one dimmer still and not tappable. Under
/// them, in "all", each kind stands under a [SectionLabel] leading to its tab.
library;

import 'package:flutter/material.dart';

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/tokens.dart';
import 'pressable.dart';

class BigTab<T> {
  const BigTab(this.id, this.label, {this.has = true});

  final T id;
  final String label;
  final bool has;
}

class BigTabs<T> extends StatelessWidget {
  const BigTabs({
    super.key,
    required this.tabs,
    required this.current,
    required this.onPick,
    this.size = 26,
  });

  final List<BigTab<T>> tabs;
  final T current;
  final ValueChanged<T> onPick;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    // Aligned so that a narrow row sits at the left edge, not in the middle.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final (i, tab) in tabs.indexed) ...[
              if (i > 0) SizedBox(width: (size * 0.6).roundToDouble()),
              Pressable(
                scale: 0.97,
                onTap: tab.has && tab.id != current
                    ? () => onPick(tab.id)
                    : null,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: bloomText(
                    size: size,
                    weight: 700,
                    color: tab.id == current
                        ? t.text
                        : t.text.withValues(alpha: tab.has ? 0.42 : 0.16),
                  ),
                  child: Text(tab.label),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A section's small grey caption in "all"; a kind's one leads to its tab.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: Text(
          text,
          style: bloomText(size: 14, weight: 600, color: context.bloom.text2),
        ),
      ),
    ),
  );
}

/// A short choice of a few, a film sliding under the chosen one.
class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onPick,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onPick;

  /// Переезд пилюли — десктопные 0.32 с.
  static const Duration slide = Duration(milliseconds: 320);

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final style = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontSize: 13);
    return IntrinsicWidth(
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: slide,
              curve: Curves.easeOutCubic,
              alignment: Alignment(
                labels.length < 2 ? 0 : -1 + 2 * index / (labels.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / labels.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.text.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPick(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: (style ?? const TextStyle()).copyWith(
                            color: i == index ? t.text : t.text2,
                          ),
                          child: Text(labels[i], maxLines: 1),
                        ),
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
