/// Tests for ambient music recognition models and recognition service.
library;

import 'dart:convert';

import 'package:bloom/features/recognition/recognition_models.dart';
import 'package:bloom/features/recognition/recognition_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  group('RecognitionResult model', () {
    test('computes searchPhrase correctly', () {
      const res = RecognitionResult(
        title: 'Numb',
        artist: 'Linkin Park',
        album: 'Meteora',
        coverUrl: 'https://example.com/cover.jpg',
      );
      expect(res.searchPhrase, 'Linkin Park Numb');
      expect(res.title, 'Numb');
      expect(res.artist, 'Linkin Park');
      expect(res.album, 'Meteora');
      expect(res.coverUrl, 'https://example.com/cover.jpg');
    });

    test('implements value equality and hashCode', () {
      const a = RecognitionResult(
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
      );
      const b = RecognitionResult(
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
      );
      const c = RecognitionResult(
        title: 'Other',
        artist: 'Artist',
        album: 'Album',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), 'RecognitionResult(Artist — Song)');
    });
  });

  group('RecognitionStatus enum', () {
    test('identifies in-progress statuses', () {
      expect(RecognitionStatus.idle.isInProgress, isFalse);
      expect(RecognitionStatus.listening.isInProgress, isTrue);
      expect(RecognitionStatus.identifying.isInProgress, isTrue);
      expect(RecognitionStatus.found.isInProgress, isFalse);
      expect(RecognitionStatus.notFound.isInProgress, isFalse);
      expect(RecognitionStatus.error.isInProgress, isFalse);
    });
  });

  group('RecognitionService HTTP identify', () {
    test('parses track details from successful Shazam response', () async {
      final fakeClient = _FakeClient((request) async {
        expect(request.url.host, 'amp.shazam.com');
        final responsePayload = {
          'track': {
            'title': 'Midnight City',
            'subtitle': 'M83',
            'images': {'coverart': 'https://images.shazam.com/cover.jpg'},
            'sections': [
              {
                'type': 'SONG',
                'metadata': [
                  {'title': 'Album', 'text': 'Hurry Up, We\'re Dreaming'},
                ],
              },
            ],
          },
        };
        return http.Response(jsonEncode(responsePayload), 200);
      });

      final service = RecognitionService(client: fakeClient);
      final result = await service.identify();

      expect(result, isNotNull);
      expect(result!.title, 'Midnight City');
      expect(result.artist, 'M83');
      expect(result.album, "Hurry Up, We're Dreaming");
      expect(result.coverUrl, 'https://images.shazam.com/cover.jpg');
      expect(result.searchPhrase, 'M83 Midnight City');
    });

    test('returns null when response contains no track', () async {
      final fakeClient = _FakeClient((request) async {
        return http.Response(jsonEncode({'matches': []}), 200);
      });

      final service = RecognitionService(client: fakeClient);
      final result = await service.identify();
      expect(result, isNull);
    });

    test('returns null on HTTP error status code', () async {
      final fakeClient = _FakeClient((request) async {
        return http.Response('Not Found', 404);
      });

      final service = RecognitionService(client: fakeClient);
      final result = await service.identify();
      expect(result, isNull);
    });

    test('returns null gracefully on network failure', () async {
      final fakeClient = _FakeClient((request) async {
        throw http.ClientException('Connection aborted');
      });

      final service = RecognitionService(client: fakeClient);
      final result = await service.identify();
      expect(result, isNull);
    });
  });
}
