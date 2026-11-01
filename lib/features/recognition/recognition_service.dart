/// Service for ambient audio and song recognition.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'recognition_models.dart';

const String _shazamBase =
    'https://amp.shazam.com/discovery/v5/en-US/US/android/-/tag';
const Duration _timeout = Duration(seconds: 12);

class RecognitionService {
  RecognitionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Identifies a song from audio signature or mock test signal.
  Future<RecognitionResult?> identify({
    String? sampleBase64,
    int sampleMs = 4500,
  }) async {
    // Generate UUIDs for request and device
    final reqId = _randomUuid();
    final devId = _randomUuid();
    final url = Uri.parse('$_shazamBase/$reqId/$devId').replace(
      queryParameters: {
        'sync': 'true',
        'webv3': 'true',
        'sampling': 'true',
        'connected': '',
        'shazamapiversion': 'v3',
        'sharehub': 'true',
        'hubv5minorversion': 'v5.1',
        'hidelb': 'true',
        'video': 'v3',
      },
    );

    try {
      final body = jsonEncode({
        'geolocation': {},
        'signature': {
          'samplems': sampleMs,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          if (sampleBase64 != null)
            'uri': 'data:audio/vnd.shazam.sig;base64,$sampleBase64',
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'timezone': 'Europe/Moscow',
      });

      final response = await _client
          .post(
            url,
            headers: const {
              'User-Agent': 'Shazam/14.1.0 (Android; ru_RU; Xiaomi 2201116SG)',
              'X-Shazam-Platform': 'android',
              'X-Shazam-AppVersion': '14.1.0',
              'Content-Type': 'application/json',
              'Accept': '*/*',
            },
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map && data.containsKey('track')) {
          final t = data['track'] as Map<String, dynamic>;
          final title = t['title'] as String? ?? '';
          final artist = t['subtitle'] as String? ?? '';
          final images = t['images'] as Map<String, dynamic>?;
          final cover = images?['coverart'] as String?;
          final sections = t['sections'] as List<dynamic>?;
          String? album;
          if (sections != null) {
            for (final s in sections) {
              if (s is Map && s['type'] == 'SONG') {
                final metadata = s['metadata'] as List<dynamic>?;
                if (metadata != null) {
                  for (final m in metadata) {
                    if (m is Map && m['title'] == 'Album') {
                      album = m['text'] as String?;
                      break;
                    }
                  }
                }
              }
            }
          }

          if (title.isNotEmpty && artist.isNotEmpty) {
            return RecognitionResult(
              title: title,
              artist: artist,
              album: album,
              coverUrl: cover,
            );
          }
        }
      }
    } catch (_) {
      // Network failure or timeout
    }

    return null;
  }

  static String _randomUuid() {
    final rnd = Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}'
        .toUpperCase();
  }
}
