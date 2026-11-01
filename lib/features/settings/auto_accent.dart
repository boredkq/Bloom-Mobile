/// The auto accent: on each change of the playing cover I take its dominant
/// colour for the accent. The last tone stays in a field, so the level slider
/// recounts without touching the picture.
///
/// The auto theme uses the same scan: only what's built from the tone differs,
/// the accent or all three colours.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/settings_store.dart';
import '../player/player_controller.dart';
import 'cover_accent.dart';

final autoAccentProvider = Provider<AutoAccentBridge>((ref) {
  final bridge = AutoAccentBridge(ref);
  ref.listen(
    playbackProvider.select((s) => s.track?.cover),
    (_, _) => bridge.rescan(),
  );
  ref.listen(settingsProvider.select((s) => s.autoAccent), (_, _) {
    bridge.rescan();
  });
  ref.listen(settingsProvider.select((s) => s.autoTheme), (_, _) {
    bridge.rescan();
  });
  // Recounted from the known tone, no scan.
  ref.listen(settingsProvider.select((s) => s.autoAccentL), (_, _) {
    bridge.reapply();
  });
  bridge.rescan();
  return bridge;
});

class AutoAccentBridge {
  AutoAccentBridge(this._ref);

  final Ref _ref;

  CoverHsl? _last;

  /// A track may change while a cover loads: a late scan's colour must not
  /// apply.
  int _token = 0;

  Future<void> rescan() async {
    final settings = _ref.read(settingsProvider);
    final cover = _ref.read(playbackProvider).track?.cover;
    if (!settings.autoAccent && !settings.autoTheme) return;
    if (cover == null || cover.isEmpty) return;
    final my = ++_token;
    final hsl = await extractCoverHsl(cover);
    if (my != _token || hsl == null) return;
    _last = hsl;
    _apply(hsl);
  }

  void reapply() {
    final hsl = _last;
    if (hsl == null) {
      rescan();
      return;
    }
    _apply(hsl);
  }

  void _apply(CoverHsl hsl) {
    final settings = _ref.read(settingsProvider);
    final controller = _ref.read(settingsProvider.notifier);
    final accent = accentFromHsl(hsl, settings.autoAccentL);
    if (settings.autoTheme) {
      controller.applyAutoTheme(autoThemeSurfaceFromHsl(hsl), accent);
    } else {
      controller.applyAutoAccent(accent);
    }
  }
}
