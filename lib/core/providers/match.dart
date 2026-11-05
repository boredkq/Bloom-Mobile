/// Matches one track across DIFFERENT platforms, for Change platform (best
/// candidate) and Transfer to platform (a ranked list, with doubtful ones going
/// to manual choice).
///
/// Score = 0.65 × title similarity + 0.35 × artist similarity, adjusted by
/// version and duration. Title and artist differ on purpose: the title is
/// symmetric (Jaccard), since extra words usually mean another song; the artist
/// is by containment, since "Artist A, Artist B" and "Artist A" are the same
/// track.
library;

import '../entities/entities.dart';

/// Normalizes: lower case, no bracketed notes, only letters and digits.
String _norm(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .trim();

/// Noise words that don't make a track different.
const Set<String> _noise = {
  'feat',
  'ft',
  'featuring',
  'prod',
  'by',
  'the',
  'a',
  'an',
  'and',
  'и',
  'official',
  'audio',
  'video',
  'lyrics',
  'hd',
  'hq',
  'remaster',
  'remastered',
  'version',
  'edition',
  'bonus',
  'track',
};

Set<String> _tokens(String s) => {
  for (final w in _norm(s).split(' '))
    if (w.isNotEmpty && !_noise.contains(w)) w,
};

/// Jaccard over token sets (1 is a full match, 0 no overlap).
double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final inter = a.intersection(b).length;
  return inter / (a.length + b.length - inter);
}

/// Containment: share of the smaller set found in the larger.
double _containment(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  return a.intersection(b).length / (a.length < b.length ? a.length : b.length);
}

/// Words that make another version of a song. They usually stand in brackets,
/// which [_norm] leaves out: "Tokyo (Slowed)" isn't "Tokyo" for sure, though it
/// may be the closest there is.
const Set<String> _versionWords = {
  'slowed',
  'slow',
  'sped',
  'speed',
  'nightcore',
  'reverb',
  'reverbed',
  'remix',
  'rmx',
  'live',
  'acoustic',
  'instrumental',
  'karaoke',
  'cover',
  'acapella',
  'mashup',
  'bootleg',
  'hardtekk',
  'hardstyle',
  'boosted',
  '8d',
  'lofi',
  'ремикс',
  'кавер',
};

Set<String> _versionOf(String title) => {
  for (final word in title.toLowerCase().split(RegExp(r'[^a-zа-яё0-9]+')))
    if (_versionWords.contains(word)) word,
};

/// What versions differing costs: enough to send a sure match to the user's
/// choice, not enough to hide it.
const double _otherVersion = 0.6;

/// Duration difference past which the score nearly zeroes.
const Duration _hardDurDelta = Duration(seconds: 20);

/// Difference that costs only a little (other masters, trailing silence).
const Duration _softDurDelta = Duration(seconds: 5);

/// Candidate's similarity to the source track, 0..1. Duration is a factor, not
/// a term: past [_hardDurDelta] it's nearly always another thing (a mix, an
/// hour-long compilation, slowed), and no title match outweighs that. If either
/// duration is unknown, no factor.
double matchScore(Track cand, Track src) {
  final nameA = _tokens(src.name);
  final nameB = _tokens(cand.name);
  final artA = _tokens(src.artist);
  final artB = _tokens(cand.artist);

  // The artist may be glued to the title (common on YTM videos: "Artist -
  // Song"), so I also look for artist tokens in the title.
  final artScore = [
    _containment(artA, artB),
    artA.isEmpty ? 0.0 : _containment(artA, {...nameB, ...artB}) * 0.9,
  ].reduce((a, b) => a > b ? a : b);

  var score = 0.65 * _jaccard(nameA, nameB) + 0.35 * artScore;

  final versionA = _versionOf(src.name);
  final versionB = _versionOf(cand.name);
  if (versionA.length != versionB.length || !versionA.containsAll(versionB)) {
    score *= _otherVersion;
  }

  final want = src.duration;
  final got = cand.duration;
  if (want > Duration.zero && got > Duration.zero) {
    final delta = (want - got).abs();
    if (delta > _hardDurDelta) {
      score *= 0.35;
    } else if (delta > _softDurDelta) {
      score *= 0.8;
    } else {
      score = score + 0.05 > 1 ? 1 : score + 0.05;
    }
  }
  return score;
}

/// A candidate with its score.
class ScoredMatch {
  const ScoredMatch(this.track, this.score);

  final Track track;
  final double score;
}

/// Ranks a platform's results against the source track: at most [limit] with a
/// score ≥ [min], best first.
List<ScoredMatch> rankMatches(
  List<Track> cands,
  Track src, {
  int limit = 5,
  double min = 0,
}) {
  final scored = [
    for (final track in cands)
      if (matchScore(track, src) case final score when score >= min)
        ScoredMatch(track, score),
  ];
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.length > limit ? scored.sublist(0, limit) : scored;
}

/// Score from which a match is trusted with no questions. High on purpose: in a
/// hundred-track playlist a matcher error isn't visible, and manual choice
/// beats silently collecting covers.
const double kAutoMatchScore = 0.72;

/// Below this a candidate isn't shown at all: it's another track.
const double kMinMatchScore = 0.28;
