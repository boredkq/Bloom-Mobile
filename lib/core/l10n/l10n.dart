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
/// utilities. The context comes from the toast host, which lives as long as
/// `MaterialApp`, so a string is found even for a toast from a timer.
///
/// `null` is possible only before the first frame or with no tree, as in store
/// unit tests: nobody's there to show it.
AppLocalizations? get globalL10n {
  final context = toaster.context;
  return context == null ? null : AppLocalizations.of(context);
}
