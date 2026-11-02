/// YouTube Music parsing and mapping with no network: the type label stays out
/// of the artist, duration from two different places, the track count only
/// where it exists, the cover upscale, the top result first in its section,
/// link parsing.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/providers/ytmusic/models.dart';
import 'package:bloom/providers/ytmusic/ytm_provider.dart';
import 'package:bloom/providers/ytmusic/ytmusic.dart';
import 'package:flutter_test/flutter_test.dart';

// ---- Building raw InnerTube nodes (only the fields that get parsed) ----

Map<String, dynamic> _artistRun(String text, String browseId) => {
  'text': text,
  'navigationEndpoint': {
    'browseEndpoint': {
      'browseId': browseId,
      'browseEndpointContextSupportedConfigs': {
        'browseEndpointContextMusicConfig': {
          'pageType': 'MUSIC_PAGE_TYPE_ARTIST',
        },
      },
    },
  },
};

Map<String, dynamic> _col(List<Object> runs) => {
  'musicResponsiveListItemFlexColumnRenderer': {
    'text': {'runs': runs},
  },
};

Map<String, dynamic> _thumb(String url) => {
  'musicThumbnailRenderer': {
    'thumbnail': {
      'thumbnails': [
        {'url': 'https://i.ytimg.com/small'},
        {'url': url},
      ],
    },
  },
};

/// A result row. [pageType] sets the row's navigation (a track has none).
Map<String, dynamic> _row({
  required List<Object> columns,
  String? videoId,
  String? browseId,
  String? pageType,
  String cover = 'https://lh3.googleusercontent.com/aaa=w60-h60-l90-rj',
  List<Object>? fixedRuns,
}) => {
  'musicResponsiveListItemRenderer': {
    'flexColumns': columns,
    if (videoId != null) 'playlistItemData': {'videoId': videoId},
    if (browseId != null)
      'navigationEndpoint': {
        'browseEndpoint': {
          'browseId': browseId,
          if (pageType != null)
            'browseEndpointContextSupportedConfigs': {
              'browseEndpointContextMusicConfig': {'pageType': pageType},
            },
        },
      },
    'thumbnail': _thumb(cover),
    if (fixedRuns != null)
      'fixedColumns': [
        {
          'musicResponsiveListItemFixedColumnRenderer': {
            'text': {'runs': fixedRuns},
          },
        },
      ],
  },
};

Map<String, dynamic> _twoRow({
  required String browseId,
  required String title,
  List<Object> subtitleRuns = const [],
}) => {
  'musicTwoRowItemRenderer': {
    'navigationEndpoint': {
      'browseEndpoint': {'browseId': browseId},
    },
    'title': {
      'runs': [
        {'text': title},
      ],
    },
    'subtitle': {'runs': subtitleRuns},
    'thumbnail': {
      'musicThumbnailRenderer': {
        'thumbnail': {
          'thumbnails': [
            {'url': 'https://lh3.googleusercontent.com/two=w226-h226-l90-rj'},
          ],
        },
      },
    },
  },
};

Map<String, dynamic> _response(List<Object> rows) => {
  'contents': {
    'tabbedSearchResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {'contents': rows},
            },
          },
        },
      ],
    },
  },
};

