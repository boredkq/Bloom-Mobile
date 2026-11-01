/// Is this the same track? The shared duplicate check. It isn't the platform
/// matcher, which picks the best of several candidates; this asks whether a
/// track is already among those picked, for recommendations and the wave.
///
/// Mostly it catches SoundCloud reuploads: one track from different users with
/// different ids. The uploader typically moves the author's name into the
/// title: "целоваться" by lightprey, "lightprey - целоваться" by クリソライト.
///
/// The key: I compare not title to title but one BAG of title and artist
/// together. Moving the name between fields then means nothing, and both
/// entries above give the same tokens.
library;

import '../../core/entities/entities.dart';

final RegExp _brackets = RegExp(r'\(.*?\)|\[.*?\]');
final RegExp _nonWord = RegExp(r'[^a-zа-я0-9]+');

/// Normalizes: lower case, ё→е, no bracketed notes, only Latin, Cyrillic and
/// digits.
String normText(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(_brackets, ' ')
    .replaceAll(_nonWord, ' ')
    .trim();

/// Noise words that don't make a track different. `prod` and `feat` especially:
/// reuploads scatter them at random.
///
/// Short on purpose: free, out and now are real titles, and striking them would
/// turn a short title into an empty set.
const Set<String> _noise = {
  'feat', 'ft', 'featuring', 'prod', 'by', 'the', 'a', 'an', 'and', 'и', //
  'official', 'audio', 'video', 'lyrics', 'hd', 'hq', //
  'remaster', 'remastered', 'version', 'edition', 'bonus', 'track',
};

/// Significant tokens of a string, no noise or blanks.
List<String> textTokens(String s) => [
  for (final w in normText(s).split(' '))
    if (w.isNotEmpty && !_noise.contains(w)) w,
];

/// Share of the smaller set found in the larger (0..1).
double containment(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var inter = 0;
  for (final t in a) {
    if (b.contains(t)) inter++;
  }
  return inter / (a.length < b.length ? a.length : b.length);
}

/// A parsed track: exact key, token bags and duration.
class TrackFingerprint {
  TrackFingerprint({
    required String name,
    required String artist,
    this.seconds = 0,
  }) {
    final n = textTokens(name);
    core = {...n, ...textTokens(artist)};
    title = n.toSet();
    key = (core.toList()..sort()).join(' ');
    titleKey = (title.toList()..sort()).join(' ');
  }

  factory TrackFingerprint.of(Track t) => TrackFingerprint(
    name: t.name,
    artist: t.artist,
    seconds: t.duration.inSeconds,
  );

  /// Title and artist as one set; see the top of the file.
  late final Set<String> core;

  /// Title only, the main sign of a reupload; see [sameTrack].
  late final Set<String> title;

  /// Exact key of the shared bag, a fast path for pairs that match fully.
  late final String key;

  late final String titleKey;

  /// Duration in seconds; 0 means unknown.
  final int seconds;
}

/// How close bags must be to count as one track. A reupload gives 1.0, two
/// DIFFERENT tracks by one artist at most about 0.67 (only the artist's name in
/// common).
const double _coreMin = 0.85;

/// Duration difference within which it's still the same track, seconds.
const int _durTolerance = 5;

/// The same tolerance for pairs with a FULLY matching title. Wider: reuploads
/// survive re-encoding, an uploader's intro and trailing silence.
const int _durToleranceSameTitle = 25;

/// A one-token bag matches anything, so the fuzzy path needs at least two
/// significant words.
const int _coreMinTokens = 2;

/// How many significant words make a title distinct enough that a full match
/// can't be chance. "I love you" can, "Серега пират team spirit" can't.
const int _titleRichTokens = 4;

/// Whether this is one track. Three paths, most reliable first: the shared
/// title and artist bag matches; the whole TITLE matches, the main sign of a
/// reupload (a long title won't match by chance, a short one also checks
/// duration); or titles are only similar, which needs both a close bag and a
/// close duration.
///
/// Duration is the safeguard: if it's unknown, the loose paths are closed.
bool sameTrack(TrackFingerprint a, TrackFingerprint b) {
  if (a.key.isNotEmpty && a.key == b.key) return true;

  final dur = a.seconds > 0 && b.seconds > 0
      ? (a.seconds - b.seconds).abs()
      : null;

  if (a.titleKey.isNotEmpty && a.titleKey == b.titleKey) {
    final shorter = a.title.length < b.title.length
        ? a.title.length
        : b.title.length;
    if (shorter >= _titleRichTokens) return true;
    return dur != null && dur <= _durToleranceSameTitle;
  }

  if (dur == null || dur > _durTolerance) return false;
  if (a.core.length < _coreMinTokens || b.core.length < _coreMinTokens) {
    return false;
  }
  return containment(a.core, b.core) >= _coreMin;
}

/// Collects unique tracks: [accept] returns `false` if a track was already
/// accepted or marked with [add].
///
/// There can be thousands of marked ones (the whole library and everything
/// heard), so fuzzy comparison runs only over prints sharing a word, not all of
/// them. This isn't an approximation: every path of [sameTrack] needs at least
/// one common token.
class DupGuard {
  final Set<String> _keys = {};
  final Map<String, List<TrackFingerprint>> _byToken = {};

  /// Marks a track as already present (library, queue) without yielding it.
  void add(Track t) => addPrint(TrackFingerprint.of(t));

  /// The same for a track with only a snapshot left (play journal).
  void addPrint(TrackFingerprint fp) {
    if (fp.key.isEmpty) return; // an empty bag matches nothing
    _keys.add(fp.key);
    for (final w in fp.core) {
      (_byToken[w] ??= []).add(fp);
    }
  }

  /// Accepts a track if it's new.
  bool accept(Track t) => acceptPrint(TrackFingerprint.of(t));

  bool acceptPrint(TrackFingerprint fp) {
    if (fp.key.isEmpty) return true; // nothing to compare, so let it through
    if (_keys.contains(fp.key)) return false;
    final checked = Set<TrackFingerprint>.identity();
    for (final w in fp.core) {
      for (final p in _byToken[w] ?? const <TrackFingerprint>[]) {
        if (checked.add(p) && sameTrack(fp, p)) return false;
      }
    }
    addPrint(fp);
    return true;
  }
}
