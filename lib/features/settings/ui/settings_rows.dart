/// The rows of the settings sections: one shell and its three kinds.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/pressable.dart';

/// A row with a switch. Only the switch toggles: a tap across the whole width
/// would read as going to a page.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final BloomGlyph? icon;

  /// What depends on a switch that's off greys out and stays in place.
  final bool enabled;

  @override
  Widget build(BuildContext context) => SettingsRowShell(
    icon: icon,
    title: title,
    subtitle: subtitle,
    enabled: enabled,
    trailing: BloomSwitch(value: value, onChanged: onChanged),
  );
}

/// A row that goes somewhere: a chevron, and the whole row presses.
class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final BloomGlyph? icon;

  /// A dangerous action: the title and the icon go red.
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SettingsRowShell(
      icon: icon,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      color: danger ? t.danger : null,
      trailing: BloomIcon(
        Bi.altArrowRight,
        size: 16,
        color: danger ? t.danger : t.text2,
      ),
      onTap: onTap,
    );
  }
}

/// A row with a choice behind it: the chosen value under the title, its picture
/// in a circle on the right, so the choice shows without opening the sheet.
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    super.key,
    required this.title,
    required this.value,
    required this.glyph,
    required this.onTap,
  });

  final String title;
  final String value;

  /// Takes its colour from [IconTheme]. One box for all: they differ in width
  /// and must stand in a straight column.
  final Widget glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SettingsRowShell(
      title: title,
      subtitle: value,
      subtitleLines: 1,
      onTap: onTap,
      trailing: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.text.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: IconTheme(
          data: IconThemeData(color: t.iconFg, size: 21),
          child: glyph,
        ),
      ),
    );
  }
}

/// Icon, text, something on the right. No plate of its own: related rows stand
/// in one `SettingsGroupCard`.
class SettingsRowShell extends StatelessWidget {
  const SettingsRowShell({
    super.key,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.subtitleLines,
    this.icon,
    this.color,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final int? subtitleLines;
  final Widget trailing;
  final BloomGlyph? icon;

  /// For the title and the icon; `null` is the theme's text.
  final Color? color;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final sub = subtitle ?? '';

    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Pressable(
          onTap: onTap,
          scale: 0.98,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                if (icon != null) ...[
                  SizedBox(
                    width: 24,
                    child: BloomIcon(icon, size: 20, color: color ?? t.iconFg),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.titleMedium?.copyWith(color: color),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          sub,
                          maxLines: subtitleLines,
                          overflow: subtitleLines == null
                              ? null
                              : TextOverflow.ellipsis,
                          style: theme.bodySmall?.copyWith(color: t.text2),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
