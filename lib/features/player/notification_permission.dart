/// Asks for notification permission (Android 13+). Without `POST_NOTIFICATIONS`
/// the playback shade just DOESN'T SHOW: the service lives and sound plays,
/// with no controls in the shade or on the lock screen.
///
/// No plugin for one permission: a couple of lines natively will do. On iOS and
/// Android before 13 the channel answers `false` and does nothing.
library;

import 'package:flutter/services.dart';

const _channel = MethodChannel('bloom/notifications');

/// Asks if not yet granted. I don't wait for the dialog: it's the system's and
/// doesn't affect playback.
Future<void> ensureNotificationPermission() async {
  try {
    await _channel.invokeMethod<bool>('ensure');
  } on PlatformException {
    // No answer from the channel is no reason not to play.
  } on MissingPluginException {
    // iOS and tests.
  }
}
