import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_dsp_models.dart';

/// Platform bridge connecting Equalizer, Bass Boost, and Virtualizer to Android AudioFX.
class AudioDspService {
  AudioDspService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('bloom/audio_fx');

  final MethodChannel _channel;
  int? _activeSessionId;

  int? get activeSessionId => _activeSessionId;

  /// Attaches AudioFX to an active playback audio session ID.
  Future<void> attach(int sessionId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _activeSessionId = sessionId;
    try {
      await _channel.invokeMethod<void>('attach', {'sessionId': sessionId});
    } catch (_) {}
  }

  /// Pushes current DSP parameters down to native Equalizer and AudioFX.
  Future<void> apply({
    required bool enabled,
    required List<int> bandLevels,
    required int bassBoost,
    required int virtualizer,
    required double safeGainDb,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    // Convert 10-band levels to millibels (-1200 mB to +1200 mB)
    final millibels = bandLevels.map((lvl) {
      final db = AudioPresets.levelToDb(lvl);
      return (db * 100.0).round();
    }).toList();

    // Map 0-100% to 0-1000 native strength
    final nativeBass = (bassBoost.clamp(0, 100) * 10).toInt();
    final nativeVirtualizer = (virtualizer.clamp(0, 100) * 10).toInt();

    try {
      await _channel.invokeMethod<void>('apply', {
        'enabled': enabled,
        'bandLevels': millibels,
        'bassBoost': nativeBass,
        'virtualizer': nativeVirtualizer,
        'safeGainDb': safeGainDb,
      });
    } catch (_) {}
  }

  /// Releases audio effects when session closes.
  Future<void> release() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _activeSessionId = null;
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
  }
}
