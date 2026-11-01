/// Models for ambient music recognition (Shazam / AudD).
library;

import 'package:flutter/foundation.dart';

@immutable
class RecognitionResult {
  const RecognitionResult({
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    this.year,
    this.genre,
  });

  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final String? year;
  final String? genre;

  String get searchPhrase => '$artist $title'.trim();

  @override
  bool operator ==(Object other) =>
      other is RecognitionResult &&
      other.title == title &&
      other.artist == artist &&
      other.album == album;

  @override
  int get hashCode => Object.hash(title, artist, album);

  @override
  String toString() => 'RecognitionResult($artist — $title)';
}

enum RecognitionStatus {
  idle,
  listening,
  identifying,
  found,
  notFound,
  error;

  bool get isInProgress =>
      this == RecognitionStatus.listening ||
      this == RecognitionStatus.identifying;
}
