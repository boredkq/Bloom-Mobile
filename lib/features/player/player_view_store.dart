/// Player view settings: title alignment, queue view and the Next plate. One
/// store (`playerView`) rather than a key per setting, so more can join with no
/// move that loses choices.
library;

import 'package:flutter/widgets.dart' show CrossAxisAlignment, TextAlign;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;

/// Where the track title and artist stand in the player. Centred by default.
enum TitleAlign {
  left,
  center,
  right;

  TextAlign get text => switch (this) {
    TitleAlign.left => TextAlign.left,
    TitleAlign.center => TextAlign.center,
    TitleAlign.right => TextAlign.right,
  };

  /// How rows sit in the caption column. [text] isn't enough: a row that fits
  /// is as wide as its text, so the column has to move it.
  CrossAxisAlignment get cross => switch (this) {
    TitleAlign.left => CrossAxisAlignment.start,
    TitleAlign.center => CrossAxisAlignment.center,
    TitleAlign.right => CrossAxisAlignment.end,
  };
}

final titleAlignProvider = NotifierProvider<TitleAlignController, TitleAlign>(
  TitleAlignController.new,
);

class TitleAlignController extends Notifier<TitleAlign> {
  @override
  TitleAlign build() {
    final raw = ref.read(jsonStoreProvider).readMap('playerView');
    // An unknown value silently becomes the default: alignment is no reason to
    // crash a launch.
    for (final v in TitleAlign.values) {
      if (v.name == raw['titleAlign']) return v;
    }
    return TitleAlign.center;
  }

  void set(TitleAlign align) {
    state = align;
    // Written over what was read, not as a bare object, so neighbouring
    // settings in `playerView` survive.
    final store = ref.read(jsonStoreProvider);
    store.write('playerView', {
      ...store.readMap('playerView'),
      'titleAlign': align.name,
    });
  }
}

/// Queue list view. [normal] is a flat list. [extended] splits it into Played,
/// Now playing and Next; the playing track is pinned there, and a drag stays
/// inside its section.
enum QueueView {
  normal,
  extended;

  bool get isExtended => this == QueueView.extended;
}

final queueViewProvider = NotifierProvider<QueueViewController, QueueView>(
  QueueViewController.new,
);

class QueueViewController extends Notifier<QueueView> {
  @override
  QueueView build() {
    final raw = ref.read(jsonStoreProvider).readMap('playerView');
    // `normal` by default; an unknown value silently becomes it, as with title
    // alignment.
    for (final v in QueueView.values) {
      if (v.name == raw['queueView']) return v;
    }
    return QueueView.normal;
  }

  void set(QueueView view) {
    state = view;
    final store = ref.read(jsonStoreProvider);
    store.write('playerView', {
      ...store.readMap('playerView'),
      'queueView': view.name,
    });
  }
}

/// Whether to show the Next plate under the slider: the track due after this
/// one. The queue is a sheet on a phone, so otherwise finding out means opening
/// it.
final nextUpProvider = NotifierProvider<NextUpController, bool>(
  NextUpController.new,
);

class NextUpController extends Notifier<bool> {
  @override
  bool build() {
    final raw = ref.read(jsonStoreProvider).readMap('playerView')['nextUp'];
    // On by default: off, nobody would ever see it.
    return raw is bool ? raw : true;
  }

  void set(bool on) {
    state = on;
    final store = ref.read(jsonStoreProvider);
    store.write('playerView', {...store.readMap('playerView'), 'nextUp': on});
  }
}
