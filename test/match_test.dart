/// The platform matcher: the same track found on another platform.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/providers/match.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track(
  String name, {
  String artist = 'Artist',
  int seconds = 200,
  MusicSource source = MusicSource.ytmusic,
}) => Track(
  id: '${source.prefix}${name.hashCode}',
  name: name,
  artist: artist,
  duration: Duration(seconds: seconds),
  source: source,
);

void main() {
  group('score', () {
    test('the same track with another title style matches confidently', () {
      final src = _track('Ночь', source: MusicSource.soundcloud);
      final cand = _track('НОЧЬ (Official Audio)');

      expect(matchScore(cand, src), greaterThanOrEqualTo(kAutoMatchScore));
    });

    test("an extra artist in the list isn't penalized", () {
      final src = _track('Ночь', artist: 'Один');
      final cand = _track('Ночь', artist: 'Один, Другой');

      expect(matchScore(cand, src), greaterThanOrEqualTo(kAutoMatchScore));
    });

    test('an artist glued to the title is still recognized', () {
      final src = _track('Ночь', artist: 'Один');
      final cand = _track('Один - Ночь', artist: '');

      expect(matchScore(cand, src), greaterThan(kMinMatchScore));
    });

    test('an hour-long version of the same title is rejected by duration', () {
      final src = _track('Ночь', seconds: 200);
      final hour = _track('Ночь', seconds: 3600);

      expect(matchScore(hour, src), lessThan(kAutoMatchScore));
      expect(matchScore(hour, src), lessThan(matchScore(_track('Ночь'), src)));
    });

    test("another track by the same artist doesn't pass as reliable", () {
      final src = _track('Ночь', artist: 'Один');
      final other = _track('Утро', artist: 'Один');

      expect(matchScore(other, src), lessThan(kAutoMatchScore));
    });

    test("a few seconds of difference don't hurt a match", () {
      final src = _track('Ночь', seconds: 200);
      final cand = _track('Ночь', seconds: 203);

      expect(matchScore(cand, src), greaterThanOrEqualTo(kAutoMatchScore));
    });
  });

  group('ranking', () {
    test('the best comes first, weak ones are cut by the threshold', () {
      final src = _track('Ночь', artist: 'Один', seconds: 200);
      final ranked = rankMatches(
        [
          _track('Совсем другое', artist: 'Кто-то'),
          _track('Ночь', artist: 'Один', seconds: 201),
          _track('Ночь', artist: 'Один', seconds: 3600),
        ],
        src,
        min: kMinMatchScore,
      );

      expect(ranked.first.track.duration.inSeconds, 201);
      // "Something else entirely" is below the threshold and stays out.
      expect(ranked.length, 2);
    });

    test('the limit: no more than asked', () {
      final src = _track('Ночь');
      final ranked = rankMatches(
        [
          _track('Ночь'),
          _track('Ночь', seconds: 201),
          _track('Ночь', seconds: 202),
        ],
        src,
        limit: 1,
      );

      expect(ranked.length, 1);
    });

    test('empty results give an empty list, not a crash', () {
      expect(rankMatches([], _track('Ночь')), isEmpty);
    });
  });
}
