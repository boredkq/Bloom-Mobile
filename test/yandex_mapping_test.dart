/// Yandex Music parsing and mapping with no network: ids as numbers and
/// strings, the `%%` cover to 400x400, the year from the first album, both
/// playlist formats, the direct link signature.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/providers/yandex/models.dart';
import 'package:bloom/providers/yandex/ym_provider.dart';
import 'package:bloom/providers/yandex/yandex.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('разбор выдачи', () {
    test('трек: id числом, артисты через запятую, обложка, год из альбома', () {
      final t = parseTrack({
        'id': 42,
        'title': 'Песня',
        'artists': [
          {'id': 7, 'name': 'Первый'},
          {'id': 8, 'name': 'Второй'},
        ],
        'coverUri': 'avatars.yandex.net/get-music/1/%%',
        'durationMs': 185000,
        'albums': [
          {'year': 2019},
        ],
      })!;

      expect(t.id, '42');
      expect(t.artist, 'Первый, Второй');
      expect(t.artistId, '7');
      expect(t.artists, [(id: '7', name: 'Первый'), (id: '8', name: 'Второй')]);
      expect(trackFromYm(t).artists.last, (name: 'Второй', id: 'ym:artist:8'));
      expect(t.cover, 'https://avatars.yandex.net/get-music/1/400x400');
      expect(t.duration, const Duration(milliseconds: 185000));
      expect(t.year, '2019');
      // No available field: Yandex only stays silent about available ones.
      expect(t.available, isTrue);
    });

    test('трек: без артистов и id — дефолты площадки, id строкой', () {
      final t = parseTrack({'id': '99', 'available': false})!;
      expect(t.id, '99');
      expect(t.title, kYmUntitled);
      expect(t.artist, kYmUnknownArtist);
      expect(t.artistId, '');
      expect(t.cover, '');
      expect(t.year, '');
      expect(t.available, isFalse);

      // With no id at all an item isn't a track, and such result rows get
      // skipped.
      expect(parseTrack({'title': 'x'}), isNull);
    });

    test('обложка берётся из coverUri, cover.uri или ogImage', () {
      expect(coverFrom({'coverUri': 'a/%%'}), 'https://a/400x400');
      expect(
        coverFrom({
          'cover': {'uri': 'b/%%'},
        }),
        'https://b/400x400',
      );
      expect(coverFrom({'ogImage': 'c/%%'}), 'https://c/400x400');
      expect(coverFrom({}), '');
    });

    test('альбом и артист: счётчик, год, похожие', () {
      final a = parseAlbum({
        'id': 5,
        'title': 'Альбом',
        'artists': [
          {'name': 'Кто-то'},
        ],
        'year': 2021,
        'trackCount': 14,
        'ogImage': 'x/%%',
      })!;
      expect(a.artist, 'Кто-то');
      expect(a.year, '2021');
      expect(a.trackCount, 14);
      expect(a.cover, 'https://x/400x400');

      final noArtists = parseAlbum({'id': 6})!;
      expect(noArtists.artist, kYmDash);
      expect(noArtists.trackCount, 0);
      expect(parseArtist({'name': 'Без id'}), isNull);
    });

    test('плейлист: владелец из login, потом uid', () {
      final byLogin = parsePlaylist({
        'kind': 1000,
        'owner': {'login': 'user', 'uid': 55},
        'title': 'Сборник',
      })!;
      expect(byLogin.kind, '1000');
      expect(byLogin.owner, 'user');

      final byUid = parsePlaylist({
        'kind': '3',
        'owner': {'uid': 55},
      })!;
      expect(byUid.owner, '55');
    });

    test('плейлист-страница: rich-tracks и плоские треки, имя владельца', () {
      final rich = playlistEntity({
        'title': 'Мой',
        'owner': {'name': 'Вася', 'login': 'vasya'},
        'tracks': [
          {
            'track': {'id': 1, 'title': 'A'},
          },
          {'id': 2, 'title': 'B'},
        ],
      });
      expect(rich.tracks.map((t) => t.id), ['1', '2']);
      // owner.name beats login: it's the display name.
      expect(rich.subtitle, 'Вася');

      // The other format: the owner as a flat field.
      final flat = playlistEntity({'ownerName': 'Петя', 'tracks': []});
      expect(flat.subtitle, 'Петя');
    });
  });

  group('сквозные id', () {
    test('плейлист: owner с тильдой разбирается по последней', () {
      final id = ymPlaylistId('user~name', '1003');
      expect(id, 'ym:pl:user~name~1003');
      final parsed = parseYmPlaylistId(id)!;
      expect(parsed.owner, 'user~name');
      expect(parsed.kind, '1003');
    });

    test('публичный плейлист и числовые id', () {
      final uuid = ymPlaylistUuidId('lk.abc-123');
      expect(parseYmPlaylistUuidId(uuid), 'lk.abc-123');
      expect(parseYmPlaylistUuidId('ym:pl:a~1'), isNull);

      expect(ymNumericId('ym:42'), '42');
      expect(ymNumericId(ymArtistId('7')), '7');
      expect(ymNumericId(ymAlbumId('9')), '9');
      // A non-numeric tail: the id doesn't parse, and the provider finds
      // nothing instead of crashing.
      expect(ymNumericId('ym:plu:abc'), '');
    });

    test('источник узнаётся по префиксу', () {
      expect(MusicSource.fromId(ymTrackId('1')), MusicSource.yandex);
      expect(MusicSource.fromId(ymPlaylistId('u', '2')), MusicSource.yandex);
    });
  });

  group('маппинг в сущности', () {
    test('трек несёт артиста, обложку и признак доступности', () {
      final t = trackFromYm(
        const YmRawTrack(
          id: '42',
          title: 'Песня',
          artist: 'Кто-то',
          artistId: '7',
          cover: 'https://c/400x400',
          duration: Duration(seconds: 100),
          year: '2019',
          available: false,
        ),
      );
      expect(t.id, 'ym:42');
      expect(t.artistId, 'ym:artist:7');
      expect(t.year, '2019');
      expect(t.source, MusicSource.yandex);
      expect(t.sourceData?['available'], isFalse);
      // An unavailable track has nothing to download, so the button doesn't
      // show.
      expect(const YandexProvider().canDownload(t), isFalse);
    });

    test('альбом: нулевой счётчик становится «неизвестно»', () {
      final a = albumFromYm(
        const YmRawAlbum(
          id: '5',
          title: 'Альбом',
          artist: 'Кто-то',
          cover: '',
          year: '',
          trackCount: 0,
        ),
      );
      expect(a.id, 'ym:album:5');
      expect(a.trackCount, isNull);
      expect(a.cover, isNull);
      expect(a.year, isNull);
      expect(a.isAlbum, isTrue);
      expect(a.sourceUrl, 'https://music.yandex.ru/album/5');
    });
  });

  group('ссылки', () {
    test('трек внутри альбома важнее самого альбома', () {
      const url = 'https://music.yandex.ru/album/123/track/456';
      expect(reAlbumTrack.firstMatch(url)?.group(1), '456');
      // The branch order in resolve: the track first, or the link would open
      // the album.
      expect(reAlbum.firstMatch(url)?.group(1), '123');
    });

    test('плейлисты обоих форматов', () {
      final old = reUserPlaylist.firstMatch(
        'https://music.yandex.ru/users/vasya/playlists/1003',
      )!;
      expect(old.group(1), 'vasya');
      expect(old.group(2), '1003');

      // A prefixed id ("I like it") goes through whole, uncut.
      expect(
        rePublicPlaylist
            .firstMatch('https://music.yandex.ru/playlists/lk.5f0e-11')
            ?.group(1),
        'lk.5f0e-11',
      );
    });
  });

  group('прямая ссылка', () {
    test('подпись: md5(соль + path без слеша + s)', () {
      expect(
        signPath('/abc/def.mp3', 'xyz'),
        '018bd052f726715baee932ed27d907fc',
      );
    });

    test('теги XML достаются по первому вхождению', () {
      const xml =
          '<download-info><host>s1.ya.net</host><path>/a/b.mp3</path>'
          '<ts>62d</ts><s>sig</s></download-info>';
      expect(xmlTag(xml, 'host'), 's1.ya.net');
      expect(xmlTag(xml, 'path'), '/a/b.mp3');
      expect(xmlTag(xml, 'ts'), '62d');
      expect(xmlTag(xml, 's'), 'sig');
      expect(xmlTag(xml, 'nope'), isNull);
    });
  });

  test('без токена площадка выключена и в поиск не идёт', () {
    setToken(null);
    expect(const YandexProvider().isEnabled, isFalse);
    setToken('  ');
    expect(activeToken(), isNull, reason: 'пробелы — это не токен');
    setToken('abc');
    expect(const YandexProvider().isEnabled, isTrue);
    setToken(null);
  });

  group('чарт и релизы', () {
    test('чарт: место и динамика из обёртки, голый трек — по порядку', () {
      final tracks = parseChart({
        'chart': {
          'tracks': [
            {
              'track': {'id': 1, 'title': 'Первый'},
              'chart': {'position': 1, 'shift': 2, 'progress': 'up'},
            },
            {
              'track': {'id': 2, 'title': 'Новичок'},
              'chart': {'position': 2, 'shift': 0, 'progress': 'new'},
            },
            // An item with no wrapper is the track itself.
            {'id': 3, 'title': 'Голый'},
          ],
        },
      });

      expect(tracks.map((t) => t.chartPos), [1, 2, 3]);
      expect(tracks.first.chartShift, 2);
      expect(tracks[1].chartNew, isTrue);
      expect(tracks.last.chartShift, 0);
      expect(tracks.last.chartNew, isFalse);
    });

    test('место в чарте доходит до трека, у обычного трека его нет', () {
      final chartTrack = trackFromYm(
        parseChart({
          'chart': {
            'tracks': [
              {
                'track': {'id': 5},
                'chart': {'position': 7, 'shift': -3},
              },
            ],
          },
        }).single,
      );
      expect(chartTrack.chartPos, 7);
      expect(chartTrack.chartShift, -3);

      expect(trackFromYm(parseTrack({'id': 6})!).chartPos, isNull);
    });

    test('альбом: id и фото первого артиста, тип и дата выхода', () {
      final raw = parseAlbum({
        'id': 10,
        'title': 'Сингл',
        'type': 'single',
        'releaseDate': '2026-08-14T00:00:00+03:00',
        'artists': [
          {
            'id': 77,
            'name': 'Артист',
            'cover': {'uri': 'avatars.yandex.net/a/%%'},
          },
        ],
      })!;
      expect(raw.artistId, '77');
      expect(raw.artistCover, 'https://avatars.yandex.net/a/1000x1000');
      expect(raw.albumType, 'single');

      final album = albumFromYm(raw);
      expect(album.ownerId, 'ym:artist:77');
      expect(album.ownerAvatar, 'https://avatars.yandex.net/a/1000x1000');
      expect(album.albumType, 'single');
      // An empty type is a regular album: no field at all.
      expect(albumFromYm(parseAlbum({'id': 11})!).albumType, isNull);
    });
  });

  group('треки артиста порциями', () {
    List<Map<String, Object>> tracks(int n, [int from = 0]) => [
      for (var i = 0; i < n; i++) {'id': from + i, 'title': 'T${from + i}'},
    ];

    test('по pager: есть ещё, пока загружено меньше total', () {
      final first = parseArtistTracksPage({
        'tracks': tracks(50),
        'pager': {'total': 120, 'perPage': 50, 'page': 0},
      }, 0);
      expect(first.tracks.length, 50);
      expect(first.nextPage, 1);
      expect(first.total, 120);

      final last = parseArtistTracksPage({
        'tracks': tracks(20, 100),
        'pager': {'total': 120, 'perPage': 50, 'page': 2},
      }, 2);
      expect(last.nextPage, isNull);
    });

    test('без pager полная страница значит «возможно, есть»', () {
      expect(parseArtistTracksPage({'tracks': tracks(50)}, 0).nextPage, 1);
      final short = parseArtistTracksPage({'tracks': tracks(12)}, 0);
      expect(short.nextPage, isNull);
      expect(short.total, isNull);
    });

    test('пустая страница заканчивает список', () {
      final empty = parseArtistTracksPage({
        'tracks': <Object>[],
        'pager': {'total': 120},
      }, 3);
      expect(empty.tracks, isEmpty);
      expect(empty.nextPage, isNull);
      expect(parseArtistTracksPage(null, 0).nextPage, isNull);
    });
  });
}
