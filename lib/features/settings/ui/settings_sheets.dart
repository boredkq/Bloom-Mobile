/// The choice sheets behind the settings rows.
library;

import 'package:flutter/material.dart';

import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';

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
    header: title == null ? null : SheetTitle(title, subtitle: subtitle),
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
