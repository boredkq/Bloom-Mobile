/// Romanization engine tests: Cyrillic, Korean Hangul, and Japanese Kana transliteration.
library;

import 'package:bloom/features/lyrics/romanization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('romanize Cyrillic', () {
    test('transliterates standard Russian Cyrillic', () {
      expect(romanize('Привет мир'), 'Privet mir');
      expect(
        romanize('Съешь же ещё этих мягких французских булок'),
        "Sesh' zhe eshchyo etikh myagkikh frantsuzskikh bulok",
      );
    });

    test('transliterates Ukrainian and Belarusian letters', () {
      expect(romanize('Київ'), 'Kiyiv');
      expect(romanize('Ў краіне'), 'W kraine');
    });
  });

  group('romanize Korean Hangul', () {
    test('transliterates basic Hangul syllables', () {
      // 가 = g + a
      expect(romanize('가'), 'ga');
      // 한 = h + a + n, 글 = g + eu + l
      expect(romanize('한글'), 'hangeul');
      // 사랑 = s + a, r + a + ng
      expect(romanize('사랑'), 'sarang');
    });

    test('transliterates syllables with complex vowels and finals', () {
      // 방탄 = b + a + ng, t + a + n
      expect(romanize('방탄소년단'), 'bangtansonyeondan');
    });
  });

  group('romanize Japanese Kana', () {
    test('transliterates Hiragana', () {
      expect(romanize('ありがとう'), 'arigatou');
      expect(romanize('さようなら'), 'sayounara');
    });

    test('transliterates Katakana', () {
      expect(romanize(' bloom '), null);
      expect(romanize('ブルーム'), 'buruumu');
      expect(romanize('トーキョー'), 'tookyoo');
    });

    test('handles digraphs correctly', () {
      // きゃ, しゅ, ちょ
      expect(romanize('きゃく'), 'kyaku');
      expect(romanize('しゅくだい'), 'shukudai');
      expect(romanize('ちょっと'), 'chotto');
    });

    test('handles small tsu gemination', () {
      // きっと -> kitto
      expect(romanize('きっと'), 'kitto');
      // マッハ -> mahha
      expect(romanize('マッハ'), 'mahha');
    });
  });

  group('romanize edge cases', () {
    test('returns null for pure Latin/English text', () {
      expect(romanize('Hello world'), isNull);
      expect(romanize('12345!@#'), isNull);
      expect(romanize(''), isNull);
      expect(romanize('   '), isNull);
    });

    test('transliterates mixed text', () {
      expect(romanize('Track 1: Привет (Intro)'), 'Track 1: Privet (Intro)');
      expect(romanize('K-Pop 사랑 love'), 'K-Pop sarang love');
    });
  });
}
