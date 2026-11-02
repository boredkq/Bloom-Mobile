/// Merging playlists: the join order and collapsing repeats.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/features/library/merge.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
  artist: 'Artist',
  duration: const Duration(seconds: 200),
  source: MusicSource.soundcloud,
);

List<Track> _list(List<String> ids) => [for (final id in ids) _track(id)];

void main() {
  test('the source playlist comes first, the others in the picked order', () {
    final merged = mergeTracks([
      _list(['a', 'b']),
      _list(['c']),
      _list(['d']),
    ], dedup: true);

    expect(merged.map((t) => t.id), ['a', 'b', 'c', 'd']);
  });

  test('a repeat stays at its first place', () {
    final merged = mergeTracks([
      _list(['a', 'b']),
      _list(['b', 'c']),
    ], dedup: true);

    expect(merged.map((t) => t.id), ['a', 'b', 'c']);
  });

  test('without collapsing a track lands as many times as it occurs', () {
    final merged = mergeTracks([
      _list(['a']),
      _list(['a']),
    ], dedup: false);

    expect(merged.map((t) => t.id), ['a', 'a']);
  });

  test('the repeat count counts what gets removed', () {
    final lists = [
      _list(['a', 'b']),
      _list(['b', 'c']),
      _list(['a']),
    ];

    expect(mergeDupCount(lists), 2);
    expect(mergeTracks(lists, dedup: true).length, 3);
  });

  test('empty lists break nothing', () {
    expect(mergeTracks([], dedup: true), isEmpty);
    expect(mergeDupCount([]), 0);
  });
}
