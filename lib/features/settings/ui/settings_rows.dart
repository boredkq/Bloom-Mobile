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
/// on the right, so the choice shows without opening the sheet.
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
      trailing: SizedBox.square(
        dimension: 26,
        child: Center(
          child: IconTheme(
            data: IconThemeData(color: t.iconFg, size: 22),
            child: glyph,
          ),
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

/// A row of a group: the title, a value on the right, a chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    required this.onTap,
    this.value,
    this.trailing,
    this.enabled = true,
  });

  final BloomGlyph? icon;
  final Widget? leading;
  final String title;
  final VoidCallback onTap;

  /// Right of the title, before the chevron: the version number.
  final String? value;

  /// Replaces the chevron: an arrow beside the flag would read as a second
  /// icon.
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final text = value;
    return SettingsRowShell(
      icon: icon,
      leading: leading,
      title: title,
      enabled: enabled,
      // Makes 64 a row with the text line.
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text != null) ...[
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.text2),
            ),
            const SizedBox(width: 10),
          ],
          trailing ?? BloomIcon(Bi.altArrowRight, size: 16, color: t.text2),
        ],
      ),
    );
  }
}

/// The plate of a choice standing on a page: lit when chosen.
class PickPlate extends StatelessWidget {
  const PickPlate({
    super.key,
    required this.active,
    required this.onTap,
    required this.child,
    this.width,
    this.height,
  });

  final bool active;
  final VoidCallback onTap;
  final Widget child;
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
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A choice shown as a picture over its name.
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

  /// Accent when chosen, dimmed otherwise; icons take it from [IconTheme].
  final Widget Function(Color ink) picture;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final ink = active ? t.accent : t.iconFg;
    return PickPlate(
      active: active,
      onTap: onTap,
      width: width,
      height: height,
      child: Padding(
        // Narrow sides: three in a row on a small phone still fit their names.
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconTheme(
              data: IconThemeData(color: ink, size: 24),
              child: picture(ink),
            ),
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
    );
  }
}

/// Few choices side by side, right on the page. [active] is a test and not a
/// value, since a set can have several lit.
class PickRow<T> extends StatelessWidget {
  const PickRow({
    super.key,
    required this.values,
    required this.active,
    required this.label,
    required this.picture,
    required this.onTap,
    this.height = 88,
  });

  final List<T> values;
  final bool Function(T value) active;
  final String Function(T value) label;
  final Widget Function(T value, Color ink) picture;
  final ValueChanged<T> onTap;

  /// `null` lets the picture set it.
  final double? height;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < values.length; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(
          child: PickCard(
            height: height,
            label: label(values[i]),
            active: active(values[i]),
            picture: (ink) => picture(values[i], ink),
            onTap: () => onTap(values[i]),
          ),
        ),
      ],
    ],
  );
}
