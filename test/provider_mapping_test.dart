/// Mapping `ScRaw*` to common entities and parsing composite ids. No network.
///
/// This is the seam between the API and the shared UI, so I pin the places
/// where such a layer usually lies.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/providers/soundcloud/models.dart';
import 'package:bloom/providers/soundcloud/sc_provider.dart';
import 'package:bloom/providers/soundcloud/soundcloud.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('источник по префиксу id', () {
    expect(MusicSource.fromId('sc:123'), MusicSource.soundcloud);
    expect(MusicSource.fromId('sc:artist:123'), MusicSource.soundcloud);
    expect(MusicSource.fromId('ym:456'), MusicSource.yandex);
    expect(MusicSource.fromId('ytm:abc'), MusicSource.ytmusic);
    expect(MusicSource.fromId('local-file'), MusicSource.local);
  });

  test('числовой id вытаскивается из сквозного', () {
    expect(scNumericId(scTrackId(88335161)), 88335161);
    expect(scNumericId(scArtistId(42)), 42);
    expect(scNumericId(scSetId(7)), 7);
    // Junk doesn't crash the provider, it just finds nothing.
    expect(scNumericId('sc:artist:нечисло'), 0);
  });

  test('трек: длительность, пустые строки в null, сырьё для стрима', () {
    final raw = mapRawTrack({
      'id': 10,
      'title': 'Song',
      'duration': 185000,
      'genre': 'House',
      'label_name': '',
      'user': {'id': 5, 'username': 'Nick'},
      'media': {
        'transcodings': [
          {'url': 'https://x'},
        ],
      },
    });
    final track = trackFromSc(raw);

    expect(track.id, 'sc:10');
    expect(track.source, MusicSource.soundcloud);
    expect(track.duration, const Duration(milliseconds: 185000));
    // Empty SoundCloud fields ("", like label_name) mustn't reach the UI as
    // strings.
    expect(track.publisher, isNull);
    expect(track.album, isNull);
    expect(track.genres, ['house']);
    expect(track.artistId, 'sc:artist:5');
    // Without media there's nothing to resolve the stream with.
    expect(track.sourceData, isNotNull);
  });

  test('альбом: счётчик 0 у SC значит «неизвестно», а не ноль треков', () {
    final withCount = setFromSc(
      mapRawPlaylist({'id': 1, 'title': 'A', 'track_count': 14}),
      isAlbum: true,
    );
    expect(withCount.trackCount, 14);
    expect(withCount.isAlbum, isTrue);
    expect(withCount.id, 'sc:set:1');

    // A missing track_count comes as zero, and "0 tracks" under an album is
    // worse than nothing.
    final noCount = setFromSc(
      mapRawPlaylist({'id': 2, 'title': 'B'}),
      isAlbum: false,
    );
    expect(noCount.trackCount, isNull);
    expect(noCount.duration, isNull);
    expect(noCount.id, 'sc:set:2');
  });

  test('артист: username в name, full_name в fullName', () {
    final artist = artistFromSc(
      mapRawArtist({
        'id': 3,
        'username': 'skrillex',
        'full_name': 'Sonny Moore',
        'followers_count': 6700572,
      }),
    );
    expect(artist.id, 'sc:artist:3');
    expect(artist.name, 'skrillex');
    expect(artist.fullName, 'Sonny Moore');
  });

  test('пустой ScPage не ломает маппинг', () {
    const page = ScPage<ScRawTrack>(items: [], hasMore: false);
    expect(page.items.map(trackFromSc).toList(), isEmpty);
  });
}
