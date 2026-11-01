/// The choice sheets behind the settings rows.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/pressable.dart';

/// A sheet's header: a title and, if there is one, a note under it.
Widget settingsSheetHeader(
  BuildContext context,
  String title, [
  String? subtitle,
]) {
  final theme = Theme.of(context).textTheme;
  return Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.titleLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle, style: theme.bodySmall),
          ],
        ],
      ),
    ),
  );
}

/// One of several: choosing applies and closes. The sheet covers what it
/// changes anyway.
Future<void> pickOneSheet<T>({
  required BuildContext context,
  String? title,
  String? subtitle,
  required List<T> values,
  required T current,
  required BloomGlyph Function(T) icon,
  required String Function(T) label,

  /// A note under a choice's name; `null` if the label is enough.
  String Function(T)? sub,

  /// Whether a choice can be picked; others grey out. `null` means all.
  bool Function(T)? enabled,
  required void Function(T) apply,
}) async {
  final picked = await showBloomSheetChild<T>(
    context: context,
    // May have no header: some choices explain themselves.
    header: title == null
        ? null
        : settingsSheetHeader(context, title, subtitle),
    // With the sheet's own context: it lives in the root navigator, the page's
    // would close Settings.
    child: Builder(
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            SheetOptionTile(
              icon: icon(value),
              label: label(value),
              sub: sub?.call(value),
              active: value == current,
              enabled: enabled?.call(value) ?? true,
              onTap: () => Navigator.of(sheetContext).pop(value),
            ),
        ],
      ),
    ),
  );
  if (picked != null) apply(picked);
}

/// A choice: icon, label, a mark on the right. Each is its own block: in a
/// solid list the chosen one can't be lit.
class SheetOptionTile extends StatelessWidget {
  const SheetOptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.sub,
    this.check = false,
    this.enabled = true,
  });

  final BloomGlyph icon;
  final String label;

  /// A note under the name; `null` for one line.
  final String? sub;

  /// The chosen choice, or a switched-on item.
  final bool active;

  /// A row of a set: a checkbox instead of a check and no lighting, since
  /// several can be on.
  final bool check;

  /// Unavailable: greyed whole and not pressable. Not hidden: the sheet shows
  /// what can be turned on, and the note says what's missing.
  final bool enabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final tint = active && !check;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: _panel(context, t, theme, tint),
    );
  }

  Widget _panel(
    BuildContext context,
    BloomTokens t,
    TextTheme theme,
    bool tint,
  ) {
    return SheetPanel(
      // Close together: these are large, a full gap would tear the list apart.
      gap: 3,
      children: [
        Pressable(
          onTap: enabled ? onTap : null,
          scale: 0.98,
          child: Ink(
            color: tint ? t.accent.withValues(alpha: 0.12) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 15, 18, 15),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? t.accent.withValues(alpha: 0.16)
                          : t.text.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(t.radius * 0.6),
                    ),
                    child: BloomIcon(
                      icon,
                      size: 20,
                      color: active ? t.accent : t.iconFg,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.titleMedium,
                        ),
                        if (sub case final text?) ...[
                          const SizedBox(height: 2),
                          Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (check)
                    _CheckBox(on: active)
                  else if (active)
                    BloomIcon(Bi.check, size: 20, color: t.accent),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An empty frame, or a square filled with accent and a check.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? t.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: on ? t.accent : t.ovlLine2, width: 1.5),
      ),
      child: on ? BloomIcon(Bi.check, size: 15, color: t.accentText) : null,
    );
  }
}

/// Big choice row of a sheet: glyph, name, optional line under it; the picked
/// one gets a ring, a circle under the glyph and a check.
class SheetChoiceTile extends StatelessWidget {
  const SheetChoiceTile({
    super.key,
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
    this.height,
    this.closes = false,
  });

  final Widget glyph;
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  final double? height;

  /// Close the sheet on pick: when there's nothing else to set in it.
  final bool closes;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final sub = this.sub;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSheetEdge, 5, kSheetEdge, 5),
      child: Pressable(
        onTap: () {
          if (closes) Navigator.of(context).pop();
          onTap();
        },
        scale: 0.98,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: sheetPanelColor(context),
            borderRadius: BorderRadius.circular(t.radius),
            border: Border.all(
              color: selected ? t.ovlLine2 : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              // The same box with or without the circle, so rows don't
              // change height when picked.
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: selected
                    ? BoxDecoration(
                        color: t.text.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      )
                    : null,
                child: glyph,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium,
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (selected) BloomIcon(Bi.check, size: 20, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}
