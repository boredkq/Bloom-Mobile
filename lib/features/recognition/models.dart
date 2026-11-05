import 'dart:convert';
import 'dart:typed_data';

/// A generated audio fingerprint signature ready for the Shazam tag endpoint.
class RecognitionSignature {
  const RecognitionSignature({
    required this.payload,
    required this.sampleDurationMs,
    required this.peakCount,
  });

  final Uint8List payload;
  final int sampleDurationMs;
  final int peakCount;

  static const String dataUriPrefix = 'data:audio/vnd.shazam.sig;base64,';

  /// Transforms raw packet bytes into the Shazam data URI.
  String toDataUri() => '$dataUriPrefix${base64Encode(payload)}';
}

/// Metadata of a recognized track returned by the Shazam service.
class RecognitionResult {
  const RecognitionResult({
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    this.year,
    this.genre,
    this.label,
    this.isrc,
    this.shazamUrl,
    this.youtubeVideoId,
  });

  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final String? year;
  final String? genre;
  final String? label;
  final String? isrc;
  final String? shazamUrl;
  final String? youtubeVideoId;

  /// Clean query phrase to find this track in Bloom providers.
  String get searchPhrase => '$artist $title'.trim();

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    if (album != null) 'album': album,
    if (coverUrl != null) 'coverUrl': coverUrl,
    if (year != null) 'year': year,
    if (genre != null) 'genre': genre,
    if (label != null) 'label': label,
    if (isrc != null) 'isrc': isrc,
    if (shazamUrl != null) 'shazamUrl': shazamUrl,
    if (youtubeVideoId != null) 'youtubeVideoId': youtubeVideoId,
  };

  factory RecognitionResult.fromJson(Map<String, dynamic> json) =>
      RecognitionResult(
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        album: json['album'] as String?,
        coverUrl: json['coverUrl'] as String?,
        year: json['year'] as String?,
        genre: json['genre'] as String?,
        label: json['label'] as String?,
        isrc: json['isrc'] as String?,
        shazamUrl: json['shazamUrl'] as String?,
        youtubeVideoId: json['youtubeVideoId'] as String?,
      );
}

enum RecognitionErrorKind {
  permissionDenied,
  unavailable,
  timeout,
  network,
  internal,
}

sealed class RecognitionState {
  const RecognitionState();
}

class RecognitionIdle extends RecognitionState {
  const RecognitionIdle();
}

class RecognitionListening extends RecognitionState {
  const RecognitionListening({this.progress = 0.0});
  final double progress;
}

class RecognitionIdentifying extends RecognitionState {
  const RecognitionIdentifying();
}

class RecognitionMatch extends RecognitionState {
  const RecognitionMatch(this.result);
  final RecognitionResult result;
}

class RecognitionNoMatch extends RecognitionState {
  const RecognitionNoMatch();
}

class RecognitionError extends RecognitionState {
  const RecognitionError(this.kind, [this.message]);
  final RecognitionErrorKind kind;
  final String? message;
}

/// A stored recognition history record.
class RecognitionHistoryEntry {
  const RecognitionHistoryEntry({
    required this.id,
    required this.result,
    required this.timestamp,
  });

  final String id;
  final RecognitionResult result;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'id': id,
    'result': result.toJson(),
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory RecognitionHistoryEntry.fromJson(Map<String, dynamic> json) =>
      RecognitionHistoryEntry(
        id: json['id'] as String? ?? '',
        result: RecognitionResult.fromJson(
          (json['result'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          json['timestamp'] as int? ?? 0,
        ),
      );
}
