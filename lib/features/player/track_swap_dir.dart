/// Direction of the track change animation (see `TrackSwap`). +1 is forward
/// (the new track arrives from the right), −1 back (from the left).
///
/// Computed ONCE on the real change ([commitSwapDir] is called by
/// `PlaybackController._load`), not in widgets: the player and mini player must
/// go one way, and by repaint the old index is lost.
///
/// Priority: an explicit [markSwapDir] from previous or next (right even on a
/// queue loop, where comparing indices says the reverse), else comparison with
/// the last change's index. A new queue is forward: indices of different queues
/// don't compare.
library;

int _dir = 1;
int? _explicit;
bool _silent = false;
bool _silentPending = false;
List<Object?>? _lastQueue;
int _lastIndex = -1;

/// Direction of the last change, read by animation layers.
int get swapDir => _dir;

/// Whether the last change needs no animation: the gesture already carried the
/// content off (see [markSwapSilent]).
bool get swapSilent => _silent;

/// Sets the next change's direction explicitly (previous or next).
void markSwapDir(int d) => _explicit = d;

/// The next change isn't animated: a finger is pulling it. `TrackFlick` slides
/// the content off, changes the track and brings the new one in itself, and
/// `TrackSwap` layers on top would be a second animation inside the first. The
/// flag is one-shot, cleared by the next [commitSwapDir], so set it only on a
/// gesture that will SURELY change the track.
void markSwapSilent() => _silentPending = true;

/// Clears an unused [markSwapSilent]: there was a gesture with no change
/// (nothing to flick to, or previous mid-track seeks to the start). The flag
/// waits for the next change, and left up it would silence the next real one.
void cancelSwapSilent() => _silentPending = false;

/// Fixes the direction at the moment of change. [queue] and [index] are the
/// queue's new state.
void commitSwapDir(List<Object?> queue, int index) {
  if (_explicit != null) {
    _dir = _explicit!;
  } else if (identical(_lastQueue, queue) && index >= 0 && _lastIndex >= 0) {
    _dir = index < _lastIndex ? -1 : 1;
  } else {
    _dir = 1;
  }
  _explicit = null;
  _silent = _silentPending;
  _silentPending = false;
  _lastQueue = queue;
  _lastIndex = index;
}

/// Forgets what built up, only for tests: the module is global and leftovers
/// would leak into the next check.
void resetSwapDirForTest() {
  _dir = 1;
  _explicit = null;
  _silent = false;
  _silentPending = false;
  _lastQueue = null;
  _lastIndex = -1;
}
