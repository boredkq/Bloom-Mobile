import 'package:flutter/services.dart';

/// Access to platform native microphone recording via MethodChannel.
class NativeAudioRecorder {
  const NativeAudioRecorder({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('bloom/recognition');

  final MethodChannel _channel;

  /// Checks if RECORD_AUDIO permission has been granted.
  Future<bool> hasPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('hasPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Prompts system permission dialog for RECORD_AUDIO.
  Future<bool> requestPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('requestPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Captures PCM16 Mono 16kHz audio for the given duration in milliseconds.
  /// Returns raw audio byte array.
  Future<Uint8List?> captureAudio({int durationMs = 6000}) async {
    try {
      final res = await _channel.invokeMethod<Uint8List>('captureAudio', {
        'durationMs': durationMs,
      });
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Cancels an in-progress capture session early.
  Future<void> cancelCapture() async {
    try {
      await _channel.invokeMethod<void>('cancelCapture');
    } catch (_) {}
  }
}
