/// Big text tabs over a page: the current one in the text color, one with
/// something in it grey, an empty one dimmer still and not tappable.
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
