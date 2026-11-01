/// Transfer to platform: a copy of a playlist built from another platform's
/// tracks. Each track is searched by title and artist, and [rankMatches] ranks
/// the results. Confident matches go in by themselves; doubtful and missing
/// ones wait for the user.
///
/// The source playlist doesn't change: the result is ALWAYS a new playlist,
/// unlike Change platform, which replaces the library entry in place.
library;

import '../../core/entities/entities.dart';
import '../../core/providers/match.dart';
import '../../core/providers/music_provider.dart';

/// Candidates shown in manual choice.
const int kConvertCandLimit = 5;

/// Tracks searched at once, sparing platform APIs. One by one a hundred tracks
/// feels endless, and full parallel hits limits.
const int kConvertConcurrency = 3;

enum ConvertStatus {
  /// Already on the target platform, nothing to transfer.
  same,

  /// Found confidently (score ≥ [kAutoMatchScore]).
  exact,

  /// There are candidates, none confident: manual choice needed.
  ambiguous,

  /// Nothing similar, or the platform answered with an error.
  notfound,
}

class ConvertItem {
  const ConvertItem({
    required this.src,
    required this.status,
    this.cands = const [],
    this.failed = false,
  });

  /// The source track from the playlist.
  final Track src;

  final ConvertStatus status;

  /// Ranked candidates (empty for `same` and `notfound`).
  final List<ScoredMatch> cands;

  /// The platform answered with an error, which differs from an honest nothing
  /// found.
  final bool failed;
}

/// What the track enters the new playlist as.
sealed class ConvertDecision {
  const ConvertDecision();
}

/// Keeps the source track as is.
class KeepOriginal extends ConvertDecision {
  const KeepOriginal();
}

/// Takes the version found on the target platform.
class TakeMatch extends ConvertDecision {
  const TakeMatch(this.track);
  final Track track;
}

/// Leaves the track out of the new playlist.
class SkipTrack extends ConvertDecision {
  const SkipTrack();
}

/// Runs tracks through search on the target platform. [onProgress] fires after
/// EACH track, for the progress bar. [cancelled] stops the scan: done ones
/// return and the rest aren't requested.
Future<List<ConvertItem>> scanPlaylistConversion(
  MusicProvider provider,
  List<Track> tracks, {
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final total = tracks.length;
  final out = List<ConvertItem?>.filled(total, null);
  var cursor = 0;
  var done = 0;

  Future<void> runOne(int i) async {
    final src = tracks[i];
    if (src.source == provider.source) {
      out[i] = ConvertItem(src: src, status: ConvertStatus.same);
      return;
    }
    var failed = false;
    var found = const <Track>[];
    try {
      found = (await provider.search(
        '${src.name} ${src.artist}'.trim(),
      )).tracks;
    } catch (_) {
      failed = true;
    }
    // A platform's results may include other platforms' tracks, so I take only
    // those really from the target.
    final cands = rankMatches(
      [
        for (final t in found)
          if (t.source == provider.source) t,
      ],
      src,
      limit: kConvertCandLimit,
      min: kMinMatchScore,
    );
    out[i] = ConvertItem(
      src: src,
      status: cands.isEmpty
          ? ConvertStatus.notfound
          : cands.first.score >= kAutoMatchScore
          ? ConvertStatus.exact
          : ConvertStatus.ambiguous,
      cands: cands,
      failed: failed,
    );
  }

  // Worker pool: result order holds (written by index), with at most
  // [kConvertConcurrency] requests in flight.
  Future<void> worker() async {
    while (true) {
      if (cancelled?.call() ?? false) return;
      final i = cursor++;
      if (i >= total) return;
      await runOne(i);
      done++;
      onProgress?.call(done, total);
    }
  }

  await Future.wait([
    for (
      var i = 0;
      i < (total < kConvertConcurrency ? total : kConvertConcurrency);
      i++
    )
      worker(),
  ]);
  return out.whereType<ConvertItem>().toList();
}

/// What goes in by itself: a confident match as the new version; the rest stays
/// original until the user decides otherwise.
Map<String, ConvertDecision> defaultDecisions(List<ConvertItem> items) => {
  for (final item in items)
    item.src.id: item.status == ConvertStatus.exact && item.cands.isNotEmpty
        ? TakeMatch(item.cands.first.track)
        : const KeepOriginal(),
};

/// The new playlist's contents by accepted decisions, in source order.
List<Track> convertResult(
  List<ConvertItem> items,
  Map<String, ConvertDecision> decisions,
) => [
  for (final item in items)
    ?switch (decisions[item.src.id] ?? const KeepOriginal()) {
      TakeMatch(:final track) => track,
      KeepOriginal() => item.src,
      // A skipped track isn't in the list at all: the null element drops.
      SkipTrack() => null,
    },
];

/// How many went where, for the count line under the list.
({int moved, int kept, int skipped}) convertStats(
  List<ConvertItem> items,
  Map<String, ConvertDecision> decisions,
) {
  var moved = 0;
  var kept = 0;
  var skipped = 0;
  for (final item in items) {
    switch (decisions[item.src.id] ?? const KeepOriginal()) {
      case TakeMatch():
        moved++;
      case KeepOriginal():
        kept++;
      case SkipTrack():
        skipped++;
    }
  }
  return (moved: moved, kept: kept, skipped: skipped);
}
