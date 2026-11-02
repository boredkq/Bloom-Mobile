/// Preset file names (`.bloompresets`). The system dialogs live in the channel
/// shared with playlist transfer and the log.
library;

export '../../core/store/text_files.dart' show openTextFile, saveTextFile;

/// Preset file extension.
const String kPresetsExt = 'bloompresets';

/// File name for exporting all presets: `bloom-presets-2026-08-15`.
String presetsFileName() {
  final now = DateTime.now();
  final date = '${now.year}-${_two(now.month)}-${_two(now.day)}';
  return 'bloom-presets-$date.$kPresetsExt';
}

/// File name of one preset, with characters forbidden in paths replaced.
String presetFileName(String name) {
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  final base = safe.isEmpty
      ? 'preset'
      : safe.substring(0, safe.length.clamp(0, 60));
  return '$base.$kPresetsExt';
}

String _two(int v) => v.toString().padLeft(2, '0');
