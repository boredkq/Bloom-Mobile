import 'package:bloom/features/offline/file_download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('largeCoverUrl', () {
    test('Yandex: 400x400 → 1000x1000', () {
      expect(
        largeCoverUrl(
          'https://avatars.yandex.net/get-music-content/123/abc/400x400',
        ),
        'https://avatars.yandex.net/get-music-content/123/abc/1000x1000',
      );
    });

    test('SoundCloud: t500x500 → original', () {
      expect(
        largeCoverUrl('https://i1.sndcdn.com/artworks-XyZ-t500x500.jpg'),
        'https://i1.sndcdn.com/artworks-XyZ-original.jpg',
      );
    });

    test('YouTube Music: w544-h544 → w1200-h1200', () {
      expect(
        largeCoverUrl('https://lh3.googleusercontent.com/abc=w544-h544-l90-rj'),
        'https://lh3.googleusercontent.com/abc=w1200-h1200-l90-rj',
      );
    });

    test('a foreign link stays unchanged', () {
      const url = 'https://example.com/cover.jpg';
      expect(largeCoverUrl(url), url);
    });
  });
}
