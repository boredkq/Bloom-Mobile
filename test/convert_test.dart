/// Moving a playlist to a platform: the scan, the track decisions and what the
/// copy holds.
///
/// The platform is fake: no network, I check how its results are parsed.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/music_provider.dart';
import 'package:bloom/features/library/convert_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(
  String id, {
  String name = 'Ночь',
  String artist = 'Один',
  int seconds = 200,
  MusicSource source = MusicSource.soundcloud,
}) => Track(
  id: id,
  name: name,
  artist: artist,
  duration: Duration(seconds: seconds),
  source: source,
);

/// Returns preset results per query; `null` means the platform failed.
class _FakeProvider extends MusicProvider {
  _FakeProvider(this.answers, {this.throwsOn = const {}});

  final Map<String, List<Track>> answers;
  final Set<String> throwsOn;

  /// How many requests went out: it shows the scan skips what's already on the
  /// platform.
  int calls = 0;

  @override
  MusicSource get source => MusicSource.ytmusic;

  @override
  Future<SearchResults> search(
    String query, {
    SearchSort sort = SearchSort.relevance,
  }) async {
    calls++;
    if (throwsOn.contains(query)) throw StateError('площадка не ответила');
    return SearchResults(tracks: answers[query] ?? const []);
  }
}

void main() {
  test('a confident match is filled in by itself', () async {
    final src = _track('sc:1');
    final provider = _FakeProvider({
      'Ночь Один': [_track('ytm:1', seconds: 201, source: MusicSource.ytmusic)],
    });

    final items = await scanPlaylistConversion(provider, [src]);
    expect(items.single.status, ConvertStatus.exact);

    final decisions = defaultDecisions(items);
    expect(convertResult(items, decisions).single.id, 'ytm:1');
  });

  test('a doubtful one stays the original until picked', () async {
    final src = _track('sc:1');
    final provider = _FakeProvider({
      // The same title but an hour longer, which the matcher doesn't call
      // confident.
      'Ночь Один': [
        _track('ytm:1', seconds: 3600, source: MusicSource.ytmusic),
      ],
    });

    final items = await scanPlaylistConversion(provider, [src]);
    expect(items.single.status, ConvertStatus.ambiguous);
    expect(convertResult(items, defaultDecisions(items)).single.id, 'sc:1');

    // A candidate picked by hand goes into the copy.
    final picked = {'sc:1': TakeMatch(items.single.cands.first.track)};
    expect(convertResult(items, picked).single.id, 'ytm:1');
  });

  test("a track already on the target platform isn't fetched", () async {
    final provider = _FakeProvider(const {});
    final items = await scanPlaylistConversion(provider, [
      _track('ytm:7', source: MusicSource.ytmusic),
    ]);

    expect(items.single.status, ConvertStatus.same);
    expect(items.single.cands, isEmpty);
    expect(provider.calls, 0);
  });

  test('a failed platform differs from an honest not found', () async {
    final provider = _FakeProvider(const {}, throwsOn: {'Ночь Один'});
    final items = await scanPlaylistConversion(provider, [_track('sc:1')]);

    expect(items.single.status, ConvertStatus.notfound);
    expect(items.single.failed, isTrue);
  });

  test("other platforms in the results don't become candidates", () async {
    final provider = _FakeProvider({
      'Ночь Один': [
        _track('sc:2', seconds: 200), // same track, not on the target
      ],
    });

    final items = await scanPlaylistConversion(provider, [_track('sc:1')]);
    expect(items.single.status, ConvertStatus.notfound);
    expect(items.single.failed, isFalse);
  });

  test(
    'a skipped track stays out of the copy, the others keep their order',
    () async {
      final provider = _FakeProvider({
        'Ночь Один': [
          _track('ytm:1', seconds: 200, source: MusicSource.ytmusic),
        ],
        'Утро Один': [
          _track(
            'ytm:2',
            name: 'Утро',
            seconds: 200,
            source: MusicSource.ytmusic,
          ),
        ],
      });
      final items = await scanPlaylistConversion(provider, [
        _track('sc:1'),
        _track('sc:2', name: 'Утро'),
      ]);

      final decisions = {...defaultDecisions(items), 'sc:1': const SkipTrack()};
      expect(convertResult(items, decisions).map((t) => t.id), ['ytm:2']);

      final stats = convertStats(items, decisions);
      expect(stats.moved, 1);
      expect(stats.skipped, 1);
      expect(stats.kept, 0);
    },
  );

  test('progress reaches the end and results keep their order', () async {
    final provider = _FakeProvider(const {});
    final tracks = [
      for (var i = 0; i < 7; i++) _track('sc:$i', name: 'Песня $i'),
    ];
    final progress = <int>[];

    final items = await scanPlaylistConversion(
      provider,
      tracks,
      onProgress: (done, _) => progress.add(done),
    );

    expect(items.map((i) => i.src.id), tracks.map((t) => t.id));
    expect(progress.last, 7);
  });

  test('cancelling stops the scan instead of finishing the list', () async {
    final provider = _FakeProvider(const {});
    var cancelled = false;
    final tracks = [
      for (var i = 0; i < 20; i++) _track('sc:$i', name: 'Песня $i'),
    ];

    final items = await scanPlaylistConversion(
      provider,
      tracks,
      cancelled: () => cancelled,
      onProgress: (done, _) {
        if (done >= 3) cancelled = true;
      },
    );

    expect(items.length, lessThan(tracks.length));
    expect(provider.calls, lessThan(tracks.length));
  });
}
