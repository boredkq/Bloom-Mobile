/// Mini player look: card background, progress indicators, cover shape and
/// corner rounding, plus buttons ([MiniButton]) and neighbours
/// ([MiniStyle.neighbors]).
///
/// The card lies in plain view above the tab bar, so rounding has four steps
/// rather than two.
library;

import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../settings/cover_accent.dart';

/// Card background.
enum MiniBg {
  /// The theme's plate, like the rest of the chrome.
  theme,

  /// A fill of the cover's dark dominant colour.
  coverColor,

  /// The cover itself as a picture under the content.
  cover,
}

/// Cover shape in the card.
enum MiniCoverShape { rounded, circle }

/// Card corner rounding.
enum MiniRadius {
  /// Square corners.
  none,

  /// Half the theme radius.
  soft,

  /// The theme radius, like other plates.
  rounded,

  /// A pill: rounding of half the height.
  pill,
}

/// Progress indicators are a set, not a choice: they don't conflict.
class MiniProgress {
  const MiniProgress({this.line = true, this.fill = false, this.ring = false});

  /// Line along the card's bottom edge.
  final bool line;

  /// Background fill from left to right.
  final bool fill;

  /// Ring around the cover.
  final bool ring;

  MiniProgress copyWith({bool? line, bool? fill, bool? ring}) => MiniProgress(
    line: line ?? this.line,
    fill: fill ?? this.fill,
    ring: ring ?? this.ring,
  );
}

/// What a row in the progress indicators sheet toggles.
enum MiniProgressKind { line, fill, ring }

/// A button in the card, in row order. Like opens the group: it isn't about
/// skipping, and shouldn't split previous, play and next.
///
/// The card is as wide as the screen and room runs out, so choosing what
/// matters is real.
enum MiniButton { fav, prev, play, next }

/// The default is the skip trio. Like is off: on, it would squeeze the caption
/// for everyone who never opened the setting.
const Set<MiniButton> kDefaultMiniButtons = {
  MiniButton.prev,
  MiniButton.play,
  MiniButton.next,
};

class MiniStyle {
  const MiniStyle({
    this.bg = MiniBg.theme,
    this.progress = const MiniProgress(),
    this.progressTint = false,
    this.shape = MiniCoverShape.rounded,
    this.radius = MiniRadius.rounded,
    this.buttons = kDefaultMiniButtons,
    this.neighbors = false,
  });

  final MiniBg bg;
  final MiniProgress progress;

  /// Indicators take the cover's accent instead of the theme's.
  final bool progressTint;
  final MiniCoverShape shape;
  final MiniRadius radius;
  final Set<MiniButton> buttons;

  /// Neighbours: the card narrows, the previous and next tracks' cards peek out
  /// at its edges, and all three follow the finger as a carousel.
  final bool neighbors;

  bool has(MiniProgressKind kind) => switch (kind) {
    MiniProgressKind.line => progress.line,
    MiniProgressKind.fill => progress.fill,
    MiniProgressKind.ring => progress.ring,
  };

  /// Whether the tint has anything to paint. The line and the ring always take
  /// it; the fill on a cover colour card already has the track's own tone.
  bool get progressTintUseful =>
      progress.line ||
      progress.ring ||
      (progress.fill && bg != MiniBg.coverColor);

  bool hasButton(MiniButton button) => buttons.contains(button);

  MiniStyle copyWith({
    MiniBg? bg,
    MiniProgress? progress,
    bool? progressTint,
    MiniCoverShape? shape,
    MiniRadius? radius,
    Set<MiniButton>? buttons,
    bool? neighbors,
  }) => MiniStyle(
    bg: bg ?? this.bg,
    progress: progress ?? this.progress,
    progressTint: progressTint ?? this.progressTint,
    shape: shape ?? this.shape,
    radius: radius ?? this.radius,
    buttons: buttons ?? this.buttons,
    neighbors: neighbors ?? this.neighbors,
  );
}

final miniStyleProvider = NotifierProvider<MiniStyleController, MiniStyle>(
  MiniStyleController.new,
);

