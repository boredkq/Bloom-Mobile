import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

import 'models.dart';

/// Shazam REST API client for song identification.
class ShazamClient {
  const ShazamClient({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const String _defaultEndpoint =
      'https://amp.shazam.com/discovery/v5/en-US/US/android/-/tag';
  static const String _userAgent =
      'Dalvik/2.1.0 (Linux; U; Android 6.0.1; SM-G920F Build/MMB29K)';

  /// Identifies a track from a fingerprint signature.
  Future<RecognitionResult?> identify(
    RecognitionSignature signature, {
    String? timezone,
  }) async {
    final client = _client ?? http.Client();
    try {
      final reqId = _randomUuid();
      final devId = _randomUuid();
      final url = Uri.parse(
        '$_defaultEndpoint/$reqId/$devId'
        '?sync=true&webv3=true&sampling=true&connected=&shazamapiversion=v3'
        '&sharehub=true&hubv5minorversion=v5.1&hidelb=true&video=v3',
      );

      final payload = {
        'timezone': timezone ?? 'Europe/Moscow',
        'signature': {
          'uri': signature.toDataUri(),
          'samplems': signature.sampleDurationMs,
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'context': <String, dynamic>{},
        'geolocation': <String, dynamic>{},
      };

      final response = await client.post(
        url,
        headers: {
          'User-Agent': _userAgent,
          'X-Shazam-Platform': 'IPHONE',
          'X-Shazam-AppVersion': '14.1.0',
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': '*/*',
          'Accept-Language': 'en-US',
          'Content-Language': 'en_US',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final dynamic data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;

      final track = data['track'];
      if (track is! Map<String, dynamic>) return null;

      return parseTrackJson(track);
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Parses track JSON dictionary from Shazam API response.
  static RecognitionResult? parseTrackJson(Map<String, dynamic> track) {
    final title = (track['title'] as String?)?.trim() ?? '';
    final artist = (track['subtitle'] as String?)?.trim() ?? '';
    if (title.isEmpty || artist.isEmpty) return null;

    final images = track['images'] as Map?;
    var cover = (images?['coverarthq'] as String?)?.trim() ?? '';
    if (cover.isEmpty) {
      cover = (images?['coverart'] as String?)?.trim() ?? '';
    }

    String? album;
    String? year;
    String? label;

    final sections = track['sections'] as List?;
    if (sections != null) {
      for (final sec in sections) {
        if (sec is Map && sec['type'] == 'SONG') {
          final metadata = sec['metadata'] as List?;
          if (metadata != null) {
            for (final entry in metadata) {
              if (entry is Map) {
                final t = (entry['title'] as String?)?.toLowerCase();
                final text = (entry['text'] as String?)?.trim();
                if (text != null && text.isNotEmpty) {
                  if (t == 'album') album = text;
                  if (t == 'released') {
                    final match = RegExp(r'\d{4}').firstMatch(text);
                    if (match != null) year = match.group(0);
                  }
                  if (t == 'label') label = text;
                }
              }
            }
          }
        }
      }
    }

    final genres = track['genres'] as Map?;
    final genre = (genres?['primary'] as String?)?.trim();
    final isrc = (track['isrc'] as String?)?.trim();
    final shazamUrl = (track['url'] as String?)?.trim();

    String? ytId;
    final hub = track['hub'] as Map?;
    if (hub != null) {
      final options = hub['options'] as List?;
      if (options != null) {
        for (final opt in options) {
          if (opt is Map &&
              (opt['type'] as String?)?.toLowerCase().contains('video') ==
                  true) {
            final actions = opt['actions'] as List?;
            if (actions != null) {
              for (final act in actions) {
                if (act is Map) {
                  final uri = act['uri'] as String?;
                  if (uri != null) {
                    final match =
                        RegExp(r'[?&]v=([A-Za-z0-9_-]{11})').firstMatch(uri) ??
                        RegExp(r'/([A-Za-z0-9_-]{11})(?:[?&#]|$)').firstMatch(
                          uri,
                        );
                    if (match != null) {
                      ytId = match.group(1);
                      break;
                    }
                  }
                }
              }
            }
          }
          if (ytId != null) break;
        }
      }
    }

    return RecognitionResult(
      title: title,
      artist: artist,
      album: album,
      coverUrl: cover.isNotEmpty ? cover : null,
      year: year,
      genre: genre,
      label: label,
      isrc: isrc?.isNotEmpty == true ? isrc : null,
      shazamUrl: shazamUrl?.isNotEmpty == true ? shazamUrl : null,
      youtubeVideoId: ytId,
    );
  }

  static String _randomUuid() {
    final rnd = math.Random();
    String hex(int len) => List.generate(
      len,
      (_) => rnd.nextInt(16).toRadixString(16).toUpperCase(),
    ).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-8${hex(3)}-${hex(12)}';
  }
}