void main() {
  group('строки выдачи', () {
    test('трек: артист из ссылок, длительность и обложка из col1', () {
      final t = parseTrack(
        _row(
          videoId: 'vid1',
          columns: [
            _col([
              {'text': 'Песня'},
            ]),
            _col([
              {'text': 'Song'}, // a type label isn't an artist
              {'text': ' • '},
              _artistRun('Первый', 'UC1'),
              {'text': ' & '},
              _artistRun('Второй', 'UC2'),
              {'text': ' • '},
              {'text': '3:45'},
            ]),
          ],
        )['musicResponsiveListItemRenderer'],
      )!;

      expect(t.id, 'vid1');
      expect(t.title, 'Песня');
      expect(t.artist, 'Первый, Второй');
      expect(t.artistId, 'UC1');
      expect(t.artists, [
        (id: 'UC1', name: 'Первый'),
        (id: 'UC2', name: 'Второй'),
      ]);
      expect(t.duration, const Duration(minutes: 3, seconds: 45));
      // I upscale the cover to 544: the card is bigger than 60px.
      expect(t.cover, 'https://lh3.googleusercontent.com/aaa=w544-h544-l90-rj');
    });

    test(
      'трек альбома: длительность из fixedColumns, артиста в строке нет',
      () {
        final t = parseTrack(
          _row(
            videoId: 'vid2',
            columns: [
              _col([
                {'text': 'Второй трек'},
              ]),
              _col([
                {'text': '1.2M plays'},
              ]),
            ],
            fixedRuns: [
              {'text': '4:02'},
            ],
          )['musicResponsiveListItemRenderer'],
        )!;

        expect(t.duration, const Duration(minutes: 4, seconds: 2));
        // The artist isn't repeated in an album's rows; the page fills it in.
        expect(t.artist, '1.2M plays');
      },
    );

    test('трек чарт-плейлиста: артист в НУЛЕВОМ run подписи', () {
      // Skipping the zeroth run unconditionally would leave a chart with no
      // artists: there the label is one run with the channel.
      final t = parseTrack(
        _row(
          videoId: 'vid3',
          columns: [
            _col([
              {'text': 'Трек'},
            ]),
            _col([
              {'text': 'Артист Чарта'},
            ]),
          ],
        )['musicResponsiveListItemRenderer'],
      )!;
      expect(t.artist, 'Артист Чарта');
    });

    test('без videoId и без заголовка строка треком не считается', () {
      expect(
        parseTrack(
          _row(
            columns: [
              _col([
                {'text': 'Есть заголовок'},
              ]),
            ],
          )['musicResponsiveListItemRenderer'],
        ),
        isNull,
      );
      expect(
        parseTrack(
          _row(
            videoId: 'v',
            columns: const [],
          )['musicResponsiveListItemRenderer'],
        ),
        isNull,
      );
    });

    test('плейлист: счётчик только когда YTM его дал', () {
      final withCount = parsePlaylist(
        _row(
          browseId: 'VLPL1',
          pageType: 'MUSIC_PAGE_TYPE_PLAYLIST',
          columns: [
            _col([
              {'text': 'Presenting Ado'},
            ]),
            _col([
              {'text': 'Playlist'},
              {'text': ' • '},
              {'text': 'YouTube Music'},
              {'text': ' • '},
              {'text': '48 songs'},
            ]),
          ],
        )['musicResponsiveListItemRenderer'],
      )!;
      expect(withCount.id, 'VLPL1');
      expect(withCount.trackCount, 48);

      final userPl = parsePlaylist(
        _row(
          browseId: 'VLPL2',
          pageType: 'MUSIC_PAGE_TYPE_PLAYLIST',
          columns: [
            _col([
              {'text': 'Чей-то плейлист'},
            ]),
            _col([
              {'text': 'Автор'},
              {'text': ' • '},
              {'text': '4.3M views'},
            ]),
          ],
        )['musicResponsiveListItemRenderer'],
      )!;
      // Unknown, not zero: otherwise the UI shows "0 tracks" for a full
      // playlist.
      expect(userPl.trackCount, isNull);
      expect(playlistFromYtm(userPl).trackCount, isNull);
    });

    test('альбом: год из col1, артист первым run', () {
      final a = parseAlbum(
        _row(
          browseId: 'MPREb_1',
          pageType: 'MUSIC_PAGE_TYPE_ALBUM',
          columns: [
            _col([
              {'text': 'Диск'},
            ]),
            _col([
              {'text': 'Артист'},
              {'text': ' • '},
              {'text': '2023'},
            ]),
          ],
        )['musicResponsiveListItemRenderer'],
      )!;
      expect(a.year, '2023');
      expect(a.artist, 'Артист');
    });

    test('альбом: метка типа в начале — тип, а не артист', () {
      final a = parseAlbum(
        _row(
          browseId: 'MPREb_2',
          pageType: 'MUSIC_PAGE_TYPE_ALBUM',
          columns: [
            _col([
              {'text': 'Magnum'},
            ]),
            _col([
              {'text': 'EP'},
              {'text': ' • '},
              _artistRun('5opka', 'UC5'),
              {'text': ' • '},
              {'text': '2026'},
            ]),
          ],
        )['musicResponsiveListItemRenderer'],
      )!;
      expect(a.artist, '5opka');
      expect(a.year, '2026');
      expect(albumFromYtm(a).albumType, 'ep');
    });
  });

  group('сборка выдачи', () {
    test('разделы по pageType, вкладка артистов вытесняет общую выдачу', () {
      final general = _response([
        _row(
          videoId: 'v1',
          columns: [
            _col([
              {'text': 'Трек'},
            ]),
            _col([
              {'text': 'Song'},
              {'text': ' • '},
              _artistRun('Кто-то', 'UC9'),
            ]),
          ],
        ),
        _row(
          browseId: 'UCwrong',
          pageType: 'MUSIC_PAGE_TYPE_ARTIST',
          columns: [
            _col([
              {'text': 'Похожий артист'},
            ]),
          ],
        ),
        _row(
          browseId: 'MPREb_x',
          pageType: 'MUSIC_PAGE_TYPE_ALBUM',
          columns: [
            _col([
              {'text': 'Альбом из общей'},
            ]),
            _col([
              {'text': 'Кто-то'},
            ]),
          ],
        ),
      ]);
      final artistsTab = _response([
        _row(
          browseId: 'UCright',
          pageType: 'MUSIC_PAGE_TYPE_ARTIST',
          columns: [
            _col([
              {'text': 'Тот самый'},
            ]),
          ],
        ),
      ]);
      final albumsTab = _response([
        _row(
          browseId: 'MPREb_y',
          pageType: 'MUSIC_PAGE_TYPE_ALBUM',
          columns: [
            _col([
              {'text': 'Альбом из вкладки'},
            ]),
            _col([
              {'text': 'Кто-то'},
            ]),
          ],
        ),
      ]);

      final d = parseSearch(
        general,
        query: 'кто-то',
        artistsOnly: artistsTab,
        albumsOnly: albumsTab,
      );

      expect(d.tracks.single.id, 'v1');
      // The general results lie about artists, so the tab replaces them.
      expect(d.artists.map((a) => a.id), ['UCright']);
      // The tab's albums only add: the general results can hold official
      // playlists with a count that the tab doesn't have.
      expect(d.albums.map((a) => a.id), ['MPREb_x', 'MPREb_y']);
      // Without a Songs tab there's nothing to page, so no token was kept.
      expect(d.tracksHasMore, isFalse);
    });

    test('топ-результат встаёт первым в своём разделе, дублей не даёт', () {
      final general = {
        'contents': [
          {
            'musicCardShelfRenderer': {
              'title': {
                'runs': [
                  {
                    'text': 'Тот самый',
                    'navigationEndpoint': {
                      'browseEndpoint': {
                        'browseId': 'UCtop',
                        'browseEndpointContextSupportedConfigs': {
                          'browseEndpointContextMusicConfig': {
                            'pageType': 'MUSIC_PAGE_TYPE_ARTIST',
                          },
                        },
                      },
                    },
                  },
                ],
              },
              'subtitle': {
                'runs': [
                  {'text': 'Artist'},
                  {'text': ' • '},
                  {'text': '1.2M subscribers'},
                ],
              },
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://lh3.googleusercontent.com/top=w120-h120'},
                ],
              },
            },
          },
        ],
      };
      final artistsTab = _response([
        _row(
          browseId: 'UCother',
          pageType: 'MUSIC_PAGE_TYPE_ARTIST',
          columns: [
            _col([
              {'text': 'Другой'},
            ]),
          ],
        ),
        _row(
          browseId: 'UCtop',
          pageType: 'MUSIC_PAGE_TYPE_ARTIST',
          columns: [
            _col([
              {'text': 'Тот самый'},
            ]),
          ],
        ),
      ]);

      final d = parseSearch(general, query: 'тот', artistsOnly: artistsTab);
      expect(d.artists.map((a) => a.id), ['UCtop', 'UCother']);
      expect(d.artists.first.cover, endsWith('=w544-h544'));
    });
  });

  group('страницы', () {
    test('альбом: строкам достаётся артист и обложка из шапки', () {
      final page = {
        'header': {
          'musicResponsiveHeaderRenderer': {
            'title': {
              'runs': [
                {'text': 'Пластинка'},
              ],
            },
            'subtitle': {
              'runs': [
                {'text': 'Album'},
                {'text': ' • '},
                {'text': '2021'},
              ],
            },
            'straplineTextOne': {
              'runs': [
                {'text': 'Артист Шапки'},
              ],
            },
            'straplineThumbnail': {
              'thumbnails': [
                {'url': 'https://lh3.googleusercontent.com/ava=w60-h60'},
              ],
            },
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://lh3.googleusercontent.com/cov=w120-h120'},
              ],
            },
          },
        },
        'contents': [
          {
            'musicResponsiveListItemRenderer': {
              'flexColumns': [
                _col([
                  {'text': 'Трек альбома'},
                ]),
              ],
              'playlistItemData': {'videoId': 'av1'},
              'fixedColumns': [
                {
                  'musicResponsiveListItemFixedColumnRenderer': {
                    'text': {
                      'runs': [
                        {'text': '2:30'},
                      ],
                    },
                  },
                },
              ],
            },
          },
        ],
      };

      final e = parseAlbumPage(page);
      expect(e.title, 'Пластинка');
      // straplineTextOne beats subtitle: that one holds metadata, not a name.
      expect(e.subtitle, 'Артист Шапки');
      expect(e.year, '2021');
      expect(e.ownerAvatar, endsWith('ava=w544-h544'));
      expect(e.tracks.single.artist, 'Артист Шапки');
      expect(e.tracks.single.cover, endsWith('cov=w544-h544'));
    });

    test('карусели артиста: MPRE — релиз, UC — похожий, прочее мимо', () {
      final page = {
        'header': {
          'musicImmersiveHeaderRenderer': {
            'title': {
              'runs': [
                {'text': 'Артист'},
              ],
            },
            'description': {'simpleText': 'Биография'},
            'subscriptionButton': {
              'subscribeButtonRenderer': {
                'subscriberCountText': {'simpleText': '39.9M subscribers'},
              },
            },
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://lh3.googleusercontent.com/ava=w120-h120'},
              ],
            },
          },
        },
        'contents': [
          _twoRow(
            browseId: 'MPREb_rel',
            title: 'Сингл',
            subtitleRuns: [
              {'text': 'Single'},
              {'text': ' • '},
              {'text': '2024'},
            ],
          ),
          _twoRow(browseId: 'UCsim', title: 'Похожий'),
          _twoRow(browseId: 'VLPLvideo', title: 'Карусель видео'),
          _row(
            videoId: 'pv1',
            columns: [
              _col([
                {'text': 'Популярный трек'},
              ]),
              _col([
                {'text': 'Song'},
                {'text': ' • '},
                _artistRun('Артист', 'UCme'),
                {'text': ' • '},
                {'text': '3:00'},
              ]),
            ],
          ),
        ],
      };

      final e = parseArtistPage(page);
      expect(e.description, 'Биография');
      expect(e.albums.map((a) => a.id), ['MPREb_rel']);
      // The type label stays out of its field, and the year is apart from the
      // artist.
      expect(e.albums.single.year, '2024');
      expect(e.albums.single.artist, '');
      expect(e.similarArtists.map((a) => a.id), ['UCsim']);
      expect(e.popularTracks.single.id, 'pv1');
    });

    test('кнопка «ещё» ищется по заголовку секции рекурсивно', () {
      final page = {
        'contents': [
          {
            'musicShelfRenderer': {
              'title': {
                'runs': [
                  {'text': 'Top songs'},
                ],
              },
              'bottomEndpoint': {
                'browseEndpoint': {'browseId': 'VLPLfull'},
              },
            },
          },
          {
            'musicCarouselShelfRenderer': {
              'header': {
                'musicCarouselShelfBasicHeaderRenderer': {
                  'title': {
                    'runs': [
                      {'text': 'Singles & EPs'},
                    ],
                  },
                  'moreContentButton': {
                    'buttonRenderer': {
                      'navigationEndpoint': {
                        'browseEndpoint': {
                          'browseId': 'MPADuc',
                          'params': 'ggMB',
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        ],
      };

      expect(shelfMore(page, const ['Top songs'])?.id, 'VLPLfull');
      final singles = shelfMore(page, const ['Singles & EPs']);
      expect(singles?.id, 'MPADuc');
      expect(singles?.params, 'ggMB');
      expect(shelfMore(page, const ['Ничего такого']), isNull);
    });
  });

  group('мелочи разбора', () {
    test('апскейл обложки не портит ссылку без размеров', () {
      expect(
        upscaleThumb('https://i.ytimg.com/vi/x/hq.jpg'),
        'https://i.ytimg.com/vi/x/hq.jpg',
      );
      expect(upscaleThumb('https://lh3/a=w60-h60'), 'https://lh3/a=w544-h544');
    });

    test('часы', () {
      expect(parseClock('3:45'), 225);
      expect(parseClock('1:02:03'), 3723);
      expect(parseClock('нет'), isNull);
      expect(parseClock('42'), isNull);
    });
  });

  group('ссылки и id', () {
    test(
      'видео важнее плейлиста, browse-префиксы разбираются без сети',
      () async {
        expect(
          (await resolve(
            'https://music.youtube.com/watch?v=abc123&list=PL1',
          )).id,
          'abc123',
        );
        expect((await resolve('https://youtu.be/xyz789?t=10')).kind, 'track');
        expect(
          (await resolve('https://music.youtube.com/browse/MPREb_1')).kind,
          'album',
        );
        expect(
          (await resolve('https://music.youtube.com/playlist?list=PLabc')).id,
          'PLabc',
        );
        expect(
          (await resolve('https://www.youtube.com/channel/UCabc')).kind,
          'artist',
        );
        await expectLater(
          resolve('https://soundcloud.com/user/track'),
          throwsA(isA<YtmException>()),
        );
      },
    );

    test('сквозные id: трек не путается с альбомом и плейлистом', () {
      expect(parseYtmTrackId(ytmTrackId('vid')), 'vid');
      expect(parseYtmTrackId(ytmAlbumId('MPRE1')), isNull);
      expect(parseYtmTrackId(ytmArtistId('UC1')), isNull);
      expect(parseYtmTrackId(ytmPlaylistId('VLPL1')), isNull);
      expect(parseYtmAlbumId(ytmAlbumId('MPRE1')), 'MPRE1');
      expect(parseYtmPlaylistId(ytmPlaylistId('VLPL1')), 'VLPL1');
      // The platform goes by id prefix: 'ytm_' before 'ym_'.
      expect(MusicSource.fromId(ytmTrackId('vid')), MusicSource.ytmusic);
    });

    test('id внутри HTML берётся целиком', () {
      expect(findId('junk MPREb_abc-123"', 'MPRE'), 'MPREb_abc-123');
      expect(findId('нет', 'UC'), isNull);
    });
  });

  group('маппинг в общие сущности', () {
    test('трек: ссылка на watch, артист по умолчанию', () {
      final t = trackFromYtm(
        const YtmRawTrack(
          id: 'vid',
          title: '',
          artist: '',
          artistId: '',
          cover: '',
          duration: Duration(minutes: 2),
        ),
      );
      expect(t.id, 'ytm:vid');
      expect(t.name, kYtmUntitled);
      expect(t.artist, kYtmUnknownArtist);
      expect(t.cover, isNull);
      expect(t.artistId, isNull);
      expect(t.url, 'https://music.youtube.com/watch?v=vid');
      expect(t.source, MusicSource.ytmusic);
    });

    test('плейлист: ссылка на list без служебного VL', () {
      final p = playlistFromYtm(
        const YtmRawPlaylist(
          id: 'VLPL42',
          title: 'Сет',
          cover: '',
          ownerName: 'Автор',
          trackCount: 7,
        ),
      );
      expect(p.id, 'ytm:pl:VLPL42');
      expect(p.sourceUrl, 'https://music.youtube.com/playlist?list=PL42');
      expect(p.trackCount, 7);
      expect(p.isAlbum, isFalse);
    });
  });
}