class MiniStyleController extends Notifier<MiniStyle> {
  @override
  MiniStyle build() {
    final raw = ref.read(jsonStoreProvider).readMap('miniStyle');
    final progress = raw['progress'];
    return MiniStyle(
      bg: _enumFromJson(MiniBg.values, raw['bg'], MiniBg.theme),
      progress: progress is Map
          ? MiniProgress(
              // The key may be missing altogether, so I take the default, not
              // off.
              line: progress['line'] as bool? ?? true,
              fill: progress['fill'] as bool? ?? false,
              ring: progress['ring'] as bool? ?? false,
            )
          : const MiniProgress(),
      progressTint: raw['progressTint'] == true,
      shape: _enumFromJson(
        MiniCoverShape.values,
        raw['shape'],
        MiniCoverShape.rounded,
      ),
      radius: _enumFromJson(
        MiniRadius.values,
        raw['radius'],
        MiniRadius.rounded,
      ),
      // No key takes the default; an empty list is a CHOICE of no buttons and
      // must not be replaced.
      buttons: raw['buttons'] is List
          ? {
              for (final button in MiniButton.values)
                if ((raw['buttons']! as List).contains(button.name)) button,
            }
          : kDefaultMiniButtons,
      // `==`, not a cast: the file could hold anything, and a card's look can't
      // crash a launch.
      neighbors: raw['neighbors'] == true,
    );
  }

  void setBg(MiniBg bg) => _set(state.copyWith(bg: bg));

  void setShape(MiniCoverShape shape) => _set(state.copyWith(shape: shape));

  void setRadius(MiniRadius radius) => _set(state.copyWith(radius: radius));

  void toggleProgress(MiniProgressKind kind, bool on) => _set(
    state.copyWith(
      progress: switch (kind) {
        MiniProgressKind.line => state.progress.copyWith(line: on),
        MiniProgressKind.fill => state.progress.copyWith(fill: on),
        MiniProgressKind.ring => state.progress.copyWith(ring: on),
      },
    ),
  );

  void setProgressTint(bool on) => _set(state.copyWith(progressTint: on));

  void setNeighbors(bool on) => _set(state.copyWith(neighbors: on));

  void toggleButton(MiniButton button, bool on) {
    final buttons = {...state.buttons};
    if (on) {
      buttons.add(button);
    } else {
      buttons.remove(button);
    }
    _set(state.copyWith(buttons: buttons));
  }

  void _set(MiniStyle next) {
    state = next;
    ref.read(jsonStoreProvider).write('miniStyle', {
      'bg': next.bg.name,
      'progress': {
        'line': next.progress.line,
        'fill': next.progress.fill,
        'ring': next.progress.ring,
      },
      'progressTint': next.progressTint,
      'shape': next.shape.name,
      'radius': next.radius.name,
      'buttons': [
        for (final button in MiniButton.values)
          if (next.buttons.contains(button)) button.name,
      ],
      'neighbors': next.neighbors,
    });
  }
}

/// Enum value from the store. A broken or unknown entry silently becomes the
/// default: a card's look is no reason to crash a launch.
T _enumFromJson<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

/// One scan per cover, shared by the card's background and the progress tint.
/// The key is the cover link, not the track: the card may show a custom
/// picture, and the colour must come from what's visible.
final _miniCoverHslProvider = FutureProvider.autoDispose
    .family<CoverHsl?, String?>((ref, cover) => extractCoverHsl(cover));

/// The cover's dark dominant, the card background in cover colour mode. `null`:
/// no cover or unreadable, so the theme's plate stays.
final miniCoverColorProvider = FutureProvider.autoDispose
    .family<Color?, String?>((ref, cover) async {
      final hsl = await ref.watch(_miniCoverHslProvider(cover).future);
      return hsl == null ? null : miniBgFromHsl(hsl);
    });

/// How light the progress tint is, whatever the auto accent's level: a thin
/// line has to read on a dark card.
const double _miniTintLevel = 0.5;

/// The cover's accent for the progress indicators. `null`: no cover or
/// unreadable, so they keep the theme's accent.
final miniProgressTintProvider = FutureProvider.autoDispose
    .family<Color?, String?>((ref, cover) async {
      final hsl = await ref.watch(_miniCoverHslProvider(cover).future);
      return hsl == null ? null : accentFromHsl(hsl, _miniTintLevel);
    });
