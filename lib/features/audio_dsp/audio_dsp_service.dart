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
  Future<void> apply(dynamic stateOrEnabled, {
    List<int>? bandLevels,
    int? bassBoost,
    int? virtualizer,
    double? safeGainDb,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final bool enabled;
    final List<int> bands;
    final int bass;
    final int virt;
    final double safeGain;

    if (stateOrEnabled is bool) {
      enabled = stateOrEnabled;
      bands = bandLevels ?? const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      bass = bassBoost ?? 0;
      virt = virtualizer ?? 0;
      safeGain = safeGainDb ?? 0.0;
    } else {
      // AudioDspState or duck-typed object
      final dynamic s = stateOrEnabled;
      enabled = s.enabled as bool;
      bands = (s.bandLevels ?? s.bands) as List<int>;
      bass = s.bassBoost as int;
      virt = s.virtualizer as int;
      safeGain = s.safeGainDb as double;
    }

    // Convert 10-band levels to millibels (-1200 mB to +1200 mB)
    final millibels = bands.map((lvl) {
      final db = AudioPresets.levelToDb(lvl);
      return (db * 100.0).round();
    }).toList();

    // Map 0-100% to 0-1000 native strength
    final nativeBass = (bass.clamp(0, 100) * 10).toInt();
    final nativeVirtualizer = (virt.clamp(0, 100) * 10).toInt();

    try {
      await _channel.invokeMethod<void>('apply', {
        'enabled': enabled,
        'bandLevels': millibels,
        'bassBoost': nativeBass,
        'virtualizer': nativeVirtualizer,
        'safeGainDb': safeGain,
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
