/// The rows of the settings sections: one shell and its three kinds.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/pressable.dart';
import '../../../shared/ui/glass.dart';

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
    this.padding = SettingsRowShell.edge,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final BloomGlyph? icon;
  final EdgeInsets padding;

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
      padding: padding,
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
      trailing: TintCircle(
        size: 40,
        color: t.text.withValues(alpha: 0.08),
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
    this.titleStyle,
    this.icon,
    this.leading,
    this.color,
    this.iconColor,
    this.onTap,
    this.enabled = true,
    this.padding = edge,
  });

  static const EdgeInsets edge = EdgeInsets.all(18);

  final String title;
  final String? subtitle;
  final int? subtitleLines;

  /// `titleMedium` in [color] when not set.
  final TextStyle? titleStyle;
  final Widget trailing;
  final BloomGlyph? icon;

  /// Instead of [icon], in its place: a platform's logo.
  final Widget? leading;

  /// For the title and the icon; `null` is the theme's text.
  final Color? color;

  /// The icon's own colour, when it differs from the title's.
  final Color? iconColor;
  final VoidCallback? onTap;
  final bool enabled;
  final EdgeInsets padding;

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
            padding: padding,
            child: Row(
              children: [
                if (icon != null || leading != null) ...[
                  SizedBox(
                    width: 24,
                    child:
                        leading ??
                        BloomIcon(
                          icon,
                          size: 20,
                          color: iconColor ?? color ?? t.iconFg,
                        ),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            titleStyle ??
                            theme.titleMedium?.copyWith(color: color),
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

/// A choice shown as a picture over its name: the chosen one is lit.
class PickCard extends StatelessWidget {
  const PickCard({
    super.key,
    required this.picture,
    required this.label,
    required this.active,
    required this.onTap,
    this.width,
    this.height,
  });

  /// Comes from outside: accent when chosen, dimmed otherwise.
  final Widget Function(Color ink) picture;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      child: SizedBox(
        width: width,
        height: height,
        child: GlassBox(
          borderRadius: BorderRadius.circular(t.radius),
          child: Ink(
            color: active ? t.accent.withValues(alpha: 0.12) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  picture(active ? t.accent : t.iconFg),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: active ? t.text : t.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
