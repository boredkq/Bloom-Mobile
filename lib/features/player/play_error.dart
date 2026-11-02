/// Playback error in the user's language. Providers throw not text but a
/// dictionary CODE (`search.err.*`, `sc.err.*`, `ym.err.*`, `ytm.err.*`). The
/// player keeps the code in [PlaybackState.error] as is, since the locale may
/// differ by display time, and it expands here at paint time.
///
/// An unknown code shows as is: either the platform's own text or a ready
/// phrase (`LocalFileGone`).
library;

import '../../core/l10n/l10n.dart';
import '../settings/ui/yandex_screen.dart' show describeYmError;

/// Error code from a thrown exception. `StateError` adds its "Bad state: " to
/// the message, and the dictionary needs the bare code.
String playErrorCode(Object err) {
  const badState = 'Bad state: ';
  final s = err.toString();
  return s.startsWith(badState) ? s.substring(badState.length) : s;
}

/// The track failed on DRM. Platforms' codes differ, but one toast is needed.
bool isDrmError(String code) => code.toLowerCase().contains('drm');

/// Code to phrase.
String describePlayError(AppLocalizations l, String code) => switch (code) {
  'search.err.drm' || 'sc.err.drm' => l.errDrm,
  'search.err.noStream' || 'sc.err.noStream' || 'sc.err.noCdn' => l.errNoStream,
  'sc.err.unavailable' => l.errScUnavailable,
  'sc.err.forbidden' => l.errScForbidden,
  'sc.err.clientIdInvalid' || 'sc.err.clientIdExpired' => l.errScClientId,
  'ytm.err.noAudio' => l.errYtmNoAudio,
  'ytm.err.network' => l.errYtmNetwork,
  'ytm.err.trackNotFound' || 'ym.err.trackNotFound' => l.errTrackNotFound,
  _ when code.startsWith('ym.err.') => describeYmError(l, code),
  _ => code,
};
