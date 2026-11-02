/// Nightcore on iOS. just_audio has no `setPitch` there and holds pitch when
/// speed changes. A native channel switches AVPlayer's time-stretch algorithm
/// so pitch follows tempo. On Android plain `setPitch` does it, and the channel
/// doesn't exist.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('bloom/nightcore');

/// Tells iOS whether nightcore is on; does nothing elsewhere.
Future<void> setIosNightcore(bool on) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await _channel.invokeMethod<void>('set', on);
  } on PlatformException {
    // The channel didn't answer: tempo still works, only with no pitch.
  } on MissingPluginException {
    // Tests.
  }
}
