import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_signal.dart';
import 'fingerprint_engine.dart';
import 'models.dart';
import 'native_audio_recorder.dart';
import 'recognition_history.dart';
import 'shazam_api.dart';

final recognitionProvider =
    StateNotifierProvider.autoDispose<RecognitionController, RecognitionState>(
      (ref) => RecognitionController(
        recorder: const NativeAudioRecorder(),
        shazamClient: const ShazamClient(),
        fingerprintEngine: AcousticFingerprintEngine(),
        onMatch:
            (result) =>
                ref.read(recognitionHistoryProvider.notifier).add(result),
      ),
    );

class RecognitionController extends StateNotifier<RecognitionState> {
  RecognitionController({
    required NativeAudioRecorder recorder,
    required ShazamClient shazamClient,
    required AcousticFingerprintEngine fingerprintEngine,
    void Function(RecognitionResult result)? onMatch,
  }) : _recorder = recorder,
       _shazamClient = shazamClient,
       _engine = fingerprintEngine,
       _onMatch = onMatch,
       super(const RecognitionIdle());

  final NativeAudioRecorder _recorder;
  final ShazamClient _shazamClient;
  final AcousticFingerprintEngine _engine;
  final void Function(RecognitionResult result)? _onMatch;
  bool _cancelled = false;

  /// Starts listening via microphone and identifies the audio with Shazam.
  Future<void> startListening({int durationMs = 6500}) async {
    _cancelled = false;
    state = const RecognitionListening(progress: 0.0);

    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      final granted = await _recorder.requestPermission();
      if (!granted) {
        state = const RecognitionError(RecognitionErrorKind.permissionDenied);
        return;
      }
    }

    if (_cancelled) return;

    // Capture raw audio from platform recorder
    final rawBytes = await _recorder.captureAudio(durationMs: durationMs);
    if (_cancelled) return;

    if (rawBytes == null || rawBytes.isEmpty) {
      state = const RecognitionError(
        RecognitionErrorKind.unavailable,
        'Failed to capture audio',
      );
      return;
    }

    state = const RecognitionIdentifying();

    // Convert raw PCM bytes to Int16List mono
    final pcm16 = Int16List.view(
      rawBytes.buffer,
      rawBytes.offsetInBytes,
      rawBytes.lengthInBytes ~/ 2,
    );

    final quality = AudioSignalQuality.analyze(pcm16);
    if (quality.isSilent) {
      state = const RecognitionNoMatch();
      return;
    }

    final signature = _engine.fingerprint(pcm16);
    if (signature == null || signature.peakCount == 0) {
      state = const RecognitionNoMatch();
      return;
    }

    try {
      final result = await _shazamClient.identify(signature);
      if (_cancelled) return;

      if (result != null) {
        _onMatch?.call(result);
        state = RecognitionMatch(result);
      } else {
        state = const RecognitionNoMatch();
      }
    } catch (e) {
      if (!_cancelled) {
        state = RecognitionError(RecognitionErrorKind.network, e.toString());
      }
    }
  }

  /// Cancels any active capture or identification request.
  void cancel() {
    _cancelled = true;
    _recorder.cancelCapture();
    state = const RecognitionIdle();
  }

  /// Resets state back to idle.
  void reset() {
    _cancelled = false;
    state = const RecognitionIdle();
  }
}
