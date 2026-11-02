/// Access to translations: a short `context.l` for widgets and [globalL10n] for
/// things with no context.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/bloom_toast.dart';

export '../../l10n/app_localizations.dart' show AppLocalizations;

extension BloomL10n on BuildContext {
  /// Translations of the current locale, short for
  /// `AppLocalizations.of(context)`.
  AppLocalizations get l => AppLocalizations.of(this);
}

/// Translations for code with no `BuildContext`: background toasts and
/// utilities. The context comes from the global messenger, which lives as long
/// as `MaterialApp`, so a string is found even for a toast from a timer.
///
/// `null` is possible only before the first frame, when nobody's there to show
/// it. `GlobalKey.currentContext` THROWS if the widget binding isn't up, as in
/// store unit tests with no tree; that's the same no-language case, so I catch
/// it and return null.
AppLocalizations? get globalL10n {
  try {
    final context = bloomMessengerKey.currentContext;
    return context == null ? null : AppLocalizations.of(context);
  } on FlutterError {
    return null;
  }
}
