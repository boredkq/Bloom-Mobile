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
  group('счёт', () {
    test('тот же трек с другим оформлением названия совпадает уверенно', () {
      final src = _track('Ночь', source: MusicSource.soundcloud);
      final cand = _track('НОЧЬ (Official Audio)');

      expect(matchScore(cand, src), greaterThanOrEqualTo(kAutoMatchScore));
    });

    test('лишний артист в списке не штрафуется', () {
      final src = _track('Ночь', artist: 'Один');
      final cand = _track('Ночь', artist: 'Один, Другой');

      expect(matchScore(cand, src), greaterThanOrEqualTo(kAutoMatchScore));
    });

    test('артист, склеенный с названием, всё равно узнаётся', () {
      final src = _track('Ночь', artist: 'Один');
      final cand = _track('Один - Ночь', artist: '');

      expect(matchScore(cand, src), greaterThan(kMinMatchScore));
    });

    test('часовая версия того же названия отбраковывается длительностью', () {
      final src = _track('Ночь', seconds: 200);
      final hour = _track('Ночь', seconds: 3600);

      expect(matchScore(hour, src), lessThan(kAutoMatchScore));
      expect(matchScore(hour, src), lessThan(matchScore(_track('Ночь'), src)));
    });

    test('другой трек того же артиста в достоверные не проходит', () {
      final src = _track('Ночь', artist: 'Один');
      final other = _track('Утро', artist: 'Один');

      expect(matchScore(other, src), lessThan(kAutoMatchScore));
    });

    test('несколько секунд разницы совпадению не мешают', () {
      final src = _track('Ночь', seconds: 200);
      final cand = _track('Ночь', seconds: 203);

      expect(matchScore(cand, src), greaterThanOrEqualTo(kAutoMatchScore));
    });
  });

  group('ранжирование', () {
    test('лучший идёт первым, слабые отсекаются порогом', () {
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

    test('лимит — не больше, чем просили', () {
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

    test('пустая выдача — пустой список, а не падение', () {
      expect(rankMatches([], _track('Ночь')), isEmpty);
    });
  });
}
