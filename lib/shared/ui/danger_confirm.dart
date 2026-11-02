/// Confirmation of something irreversible: a sheet with a red button. A row in
/// a list is easy to hit by accident on a phone, a button in a sheet isn't. One
/// look everywhere: resets, clearing storage, disconnecting a computer.
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'bloom_sheet.dart';

/// Sheet with an icon, what will happen and a red button; `true` if pressed.
Future<bool> confirmDanger(
  BuildContext context, {
  required BloomGlyph icon,
  required String title,
  required String body,
  required String button,
}) async =>
    await showBloomSheetChild<bool>(
      context: context,
      child: DangerConfirmBody(
        icon: icon,
        title: title,
        body: body,
        button: button,
      ),
    ) ==
    true;

/// Sheet body: a large icon on a red circle, a title, what happens and
/// [DangerSheetButton].
class DangerConfirmBody extends StatelessWidget {
  const DangerConfirmBody({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.button,
  });

  final BloomGlyph icon;
  final String title;
  final String body;
  final String button;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Column(
        children: [
          TintCircle(
            size: 72,
            color: t.danger.withValues(alpha: 0.12),
            child: BloomIcon(icon, size: 28, color: t.danger),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: theme.titleLarge),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.bodySmall?.copyWith(color: t.text2),
          ),
          const SizedBox(height: 20),
          DangerSheetButton(label: button),
        ],
      ),
    );
  }
}

/// Full-width red button that closes the sheet with `true`. With [enabled]
/// false there's nothing to do (an empty cache).
class DangerSheetButton extends StatelessWidget {
  const DangerSheetButton({
    super.key,
    required this.label,
    this.enabled = true,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => BloomButton(
    label: label,
    tone: ButtonTone.danger,
    pill: false,
    height: 54,
    onTap: enabled ? () => Navigator.of(context).pop(true) : null,
  );
}
