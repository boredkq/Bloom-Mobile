/// SoundCloud mapping with no network: JS-falsy fallbacks, `-large` to
/// `-t300x300`, the year from release_date/created_at.
library;

import 'package:bloom/providers/soundcloud/soundcloud.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('track: t300 cover, year, tags, publisher', () {
    final t = mapRawTrack({
      'id': 1,
      'title': 'Song',
      'artwork_url': 'https://i1.sndcdn.com/artworks-abc-large.jpg',
      'duration': 185000,
      'tag_list': 'house  techno',
      'created_at': '2019-05-01T00:00:00Z',
      'label_name': '',
      'user': {'username': 'Nick', 'id': 42, 'verified': true},
      'publisher_metadata': {'publisher': 'Label', 'explicit': 1},
    });

    expect(t.artwork, 'https://i1.sndcdn.com/artworks-abc-t300x300.jpg');
    expect(t.year, '2019');
    expect(t.tags, ['house', 'techno']);
    // An empty label_name is JS-falsy and falls through to publisher_metadata.
    expect(t.publisher, 'Label');
    expect(t.explicit, isTrue);
    expect(t.artistVerified, isTrue);
    expect(t.artistScId, 42);
  });

  test('track: release_date beats created_at, no user gives Unknown', () {
    final t = mapRawTrack({
      'id': 2,
      'release_date': '2021-09-09T00:00:00Z',
      'created_at': '2023-01-01T00:00:00Z',
    });
    expect(t.year, '2021');
    expect(t.artist, 'Unknown');
    expect(t.title, '');
    expect(t.media, isNull);
  });

  test('playlist: album year, cover from calculated_artwork_url', () {
    final p = mapRawPlaylist({
      'id': 7,
      'title': 'Album',
      'artwork_url': '',
      'calculated_artwork_url': 'https://i1.sndcdn.com/x-large.jpg',
      'release_date': '2020-02-02',
      'created_at': '2024-02-02',
      'track_count': 12,
      'user': {'username': 'Owner', 'avatar_url': 'https://a/av-large.jpg'},
    });
    expect(p.artwork, 'https://i1.sndcdn.com/x-t300x300.jpg');
    expect(p.year, '2020');
    expect(p.trackCount, 12);
    expect(p.artistAvatar, 'https://a/av-t300x300.jpg');
  });

  test('stream: DRM-only gives the code sc.err.drm', () async {
    await expectLater(
      streamUrl({
        'transcodings': [
          {
            'url': 'https://x',
            'format': {'protocol': 'encrypted-hls'},
          },
        ],
      }),
      throwsA(predicate((e) => e.toString() == 'sc.err.drm')),
    );
  });

  test('stream: empty transcodings give search.err.noStream', () async {
    await expectLater(
      streamUrl(null),
      throwsA(predicate((e) => e.toString() == 'search.err.noStream')),
    );
  });

  // Downloading takes only progressive: HLS is a playlist of chunks and can't
  // be saved as a file. Such a track still plays; only saving must fail, with a
  // clear code rather than "no stream".
  test('download: an HLS-only track gives the code sc.err.hlsOnly', () async {
    final media = {
      'transcodings': [
        {
          'url': 'https://x',
          'format': {'protocol': 'hls'},
        },
      ],
    };
    await expectLater(
      streamUrl(media, progressiveOnly: true),
      throwsA(predicate((e) => e.toString() == 'sc.err.hlsOnly')),
    );
  });
}
