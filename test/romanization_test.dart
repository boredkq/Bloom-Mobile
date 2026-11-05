import 'package:bloom/features/lyrics/romanization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('romanize', () {
    test('returns null for empty or already Latin strings', () {
      expect(romanize(''), null);
      expect(romanize('   '), null);
      expect(romanize('Hello world'), null);
      expect(romanize('123 !?'), null);
    });

    test('transliterates Cyrillic text', () {
      expect(romanize('Привет мир'), 'Privet mir');
      expect(
        romanize("Съешь же ещё этих мягких французских булок"),
        "Sesh' zhe eshchyo etikh myagkikh frantsuzskikh bulok",
      );
      expect(romanize('Київ'), 'Kiyiv');
      expect(romanize('Ў краіне'), 'W kraine');
    });

    test('transliterates Korean Hangul syllables', () {
      expect(romanize('안녕하세요'), 'annyeonghaseyo');
      expect(romanize('한글'), 'hangeul');
      expect(romanize('케이팝'), 'keipap');
    });

    test('transliterates Japanese Hiragana', () {
      expect(romanize('さくら'), 'sakura');
      expect(romanize('ありがとう'), 'arigatou');
    });

    test('transliterates Japanese Katakana', () {
      expect(romanize('ブルーム'), 'buruumu');
      expect(romanize('トーキョー'), 'tookyoo');
    });

    test('handles Japanese digraphs and gemination correctly', () {
      expect(romanize('きょう'), 'kyou');
      expect(romanize('ちょっと'), 'chotto');
      expect(romanize('やっぱり'), 'yappari');
      expect(romanize('コーヒー'), 'koohii');
    });
  });
}
